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
            deconstruct_active = false,
            speed = 1,
            placement_acc = 0,
            scan_multiplier = 20
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
    
    if (p_data.active or p_data.deconstruct_active) and not is_allowed(player) then
        debug_print(player, "Permissions denied: admin-only")
        p_data.active = false
        p_data.deconstruct_active = false
        player.set_shortcut_toggled("fbp-toggle", false)
        player.set_shortcut_toggled("fbp-deconstruct-toggle", false)
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
    elseif event.prototype_name == "fbp-deconstruct-toggle" then
        local player = game.get_player(event.player_index)
        if not player then return end

        if not is_allowed(player) then
            debug_print(player, "Shortcut toggle denied: admin-only")
            player.create_local_flying_text({text={"fbp-message.admin-only"}, create_at_cursor=true})
            player.set_shortcut_toggled("fbp-deconstruct-toggle", false)
            if storage.players[event.player_index] then
                storage.players[event.player_index].deconstruct_active = false
            end
            return
        end

        ensure_player_storage(event.player_index)
        local p_data = storage.players[event.player_index]
        p_data.deconstruct_active = not p_data.deconstruct_active

        player.set_shortcut_toggled("fbp-deconstruct-toggle", p_data.deconstruct_active)

        if p_data.deconstruct_active then
            debug_print(player, "Deconstruction activated")
            player.create_local_flying_text({text = {"fbp-message.deconstruct-active"}, position = player.position})
        else
            debug_print(player, "Deconstruction deactivated")
            player.create_local_flying_text({text = {"fbp-message.deconstruct-inactive"}, position = player.position})
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
    local state = player.mining_state
    if state.mining then
        if state.target and state.target.valid then
            if state.target.to_be_deconstructed(player.force) then
                player.update_selected_entity(state.target.position)
            end
            return
        elseif not state.target and state.position then
            -- Tile mining
            local tile = player.surface.get_tile(state.position)
            if tile and tile.valid and tile.to_be_deconstructed(player.force) then
                player.update_selected_entity(state.position)
            end
            return
        end
    end

    local entity = player.surface.find_entities_filtered{
        position = player.position,
        radius = player.build_distance,
        to_be_deconstructed = true,
        force = player.force,
        limit = 1
    }[1]

    if entity then
        player.update_selected_entity(entity.position)
        player.mining_state = {mining = true, position = entity.position, target = entity}
        return
    end

    local tile = player.surface.find_tiles_filtered{
        position = player.position,
        radius = player.build_distance,
        to_be_deconstructed = true,
        force = player.force,
        limit = 1
    }[1]

    if tile then
        player.update_selected_entity(tile.position)
        player.mining_state = {mining = true, position = tile.position}
    end
end

local function process_player(player, p_data, limit)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then
        debug_print(player, "No valid main inventory found")
        return 
    end

    if not p_data.scan_multiplier then
        p_data.scan_multiplier = 20
    end

    local target_limit = limit or 5
    local scan_limit = target_limit * p_data.scan_multiplier
    local ghosts = player.surface.find_entities_filtered{
        type = "entity-ghost",
        position = player.position,
        radius = player.build_distance,
        limit = scan_limit
    }

    local found_ghosts_count = #ghosts
    if found_ghosts_count == 0 then
        return
    end

    local revived_count = 0

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
                            revived_count = revived_count + 1
                            break
                        else
                            debug_print(player, "Failed to revive ghost: " .. item_name)
                        end
                    end
                end
            end
        end
        if revived_count >= target_limit then
            break
        end
    end

    if revived_count < target_limit and found_ghosts_count == scan_limit then
        p_data.scan_multiplier = math.min(p_data.scan_multiplier + 10, 200)
        debug_print(player, "Scanning ramp-up: " .. p_data.scan_multiplier)
    else
        p_data.scan_multiplier = math.max(p_data.scan_multiplier - 5, 5)
        debug_print(player, "Scanning ramp-down: " .. p_data.scan_multiplier)
    end
end

script.on_event(defines.events.on_tick, function(event)
    for index, player in pairs(game.connected_players) do
        local p_data = storage.players[index]
        
        -- Permission check removed from on_tick. Permissions are now event-driven
        -- via on_player_joined_game, on_player_demoted, and on_runtime_mod_setting_changed.
        if p_data then
            local speed = p_data.speed or 1
            if speed < 1 then speed = 1 end
            
            if not p_data.placement_acc then p_data.placement_acc = 0 end

            local batch_mode = settings.get_player_settings(player)["fbp-batch-mode"].value
            if batch_mode then
                if event.tick % speed == 0 then
                    if p_data.active then
                        process_player(player, p_data, 5)
                    end
                    
                    if p_data.deconstruct_active then
                        process_deconstruction(player)
                    end
                end
            else
                p_data.placement_acc = math.min(p_data.placement_acc + (5 / speed), 2.0)
                
                if p_data.active and p_data.placement_acc >= 1 then
                    process_player(player, p_data, 1)
                    p_data.placement_acc = p_data.placement_acc - 1
                end

                if p_data.deconstruct_active and event.tick % speed == 0 then
                    process_deconstruction(player)
                end
            end
        end
    end
end)
