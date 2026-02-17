local utils = require("scripts.utils")
local core = {}

local debug_print = utils.debug_print
local ensure_player_storage = utils.ensure_player_storage
local is_allowed = utils.is_allowed
local is_container_type = utils.is_container_type
local is_inventory_nearly_full = utils.is_inventory_nearly_full

function core.check_active_permissions(player, player_index)
    if not player or not player.valid then return end
    ensure_player_storage(player_index)
    local p_data = storage.players[player_index]
    
    local allowed, reason = is_allowed(player)
    
    if p_data.active and not allowed then
        local msg_key = "fbp-message." .. (reason or "admin-only")
        debug_print(player, {msg_key})
        p_data.active = false
        player.set_shortcut_toggled("fbp-toggle", false)
        player.create_local_flying_text({text={msg_key}, create_at_cursor=true})
    end
end

function core.process_deconstruction(player)
    -- Stop auto-mining while walking to prevent camera twitching
    if player.walking_state.walking then return end

    local max_radius = settings.get_player_settings(player)["fbp-scan-radius"].value
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
        radius = math.min(player.build_distance, max_radius),
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

    -- Process Auto Mine (Trees/Rocks) if enabled
    ensure_player_storage(player.index)
    local p_data = storage.players[player.index]
    if p_data.features.auto_mine then
        local neutral_target = player.surface.find_entities_filtered{
            position = player.position,
            radius = math.min(player.build_distance, max_radius),
            type = {"tree", "simple-entity"},
            limit = 1
        }[1]
        
        if neutral_target and neutral_target.valid and neutral_target.to_be_deconstructed(player.force) then
             player.update_selected_entity(neutral_target.position)
             player.mining_state = {mining = true, position = neutral_target.position, target = neutral_target}
             return
        end
    end

    local tile = player.surface.find_tiles_filtered{
        position = player.position,
        radius = math.min(player.build_distance, max_radius),
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
        radius = math.min(player.build_distance, max_radius),
        type = "item-on-ground",
        limit = 10
    }

    local inventory = player.get_main_inventory()
    if inventory and inventory.valid then
        for _, item_entity in pairs(items_on_ground) do
        if item_entity.valid and item_entity.to_be_deconstructed(player.force) then
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

function core.process_upgrades(player, limit)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then return end
    
    local max_radius = settings.get_player_settings(player)["fbp-scan-radius"].value
    local target_limit = limit or 5
    local entities = player.surface.find_entities_filtered{
        position = player.position,
        radius = math.min(player.build_distance, max_radius),
        force = player.force,
        limit = 100
    }
    
    local upgraded_count = 0
    for _, entity in pairs(entities) do
        if entity.valid and entity.to_be_upgraded() then
            local upgrade_target = entity.get_upgrade_target()
            
            if upgrade_target then
                local target_name = upgrade_target.name
                local items_needed = upgrade_target.items_to_place_this
                
                if items_needed and items_needed[1] then
                    local item_name = items_needed[1].name
                    local quality = entity.quality and entity.quality.name or "normal"
                    
                    if inventory.get_item_count({name = item_name, quality = quality}) >= 1 then
                        local new_entity = player.surface.create_entity{
                            name = target_name,
                            position = entity.position,
                            direction = entity.direction,
                            force = entity.force,
                            quality = quality,
                            fast_replace = true,
                            player = player,
                            raise_built = true
                        }
                        
                        if new_entity then
                            inventory.remove({name = item_name, quality = quality, count = 1})
                            upgraded_count = upgraded_count + 1
                        end
                    end
                end
            end
        end
        
        if upgraded_count >= target_limit then break end
    end
end

function core.process_auto_place(player, p_data, limit)
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
    local max_radius = settings.get_player_settings(player)["fbp-scan-radius"].value
    local ghosts = player.surface.find_entities_filtered{
        type = "entity-ghost",
        position = player.position,
        radius = math.min(player.build_distance, max_radius),
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
                        local bbox = ghost.bounding_box
                        local surface = ghost.surface
                        local water_tiles = surface.find_tiles_filtered{
                            area = bbox,
                            collision_mask = "water_tile"
                        }
                        
                        if #water_tiles > 0 then
                            if not p_data.features.auto_landfill then
                                goto continue_ghost
                            end
                            
                            local landfill_available = inventory.get_item_count({name = "landfill"})
                            if landfill_available < #water_tiles then
                                goto continue_ghost
                            end
                            
                            local tiles_to_place = {}
                            for _, tile in pairs(water_tiles) do
                                table.insert(tiles_to_place, {name = "landfill", position = tile.position})
                            end
                            surface.set_tiles(tiles_to_place)
                            inventory.remove({name = "landfill", count = #water_tiles})
                        end
                        
                        local module_requests = ghost.item_requests
                        
                        -- 在 revive 前获取物品的 health 比率
                        local item_health_ratio = 1.0
                        local found_item = inventory.find_item_stack(item_name)
                        if found_item and found_item.valid and found_item.health then
                            item_health_ratio = found_item.health
                        end
                        
                        local success, revived_entity = ghost.revive({raise_revive = true})
                        
                        if success then
                            debug_print(player, {"message.placed_item", item_name})
                            inventory.remove({name = item_name, quality = required_quality, count = count})
                            
                            -- 恢复实体的 health（从物品比率 → 实体绝对值）
                            if revived_entity and revived_entity.valid and revived_entity.max_health then
                                revived_entity.health = item_health_ratio * revived_entity.max_health
                            end
                            
                            if module_requests and revived_entity and revived_entity.valid and p_data.features.auto_modules then
                                local module_inventory = revived_entity.get_module_inventory()
                                if module_inventory then
                                    for _, module_request in pairs(module_requests) do
                                        local module_name = module_request.name
                                        local module_quality = module_request.quality and module_request.quality.name or "normal"
                                        local module_count = module_request.count or 1
                                        
                                        local available = inventory.get_item_count({name = module_name, quality = module_quality})
                                        local to_insert = math.min(available, module_count)
                                        
                                        if to_insert > 0 then
                                            local inserted = module_inventory.insert({name = module_name, quality = module_quality, count = to_insert})
                                            if inserted > 0 then
                                                inventory.remove({name = module_name, quality = module_quality, count = inserted})
                                            end
                                        end
                                    end
                                end
                            end
                            
                            revived_count = revived_count + 1
                            break
                        else
                            debug_print(player, {"message.failed_to_revive", item_name})
                        end
                    end
                end
            end
        end
        ::continue_ghost::
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

return core
