#!/usr/bin/env bash
# Optional host-side smoke test. No real mounts or network connections are used.
# A notify service which never sends READY=1 must not hold up its wanted-by target.
set -euo pipefail
cd "$(dirname "$0")/.."

settings=$(nix eval --offline --json \
  '.#nixosConfigurations.amdmini-1.config.home-manager.users.peter.systemd.user.services."rclone-mount:@garage"')
temporary=$(mktemp -d "${XDG_RUNTIME_DIR:?No systemd user runtime directory}/rclone-start-test.XXXXXX")
service="${temporary##*/}.service"
target="${temporary##*/}.target"
cleanup() {
  systemctl --user kill --signal=KILL "$service" >/dev/null 2>&1 || true
  timeout 15s systemctl --user stop "$target" "$service" >/dev/null 2>&1 || true
  rm -f -- "$XDG_RUNTIME_DIR/systemd/user/$service" "$XDG_RUNTIME_DIR/systemd/user/$target"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
  rm -rf -- "$temporary"
}
trap cleanup EXIT

# Reproduce target/service ordering without depending on the real credential unit.
{
  printf '[Unit]\nDescription=Rclone startup policy smoke test\n'
  jq -r '.Unit | "DefaultDependencies=\(.DefaultDependencies)\nBefore=\(.Before | join(" "))\nConflicts=\(.Conflicts | join(" "))"' <<< "$settings"
  printf 'After=basic.target\n[Service]\n'
  jq -r '
    .Service | to_entries[]
    | select(
        .key == "Type" or .key == "TimeoutStartSec" or .key == "TimeoutStartFailureMode"
        or .key == "TimeoutStopSec" or .key == "TimeoutStopFailureMode"
        or .key == "KillMode" or .key == "SendSIGKILL" or .key == "FinalKillSignal"
      )
    | "\(.key)=\(.value)"
  ' <<< "$settings"
  printf 'ExecStart=%s 300\n' "$(command -v sleep)"
} > "$temporary/$service"
printf '[Unit]\nDescription=Rclone startup policy test target\nWants=%s\n' "$service" > "$temporary/$target"

# Control: ordinary defaults must make the target wait for the never-ready service.
cp "$temporary/$service" "$temporary/configured-service"
sed -i 's/^DefaultDependencies=.*/DefaultDependencies=yes/' "$temporary/$service"
systemctl --user link --runtime "$temporary/$service" "$temporary/$target" >/dev/null 2>&1
status=0
timeout 2s systemctl --user start "$target" >/dev/null 2>&1 || status=$?
((status == 124)) || { echo 'Control did not reproduce a target waiting for readiness' >&2; exit 1; }
timeout 15s systemctl --user stop "$target" "$service" >/dev/null 2>&1

# Configured policy: target reaches active while its wanted service is still starting.
cp "$temporary/configured-service" "$temporary/$service"
systemctl --user daemon-reload
SECONDS=0
timeout 5s systemctl --user start "$target"
elapsed=$SECONDS
[[ "$(systemctl --user show "$target" --property=ActiveState --value)" == active ]]
[[ "$(systemctl --user show "$service" --property=ActiveState --value)" == activating ]]
printf 'Startup policy passed: target active after %ss while the never-ready service is still activating.\n' "$elapsed"
