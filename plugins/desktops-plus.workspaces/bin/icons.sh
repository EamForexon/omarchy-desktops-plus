#!/bin/bash
# Resolve an icon for each Hyprland window.
# stdin: `hyprctl -j clients`; stdout: { "<address>": { "glyph": hex, "mono": path, "color": path } }
#   glyph = Nerd Font codepoint, for brands Simple Icons doesn't carry
#   mono  = monochrome brand SVG from Simple Icons (tinted by the overview)
#   color = the app's own themed icon, used desaturated when there's no mono one

simple_icons="$HOME/.local/share/simple-icons/icons"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/desktops-plus"
color_cache="$cache_dir/color-icons.tsv"
desktop_cache="$cache_dir/desktop-entries.tsv"
mkdir -p "$cache_dir"
for f in "$color_cache" "$desktop_cache"; do [[ -e "$f" ]] || : >"$f"; done

app_dirs=(
  "$HOME/.local/share/applications"
  "$HOME/.local/share/flatpak/exports/share/applications"
  /var/lib/flatpak/exports/share/applications
  /usr/share/applications
)
icon_dirs=(
  "$HOME/.local/share/icons"
  "$HOME/.icons"
  "$HOME/.local/share/flatpak/exports/share/icons"
  /var/lib/flatpak/exports/share/icons
  /usr/share/icons
)

# Installing or removing an app touches its applications dir: start over.
for dir in "${app_dirs[@]}"; do
  if [[ -d "$dir" && "$dir" -nt "$desktop_cache" ]]; then
    : >"$desktop_cache"
    : >"$color_cache"
    break
  fi
done

# Nerd Font glyphs for brands missing from Simple Icons (e.g. Microsoft's).
declare -A glyphs=(
  [code-oss]=f0a1e [code]=f0a1e [visual-studio-code]=f0a1e
)

# Classes/processes whose Simple Icons slug isn't derivable from their name.
declare -A aliases=(
  [code-oss]=vscodium [code]=vscodium [codium]=vscodium [cursor]=cursor
  [vesktop]=discord [webcord]=discord [legcord]=discord
  [godot]=godotengine
  [foot]=gnometerminal [kitty]=gnometerminal [ghostty]=ghostty
  [org.omarchy.agent]=gnometerminal
  [nvim]=neovim [vim]=vim [node]=nodedotjs [python3]=python [btop]=gnometerminal
  [lazygit]=git [lazydocker]=docker [spotify_player]=spotify [ncspot]=spotify
  [steam]=steam [obs]=obsstudio [com.obsproject.studio]=obsstudio
  [org.gnome.nautilus]=gnome [nautilus]=gnome [mpv]=mpv [imv]=gnome
)
browsers=" firefox chromium google-chrome brave-browser zen librewolf vivaldi-stable "
terminals=" foot alacritty kitty ghostty org.omarchy.agent wezterm "
shells=" bash zsh fish sh tmux zellij sudo "

# Simple Icons slug rules: lowercase, "+" -> plus, "." -> dot, "&" -> and, drop the rest.
slug_of() {
  local s="${1,,}"
  s="${s//+/plus}"; s="${s//&/and}"
  local dotted="${s//./dot}"
  echo "${dotted//[^a-z0-9]/}"
  echo "${s//[^a-z0-9]/}"
}

mono_for() {
  local name slug
  for name in "$@"; do
    [[ -z "$name" ]] && continue
    [[ -n "${aliases[${name,,}]:-}" ]] && name="${aliases[${name,,}]}"
    while read -r slug; do
      [[ -n "$slug" && -f "$simple_icons/$slug.svg" ]] && { echo "$simple_icons/$slug.svg"; return; }
    done < <(slug_of "$name"; slug_of "${name##*.}")
  done
}

# One snapshot of the process tree, read only when a terminal needs it.
declare -A children=() comms=()
process_tree_loaded=0
load_process_tree() {
  (( process_tree_loaded )) && return
  process_tree_loaded=1
  local pid ppid comm
  while read -r pid ppid comm; do
    comms[$pid]="$comm"
    children[$ppid]+="$pid "
  done < <(ps -eo pid=,ppid=,comm=)
}

# Commands running under a pid (depth-first), most interesting first.
descendant_cmds() {
  local pid
  for pid in ${children[$1]:-}; do
    [[ " $shells " != *" ${comms[$pid]} "* ]] && echo "${comms[$pid]}"
    descendant_cmds "$pid"
  done
}

# Cached per class: scanning every .desktop file is the slow part.
desktop_entry() {
  local class="$1" file
  file=$(awk -F'\t' -v c="$class" '$1 == c { print $2; found = 1; exit } END { exit !found }' "$desktop_cache") && { echo "$file"; return; }
  file=$(grep -lisx -R --include="*.desktop" "StartupWMClass=$class" "${app_dirs[@]}" 2>/dev/null | head -n1)
  if [[ -z "$file" ]]; then
    for dir in "${app_dirs[@]}"; do
      file=$(find -L "$dir" -maxdepth 1 -iname "$class.desktop" 2>/dev/null | head -n1)
      [[ -n "$file" ]] && break
    done
  fi
  printf '%s\t%s\n' "$class" "$file" >>"$desktop_cache"
  echo "$file"
}

icon_file() {
  local name="$1" found
  [[ "$name" == /* && -f "$name" ]] && { echo "$name"; return; }
  # Prefer scalable, then the biggest raster.
  found=$(find -L "${icon_dirs[@]}" -path "*/apps/*" \( -name "$name.svg" -o -name "$name.png" \) 2>/dev/null \
    | awk '{ size = 0; if ($0 ~ /scalable/) size = 9999; else if (match($0, /[0-9]+x[0-9]+/)) size = substr($0, RSTART, index(substr($0, RSTART), "x") - 1); print size "\t" $0 }' \
    | sort -rn | head -n1 | cut -f2)
  [[ -z "$found" ]] && found=$(find /usr/share/pixmaps -maxdepth 1 \( -name "$name.svg" -o -name "$name.png" \) 2>/dev/null | head -n1)
  echo "$found"
}

color_for() {
  local class="$1" cached path=""
  cached=$(awk -F'\t' -v c="$class" '$1 == c { print $2; found = 1; exit } END { exit !found }' "$color_cache") && { echo "$cached"; return; }
  local file icon
  file=$(desktop_entry "$class")
  [[ -n "$file" ]] && icon=$(sed -n 's/^Icon=//p' "$file" | head -n1)
  [[ -n "$icon" ]] && path=$(icon_file "$icon")
  [[ -z "$path" ]] && path=$(icon_file "${class,,}")
  printf '%s\t%s\n' "$class" "$path" >>"$color_cache"
  echo "$path"
}

while IFS=$'\t' read -r address class pid title; do
  lower="${class,,}"
  candidates=()

  # What's running inside a terminal (e.g. claude, nvim) beats the terminal itself.
  if [[ "$terminals" == *" $lower "* ]]; then
    load_process_tree
    mapfile -t cmds < <(descendant_cmds "$pid")
    candidates+=("${cmds[@]}")
  fi

  # Browsers: the site in the title (WhatsApp, YouTube, GitHub…).
  if [[ "$browsers" == *" $lower "* ]]; then
    IFS=$'\x1f' read -ra parts <<<"$(sed -E 's/ [—–|·-] /\x1f/g' <<<"$title")"
    for (( i = ${#parts[@]} - 1; i >= 0; i-- )); do
      part="${parts[i]}"
      part="${part#(*) }"
      [[ "${part,,}" == *firefox* || "${part,,}" == *chrom* ]] && continue
      candidates+=("$part")
    done
  fi

  candidates+=("$class")
  file=$(desktop_entry "$class")
  if [[ -n "$file" ]]; then
    candidates+=("$(sed -n 's/^Name=//p' "$file" | head -n1)" "$(sed -n 's/^Icon=//p' "$file" | head -n1)")
  fi

  glyph="${glyphs[$lower]:-}"
  mono="" color=""
  [[ -z "$glyph" ]] && mono=$(mono_for "${candidates[@]}")
  [[ -z "$glyph" && -z "$mono" ]] && color=$(color_for "$class")
  printf '%s\t%s\t%s\t%s\n' "$address" "$glyph" "$mono" "$color"
done < <(jq -r '.[] | [.address, .class, (.pid | tostring), .title] | @tsv') \
  | jq -Rn '[inputs | split("\t") | {key: .[0], value: {glyph: .[1], mono: .[2], color: .[3]}}] | from_entries' 
