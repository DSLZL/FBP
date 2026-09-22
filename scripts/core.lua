local player_state = require("scripts.player_state")
local construction = require("scripts.construction")
local deconstruction = require("scripts.deconstruction")

local core = {}

function core.on_tick(event)
    for _, player in pairs(game.connected_players) do
        local state, allowed = player_state.enforce(player)
        if state and allowed and state.active then
            local speed = math.max(1, state.speed)
            if (event.tick + player.index) % speed == 0 then
                local context = {}
                if state.features.auto_place then
                    construction.place(player, state, 5, context)
                end
                if state.features.auto_upgrade then
                    construction.upgrade(player, state, 5, context)
                end
                if state.deconstruct_active then
                    deconstruction.process(player, state, context)
                end
            end
        end
    end
end

return core
