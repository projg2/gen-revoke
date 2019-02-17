==========
gen-revoke
==========
:Author: Michał Górny
:Copyright: 2-clause BSD license


Purpose
=======
gen-revoke generates and exports revocation signatures for an OpenPGP
key.  Unlike ``gpg --gen-revoke``, separate revocation signatures are
generated for the primary key and every subkey.  Furthermore, separate
signatures are created for each of the specified recipients, explicitly
indicating whom the particular revocation signature belongs to.

The specific use case are shared OpenPGP keys used by organizations,
with the secret portion of primary key being stored protected
and unavailable to most of the authorized organization members.
The design allows for revoking subkeys rather than whole key depending
on the level of compromise, and for multiple members holding revocation
signatures, with the signature explicitly providing audit trail
as to whose signature was used to revoke the key.


Requirements
============
In order to use gen-revoke, you need to have:

- GnuPG 2.1 or newer installed as ``gpg``,

- expect(1),

- the secret portion of the primary key,

- public encryption keys of all recipients.


Usage
=====
The usage is::

    ./gen-revoke.bash <key-id> <recipient>...

*key-id* specifies the key to generate revocation signatures for.  This
can be any identifier valid for ``gpg --list-keys``.  It needs to match
a single key.

*recipient* specifies one or more recipients for the revocation
signatures.  This can be any identifier valid for ``gpg --recipient``.

The script will write files to the current directory, named:

- ``<primary-key-id>-primary-<rcpt>.gpg.gpg`` for the primary key,

- ``<primary-key-id>-subkey-<subkey-id>-<rcpt>.gpg.gpg`` for each
  subkey.

Each of the files will contain a key export containing revocation
signature for the primary key or the specified subkey, attributed
and encrypted to the specified recipient.
