#!/usr/bin/env bash
# Generate units into a temporary directory, never load or start them.
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repository"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
generator=/run/current-system/systemd/lib/systemd/system-generators/systemd-fstab-generator

for host in peter-laptop amdmini-1; do
  output="$work/$host"
  mkdir -p "$output/normal" "$output/early" "$output/late"
  nix eval --offline --raw "path:.#nixosConfigurations.$host.config.environment.etc.fstab.text" >"$output/fstab"
  SYSTEMD_FSTAB="$output/fstab" SYSTEMD_IN_INITRD=0 "$generator" "$output/normal" "$output/early" "$output/late"
done

client="$work/peter-laptop/normal"
grep -Fxq 'TimeoutSec=10s' "$client/mnt-shared.mount"
grep -Fxq 'TimeoutIdleSec=1min' "$client/mnt-shared.automount"
test -L "$client/remote-fs.target.wants/mnt-shared.automount"
test ! -e "$client/remote-fs.target.requires/mnt-shared.mount"
test ! -e "$client/remote-fs.target.wants/mnt-shared.mount"
# Only the actual mount, not starting the automount, should need connectivity.
if grep -Eq '^(After|Wants|Requires)=.*network' "$client/mnt-shared.automount"; then
  echo 'Automount unexpectedly waits for networking' >&2
  exit 1
fi

server="$work/amdmini-1/normal"
grep -Fxq 'What=/mnt/data/shared' "$server/mnt-shared.mount"
grep -Fxq 'Type=none' "$server/mnt-shared.mount"
grep -q '^Options=bind,' "$server/mnt-shared.mount"
grep -Fxq 'RequiresMountsFor=/mnt/data' "$server/mnt-shared.mount"
grep -Fxq 'Requires=shared-workspace-directory.service' "$server/mnt-shared.mount"
grep -Fxq 'After=shared-workspace-directory.service' "$server/mnt-shared.mount"
if grep -q 'systemd-fsck' "$server/mnt-shared.mount"; then
  echo 'Unexpected fsck for an ordinary directory bind mount' >&2
  exit 1
fi
printf '%s\n' 'PASS: generated on-demand client units, non-gating automount, mount/idle timeouts, ordered server directory preparation'
