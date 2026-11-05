#!/bin/bash
# Install Omarchy Desktops+.
#
#   ./install.sh               copy the plugins and apply the bar preset
#   ./install.sh --keep-layout install the plugins but leave your bar layout alone
#   ./install.sh --link        symlink the plugins to this checkout (development)
#   ./install.sh --uninstall   remove the plugins and restore the backed-up config
#
# Re-run to update. Your shell.json and hypr/bindings.lua are backed up first.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugins_dir="$HOME/.config/omarchy/plugins"
shell_json="$HOME/.config/omarchy/shell.json"
bindings="$HOME/.config/hypr/bindings.lua"
backups="$HOME/.config/omarchy/plugin-backups"
last_backup_file="${XDG_STATE_HOME:-$HOME/.local/state}/desktops-plus/last-backup"
bindings_line='dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/desktops-plus.workspaces/hypr/bindings.lua")'
simple_icons="$HOME/.local/share/simple-icons"

mode=copy
keep_layout=0
for arg in "$@"; do
  case "$arg" in
  --link) mode=link ;;
  --keep-layout) keep_layout=1 ;;
  --uninstall) mode=uninstall ;;
  -h | --help) sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 0 ;;
  *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

for cmd in jq hyprctl omarchy-shell; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd: this needs Omarchy 4 with Hyprland." >&2; exit 1; }
done

plugin_ids=()
for dir in "$repo"/plugins/*/; do
  plugin_ids+=("$(basename "$dir")")
done

restart() {
  hyprctl reload >/dev/null || true
  omarchy restart shell >/dev/null 2>&1 || true
}

if [[ "$mode" == uninstall ]]; then
  for id in "${plugin_ids[@]}"; do
    rm -rf "${plugins_dir:?}/$id"
  done
  [[ -f "$bindings" ]] && sed -i "\|desktops-plus.workspaces/hypr/bindings.lua|d; \|^-- Omarchy Desktops+|d" "$bindings"
  if [[ -f "$last_backup_file" && -f "$(<"$last_backup_file")/shell.json" ]]; then
    cp "$(<"$last_backup_file")/shell.json" "$shell_json"
    echo "Restored shell.json from $(<"$last_backup_file")"
  else
    echo "No backup found; reset the bar with: omarchy bar reset"
  fi
  restart
  echo "Omarchy Desktops+ removed."
  exit 0
fi

# Back up what we're about to touch.
backup="$backups/desktops-plus-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup" "$(dirname "$last_backup_file")"
[[ -f "$shell_json" ]] && cp "$shell_json" "$backup/"
[[ -f "$bindings" ]] && cp "$bindings" "$backup/"
# Only the first install's backup is the one to restore on uninstall.
[[ -f "$last_backup_file" ]] || echo "$backup" >"$last_backup_file"

# Plugins.
mkdir -p "$plugins_dir"
for id in "${plugin_ids[@]}"; do
  target="$plugins_dir/$id"
  if [[ -e "$target" && ! -L "$target" ]]; then
    mkdir -p "$backup/plugins"
    mv "$target" "$backup/plugins/"
  fi
  rm -f "$target"
  if [[ "$mode" == link ]]; then
    ln -s "$repo/plugins/$id" "$target"
  else
    cp -r "$repo/plugins/$id" "$target"
  fi
done
echo "Installed ${#plugin_ids[@]} plugins ($mode)."

# Bar: the preset layout, or just swap in our bar and widget ids.
[[ -f "$shell_json" ]] || echo '{}' >"$shell_json"
if (( keep_layout )); then
  jq '.bar.id = "desktops-plus.bar"
    | .bar.layout |= ((. // {}) | with_entries(.value |= map(if .id == "omarchy.workspaces" then .id = "desktops-plus.workspaces" else . end)))
    | if .bar.centerAnchor == "omarchy.workspaces" then .bar.centerAnchor = "desktops-plus.workspaces" else . end' \
    "$shell_json" >"$shell_json.tmp"
  # The overview and workspace service ride on the workspaces widget; make sure it's somewhere.
  if ! jq -e '[.bar.layout[]?[]?.id] | index("desktops-plus.workspaces")' "$shell_json.tmp" >/dev/null; then
    jq '.bar.layout.center = ([{id: "desktops-plus.workspaces"}] + (.bar.layout.center // []))' "$shell_json.tmp" >"$shell_json.tmp2"
    mv "$shell_json.tmp2" "$shell_json.tmp"
  fi
else
  jq --slurpfile preset "$repo/presets/bar.json" '.bar = ((.bar // {}) + $preset[0])' "$shell_json" >"$shell_json.tmp"
fi
mv "$shell_json.tmp" "$shell_json"
echo "Bar configured."

# Keybindings.
if [[ -f "$bindings" ]] && ! grep -qF "$bindings_line" "$bindings"; then
  printf '\n-- Omarchy Desktops+: overview, renumber and move-workspace bindings.\n%s\n' "$bindings_line" >>"$bindings"
  echo "Keybindings added to $bindings."
fi

# Brand icons for the overview (optional; it falls back to app icons).
if [[ ! -d "$simple_icons/icons" ]] && command -v curl >/dev/null; then
  echo "Downloading Simple Icons for the overview..."
  tarball=$(curl -fsSL https://registry.npmjs.org/simple-icons/latest | jq -r '.dist.tarball') &&
    mkdir -p "$simple_icons" &&
    curl -fsSL "$tarball" | tar -xz -C "$simple_icons" --strip-components=1 package/icons package/package.json ||
    echo "Couldn't download Simple Icons; the overview will use app icons instead."
fi

restart
echo
echo "Done. Backup: $backup"
echo "Optional, for RAM speed and real CPU power in system stats:"
echo "  sudo $plugins_dir/desktops-plus.system-stats/bin/root-sensors-setup"
