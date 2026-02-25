local utils = require("scripts.utils")
local gui = require("scripts.gui")
local core = require("scripts.core")

local function debug_print(player, msg)
    utils.debug_print(player, msg)
end

local function ensure_player_storage(index)
    utils.ensure_player_storage(index)
end

local function check_active_permissions(player, index)
    if not player or not player.valid then
        core.check_active_permissions(player, index)
        return
    end

    ensure_player_storage(index)
    local p_data = storage.players[index]
    local had_active = p_data.active and true or false

    core.check_active_permissions(player, index)

    local allowed, reason = utils.is_allowed(player)
    if allowed then return end

    p_data = storage.players[index]
    if not p_data then return end

    local had_deconstruct = (p_data.deconstruct_active or (p_data.features and (p_data.features.auto_deconstruct or p_data.features.auto_mine))) and true or false
    p_data.deconstruct_active = false
    if p_data.features then
        p_data.features.auto_deconstruct = false
        p_data.features.auto_mine = false
    end
    player.set_shortcut_toggled("fbp-deconstruct-toggle", false)

    if had_deconstruct and not had_active then
        local msg_key = "fbp-message." .. (reason or "admin-only")
        debug_print(player, {msg_key})
        player.create_local_flying_text({text={msg_key}, create_at_cursor=true})
    end
end

local function on_init()
    storage.players = {}
    for index, player in pairs(game.players) do
        ensure_player_storage(index)
        local p_data = storage.players[index]
        if player.valid then
            local settings_obj = settings.get_player_settings(player)
            p_data.scan_radius = settings_obj["fbp-scan-radius"].value
            p_data.speed = settings_obj["fbp-speed"].value
        end
    end
end

local function on_configuration_changed(data)
    if not storage.players then
        storage.players = {}
    end
    
    for index, player in pairs(game.players) do
        ensure_player_storage(index)
        local p_data = storage.players[index]

        if not p_data.features then
            p_data.features = {
                auto_place = true,
                auto_upgrade = true,
                auto_deconstruct = false,
                auto_mine = false,
                auto_modules = true,
                auto_landfill = true
            }
        end

        if p_data.features.auto_deconstruct == nil then
            p_data.features.auto_deconstruct = false
        end

        if p_data.features.auto_mine == nil then
            p_data.features.auto_mine = false
        end

        local migrated_deconstruct_state
        if p_data.deconstruct_active ~= nil then
            migrated_deconstruct_state = p_data.deconstruct_active
        elseif p_data.features.auto_deconstruct ~= nil then
            migrated_deconstruct_state = p_data.features.auto_deconstruct
        elseif p_data.features.auto_mine ~= nil then
            migrated_deconstruct_state = p_data.features.auto_mine
        else
            migrated_deconstruct_state = false
        end

        p_data.deconstruct_active = migrated_deconstruct_state and true or false
        p_data.features.auto_deconstruct = p_data.deconstruct_active
        p_data.features.auto_mine = p_data.deconstruct_active
        
        if player.valid then
            local settings_obj = settings.get_player_settings(player)
            p_data.scan_radius = settings_obj["fbp-scan-radius"].value
            p_data.speed = settings_obj["fbp-speed"].value
        end
    end
end

local function on_player_created(event)
    ensure_player_storage(event.player_index)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        local p_data = storage.players[event.player_index]
        local settings_obj = settings.get_player_settings(player)
        p_data.scan_radius = settings_obj["fbp-scan-radius"].value
        p_data.speed = settings_obj["fbp-speed"].value
    end
end

local function on_player_joined_game(event)
    local player = game.get_player(event.player_index)
    check_active_permissions(player, event.player_index)
    
    if player and player.valid then
        ensure_player_storage(event.player_index)
        local p_data = storage.players[event.player_index]
        local settings_obj = settings.get_player_settings(player)
        p_data.scan_radius = settings_obj["fbp-scan-radius"].value
        p_data.speed = settings_obj["fbp-speed"].value
    end
end

local function on_tick(event)
    for index, player in pairs(game.connected_players) do
        local p_data = storage.players[index]
        if p_data then
            if p_data.deconstruct_active == nil then
                p_data.deconstruct_active = (p_data.features and (p_data.features.auto_deconstruct or p_data.features.auto_mine)) and true or false
            end

            local speed = p_data.speed or 1
            if speed < 1 then speed = 1 end
            
            if (event.tick + index) % speed == 0 then
                local deconstruct_active = p_data.deconstruct_active and true or false
                if p_data.features then
                    p_data.features.auto_deconstruct = deconstruct_active
                    p_data.features.auto_mine = deconstruct_active
                end

                local arbitration_context = {
                    consumed_positions = {}
                }

                if p_data.active and p_data.features and p_data.features.auto_place then
                    core.process_auto_place(player, p_data, 5, arbitration_context)
                end
                if p_data.active and p_data.features and p_data.features.auto_upgrade then
                    core.process_upgrades(player, 5, arbitration_context)
                end
                if deconstruct_active then
                    core.process_deconstruction(player, arbitration_context)
                end
            end
        end
    end
end

script.on_init(on_init)
script.on_configuration_changed(on_configuration_changed)
script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(defines.events.on_player_joined_game, on_player_joined_game)
script.on_event(defines.events.on_tick, on_tick)

script.on_nth_tick(1800, function()
    for index, player in pairs(game.connected_players) do
        local player = game.get_player(index)
        if player and player.valid then
            check_active_permissions(player, index)
        end
    end
end)

script.on_event(defines.events.on_player_demoted, function(event)
    local player = game.get_player(event.player_index)
    check_active_permissions(player, event.player_index)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    ensure_player_storage(event.player_index)
    local p_data = storage.players[event.player_index]
    
    if event.setting == "fbp-speed" then
        p_data.speed = settings.get_player_settings(player)["fbp-speed"].value
    elseif event.setting == "fbp-scan-radius" then
        p_data.scan_radius = settings.get_player_settings(player)["fbp-scan-radius"].value
    elseif event.setting == "fbp-enable-for-me" then
         check_active_permissions(player, event.player_index)
    end
end)

script.on_event("fbp-open-config", gui.toggle_config_gui)
script.on_event(defines.events.on_gui_click, gui.handle_gui_click)
script.on_event(defines.events.on_gui_checked_state_changed, gui.handle_gui_checked_state_changed)

script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "fbp-toggle" then
        local player = game.get_player(event.player_index)
        if not player then return end

        local allowed, reason = utils.is_allowed(player)
        if not allowed then
            local msg_key = "fbp-message." .. (reason or "admin-only")
            debug_print(player, {msg_key})
            player.create_local_flying_text({text={msg_key}, create_at_cursor=true})
            player.set_shortcut_toggled("fbp-toggle", false)
            if storage.players[event.player_index] then
                storage.players[event.player_index].active = false
            end
            return
        end

        ensure_player_storage(event.player_index)
        local p_data = storage.players[event.player_index]
        p_data.active = not p_data.active

        player.set_shortcut_toggled("fbp-toggle", p_data.active)

        if p_data.active then
            debug_print(player, {"message.printer_activated"})
            player.create_local_flying_text({text = {"fbp-message.printer-active"}, position = player.position})

            local inventory = player.get_main_inventory()
            if not inventory or not inventory.valid then
                player.print({"fbp-message.no-inventory-chat"})
                player.create_local_flying_text({text = {"fbp-message.no-inventory-flying"}, position = player.position, color = {1, 0, 0}, create_at_cursor = false})
            end
        else
            debug_print(player, {"message.printer_deactivated"})
            player.create_local_flying_text({text = {"fbp-message.printer-inactive"}, position = player.position})
        end
        return
    elseif event.prototype_name == "fbp-deconstruct-toggle" then
        local player = game.get_player(event.player_index)
        if not player then return end

        local allowed, reason = utils.is_allowed(player)
        if not allowed then
            local msg_key = "fbp-message." .. (reason or "admin-only")
            debug_print(player, {msg_key})
            player.create_local_flying_text({text={msg_key}, create_at_cursor=true})
            player.set_shortcut_toggled("fbp-deconstruct-toggle", false)
            if storage.players[event.player_index] then
                storage.players[event.player_index].deconstruct_active = false
                if storage.players[event.player_index].features then
                    storage.players[event.player_index].features.auto_deconstruct = false
                    storage.players[event.player_index].features.auto_mine = false
                end
            end
            return
        end

        ensure_player_storage(event.player_index)
        local p_data = storage.players[event.player_index]
        local new_state = not (p_data.deconstruct_active or false)
        p_data.deconstruct_active = new_state
        p_data.features.auto_deconstruct = new_state
        p_data.features.auto_mine = new_state

        player.set_shortcut_toggled("fbp-deconstruct-toggle", new_state)

        if new_state then
            debug_print(player, {"message.deconstruction_activated"})
            player.create_local_flying_text({text = {"fbp-message.deconstruct-active"}, position = player.position})
        else
            debug_print(player, {"message.deconstruction_deactivated"})
            player.create_local_flying_text({text = {"fbp-message.deconstruct-inactive"}, position = player.position})
        end
    end
end)

commands.add_command("fbp-check", {"message.diagnostic_command_desc"}, function(cmd)
    local player = game.get_player(cmd.player_index)
    if not player or not player.valid then return end
    
    player.print("=== FBP Diagnostic Check ===")
    player.print({"message.player_name", player.name})
    player.print({"message.controller_type", tostring(player.controller_type)})
    player.print({"message.admin_status", tostring(player.admin)})
    
    local player_settings = settings.get_player_settings(player)
    if player_settings and player_settings["fbp-enable-for-me"] then
        player.print({"message.player_enabled_setting", tostring(player_settings["fbp-enable-for-me"].value)})
    else
        player.print("Player setting fbp-enable-for-me not found")
    end
    
    ensure_player_storage(cmd.player_index)
    local p_data = storage.players[cmd.player_index]
    player.print({"message.active_state", tostring(p_data.active)})
    
    local inventory = player.get_main_inventory()
    if inventory and inventory.valid then
        player.print({"message.inventory_valid"})
    else
        player.print({"message.inventory_invalid"})
    end
    player.print("============================")
end)
