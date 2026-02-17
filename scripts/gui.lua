local utils = require("scripts.utils")

local gui = {}

gui.FEATURE_LABELS = {
    {key = "auto_place", caption = {"fbp-gui.auto-place"}},
    {key = "auto_upgrade", caption = {"fbp-gui.auto-upgrade"}},
    {key = "auto_deconstruct", caption = {"fbp-gui.auto-deconstruct"}},
    {key = "auto_mine", caption = {"fbp-gui.auto-mine"}},
    {key = "auto_modules", caption = {"fbp-gui.auto-modules"}},
    {key = "auto_landfill", caption = {"fbp-gui.auto-landfill"}}
}

function gui.create_config_gui(player)
    if player.gui.screen["fbp-config-frame"] then return end

    local player_index = player.index
    utils.ensure_player_storage(player_index)
    local p_data = storage.players[player_index]

    local frame = player.gui.screen.add{
        type = "frame",
        name = "fbp-config-frame",
        caption = "FBP Configuration",
        direction = "vertical"
    }
    frame.auto_center = true

    frame.add{
        type = "button",
        name = "fbp-config-close",
        caption = "Close"
    }

    for _, feat in pairs(gui.FEATURE_LABELS) do
        frame.add{
            type = "checkbox",
            name = "fbp-feature-" .. feat.key,
            caption = feat.caption,
            state = p_data.features[feat.key] or false
        }
    end
end

function gui.destroy_config_gui(player)
    local frame = player.gui.screen["fbp-config-frame"]
    if frame then
        frame.destroy()
    end
end

function gui.toggle_config_gui(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    if player.gui.screen["fbp-config-frame"] then
        gui.destroy_config_gui(player)
    else
        gui.create_config_gui(player)
    end
end

function gui.handle_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end
    if element.name == "fbp-config-close" then
        local player = game.get_player(event.player_index)
        if player then
            gui.destroy_config_gui(player)
        end
    end
end

function gui.handle_gui_checked_state_changed(event)
    local element = event.element
    if not element or not element.valid then return end
    if not element.name or not element.name:find("^fbp%-feature%-") then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    utils.ensure_player_storage(event.player_index)
    local p_data = storage.players[event.player_index]

    local feature_key = element.name:gsub("^fbp%-feature%-", "")
    if p_data.features[feature_key] ~= nil then
        p_data.features[feature_key] = element.state
    end
end

return gui
