#!/usr/bin/env bash

# die <message>...
# Print the message and exit unsuccessfully.
die() {
	echo "${@}" >&2
	exit 1
}

# fill_key_ids <key-id>
# Get fingerprints of the primary key and subkeys and put them
# into key_ids array.
fill_key_ids() {
	local key_id=${1}
	local l fpr
	local skip_next=0

	while read -r l; do
		if [[ ${l} == sub:r:* ]]; then
			# subkey already revoked
			skip_next=1
		elif [[ ${l} == fpr:* ]]; then
			if [[ ${skip_next} == 1 ]]; then
				skip_next=0
				continue
			fi

			fpr=${l#fpr:::::::::}
			fpr=${fpr%:}
			[[ ${#fpr} == 40 ]] || die "Invalid fingerprint: ${l}"
			key_ids+=( "${fpr}" )
		fi
	done < <(gpg --with-colons --list-keys "${key_id}" ||
		die "gpg failed (invalid key id?)")
}

# make_gpghome <key-id>
# Create an isolated GNUPGHOME and import the specified key from parent
# environment.  The path to the new home is put into LOCAL_GNUPGHOME.
make_gpghome() {
	local key=${1}

	LOCAL_GNUPGHOME=$(mktemp -d || die "mktemp failed")
	trap 'nuke_gpghome' EXIT
	gpg --export-secret-keys "${key}" |
		GNUPGHOME="${LOCAL_GNUPGHOME}" gpg --quiet --import ||
		die "importing secrets keys into temporary home failed"
}

# nuke_gpghome
# Nuke temporary directory created by make_gpghome.
nuke_gpghome() {
	[[ -n ${LOCAL_GNUPGHOME} ]] && rm -r "${LOCAL_GNUPGHOME}"
	unset LOCAL_GNUPGHOME
}

# revoke_subkey <key-id> <owner> <is_primary>
# Revoke a specific key or subkey.
revoke_subkey() {
	local key=${1}
	local owner=${2}
	local is_primary=${3}

	local subkey exp_confirm
	if [[ ${is_primary} == 1 ]]; then
		subkey=0
		exp_confirm='Do you really want to revoke the entire key?'
	else
		subkey=${key}
		exp_confirm='Do you really want to revoke this subkey?'
	fi

	local -x GNUPGHOME=${LOCAL_GNUPGHOME}
	expect - <<-EOF || die "revocation failed"
		set timeout -1
		spawn gpg --edit-key ${key}
		expect "gpg>"
		send "key ${subkey}\n"
		expect {
			"No subkey with key ID" {
				exit 1
			}
			"gpg>" {
				send "revkey\n"
				expect "${exp_confirm}"
				send "y\n"
				expect "Your decision?"
				send "1\n"
				expect ">"
				send "Key revoked by ${owner}\n\n"
				expect "Is this okay?"
				send "y\n"
				expect "gpg>"
				send "minimize\n"
				expect "gpg>"
				send "save\n"
				wait
			}
		}
	EOF
}

# export_revoke <key-id> <recipient> <primary-key-id>
# Export revocation and encrypt it for the specified recipient.
export_revoke() {
	local key=${1}
	local rcpt=${2}
	local primary=${3}

	local name=${primary:(-16)}
	if [[ ${key} == ${primary} ]]; then
		name+=-primary
	else
		name+=-subkey-${key:(-16)}
	fi
	name+=-${rcpt}.gpg.gpg

	gpg --encrypt --recipient="${rcpt}" \
		< <(GNUPGHOME=${LOCAL_GNUPGHOME} gpg --export "${key}") \
		> "${name}" || die "gpg export+encrypt failed"
}

# main <key-id> <recipient>...
# Prepare revocation certificates for the specified key and its subkeys,
# for each of the listed recipients.
main() {
	[[ ${#} -ge 2 ]] || die "Usage: ${0} <key-id> <recipient>..."

	local key=${1}
	local rcpts=( "${@:2}" )

	# verify key id and get subkeys
	local key_ids=()
	fill_key_ids "${key}"

	# generate revocations for each of the key ids
	local k r
	for k in "${key_ids[@]}"; do
		local is_primary=0
		[[ ${k} == ${key_ids[0]} ]] && is_primary=1

		# ...for each recipient
		for r in "${rcpts[@]}"; do
			make_gpghome "${k}"
			revoke_subkey "${k}" "${r}" "${is_primary}"
			export_revoke "${k}" "${r}" "${key_ids[0]}"
			nuke_gpghome
		done
	done
}

umask 077
main "${@}"
