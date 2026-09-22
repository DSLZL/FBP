-- Installed only into disposable test copies by run_engine.py.
local validation = {}
local construction, player_state, deconstruction, gui, core, scan

local function check(value, message)
    assert(value, "FBP_VALIDATION: " .. message)
end

local function pass(message)
    log("FBP_VALIDATION PASS " .. message)
end

local function preferences(player)
    storage.players[player.index] = {
        active = true, deconstruct_active = false, speed = 30, scan_radius = 100,
        scan_multiplier = 37, placement_acc = 17, migration_marker = "preserved",
        features = {auto_place = false, auto_upgrade = false, auto_modules = false,
            auto_landfill = false, auto_deconstruct = false, auto_mine = false}
    }
end

local function assert_preferences(player)
    local state = storage.players[player.index]
    check(state.active and not state.deconstruct_active, "shortcut preferences migrated")
    check(not state.features.auto_place and not state.features.auto_upgrade
        and not state.features.auto_modules and not state.features.auto_landfill, "false preferences migrated")
    check(state.scan_multiplier == 37 and state.placement_acc == 17
        and state.migration_marker == "preserved", "saved fields retained")
    check(player.is_shortcut_toggled("fbp-toggle"), "shortcut restored")
end

local function prepare(player)
    player.admin = true
    local surface = game.surfaces["fbp-validation"] or game.create_surface("fbp-validation", {
        width = 64, height = 64, autoplace_settings = {
            entity = {treat_missing_as_default = false},
            decorative = {treat_missing_as_default = false}, tile = {treat_missing_as_default = false}
        }
    })
    surface.request_to_generate_chunks({0, 0}, 1)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for x = -16, 16 do for y = -16, 16 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
    surface.set_tiles(tiles)
    player.teleport({0, 0}, surface)
    if not player.character then
        player.set_controller({type = defines.controllers.god})
        check(player.create_character(), "test character created")
    end
    player.force.manual_mining_speed_modifier = 100
    return surface
end

local function clear(player)
    player.mining_state = {mining = false}
    storage.players[player.index].auto_mining = nil
    storage.players[player.index].scans = nil
    for _, entity in pairs(player.surface.find_entities_filtered({area = {{-10, -10}, {10, 10}}, limit = 1000})) do
        if entity.type ~= "character" then entity.destroy() end
    end
    local inventory = player.get_main_inventory()
    inventory.clear()
    for index = 1, #inventory do inventory.set_filter(index, nil) end
    return inventory
end

local function operations(player)
    gui.create_config_gui(player)
    local frame = player.gui.screen["fbp-config-frame"]
    local checkbox = frame["fbp-feature-auto_deconstruct"]
    for _, enabled in ipairs({true, false}) do
        checkbox.state = enabled
        script.get_event_handler(defines.events.on_gui_checked_state_changed)({player_index = player.index, element = checkbox})
        check(storage.players[player.index].deconstruct_active == enabled
            and player.is_shortcut_toggled("fbp-deconstruct-toggle") == enabled, "GUI and shortcut agree")
    end
    gui.destroy_config_gui(player)
    pass("native GUI transitions and shortcuts")
    local state = player_state.get(player.index)
    local inventory = clear(player)
    state.active, state.deconstruct_active, state.speed = true, true, 1
    state.features.auto_place, state.features.auto_upgrade = true, true
    local mining_target = player.surface.create_entity({name = "wooden-chest", position = {3, 0}, force = player.force})
    check(mining_target.order_deconstruction(player.force), "shortcut mining target marked")
    deconstruction.process(player, state, {})
    check(player.mining_state.mining and state.auto_mining, "automatic mining started")
    local shortcut = script.get_event_handler(defines.events.on_lua_shortcut)
    shortcut({player_index = player.index, prototype_name = "fbp-toggle"})
    check(not state.active and not player.mining_state.mining and not state.auto_mining,
        "master shortcut stops native mining immediately")
    check(state.deconstruct_active and state.features.auto_deconstruct, "master pause retains preferences")
    inventory.insert({name = "wooden-chest", count = 1})
    local paused_ghost = player.surface.create_entity({name = "entity-ghost", inner_name = "wooden-chest",
        position = {4, 2}, force = player.force})
    core.on_tick({tick = game.tick})
    check(paused_ghost.valid and not player.mining_state.mining, "master off blocks placement and mining restart")
    shortcut({player_index = player.index, prototype_name = "fbp-toggle"})
    core.on_tick({tick = game.tick})
    check(not paused_ghost.valid and player.mining_state.mining, "master shortcut resumes selected groups")
    shortcut({player_index = player.index, prototype_name = "fbp-toggle"})
    check(not player.mining_state.mining, "repeated master pause stops mining")
    pass("native master shortcut pause and resume")
    state.active, state.deconstruct_active = false, false
    clear(player)
    local build_bonus = player.character_build_distance_bonus
    player.character_build_distance_bonus = build_bonus + 30
    local far = player.surface.create_entity({name = "wooden-chest", position = {0, -20}, force = player.force})
    local near = player.surface.create_entity({name = "wooden-chest", position = {3, 0}, force = player.force})
    check(far.order_deconstruction(player.force) and near.order_deconstruction(player.force), "reachability targets marked")
    check(player.build_distance > 20 and not player.can_reach_entity(far) and player.can_reach_entity(near),
        "build range includes an unreachable mining target")
    player.update_selected_entity(far.position)
    player.mining_state = {mining = true, position = far.position}
    state.auto_mining = {surface = player.surface, position = far.position, entity = far}
    check(player.selected == far and player.mining_state.mining, "unreachable owned mining fixture")
    deconstruction.process(player, state, {})
    check(state.auto_mining and state.auto_mining.entity == near and player.selected == near,
        "unreachable owned target yields to reachable mining")
    player_state.stop_mining(player, state)
    far.destroy()
    near.destroy()
    player.character_build_distance_bonus = build_bonus
    pass("native unreachable mining target recovery")
    state.features.auto_modules, state.features.auto_landfill = true, true
    local surface = player.surface
    local inventory = clear(player)
    inventory.insert({name = "assembling-machine-2", quality = "rare", count = 1})
    inventory.find_item_stack({name = "assembling-machine-2", quality = "rare"}).health = 0.4
    inventory.insert({name = "speed-module", quality = "rare", count = 1})
    local ghost = surface.create_entity({name = "entity-ghost", inner_name = "assembling-machine-2",
        quality = "rare", position = {3, 0}, force = player.force})
    ghost.insert_plan = {{id = {name = "speed-module", quality = "rare"}, items = {in_inventory = {
        {inventory = defines.inventory.crafter_modules, stack = 0, count = 1},
        {inventory = defines.inventory.crafter_modules, stack = 1, count = 1}
    }}}}
    local ghost_position = ghost.position
    construction.place(player, state, 5, {})
    check(not ghost.valid, "ghost revived")
    local machine = surface.find_entity({name = "assembling-machine-2", quality = "rare"}, ghost_position)
    check(machine and machine.quality.name == "rare", "placement quality")
    check(math.abs(machine.health / machine.max_health - 0.4) < 0.001, "placement health")
    check(machine.get_module_inventory().get_item_count({name = "speed-module", quality = "rare"}) == 1, "module delivered")
    local proxies = surface.find_entities_filtered({type = "item-request-proxy", limit = 10})
    check(#proxies == 1 and proxies[1].item_requests[1].count == 1, "remaining module request retained")
    check(inventory.get_item_count({name = "assembling-machine-2", quality = "rare"}) == 0, "building charged once")
    pass("quality, health and partial module requests")

    inventory = clear(player)
    inventory.insert({name = "fast-transport-belt", quality = "rare", count = 1})
    local old = surface.create_entity({name = "transport-belt", position = {3, 0}, force = player.force})
    local old_position = old.position
    check(old.order_upgrade({force = player.force, target = {name = "fast-transport-belt", quality = "rare"}}), "upgrade marked")
    construction.upgrade(player, state, 5, {})
    local upgraded = surface.find_entity({name = "fast-transport-belt", quality = "rare"}, old_position)
    check(not old.valid and upgraded and upgraded.quality.name == "rare", "target quality upgraded")
    check(inventory.get_item_count("transport-belt") == 1, "old upgrade material returned")
    check(inventory.get_item_count({name = "fast-transport-belt", quality = "rare"}) == 0, "upgrade charged once")
    pass("native fast replacement and target quality")

    inventory = clear(player)
    inventory.insert({name = "wooden-chest", count = 1})
    -- All but the construction item's slot reject iron plates. Two collided
    -- item types exercise both reinsertion and spill without deleting either.
    for index = 2, #inventory do inventory.set_filter(index, "copper-plate") end
    ghost = surface.create_entity({name = "entity-ghost", inner_name = "wooden-chest", position = {3, 0}, force = player.force})
    surface.create_entity({name = "item-on-ground", stack = {name = "iron-plate", count = 3}, position = ghost.position})
    local damaged = surface.create_entity({name = "item-on-ground", stack = {name = "stone-furnace", count = 1}, position = ghost.position})
    damaged.stack.health = 0.25
    construction.place(player, state, 5, {})
    check(not ghost.valid, "colliding items permit revival")
    local totals = { ["iron-plate"] = inventory.get_item_count("iron-plate"), ["stone-furnace"] = inventory.get_item_count("stone-furnace") }
    local returned_health
    local returned = inventory.find_item_stack("stone-furnace")
    if returned then returned_health = returned.health end
    for _, entity in pairs(surface.find_entities_filtered({type = "item-entity", limit = 50})) do
        totals[entity.stack.name] = (totals[entity.stack.name] or 0) + entity.stack.count
        if entity.stack.name == "stone-furnace" then returned_health = entity.stack.health end
    end
    check(totals["iron-plate"] == 3 and totals["stone-furnace"] == 1,
        "revive item conservation: iron=" .. totals["iron-plate"] .. ", furnace=" .. totals["stone-furnace"])
    check(returned_health == 0.25, "overflow retains item health: " .. tostring(returned_health))
    pass("revive overflow with restricted inventory")

    inventory = clear(player)
    inventory.insert({name = "wooden-chest", count = 1})
    ghost = surface.create_entity({name = "entity-ghost", inner_name = "wooden-chest", position = {3, 0}, force = player.force})
    local obstruction = surface.create_entity({name = "stone-furnace", position = {3, 0}, force = player.force, preserve_ghosts_and_corpses = true})
    construction.place(player, state, 5, {})
    check(ghost.valid and obstruction.valid and inventory.get_item_count("wooden-chest") == 1, "failed revive refunded")
    pass("failed revival preserves materials")

    inventory = clear(player)
    surface.set_tiles({{name = "water", position = {3, 0}}})
    ghost = surface.create_entity({name = "entity-ghost", inner_name = "wooden-chest", position = {3.5, 0.5}, force = player.force})
    inventory.insert({name = "wooden-chest", count = 1})
    construction.place(player, state, 5, {})
    check(ghost.valid and surface.get_tile(3, 0).name == "water", "landfill shortage leaves water")
    inventory.insert({name = "landfill", count = 10})
    local water = surface.find_tiles_filtered({area = ghost.bounding_box, collision_mask = "water_tile", limit = 100})
    construction.place(player, state, 5, {})
    check(not ghost.valid and surface.get_tile(3, 0).name == "landfill", "construction landfill")
    check(inventory.get_item_count("landfill") == 10 - #water, "landfill charged once")
    pass("construction landfill and material shortage")
end

function validation.install(phase)
    if phase ~= "seed" then
        construction = require("scripts.construction")
        player_state = require("scripts.player_state")
        deconstruction = require("scripts.deconstruction")
        gui = require("scripts.gui")
        core = require("scripts.core")
        scan = require("scripts.scan")
    end
    local previous = script.get_event_handler(defines.events.on_tick)
    local started, finished, mining_stage, target, started_tick = false, false, 0, nil, nil
    local function finish(player)
        local scans = storage.players[player.index].scans
        preferences(player)
        storage.players[player.index].scans = scans
        -- Synchronize with either the old or refactored runtime before saving.
        player.set_shortcut_toggled("fbp-toggle", true)
        player.set_shortcut_toggled("fbp-deconstruct-toggle", false)
        game.auto_save("fbp-" .. phase)
        helpers.write_file("fbp-" .. phase .. ".ok", "PASS\n", false)
        pass(phase .. " complete")
        finished = true
    end
    script.on_event(defines.events.on_tick, function(event)
        if previous then previous(event) end
        if finished then return end
        local player = game.players[1]
        if not player then return end
        local ok, err = pcall(function()
            if not started then
                started = true
                if phase == "seed" then prepare(player); finish(player); return end
                assert_preferences(player)
                pass(phase .. " saved preferences")
                if phase == "reload" then
                    local state = storage.players[player.index]
                    local entity = scan.entities(player, state, "save-probe", {type = "entity-ghost", force = player.force})()
                    local tile = scan.tiles(player, state, "save-tiles", {to_be_deconstructed = true, force = player.force})()
                    local expected = storage.scan_expected
                    check(entity and entity.position.x == expected.entity.x and entity.position.y == expected.entity.y,
                        "cached entity scan resumes after reload")
                    check(tile and tile.position.x == expected.tile.x and tile.position.y == expected.tile.y,
                        "cached tile scan resumes after reload")
                    pass("native entity and tile scan cursors survive reload")
                    finish(player); return
                end
                prepare(player)
                operations(player)
            end
            local state = storage.players[player.index]
            if target then
                local done = mining_stage == 4 and not player.surface.get_tile(3, 0).to_be_deconstructed(player.force)
                    or mining_stage ~= 4 and not target.valid
                if done then
                    pass("native mining stage " .. mining_stage)
                    player_state.stop_mining(player, state)
                    target = nil
                else
                    check(event.tick - started_tick < 240, "native mining timed out at stage " .. mining_stage)
                    deconstruction.process(player, state, {})
                    return
                end
            end
            mining_stage = mining_stage + 1
            clear(player)
            if mining_stage <= 3 then
                local names = {"wooden-chest", "tree-01", "big-rock"}
                target = player.surface.create_entity({name = names[mining_stage], position = {3, 0},
                    force = mining_stage == 1 and player.force or "neutral"})
                check(target.order_deconstruction(player.force), "mining target marked")
            elseif mining_stage == 4 then
                player.surface.set_tiles({{name = "stone-path", position = {3, 0}}})
                target = player.surface.get_tile(3, 0)
                check(target.order_deconstruction(player.force), "tile marked")
            else
                local inventory = player.get_main_inventory()
                target = player.surface.create_entity({name = "item-on-ground", stack = {name = "iron-plate", count = 7}, position = {3, 0}})
                check(target.order_deconstruction(player.force), "ground item marked")
                deconstruction.process(player, state, {})
                check(not target.valid and inventory.get_item_count("iron-plate") == 7, "marked ground items collected")
                pass("marked ground items")
                clear(player)
                for x = 2, 4 do
                    player.surface.create_entity({name = "entity-ghost", inner_name = "wooden-chest",
                        position = {x, 0}, force = player.force})
                    player.surface.set_tiles({{name = "stone-path", position = {x, 2}}})
                    check(player.surface.get_tile(x, 2).order_deconstruction(player.force), "scan save tile marked")
                end
                check(scan.entities(player, state, "save-probe", {type = "entity-ghost", force = player.force})(), "scan save entity found")
                check(scan.tiles(player, state, "save-tiles", {to_be_deconstructed = true, force = player.force})(), "scan save tile found")
                local entities, tiles = state.scans["save-probe"], state.scans["save-tiles"]
                check(entities.items[entities.next] and tiles.items[tiles.next], "pending native scan batches")
                storage.scan_expected = {entity = entities.items[entities.next].position, tile = tiles.items[tiles.next].position}
                finish(player)
                return
            end
            started_tick = event.tick
            deconstruction.process(player, state, {})
        end)
        if not ok then
            log("FBP_VALIDATION FAIL " .. tostring(err))
            helpers.write_file("fbp-" .. phase .. ".failed", tostring(err), false)
            finished = true
        end
    end)
end

return validation
