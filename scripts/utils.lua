local utils = {}

function utils.debug_print(source_player, msg)
    for _, p in pairs(game.connected_players) do
        local debug_setting = settings.get_player_settings(p)["fbp-debug-mode"].value
        if debug_setting == "all" then
            p.print({"", "[FBP Debug] (" .. source_player.name .. ") ", msg})
        elseif debug_setting == "personal" and p.index == source_player.index then
            p.print({"", "[FBP Debug] ", msg})
        end
    end
end

function utils.ensure_player_storage(player_index)
    if not storage.players then
        storage.players = {}
    end
    if not storage.players[player_index] then
        storage.players[player_index] = {
            active = false,
            speed = 1,
            placement_acc = 0,
            scan_multiplier = 20,
            scan_radius = 100,
            features = {
                auto_place = true,
                auto_upgrade = true,
                auto_deconstruct = false,
                auto_mine = false,
                auto_modules = true,
                auto_landfill = true
            }
        }
    end
end

function utils.is_allowed(player)
    local player_settings = settings.get_player_settings(player)
    if not player_settings then return false, "unknown-error" end
    
    if player_settings["fbp-enable-for-me"] and not player_settings["fbp-enable-for-me"].value then
        return false, "disabled-by-user"
    end
    
    if player.admin then return true end
    
    if settings.global["fbp-allow-others"] and settings.global["fbp-allow-others"].value then
        return true
    end
    
    return false, "admin-only"
end

local CONTAINER_TYPES = {
    ["container"] = true,
    ["logistic-container"] = true,
    ["infinity-container"] = true,
    ["linked-container"] = true,
    ["cargo-wagon"] = true,
    ["storage-tank"] = true,
}

function utils.is_container_type(entity)
    return CONTAINER_TYPES[entity.type] or false
end

function utils.is_inventory_nearly_full(player, threshold)
    local inventory = player.get_main_inventory()
    if not inventory or not inventory.valid then return true end
    local empty = inventory.count_empty_stacks()
    local total = #inventory
    return (empty / total) < (1 - threshold)
end

return utils
