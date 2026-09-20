-- Plain Lua 5.2 runner: lua tests/runtime.lua [--multiplayer-only] [source-directory]
local source = "."
local multiplayer_only = false
for _, value in ipairs(arg or {}) do
    if value == "--multiplayer-only" then multiplayer_only = true else source = value end
end
package.path = source .. "/?.lua;" .. package.path

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

local function equal(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function inventory(items, capacity)
    local inv = {valid = true, items = items or {}, capacity = capacity or math.huge}
    local function key(stack)
        if type(stack) == "string" then return stack .. ":normal" end
        assert(type(stack.quality or "normal") == "string", "item quality must be a string")
        return stack.name .. ":" .. (stack.quality or "normal")
    end
    inv.get_item_count = function(stack) return inv.items[key(stack)] or 0 end
    inv.remove = function(stack)
        local count = math.min(inv.get_item_count(stack), stack.count)
        inv.items[key(stack)] = inv.get_item_count(stack) - count
        return count
    end
    inv.insert = function(stack)
        local count = math.min(stack.count, inv.capacity)
        inv.items[key(stack)] = inv.get_item_count(stack) + count
        return count
    end
    inv.find_item_stack = function(stack)
        if inv.get_item_count(stack) == 0 then return nil end
        local item_key = key(stack)
        return setmetatable({valid = true, health = inv.health or 1}, {
            __index = function(_, field)
                if field == "count" then return inv.items[item_key] end
                if field == "valid_for_read" then return inv.items[item_key] > 0 end
            end,
            __newindex = function(_, field, value)
                assert(field == "count")
                inv.items[item_key] = value
            end
        })
    end
    inv.count_empty_stacks = function() return 10 end
    for i = 1, 10 do inv[i] = {} end
    return inv
end

local function surface(index)
    local result = {index = index or 1, valid = true, queries = {}, spilled = {}}
    result.find_entities_filtered = function(filter)
        assert(filter.limit and filter.limit > 0, "unbounded entity scan")
        result.queries[#result.queries + 1] = filter
        return {}
    end
    result.find_tiles_filtered = function(filter)
        assert(filter.limit and filter.limit > 0, "unbounded tile scan")
        return {}
    end
    result.spill_item_stack = function(request)
        result.spilled[#result.spilled + 1] = request.stack
        return {}
    end
    return result
end

local function player(index, player_inventory)
    local result = {
        index = index, name = "P" .. index, valid = true, connected = true, admin = true,
        controller_type = defines.controllers.character, position = {x = 0, y = 0},
        surface = surface(index), force = {name = "player"}, build_distance = 100,
        walking_state = {walking = false}, mining_state = {mining = false},
        shortcuts = {}, messages = {}, gui = {screen = {}},
        settings = { ["fbp-speed"] = {value = 1}, ["fbp-scan-radius"] = {value = 100},
            ["fbp-enable-for-me"] = {value = true}, ["fbp-debug-mode"] = {value = "none"} }
    }
    result.inventory = player_inventory or inventory()
    result.get_main_inventory = function() return result.inventory end
    result.set_shortcut_toggled = function(name, value) result.shortcuts[name] = value end
    result.print = function(message) result.messages[#result.messages + 1] = message end
    result.create_local_flying_text = function() end
    result.update_selected_entity = function(position) result.selected_position = position end
    return result
end

local function environment(indices)
    for name in pairs(package.loaded) do
        if name:match("^scripts%.") then package.loaded[name] = nil end
    end
    defines = {controllers = {character = 1, god = 2, editor = 3, spectator = 4, remote = 5}, events = {}}
    for _, name in ipairs({"on_player_created", "on_player_joined_game", "on_tick", "on_player_demoted",
        "on_runtime_mod_setting_changed", "on_gui_click", "on_gui_checked_state_changed", "on_lua_shortcut",
        "on_player_left_game", "on_player_removed", "on_player_controller_changed", "on_player_changed_surface"}) do
        defines.events[name] = name
    end
    storage = {}
    local handlers, periodic, commands_registered = {}, {}, {}
    script = {
        on_init = function(fn) handlers.init = fn end,
        on_configuration_changed = function(fn) handlers.configuration = fn end,
        on_event = function(event, fn)
            if type(event) == "table" then for _, name in pairs(event) do handlers[name] = fn end
            else handlers[event] = fn end
        end,
        on_nth_tick = function(tick, fn) periodic[tick] = fn end
    }
    commands = {add_command = function(name, _, fn) commands_registered[name] = fn end}
    settings = {
        global = {["fbp-allow-others"] = {value = true}},
        get_player_settings = function(p) return p.settings end
    }
    game = {players = {}, connected_players = {}}
    game.get_player = function(index) return game.players[index] end
    for _, index in ipairs(indices or {1}) do
        local p = player(index)
        game.players[index] = p
        game.connected_players[#game.connected_players + 1] = p
    end
    dofile(source .. "/control.lua")
    handlers.init()
    return handlers, periodic, commands_registered
end

local function placement_scans(p)
    local count = 0
    for _, query in ipairs(p.surface.queries) do
        if query.type == "entity-ghost" then count = count + 1 end
    end
    return count
end

test("multiplayer A/B/C joins and leaves preserve state association", function()
    local handlers = environment({1, 2, 3})
    local b, c, a = game.players[1], game.players[2], game.players[3]
    storage.players[1].active, storage.players[2].active, storage.players[3].active = true, false, true
    for _, online in ipairs({{b, a}, {b, c}, {b, c, a}, {b, a}, {a, c, b}, {a, b}}) do
        game.connected_players = online
        local expected = {}
        for _, p in ipairs(online) do
            p.surface.queries = {}
            expected[p.index] = storage.players[p.index].active and 1 or 0
        end
        handlers.on_tick({tick = 30})
        for _, p in ipairs(online) do
            equal(placement_scans(p), expected[p.index], "player " .. p.index .. " placement scans")
        end
        equal(storage.players[2].active, false, "C preference")
    end
end)

test("sparse IDs keep each player's speed, radius and tick phase", function()
    local handlers = environment({4, 17, 91})
    for _, index in ipairs({4, 17, 91}) do
        local p = game.players[index]
        p.settings["fbp-speed"].value = index == 17 and 7 or 3
        p.settings["fbp-scan-radius"].value = index == 91 and 50 or 20
        handlers.on_player_joined_game({player_index = index})
        storage.players[index].active = true
        storage.players[index].features.auto_upgrade = index ~= 17
    end
    game.connected_players = {game.players[91], game.players[4]}
    for tick = 1, 15 do
        for _, p in ipairs(game.connected_players) do p.surface.queries = {} end
        handlers.on_tick({tick = tick})
        for _, p in ipairs(game.connected_players) do
            equal(placement_scans(p), (tick + p.index) % 3 == 0 and 1 or 0, "stable phase " .. p.index)
            for _, query in ipairs(p.surface.queries) do
                equal(query.radius, p.settings["fbp-scan-radius"].value, "personal radius")
            end
        end
    end
end)

test("periodic permission checks use actual online player IDs", function()
    local _, periodic = environment({1, 2, 3})
    local b, c, a = game.players[1], game.players[2], game.players[3]
    b.admin, c.admin, a.admin = true, false, false
    storage.players[2].active, storage.players[3].active = true, true
    game.connected_players = {b, a}
    settings.global["fbp-allow-others"].value = false
    periodic[1800]()
    equal(storage.players[3].active, false, "online A loses permission")
    equal(storage.players[2].active, true, "offline C is untouched")
end)

-- Operation and transition cases follow the shared multiplayer checks.
if not multiplayer_only then
    test("migration preserves false values, legacy precedence and independent tables", function()
        local handlers = environment({1, 2, 3})
        storage.players = {
            [1] = {active = true, deconstruct_active = false, placement_acc = 9, custom = "kept",
                features = {auto_place = false, auto_deconstruct = true, auto_modules = false}},
            [2] = {features = {auto_mine = true}},
            [3] = {features = {auto_deconstruct = false, auto_mine = true}}
        }
        for _ = 1, 2 do
            handlers.configuration({})
            equal(storage.players[1].active, true)
            equal(storage.players[1].deconstruct_active, false)
            equal(storage.players[1].features.auto_place, false)
            equal(storage.players[1].features.auto_modules, false)
            equal(storage.players[1].placement_acc, 9)
            equal(storage.players[1].custom, "kept")
            equal(storage.players[2].deconstruct_active, true)
            equal(storage.players[3].deconstruct_active, false)
        end
        assert(storage.players[1].features ~= storage.players[2].features)
        equal(game.players[2].shortcuts["fbp-deconstruct-toggle"], true)
    end)

    test("global policy, personal disable, GUI and shortcuts share transitions", function()
        local handlers, _, registered = environment({1, 2})
        local p, state = game.players[2], storage.players[2]
        p.admin = false
        handlers.on_gui_checked_state_changed({player_index = 2,
            element = {valid = true, name = "fbp-feature-auto_deconstruct", state = true}})
        equal(state.deconstruct_active, true)
        handlers.on_tick({tick = 1})
        equal(state.features.auto_deconstruct, true)
        equal(p.shortcuts["fbp-deconstruct-toggle"], true)
        settings.global["fbp-allow-others"].value = false
        handlers.on_runtime_mod_setting_changed({setting = "fbp-allow-others"})
        equal(state.deconstruct_active, false)
        equal(p.shortcuts["fbp-deconstruct-toggle"], false)
        p.admin = true
        handlers.on_lua_shortcut({player_index = 2, prototype_name = "fbp-toggle"})
        equal(state.active, true)
        p.settings["fbp-enable-for-me"].value = false
        handlers.on_runtime_mod_setting_changed({player_index = 2, setting = "fbp-enable-for-me"})
        equal(state.active, false)
        registered["fbp-check"]({})
        registered["fbp-check"]({player_index = 2})
        assert(#p.messages > 0)
    end)

    test("leave and removal affect only the departing player", function()
        local handlers = environment({1, 3})
        local p, state = game.players[3], storage.players[3]
        storage.players[1].active, state.active = true, true
        state.auto_mining = {surface = p.surface, position = {x = 1, y = 1}}
        p.mining_state = {mining = true, position = {x = 1, y = 1}}
        handlers.on_player_left_game({player_index = 3})
        equal(p.mining_state.mining, false)
        equal(state.active, true)
        equal(storage.players[1].active, true)
        handlers.on_player_removed({player_index = 3})
        equal(storage.players[3], nil)
        equal(storage.players[1].active, true)
    end)

    test("editor blocks automation and unsupported controllers never write mining state", function()
        local handlers = environment()
        local p, state = game.players[1], storage.players[1]
        state.active, state.deconstruct_active = true, true
        p.controller_type = defines.controllers.editor
        handlers.on_player_controller_changed({player_index = 1})
        equal(state.active, false)
        equal(state.deconstruct_active, false)
        p.controller_type = defines.controllers.remote
        state.auto_mining = {surface = p.surface, position = p.position}
        p.mining_state = nil
        setmetatable(p, {__newindex = function(_, key) error("unexpected controller write: " .. key) end})
        require("scripts.player_state").stop_mining(p, state)
        equal(state.auto_mining, nil)
    end)

    test("cycle shares arbitration and retains Place then Upgrade then Deconstruct", function()
        local handlers = environment()
        local state = storage.players[1]
        state.active, state.deconstruct_active = true, true
        local order, seen = {}, nil
        local function operation(label)
            return function(_, _, third, fourth)
                local context = fourth or third
                if seen then equal(context, seen) else seen = context end
                order[#order + 1] = label
            end
        end
        require("scripts.construction").place = operation("place")
        require("scripts.construction").upgrade = operation("upgrade")
        require("scripts.deconstruction").process = operation("deconstruct")
        handlers.on_tick({tick = 1})
        equal(table.concat(order, ","), "place,upgrade,deconstruct")
    end)

    local function invalidate(entity)
        for key in pairs(entity) do entity[key] = nil end
        entity.valid = false
        setmetatable(entity, {__index = function(_, key) error("read invalid entity: " .. key) end})
    end

    local function ghost_for(p, quality)
        local ghost = {valid = true, surface = p.surface, position = {x = 2, y = 2},
            ghost_name = "assembling-machine-2", quality = {name = quality or "normal"},
            ghost_prototype = {items_to_place_this = {{name = "assembling-machine-2", count = 1}}},
            bounding_box = {{1, 1}, {4, 4}}}
        p.surface.find_entities_filtered = function(filter)
            assert(filter.limit > 0)
            equal(filter.force, p.force)
            return {ghost}
        end
        return ghost
    end

    test("revival uses exact quality and health, handles overflow, and never rereads ghost", function()
        environment()
        local p, state = game.players[1], storage.players[1]
        p.inventory = inventory({["assembling-machine-2:rare"] = 1, ["assembling-machine-2:normal"] = 4}, 0)
        p.inventory.health = 0.4
        local ghost = ghost_for(p, "rare")
        local revived = {valid = true, health = 100, max_health = 200, get_module_inventory = function() end}
        ghost.revive = function(options)
            equal(options.overflow, p.inventory)
            invalidate(ghost)
            return {{name = "iron-plate", quality = "normal", count = 3}}, revived
        end
        require("scripts.construction").place(p, state, 5, {})
        equal(p.inventory.get_item_count({name = "assembling-machine-2", quality = "rare"}), 0)
        equal(p.inventory.get_item_count("assembling-machine-2"), 4)
        equal(revived.health, 80)
        equal(p.surface.spilled[1].count, 3)
    end)

    test("failed revival refunds building and landfill shortage changes no tiles", function()
        environment()
        local p, state = game.players[1], storage.players[1]
        p.inventory = inventory({["assembling-machine-2:normal"] = 1})
        local ghost = ghost_for(p)
        ghost.revive = function() return nil end
        require("scripts.construction").place(p, state, 5, {})
        equal(p.inventory.get_item_count("assembling-machine-2"), 1)
        p.surface.find_tiles_filtered = function() return {{position = {x = 2, y = 2}}} end
        ghost.revive = function() error("must not revive without landfill") end
        require("scripts.construction").place(p, state, 5, {})
        equal(p.inventory.get_item_count("assembling-machine-2"), 1)
    end)

    test("partial module delivery retains missing modules and non-module requests", function()
        environment()
        local p, state = game.players[1], storage.players[1]
        p.inventory = inventory({["assembling-machine-2:normal"] = 1, ["speed-module:rare"] = 1})
        local ghost = ghost_for(p)
        local transferred = 0
        local modules = {{transfer_stack = function(stack, count)
            stack.count = stack.count - count
            transferred = transferred + count
        end}, {transfer_stack = function() error("no second module available") end}}
        local proxy = {valid = true, insert_plan = {
            {id = {name = "speed-module", quality = "rare"}, items = {in_inventory = {
                {inventory = 4, stack = 0, count = 1}, {inventory = 4, stack = 1, count = 1}}}},
            {id = {name = "iron-plate", quality = "normal"}, items = {in_inventory = {{inventory = 1, stack = 0, count = 2}}}}
        }}
        local revived = {valid = true, get_module_inventory = function() return modules end,
            get_inventory = function(id) if id == 4 then return modules end end}
        ghost.revive = function() invalidate(ghost); return {}, revived, proxy end
        require("scripts.construction").place(p, state, 5, {})
        equal(transferred, 1)
        equal(#proxy.insert_plan, 2)
        equal(#proxy.insert_plan[1].items.in_inventory, 1)
        equal(proxy.insert_plan[1].items.in_inventory[1].stack, 1)
        equal(proxy.insert_plan[2].items.in_inventory[1].count, 2)
    end)

    test("upgrades honor target quality, skip shortages and survive old entity invalidation", function()
        environment()
        local p, state = game.players[1], storage.players[1]
        p.inventory = inventory({["fast-transport-belt:rare"] = 1})
        local function marked(x, item)
            return {valid = true, surface = p.surface, position = {x = x, y = 0},
                quality = {name = "normal"}, force = p.force, direction = 0, type = "transport-belt", mirroring = false,
                to_be_upgraded = function() return true end,
                get_upgrade_target = function() return {name = item, items_to_place_this = {{name = item, count = 1}}}, {name = "rare"} end}
        end
        local missing, available = marked(1, "express-transport-belt"), marked(2, "fast-transport-belt")
        p.surface.find_entities_filtered = function() return {missing, available} end
        p.surface.create_entity = function(options)
            equal(options.quality, "rare")
            equal(options.name, "fast-transport-belt")
            invalidate(available)
            return {valid = true}
        end
        local context = {}
        require("scripts.construction").upgrade(p, state, 5, context)
        equal(p.inventory.get_item_count({name = "fast-transport-belt", quality = "rare"}), 0)
        equal(require("scripts.utils").is_consumed(context, p.surface, {x = 2, y = 0}), true)
    end)

    test("automatic mining yields to walking and preserves a different manual target", function()
        environment()
        local p, state = game.players[1], storage.players[1]
        local entity = {valid = true, type = "tree", minable = true, position = {x = 2, y = 2}, to_be_deconstructed = function() return true end}
        p.surface.find_entities_filtered = function() return {entity} end
        p.update_selected_entity = function() p.selected = entity end
        local deconstruct = require("scripts.deconstruction")
        deconstruct.process(p, state, {})
        equal(p.mining_state.mining, true)
        assert(state.auto_mining)
        p.walking_state.walking = true
        deconstruct.process(p, state, {})
        equal(p.mining_state.mining, false)
        p.walking_state.walking = false
        deconstruct.process(p, state, {})
        p.mining_state = {mining = true, position = {x = 9, y = 9}}
        require("scripts.player_state").set_active(p, "deconstruct_active", false)
        equal(p.mining_state.mining, true)
        equal(p.mining_state.position.x, 9)
        equal(state.auto_mining, nil)
    end)

    test("marked ground items retain partial remainder and arbitration skips consumed tiles", function()
        environment()
        local p, state = game.players[1], storage.players[1]
        p.inventory = inventory({}, 2)
        local ground = {valid = true, position = {x = 2, y = 2},
            stack = {name = "iron-plate", quality = "normal", count = 5},
            to_be_deconstructed = function() return true end}
        ground.destroy = function() invalidate(ground) end
        p.surface.find_entities_filtered = function(filter) return filter.type == "item-entity" and {ground} or {} end
        local context = {}
        require("scripts.deconstruction").process(p, state, context)
        equal(ground.stack.count, 3)
        equal(p.inventory.get_item_count("iron-plate"), 2)
        require("scripts.deconstruction").process(p, state, context)
        equal(ground.stack.count, 3)
        p.inventory.capacity = 3
        require("scripts.deconstruction").process(p, state, {})
        equal(ground.valid, false)
        equal(p.inventory.get_item_count("iron-plate"), 5)
    end)

    test("tile deconstruction uses native inventory-aware mining and skips tile proxies", function()
        environment()
        local p, state = game.players[1], storage.players[1]
        local tile = {valid = true, position = {x = 2, y = 2}, to_be_deconstructed = function() return true end}
        local proxy = {valid = true, type = "deconstructible-tile-proxy", minable = true,
            position = tile.position, to_be_deconstructed = function() return true end}
        p.surface.find_entities_filtered = function() return {proxy} end
        p.surface.find_tiles_filtered = function() return {tile} end
        p.update_selected_entity = function() error("tile proxies must not become entity mining targets") end
        p.mine_tile = function(value) equal(value, tile); return true end
        local context = {}
        require("scripts.deconstruction").process(p, state, context)
        equal(require("scripts.utils").is_consumed(context, p.surface, tile.position), true)
        equal(state.auto_mining, nil)
    end)

    test("failed fast replacement refunds matching quality and health", function()
        environment()
        local p, state = game.players[1], storage.players[1]
        p.inventory = inventory({["fast-transport-belt:rare"] = 1})
        p.inventory.health = 0.25
        local inserted = p.inventory.insert
        p.inventory.insert = function(stack) equal(stack.health, 0.25); return inserted(stack) end
        local entity = {valid = true, surface = p.surface, position = {x = 2, y = 0},
            force = p.force, direction = 0, type = "transport-belt", mirroring = false,
            to_be_upgraded = function() return true end,
            get_upgrade_target = function()
                return {name = "fast-transport-belt", items_to_place_this = {{name = "fast-transport-belt", count = 1}}}, {name = "rare"}
            end}
        p.surface.find_entities_filtered = function() return {entity} end
        p.surface.create_entity = function() return nil end
        require("scripts.construction").upgrade(p, state, 5, {})
        equal(p.inventory.get_item_count({name = "fast-transport-belt", quality = "rare"}), 1)
        equal(entity.valid, true)
    end)
end

print(string.format("Runtime checks: %d passed, %d failed", passed, failed))
if failed > 0 then error("runtime checks failed") end
