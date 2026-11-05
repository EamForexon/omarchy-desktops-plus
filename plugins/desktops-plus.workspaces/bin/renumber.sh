#!/bin/bash
# Give the active workspace a new number without changing monitors.
# Its windows move to workspace N on the same monitor. If N already had windows,
# they swap into the old number and stay on the monitor N was on.

set -euo pipefail

target="${1:?usage: renumber.sh <workspace>}"

dispatch() { hyprctl dispatch "$1" >/dev/null; }

active=$(hyprctl activeworkspace -j)
current=$(jq -r '.id' <<<"$active")
current_mon=$(jq -r '.monitor' <<<"$active")

[[ "$target" == "$current" ]] && exit 0

clients=$(hyprctl clients -j)
current_wins=$(jq -r --argjson ws "$current" '.[] | select(.workspace.id == $ws) | .address' <<<"$clients")
target_wins=$(jq -r --argjson ws "$target" '.[] | select(.workspace.id == $ws) | .address' <<<"$clients")
target_mon=$(hyprctl workspaces -j | jq -r --argjson ws "$target" '.[] | select(.id == $ws) | .monitor')

# Omarchy stores the tiling layout per workspace number
# (omarchy-hyprland-workspace-layout-toggle), so swap it along with the windows.
layouts_dir="$HOME/.local/state/omarchy/workspace-layouts"
default_layout=$(hyprctl getoption general:layout -j | jq -r '.str')
layout_of() {
  local file="$layouts_dir/$1.lua"
  if [[ -f "$file" ]]; then
    sed -n 's/.*layout = "\([^"]*\)".*/\1/p' "$file"
  else
    echo "$default_layout"
  fi
}
set_layout() {
  mkdir -p "$layouts_dir"
  printf 'hl.workspace_rule({ workspace = "%s", layout = "%s" })\n' "$1" "$2" >"$layouts_dir/$1.lua"
  hyprctl eval "hl.workspace_rule({ workspace = \"$1\", layout = \"$2\" })" >/dev/null
}

current_layout=$(layout_of "$current")
target_layout=$(layout_of "$target")
if [[ "$current_layout" != "$target_layout" ]]; then
  set_layout "$target" "$current_layout"
  set_layout "$current" "$target_layout"
fi

for addr in $current_wins; do
  dispatch "hl.dsp.window.move({ workspace = \"$target\", follow = false, window = \"address:$addr\" })"
done
for addr in $target_wins; do
  dispatch "hl.dsp.window.move({ workspace = \"$current\", follow = false, window = \"address:$addr\" })"
done

# Only touch monitors when the target number lives on another one.
new_target_mon=$(hyprctl workspaces -j | jq -r --argjson ws "$target" '.[] | select(.id == $ws) | .monitor')
if [[ -n "$new_target_mon" && "$new_target_mon" != "$current_mon" ]]; then
  dispatch "hl.dsp.workspace.move({ workspace = \"$target\", monitor = \"$current_mon\" })"
  if [[ -n "$target_wins" ]]; then
    dispatch "hl.dsp.workspace.move({ workspace = \"$current\", monitor = \"$target_mon\" })"
  fi
fi

dispatch "hl.dsp.focus({ workspace = \"$target\" })"
