local utils = {}

function utils.debug_print(source_player, message)
    if not source_player or not source_player.valid then return end
    for _, player in pairs(game.connected_players) do
        local mode = settings.get_player_settings(player)["fbp-debug-mode"].value
        if mode == "all" then
            player.print({"", "[FBP Debug] (" .. source_player.name .. ") ", message})
        elseif mode == "personal" and player.index == source_player.index then
            player.print({"", "[FBP Debug] ", message})
        end
    end
end

function utils.same_position(a, b)
    return a and b and a.x == b.x and a.y == b.y
end

function utils.position_key(surface, position)
    return surface.index .. ":" .. math.floor(position.x) .. ":" .. math.floor(position.y)
end

function utils.is_consumed(context, surface, position)
    return context and context[utils.position_key(surface, position)] == true
end

function utils.consume(context, surface, position)
    if context then context[utils.position_key(surface, position)] = true end
end

function utils.return_items(inventory, surface, position, stack)
    if stack.count <= 0 then return end
    local inserted = inventory.insert(stack)
    if inserted < stack.count then
        surface.spill_item_stack({
            position = position,
            stack = {name = stack.name, quality = stack.quality, count = stack.count - inserted, health = stack.health},
            enable_looted = true,
            allow_belts = false
        })
    end
end

local CONTAINER_TYPES = {
    ["container"] = true, ["logistic-container"] = true, ["infinity-container"] = true,
    ["linked-container"] = true, ["cargo-wagon"] = true, ["storage-tank"] = true
}

function utils.container_inventory_full(player, entity)
    if not CONTAINER_TYPES[entity.type] then return false end
    local inventory = player.get_main_inventory()
    return not inventory or not inventory.valid or #inventory == 0
        or inventory.count_empty_stacks() / #inventory < 0.1
end

return utils
