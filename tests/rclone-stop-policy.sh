#!/usr/bin/env bash
# Optional host-side smoke test: starts only a throwaway user service, not a mount.
# Requires a running systemd user manager, nix, jq, and coreutils.
set -euo pipefail
cd "$(dirname "$0")/.."

settings=$(nix eval --offline --json \
  '.#nixosConfigurations.amdmini-1.config.home-manager.users.peter.systemd.user.services."rclone-mount:@garage".Service')
properties=()
for key in TimeoutStopSec TimeoutStopFailureMode KillMode SendSIGKILL FinalKillSignal; do
  properties+=(--property="$key=$(jq -er --arg key "$key" '.[$key] | tostring' <<< "$settings")")
done

temporary=$(mktemp -d "${XDG_RUNTIME_DIR:?No systemd user runtime directory}/rclone-stop-test.XXXXXX")
unit="rclone-stop-test-${temporary##*/}.service"
cleanup() {
  systemctl --user kill --signal=KILL "$unit" >/dev/null 2>&1 || true
  timeout 5s systemctl --user stop "$unit" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  rm -rf -- "$temporary"
}
trap cleanup EXIT

# Ignore SIGTERM to force systemd to exercise the timeout and final SIGKILL.
cat > "$temporary/ignore-term.sh" <<'SCRIPT'
trap '' TERM
printf '%s\n' "$BASHPID" > "$1"
while :; do sleep 3600 & wait "$!"; done
SCRIPT
systemd-run --user --quiet --unit="$unit" --property=Type=exec \
  "${properties[@]}" "$(command -v bash)" "$temporary/ignore-term.sh" "$temporary/ready"
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ ! -f "$temporary/ready" ]] || break
  sleep 0.05
done
[[ -f "$temporary/ready" ]] || { echo 'Test process did not become ready' >&2; exit 1; }

SECONDS=0
status=0
timeout 20s systemctl --user stop "$unit" > "$temporary/stop.log" 2>&1 || status=$?
if ((status == 124 || SECONDS >= 20)); then
  cat "$temporary/stop.log" >&2
  echo 'Stop policy exceeded the smoke-test deadline' >&2
  exit 1
fi
state=$(systemctl --user show "$unit" --property=ActiveState --value)
[[ "$state" == inactive || "$state" == failed ]]
! kill -0 "$(cat "$temporary/ready")" 2>/dev/null
printf 'Stop policy passed: SIGTERM-ignoring process terminated after %ss (state=%s).\n' "$SECONDS" "$state"
