local utils = require("scripts.utils")
local scan = require("scripts.scan")

local construction = {}

local function insert_modules(inventory, entity, proxy)
    local modules = entity.get_module_inventory()
    if not modules or not proxy or not proxy.valid then return end
    local remaining = {}
    for _, plan in ipairs(proxy.insert_plan) do
        local requests = {}
        for _, request in ipairs(plan.items.in_inventory or {}) do
            local needed = request.count or 1
            if entity.get_inventory(request.inventory) == modules then
                local destination = request.stack < #modules and modules[request.stack + 1]
                while destination and needed > 0 do
                    local source = inventory.find_item_stack(plan.id)
                    if not source then break end
                    local before = source.count
                    destination.transfer_stack(source, math.min(needed, before))
                    local moved = before - (source.valid_for_read and source.count or 0)
                    if moved == 0 then break end
                    needed = needed - moved
                end
            end
            if needed > 0 then
                request.count = needed
                requests[#requests + 1] = request
            end
        end
        plan.items.in_inventory = requests
        if #requests > 0 or (plan.items.grid_count or 0) > 0 then
            remaining[#remaining + 1] = plan
        end
    end
    -- Keep requests for missing modules and for every other inventory intact.
    proxy.insert_plan = remaining
end

local function landfill(player, state, ghost, inventory)
    local surface, position = ghost.surface, ghost.position
    -- ponytail: cap a single footprint at 4096 water tiles; larger modded
    -- structures need a resumable tile job before raising this bound.
    local water = surface.find_tiles_filtered({area = ghost.bounding_box, collision_mask = "water_tile", limit = 4097})
    if #water == 0 then return true end
    if not state.features.auto_landfill or #water > 4096 then return false end
    local stack = {name = "landfill", quality = "normal", count = #water}
    if inventory.get_item_count(stack) < stack.count then return false end
    local removed = inventory.remove(stack)
    if removed < stack.count then
        stack.count = removed
        utils.return_items(inventory, surface, position, stack)
        return false
    end
    local tiles = {}
    for _, tile in ipairs(water) do
        tiles[#tiles + 1] = {name = "landfill", position = tile.position}
    end
    surface.set_tiles(tiles, true, false, false, true)
    local placed = 0
    for _, tile in ipairs(tiles) do
        if surface.get_tile(tile.position).name == "landfill" then placed = placed + 1 end
    end
    if placed < removed then
        stack.count = removed - placed
        utils.return_items(inventory, surface, position, stack)
    end
    return placed == #tiles
end

local function place_ghost(player, state, ghost, inventory)
    local surface, position = ghost.surface, ghost.position
    local name, quality = ghost.ghost_name, ghost.quality.name
    for _, item in pairs(ghost.ghost_prototype.items_to_place_this or {}) do
        local stack = {name = item.name, quality = quality, count = item.count}
        if inventory.get_item_count(stack) >= stack.count then
            local source = inventory.find_item_stack(stack)
            local health = source and source.health or 1
            local removed = inventory.remove(stack)
            if removed == stack.count and landfill(player, state, ghost, inventory) and ghost.valid then
                local collided, revived, proxy = ghost.revive({raise_revive = true, overflow = inventory})
                if collided then
                    for _, returned in pairs(collided) do
                        utils.return_items(inventory, surface, position, returned)
                    end
                    if revived and revived.valid then
                        if revived.health then revived.health = revived.max_health * health end
                        if state.features.auto_modules then insert_modules(inventory, revived, proxy) end
                    end
                    utils.debug_print(player, {"message.placed_item", name})
                    return true
                end
                utils.debug_print(player, {"message.failed_to_revive", name})
            end
            stack.count, stack.health = removed, health
            utils.return_items(inventory, surface, position, stack)
            return false
        end
    end
    return false
end

function construction.place(player, state, limit, context)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then return end
    local placed = 0
    for ghost in scan.entities(player, state, "place", {type = "entity-ghost", force = player.force}) do
        if ghost.valid and not utils.is_consumed(context, ghost.surface, ghost.position) then
            local surface, position = ghost.surface, ghost.position
            if place_ghost(player, state, ghost, inventory) then
                placed = placed + 1
                utils.consume(context, surface, position)
                if placed >= limit then break end
            end
        end
    end
end

function construction.upgrade(player, state, limit, context)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then return end
    local upgraded, attempted = 0, {}
    for entity in scan.entities(player, state, "upgrade", {force = player.force, to_be_upgraded = true}) do
        if entity.valid and entity.to_be_upgraded() then
            local surface, position = entity.surface, entity.position
            local key = utils.position_key(surface, position)
            if not attempted[key] and not utils.is_consumed(context, surface, position) then
                attempted[key] = true
                local target, target_quality = entity.get_upgrade_target()
                local item = target and target.items_to_place_this and target.items_to_place_this[1]
                if item then
                    local quality = target_quality and target_quality.name or "normal"
                    local stack = {name = item.name, quality = quality, count = item.count}
                    if inventory.get_item_count(stack) >= stack.count then
                        local source = inventory.find_item_stack(stack)
                        stack.health = source and source.health or 1
                        local removed = inventory.remove(stack)
                        local replacement
                        if removed == stack.count then
                            replacement = surface.create_entity({
                                name = target.name, position = position, direction = entity.direction,
                                force = entity.force, quality = quality, mirror = entity.mirroring,
                                type = entity.type == "underground-belt" and entity.belt_to_ground_type or nil,
                                fast_replace = true, player = player, raise_built = true
                            })
                        end
                        if replacement then
                            upgraded = upgraded + 1
                            utils.consume(context, surface, position)
                            if upgraded >= limit then break end
                        else
                            stack.count = removed
                            utils.return_items(inventory, surface, position, stack)
                        end
                    end
                end
            end
        end
    end
end

return construction
