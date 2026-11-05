-- Omarchy Desktops+ keybindings. Load from ~/.config/hypr/bindings.lua with:
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/desktops-plus.workspaces/hypr/bindings.lua")

local plugin = os.getenv("HOME") .. "/.config/omarchy/plugins/desktops-plus.workspaces"

-- SUPER+SHIFT+ALT+SPACE: overview of every workspace, per monitor.
o.bind("SUPER + SHIFT + ALT + SPACE", "Workspace overview", "omarchy-shell shell toggle desktops-plus.workspaces")

-- SUPER+ALT+number: renumber the active workspace, keeping its monitor
-- (swaps with the target if it has windows). Was: switch to group window 1-5.
for workspace = 1, 10 do
  local key = "SUPER + ALT + code:" .. tostring(workspace + 9)
  hl.unbind(key)
  o.bind(key, "Renumber workspace to " .. workspace, plugin .. "/bin/renumber.sh " .. workspace)
end

-- SUPER+ALT+arrows: move the active workspace to the monitor in that direction
-- (same as SUPER+SHIFT+ALT+arrows). Was: move window into group.
for _, dir in ipairs({ { "LEFT", "l", "left" }, { "RIGHT", "r", "right" }, { "UP", "u", "up" }, { "DOWN", "d", "down" } }) do
  local key = "SUPER + ALT + " .. dir[1]
  hl.unbind(key)
  o.bind(key, "Move workspace to " .. dir[3] .. " monitor", hl.dsp.workspace.move({ monitor = dir[2] }))
end

-- SUPER+SHIFT+ALT with numbers/arrows does nothing; use SUPER+SHIFT or SUPER+ALT.
for workspace = 1, 10 do
  hl.unbind("SUPER + SHIFT + ALT + code:" .. tostring(workspace + 9))
end
for _, key in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
  hl.unbind("SUPER + SHIFT + ALT + " .. key)
end
