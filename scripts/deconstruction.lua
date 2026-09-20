local player_state = require("scripts.player_state")
local utils = require("scripts.utils")

local deconstruction = {}

local function start_mining(player, state, position, entity, context)
    player.update_selected_entity(position)
    if entity and player.selected ~= entity then return false end
    player.mining_state = {mining = true, position = position}
    state.auto_mining = {surface = player.surface, position = position, entity = entity}
    utils.consume(context, player.surface, position)
    return true
end

function deconstruction.process(player, state, context)
    local inventory = player.get_main_inventory()
    if not player_state.can_mine(player) or not inventory or not inventory.valid
        or player.walking_state.walking then
        player_state.stop_mining(player, state)
        return
    end
    local radius = math.min(player.build_distance, state.scan_radius)
    local owned = state.auto_mining
    if owned then
        local dx, dy = owned.position.x - player.position.x, owned.position.y - player.position.y
        local valid = owned.surface == player.surface and dx * dx + dy * dy <= radius * radius
            and not utils.is_consumed(context, owned.surface, owned.position)
        if owned.entity then
            valid = valid and owned.entity.valid and owned.entity.to_be_deconstructed()
                and not utils.container_inventory_full(player, owned.entity)
        else
            valid = valid and owned.surface.get_tile(owned.position).to_be_deconstructed(player.force)
        end
        if valid and player.mining_state.mining
            and utils.same_position(player.mining_state.position, owned.position)
            and (not owned.entity or player.selected == owned.entity) then
            utils.consume(context, owned.surface, owned.position)
            return
        end
        player_state.stop_mining(player, state)
    end
    -- Do not replace a manual mining action with an automatic target.
    if player.mining_state.mining then return end
    local surface = player.surface
    local function mine_entities(filter)
        filter.position, filter.radius, filter.limit = player.position, radius, 10
        filter.to_be_deconstructed = true
        for _, entity in pairs(surface.find_entities_filtered(filter)) do
            if entity.valid and entity.type ~= "deconstructible-tile-proxy"
                and entity.to_be_deconstructed() and entity.minable
                and not utils.is_consumed(context, surface, entity.position)
                and not utils.container_inventory_full(player, entity) then
                if start_mining(player, state, entity.position, entity, context) then return true end
            end
        end
        return false
    end
    if mine_entities({force = player.force}) then return end
    if mine_entities({force = "neutral", type = {"tree", "simple-entity"}}) then return end
    local tiles = surface.find_tiles_filtered({
        position = player.position, radius = radius, limit = 10, to_be_deconstructed = true
    })
    for _, tile in pairs(tiles) do
        if tile.valid and tile.to_be_deconstructed(player.force)
            and not utils.is_consumed(context, surface, tile.position) then
            local position = tile.position
            if player.mine_tile(tile) then
                utils.consume(context, surface, position)
                return
            end
        end
    end
    for _, entity in pairs(surface.find_entities_filtered({
        type = "item-entity", position = player.position, radius = radius, limit = 10,
        to_be_deconstructed = true
    })) do
        if entity.valid and entity.to_be_deconstructed()
            and not utils.is_consumed(context, surface, entity.position) then
            local position, stack = entity.position, entity.stack
            local inserted = inventory.insert(stack)
            if inserted > 0 then
                if inserted == stack.count then entity.destroy()
                else stack.count = stack.count - inserted end
                utils.consume(context, surface, position)
            end
        end
    end
end

return deconstruction
