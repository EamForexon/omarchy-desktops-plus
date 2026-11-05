#!/bin/bash
# Remember which monitor each workspace lives on and keep it there.
#
#   sync.sh [keep-alive] [restore]
#
# keep-alive  workspaces 1..N stay alive when empty (default 5); higher ones
#             close like stock Omarchy but come back on their saved monitor.
# restore     move workspaces back to their saved monitor if it is connected
#             again (run after a monitor is plugged in).
#
# The saved map only follows the live layout while a workspace's saved monitor
# is connected, so unplugging a monitor doesn't forget where its workspaces go.
# Safe to run any number of times.

keep_alive="${1:-5}"
mode="${2:-}"

state="${XDG_STATE_HOME:-$HOME/.local/state}/desktops-plus/workspace-monitors.json"
mkdir -p "$(dirname "$state")"
[[ -s "$state" ]] || echo '{}' >"$state"

live_layout() {
  hyprctl -j workspaces | jq -c '[.[] | select(.id > 0) | {key: (.id | tostring), value: .monitor}] | from_entries'
}

monitors=$(hyprctl -j monitors | jq -c '[.[].name]')
live=$(live_layout)
saved=$(cat "$state")

if [[ "$mode" == restore ]]; then
  moves=$(jq -r --argjson live "$live" --argjson mons "$monitors" '
    to_entries[]
    | select(.value as $m | $mons | index($m))
    | select($live[.key] != null and $live[.key] != .value)
    | "hl.dsp.workspace.move({ workspace = \"\(.key)\", monitor = \"\(.value)\" })"
  ' <<<"$saved")
  while IFS= read -r move; do
    [[ -n "$move" ]] && hyprctl dispatch "$move" >/dev/null
  done <<<"$moves"
  [[ -n "$moves" ]] && live=$(live_layout)
fi

# Live wins, except for workspaces parked on a fallback monitor while their own
# is unplugged.
merged=$(jq -c --argjson live "$live" --argjson mons "$monitors" '
  . as $saved
  | . + ($live | with_entries(select(($saved[.key] // null) as $m | $m == null or ($mons | index($m)))))
' <<<"$saved")
[[ "$merged" != "$saved" ]] && echo "$merged" >"$state"

# One eval for every rule, only for monitors that are connected.
rules=$(jq -r --argjson mons "$monitors" --argjson keep "$keep_alive" '
  to_entries[]
  | select(.value as $m | $mons | index($m))
  | "hl.workspace_rule({ workspace = \"\(.key)\", monitor = \"\(.value)\", persistent = \((.key | tonumber) <= $keep) })"
' <<<"$merged")
[[ -n "$rules" ]] && hyprctl eval "$rules" >/dev/null
exit 0
