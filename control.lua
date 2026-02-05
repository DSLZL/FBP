local function debug_print(player, msg)
    if settings.get_player_settings(player)["fbp-debug-mode"].value then
        player.print({"", "[FBP Debug] ", msg})
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
    local player_settings = settings.get_player_settings(player)
    if not player_settings then return false end
    
    local player_enabled = player_settings["fbp-enable-for-me"]
    if not player_enabled then return false end
    
    return player_enabled.value
end

local function check_active_permissions(player, player_index)
    if not player or not player.valid then return end
    ensure_player_storage(player_index)
    local p_data = storage.players[player_index]
    
    if (p_data.active or p_data.deconstruct_active) and not is_allowed(player) then
        debug_print(player, {"fbp-message.admin-only"})
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

script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "fbp-toggle" then
        local player = game.get_player(event.player_index)
        if not player then return end
        
        if not is_allowed(player) then
            debug_print(player, {"fbp-message.admin-only"})
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
    elseif event.prototype_name == "fbp-deconstruct-toggle" then
        local player = game.get_player(event.player_index)
        if not player then return end

        if not is_allowed(player) then
            debug_print(player, {"fbp-message.admin-only"})
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
            debug_print(player, {"message.deconstruction_activated"})
            player.create_local_flying_text({text = {"fbp-message.deconstruct-active"}, position = player.position})
        else
            debug_print(player, {"message.deconstruction_deactivated"})
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
    end
end)

script.on_nth_tick(1800, function()
    for index, player in pairs(game.connected_players) do
        check_active_permissions(player, index)
    end
end)

local CONTAINER_TYPES = {
    ["container"] = true,
    ["logistic-container"] = true,
    ["infinity-container"] = true,
    ["linked-container"] = true,
    ["cargo-wagon"] = true,
    ["storage-tank"] = true,
}

local function is_container_type(entity)
    return CONTAINER_TYPES[entity.type] or false
end

local function is_inventory_nearly_full(player, threshold)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then return true end
    local empty = inventory.count_empty_stacks()
    local total = #inventory
    return (empty / total) < (1 - threshold)
end

local function process_deconstruction(player)
    -- Stop auto-mining while walking to prevent camera twitching
    if player.walking_state.walking then return end

    local state = player.mining_state
    if state.mining then
        -- Entity mining
        if state.target then
            if state.target.valid then
                if state.target.to_be_deconstructed(player.force) then
                    -- Continue mining current target
                    player.update_selected_entity(state.target.position)
                    return
                else
                    -- Target no longer marked for deconstruction, stop mining
                    player.mining_state = {mining = false}
                    return
                end
            else
                -- Target is invalid (was destroyed), explicitly stop mining
                player.mining_state = {mining = false}
                return
            end
        -- Tile mining
        elseif state.position then
            local tile = player.surface.get_tile(state.position)
            if tile and tile.valid and tile.to_be_deconstructed(player.force) then
                -- Continue mining current tile
                player.update_selected_entity(state.position)
                return
            else
                -- Tile no longer needs deconstruction, stop mining
                player.mining_state = {mining = false}
                return
            end
        end
    end

    -- Only search for new targets when explicitly not mining
    local entity = player.surface.find_entities_filtered{
        position = player.position,
        radius = player.build_distance,
        to_be_deconstructed = true,
        force = player.force,
        limit = 1
    }[1]

    if entity then
        if is_container_type(entity) and is_inventory_nearly_full(player, 0.9) then
            return
        end
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

    -- 搜索被标记的地面物品
    local items_on_ground = player.surface.find_entities_filtered{
        position = player.position,
        radius = player.build_distance,
        type = "item-on-ground",
        to_be_deconstructed = true,
        force = player.force,
        limit = 10
    }

    local inventory = player.get_main_inventory()
    if inventory and inventory.valid then
        for _, item_entity in pairs(items_on_ground) do
            if item_entity.valid then
                local stack = item_entity.stack
                if stack and stack.valid then
                    local inserted = inventory.insert(stack)
                    if inserted > 0 then
                        if inserted >= stack.count then
                            item_entity.destroy()
                        else
                            stack.count = stack.count - inserted
                        end
                    end
                end
            end
        end
    end
end

local function process_upgrades(player, limit)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then return end
    
    local target_limit = limit or 5
    local entities = player.surface.find_entities_filtered{
        position = player.position,
        radius = player.build_distance,
        force = player.force,
        limit = target_limit * 5
    }
    
    local upgraded_count = 0
    for _, entity in pairs(entities) do
        if entity.valid and entity.to_be_upgraded() then
            local upgrade_target = entity.get_upgrade_target()
            local upgrade_direction = entity.get_upgrade_direction()
            
            if upgrade_target then
                local target_name = upgrade_target.name
                local items_needed = upgrade_target.items_to_place_this
                
                if items_needed and items_needed[1] then
                    local item_name = items_needed[1].name
                    local quality = entity.quality and entity.quality.name or "normal"
                    
                    if inventory.get_item_count({name = item_name, quality = quality}) >= 1 then
                        local position = entity.position
                        local direction = upgrade_direction or entity.direction
                        local force = entity.force
                        
                        -- 获取旧实体物品用于返还
                        local old_items = entity.prototype.items_to_place_this
                        
                        -- 移除旧实体
                        entity.destroy()
                        
                        -- 放置新实体
                        local new_entity = player.surface.create_entity{
                            name = target_name,
                            position = position,
                            direction = direction,
                            force = force,
                            quality = quality,
                            raise_built = true
                        }
                        
                        if new_entity then
                            inventory.remove({name = item_name, quality = quality, count = 1})
                            upgraded_count = upgraded_count + 1
                            
                            -- 返还旧实体物品
                            if old_items and old_items[1] then
                                inventory.insert({name = old_items[1].name, quality = quality, count = 1})
                            end
                        end
                    end
                end
            end
        end
        
        if upgraded_count >= target_limit then break end
    end
end

local function process_player(player, p_data, limit)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then
        debug_print(player, {"message.no_inventory_found"})
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
            local required_quality = ghost.quality and ghost.quality.name or "normal"
            local items_to_place = ghost.ghost_prototype.items_to_place_this
            
            if items_to_place then
                for _, item_stack in pairs(items_to_place) do
                    local item_name = item_stack.name
                    local count = item_stack.count or 1
                    
                    if inventory.get_item_count({name = item_name, quality = required_quality}) >= count then
                        local success, revived_entity = ghost.revive({raise_revive = true})
                        
                        if success then
                            debug_print(player, {"message.placed_item", item_name})
                            inventory.remove({name = item_name, quality = required_quality, count = count})
                            revived_count = revived_count + 1
                            break
                        else
                            debug_print(player, {"message.failed_to_revive", item_name})
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
        debug_print(player, {"message.scanning_ramp_up", p_data.scan_multiplier})
    else
        p_data.scan_multiplier = math.max(p_data.scan_multiplier - 5, 5)
        debug_print(player, {"message.scanning_ramp_down", p_data.scan_multiplier})
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
                        process_upgrades(player, 5)
                    end
                    
                    if p_data.deconstruct_active then
                        process_deconstruction(player)
                    end
                end
            else
                p_data.placement_acc = math.min(p_data.placement_acc + (5 / speed), 2.0)
                
                if p_data.active and p_data.placement_acc >= 1 then
                    process_player(player, p_data, 1)
                    process_upgrades(player, 1)
                    p_data.placement_acc = p_data.placement_acc - 1
                end

                if p_data.deconstruct_active and event.tick % speed == 0 then
                    process_deconstruction(player)
                end
            end
        end
    end
end)
