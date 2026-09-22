local utils = require("scripts.utils")

local player_state = {}

local FEATURE_DEFAULTS = {
    auto_place = true,
    auto_upgrade = true,
    auto_deconstruct = false,
    auto_mine = false,
    auto_modules = true,
    auto_landfill = true
}

function player_state.get(index)
    storage.players = storage.players or {}
    local state = storage.players[index]
    if not state then
        state = {}
        storage.players[index] = state
    end
    state.features = state.features or {}
    if state.deconstruct_active == nil then
        local legacy = state.features.auto_deconstruct
        if legacy == nil then legacy = state.features.auto_mine end
        state.deconstruct_active = legacy and true or false
    end
    for key, value in pairs(FEATURE_DEFAULTS) do
        if state.features[key] == nil then state.features[key] = value end
    end
    if state.active == nil then state.active = false end
    state.speed = state.speed or 1
    state.scan_radius = state.scan_radius or 100
    state.scan_multiplier = state.scan_multiplier or 20
    state.placement_acc = state.placement_acc or 0
    state.features.auto_deconstruct = state.deconstruct_active
    state.features.auto_mine = state.deconstruct_active
    return state
end

function player_state.allowed(player)
    if not player or not player.valid then return false, "unknown-error" end
    local personal = settings.get_player_settings(player)
    if not personal or not personal["fbp-enable-for-me"].value then
        return false, "disabled-by-user"
    end
    if player.admin or settings.global["fbp-allow-others"].value then return true end
    return false, "admin-only"
end

function player_state.can_mine(player)
    local controller = player.controller_type
    return controller == defines.controllers.character or controller == defines.controllers.god
end

function player_state.stop_mining(player, state)
    local owned = state.auto_mining
    state.auto_mining = nil
    if not owned or not player or not player.valid then return end
    local controller = player.controller_type
    if not player_state.can_mine(player) and controller ~= defines.controllers.editor then return end
    local mining = player.mining_state
    if mining.mining and owned.surface == player.surface
        and utils.same_position(mining.position, owned.position)
        and (not owned.entity or player.selected == owned.entity) then
        player.mining_state = {mining = false}
    end
end

function player_state.sync_shortcuts(player, state)
    player.set_shortcut_toggled("fbp-toggle", state.active and true or false)
    player.set_shortcut_toggled("fbp-deconstruct-toggle", state.deconstruct_active and true or false)
end

function player_state.enforce(player)
    if not player or not player.valid then return nil, false end
    local state = player_state.get(player.index)
    local allowed, reason = player_state.allowed(player)
    local editor = player.controller_type == defines.controllers.editor
    if not allowed or editor then
        local changed = state.active or state.deconstruct_active
        state.active = false
        state.deconstruct_active = false
        state.features.auto_deconstruct = false
        state.features.auto_mine = false
        player_state.stop_mining(player, state)
        if changed then player_state.sync_shortcuts(player, state) end
    elseif not state.active or not state.deconstruct_active or not player_state.can_mine(player) then
        player_state.stop_mining(player, state)
    end
    return state, allowed and not editor, reason
end

function player_state.refresh(player)
    if not player or not player.valid then return end
    local state = player_state.get(player.index)
    local personal = settings.get_player_settings(player)
    state.speed = personal["fbp-speed"].value
    state.scan_radius = personal["fbp-scan-radius"].value
    player_state.enforce(player)
    player_state.sync_shortcuts(player, state)
    return state
end

function player_state.set_active(player, key, enabled)
    local state, allowed, reason = player_state.enforce(player)
    if not state then return end
    enabled = enabled and true or false
    if enabled and not allowed then
        if reason then
            local message = {"fbp-message." .. reason}
            utils.debug_print(player, message)
            player.create_local_flying_text({text = message, create_at_cursor = true})
        end
        return state
    end
    state[key] = enabled
    if key == "deconstruct_active" then
        state.features.auto_deconstruct = enabled
        state.features.auto_mine = enabled
    end
    if not state.active or not state.deconstruct_active then player_state.stop_mining(player, state) end
    player_state.sync_shortcuts(player, state)
    return state
end

function player_state.set_feature(player, key, enabled)
    if FEATURE_DEFAULTS[key] == nil then return end
    if key == "auto_deconstruct" or key == "auto_mine" then
        return player_state.set_active(player, "deconstruct_active", enabled)
    end
    local state = player_state.get(player.index)
    state.features[key] = enabled and true or false
    return state
end

return player_state
