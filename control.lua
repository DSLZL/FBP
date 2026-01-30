local function debug_print(player, msg)
    if settings.get_player_settings(player)["fbp-debug-mode"].value then
        player.print("[FBP Debug] " .. tostring(msg))
    end
end

local function ensure_player_storage(player_index)
    if not storage.players then
        storage.players = {}
    end
    if not storage.players[player_index] then
        storage.players[player_index] = {
            active = false,
            speed = 1
        }
    end
end

local function is_allowed(player)
    if player.admin then return true end
    return settings.global["fbp-allow-others"].value
end

local function check_active_permissions(player, player_index)
    if not player or not player.valid then return end
    ensure_player_storage(player_index)
    local p_data = storage.players[player_index]
    
    if p_data.active and not is_allowed(player) then
        debug_print(player, "Permissions denied: admin-only")
        p_data.active = false
        player.set_shortcut_toggled("fbp-toggle", false)
        player.create_local_flying_text({text={"fbp-message.admin-only"}, create_at_cursor=true})
    end
end

local function on_init()
    storage.players = {}
    
    for index, _ in pairs(game.players) do
        ensure_player_storage(index)
    end
end

local function on_configuration_changed(data)
    if not storage.players then
        storage.players = {}
    end
    
    for index, _ in pairs(game.players) do
        ensure_player_storage(index)
    end
end

local function on_player_created(event)
    ensure_player_storage(event.player_index)
end

script.on_event(defines.events.on_player_created, on_player_created)

script.on_event(defines.events.on_player_joined_game, function(event)
    for index, player in pairs(game.connected_players) do
        check_active_permissions(player, index)
    end
end)

script.on_event(defines.events.on_player_demoted, function(event)
    local player = game.get_player(event.player_index)
    check_active_permissions(player, event.player_index)
end)

script.on_init(on_init)
script.on_configuration_changed(on_configuration_changed)

commands.add_command("fbp-check", "Diagnostic: Check why printer might not be working", function(cmd)
    local player = game.get_player(cmd.player_index)
    if not player or not player.valid then return end
    
    player.print("=== FBP Diagnostic Check ===")
    player.print("Player Name: " .. player.name)
    player.print("Controller Type ID: " .. tostring(player.controller_type))
    player.print("Admin Status: " .. tostring(player.admin))
    player.print("Global 'Allow Others': " .. tostring(settings.global["fbp-allow-others"].value))
    
    ensure_player_storage(cmd.player_index)
    local p_data = storage.players[cmd.player_index]
    player.print("Active State: " .. tostring(p_data.active))
    
    local inventory = player.get_main_inventory()
    if inventory and inventory.valid then
        player.print("Inventory Status: Valid")
    else
        player.print("Inventory Status: INVALID (nil or invalid)")
    end
    player.print("============================")
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "fbp-toggle" then
        local player = game.get_player(event.player_index)
        if not player then return end
        
        if not is_allowed(player) then
            debug_print(player, "Shortcut toggle denied: admin-only")
            player.create_local_flying_text({text={"fbp-message.admin-only"}, create_at_cursor=true})
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
            debug_print(player, "Printer activated")
            player.create_local_flying_text({text = {"fbp-message.printer-active"}, position = player.position})
            
            local inventory = player.get_main_inventory()
            if not inventory or not inventory.valid then
                player.print({"fbp-message.no-inventory-chat"})
                player.create_local_flying_text({text = {"fbp-message.no-inventory-flying"}, position = player.position, color = {1, 0, 0}, create_at_cursor = false})
            end
        else
            debug_print(player, "Printer deactivated")
            player.create_local_flying_text({text = {"fbp-message.printer-inactive"}, position = player.position})
        end
    end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "fbp-speed" then
        local player = game.get_player(event.player_index)
        if not player then return end
        
        ensure_player_storage(event.player_index)
        
        local new_speed = settings.get_player_settings(player)["fbp-speed"].value
        storage.players[event.player_index].speed = new_speed
    elseif event.setting == "fbp-allow-others" then
        for index, player in pairs(game.players) do
            check_active_permissions(player, index)
        end
    end
end)

script.on_nth_tick(1800, function()
    for index, player in pairs(game.connected_players) do
        check_active_permissions(player, index)
    end
end)

local function process_deconstruction(player)
    if not settings.get_player_settings(player)["fbp-deconstruct"].value then
        return
    end

    local entities = player.surface.find_entities_filtered{
        position = player.position,
        radius = player.build_distance,
        to_be_deconstructed = true,
        force = player.force,
        limit = 50
    }

    for _, entity in pairs(entities) do
        if entity.valid then
            player.mine_entity(entity)
        end
    end

    local tiles = player.surface.find_tiles_filtered{
        position = player.position,
        radius = player.build_distance,
        to_be_deconstructed = true,
        force = player.force,
        limit = 50
    }

    for _, tile in pairs(tiles) do
        if tile.valid then
            player.mine_tile(tile)
        end
    end
end

local function process_player(player, p_data)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then
        debug_print(player, "No valid main inventory found")
        return 
    end

    local ghosts = player.surface.find_entities_filtered{
        type = "entity-ghost",
        position = player.position,
        radius = player.build_distance,
        limit = 5
    }

    if #ghosts == 0 then
        return
    end

    for _, ghost in pairs(ghosts) do
        if ghost.valid then
            local items_to_place = ghost.ghost_prototype.items_to_place_this
            
            if items_to_place then
                for _, item_stack in pairs(items_to_place) do
                    local item_name = item_stack.name
                    local count = item_stack.count or 1
                    
                    if inventory.get_item_count(item_name) >= count then
                        local success, revived_entity = ghost.revive({raise_revive = true})
                        
                        if success then
                            debug_print(player, "Placed: " .. item_name)
                            inventory.remove({name = item_name, count = count})
                            break
                        else
                            debug_print(player, "Failed to revive ghost: " .. item_name)
                        end
                    end
                end
            end
        end
    end
end

script.on_event(defines.events.on_tick, function(event)
    for index, player in pairs(game.connected_players) do
        local p_data = storage.players[index]
        
        -- Permission check removed from on_tick. Permissions are now event-driven
        -- via on_player_joined_game, on_player_demoted, and on_runtime_mod_setting_changed.
        if p_data and p_data.active then
            local speed = p_data.speed or 1
            if speed < 1 then speed = 1 end
            
            if event.tick % speed == 0 then
                process_player(player, p_data)
                process_deconstruction(player)
            end
        end
    end
end)
