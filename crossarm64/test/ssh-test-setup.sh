#!/usr/bin/bash
# Create the keys and sshd config the ssh tests share.  Runs INSIDE the ARM64
# root (it uses that root's ssh-keygen):
#
#   bash ssh-test-setup.sh <work-dir-in-msys-form>      e.g. /c/sshtest
#
# Produces <work>/ssh/{hostkey,id_ed25519,id_rsa,id_ecdsa,id_enc,authorized_keys,
# sshd_config} and <work>/askpass.sh.  id_enc is passphrase-protected
# ("secret-pass") for the askpass tests.  Idempotent.
set -eu
W=${1:?usage: ssh-test-setup.sh <work-dir>}
D=$W/ssh
mkdir -p "$D" "$W/home/.ssh"
[ -f "$D/hostkey" ]    || ssh-keygen -q -t ed25519 -N '' -f "$D/hostkey"
[ -f "$D/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -f "$D/id_ed25519"
[ -f "$D/id_rsa" ]     || ssh-keygen -q -t rsa -b 3072 -N '' -f "$D/id_rsa"
[ -f "$D/id_ecdsa" ]   || ssh-keygen -q -t ecdsa -N '' -f "$D/id_ecdsa"
[ -f "$D/id_enc" ]     || ssh-keygen -q -t ed25519 -N 'secret-pass' -f "$D/id_enc"
cat "$D"/id_ed25519.pub "$D"/id_rsa.pub "$D"/id_ecdsa.pub "$D"/id_enc.pub > "$D/authorized_keys"
# Port and PidFile are added per test by common.ps1.
cat > "$D/sshd_config" <<CFG
ListenAddress 127.0.0.1
HostKey $D/hostkey
AuthorizedKeysFile $D/authorized_keys
StrictModes no
PasswordAuthentication no
CFG
printf '#!/bin/sh\necho secret-pass\n' > "$W/askpass.sh"
echo "ssh test fixtures ready in $W"
