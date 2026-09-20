local player_state = require("scripts.player_state")

local gui = {}
local FEATURES = {"auto_place", "auto_upgrade", "auto_deconstruct", "auto_modules", "auto_landfill"}

function gui.refresh(player)
    local frame = player.gui.screen["fbp-config-frame"]
    if not frame then return end
    local state = player_state.get(player.index)
    for _, key in ipairs(FEATURES) do
        local checkbox = frame["fbp-feature-" .. key]
        if checkbox then checkbox.state = state.features[key] end
    end
end

function gui.destroy_config_gui(player)
    local frame = player.gui.screen["fbp-config-frame"]
    if frame then frame.destroy() end
end

function gui.create_config_gui(player)
    if player.gui.screen["fbp-config-frame"] then return end
    local state = player_state.get(player.index)
    local frame = player.gui.screen.add{
        type = "frame", name = "fbp-config-frame",
        caption = {"fbp-gui.config-title"}, direction = "vertical"
    }
    frame.auto_center = true
    frame.add{type = "button", name = "fbp-config-close", caption = {"fbp-gui.close"}}
    for _, key in ipairs(FEATURES) do
        frame.add{
            type = "checkbox", name = "fbp-feature-" .. key,
            caption = {"fbp-gui." .. key:gsub("_", "-")}, state = state.features[key]
        }
    end
end

function gui.toggle_config_gui(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    if player.gui.screen["fbp-config-frame"] then
        gui.destroy_config_gui(player)
    else
        gui.create_config_gui(player)
    end
end

function gui.handle_gui_click(event)
    local element = event.element
    if not element or not element.valid or element.name ~= "fbp-config-close" then return end
    local player = game.get_player(event.player_index)
    if player and player.valid then gui.destroy_config_gui(player) end
end

function gui.handle_gui_checked_state_changed(event)
    local element = event.element
    if not element or not element.valid then return end
    local key = element.name:match("^fbp%-feature%-(.+)$")
    if not key then return end
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    player_state.set_feature(player, key, element.state)
    gui.refresh(player)
end

return gui
