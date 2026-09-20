local player_state = require("scripts.player_state")
local gui = require("scripts.gui")
local core = require("scripts.core")
local utils = require("scripts.utils")

local function refresh_all()
    storage.players = storage.players or {}
    for _, player in pairs(game.players) do
        player_state.refresh(player)
        gui.refresh(player)
    end
end

local function refresh_player(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    local state = player_state.get(player.index)
    player_state.stop_mining(player, state)
    player_state.refresh(player)
    gui.refresh(player)
end

local function check_permissions(player)
    if not player or not player.valid then return end
    player_state.enforce(player)
    gui.refresh(player)
end

script.on_init(refresh_all)
script.on_configuration_changed(refresh_all)
script.on_event(defines.events.on_player_created, refresh_player)
script.on_event(defines.events.on_player_joined_game, refresh_player)
script.on_event(defines.events.on_player_demoted, refresh_player)
script.on_event(defines.events.on_player_controller_changed, refresh_player)
script.on_event(defines.events.on_player_changed_surface, refresh_player)
script.on_event(defines.events.on_tick, core.on_tick)

script.on_event(defines.events.on_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        player_state.stop_mining(player, player_state.get(player.index))
    end
end)

script.on_event(defines.events.on_player_removed, function(event)
    if storage.players then storage.players[event.player_index] = nil end
end)

script.on_nth_tick(1800, function()
    for _, player in pairs(game.connected_players) do check_permissions(player) end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "fbp-allow-others" then
        for _, player in pairs(game.connected_players) do check_permissions(player) end
    elseif event.player_index and (event.setting == "fbp-speed"
        or event.setting == "fbp-scan-radius" or event.setting == "fbp-enable-for-me") then
        refresh_player(event)
    end
end)

script.on_event("fbp-open-config", gui.toggle_config_gui)
script.on_event(defines.events.on_gui_click, gui.handle_gui_click)
script.on_event(defines.events.on_gui_checked_state_changed, gui.handle_gui_checked_state_changed)

script.on_event(defines.events.on_lua_shortcut, function(event)
    local deconstruct = event.prototype_name == "fbp-deconstruct-toggle"
    if not deconstruct and event.prototype_name ~= "fbp-toggle" then return end
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end
    local key = deconstruct and "deconstruct_active" or "active"
    local state = player_state.get(player.index)
    state = player_state.set_active(player, key, not state[key])
    local group = deconstruct and "deconstruct" or "printer"
    player.create_local_flying_text({
        text = {"fbp-message." .. group .. (state[key] and "-active" or "-inactive")},
        position = player.position
    })
    gui.refresh(player)
    if state.active then
        local inventory = player.get_main_inventory()
        if not inventory or not inventory.valid then
            player.print({"fbp-message.no-inventory-chat"})
        end
    end
    utils.debug_print(player, {"message." .. (deconstruct and "deconstruction" or "printer")
        .. (state[key] and "_activated" or "_deactivated")})
end)

commands.add_command("fbp-check", {"message.diagnostic_command_desc"}, function(command)
    if not command.player_index then return end
    local player = game.get_player(command.player_index)
    if not player or not player.valid then return end
    local state = player_state.get(player.index)
    local allowed, reason = player_state.allowed(player)
    local personal = settings.get_player_settings(player)
    player.print({"message.diagnostic_header"})
    player.print({"message.player_name", player.name})
    player.print({"message.player_index", player.index})
    player.print({"message.player_connected", tostring(player.connected)})
    player.print({"message.controller_type", tostring(player.controller_type)})
    player.print({"message.admin_status", tostring(player.admin)})
    player.print({"message.allow_others_setting", tostring(settings.global["fbp-allow-others"].value)})
    player.print({"message.player_enabled_setting", tostring(personal["fbp-enable-for-me"].value)})
    player.print({"message.active_state", tostring(state.active)})
    player.print({"message.deconstruct_state", tostring(state.deconstruct_active)})
    player.print({"message.permission_allowed", tostring(allowed)})
    player.print({"message.permission_reason", reason or "none"})
    if player.controller_type == defines.controllers.editor then
        player.print({"message.editor_blocked"})
    end
    local inventory = player.get_main_inventory()
    player.print({inventory and inventory.valid and "message.inventory_valid" or "message.inventory_invalid"})
end)
