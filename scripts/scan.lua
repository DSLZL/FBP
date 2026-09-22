local scan = {}

local CELL_SIZE, CELL_BUDGET, CANDIDATE_BUDGET = 32, 8, 100

local function restart(cursor)
    cursor.x, cursor.y, cursor.dx, cursor.dy = 0, 0, 0, -1
    cursor.visited, cursor.next, cursor.items = 0, 1, nil
end

local function iterate(player, state, key, filter, tiles)
    local radius = math.min(player.build_distance, state.scan_radius)
    if radius <= 0 then return function() end end
    local cx, cy = math.floor(player.position.x / CELL_SIZE), math.floor(player.position.y / CELL_SIZE)
    state.scans = state.scans or {}
    local cursor = state.scans[key]
    if not cursor or cursor.surface ~= player.surface or cursor.force ~= player.force
        or cursor.cx ~= cx or cursor.cy ~= cy or cursor.radius ~= radius then
        cursor = {surface = player.surface, force = player.force, cx = cx, cy = cy, radius = radius}
        restart(cursor)
        state.scans[key] = cursor
    end
    local cell_count = (2 * math.ceil(radius / CELL_SIZE) + 1) ^ 2
    if cursor.visited == cell_count and (not cursor.items or cursor.next > #cursor.items) then restart(cursor) end
    local inspected, cells = 0, 0
    return function()
        while inspected < CANDIDATE_BUDGET do
            if cursor.items and cursor.next <= #cursor.items then
                local target = cursor.items[cursor.next]
                cursor.next, inspected = cursor.next + 1, inspected + 1
                if target.valid and target.surface == player.surface then
                    local position = target.position
                    local dx, dy = position.x - player.position.x, position.y - player.position.y
                    -- Area queries use collision boxes; assign each center to exactly one cell.
                    if position.x >= cursor.left and position.x < cursor.left + CELL_SIZE
                        and position.y >= cursor.top and position.y < cursor.top + CELL_SIZE
                        and dx * dx + dy * dy <= radius * radius
                        and (tiles or not filter.force or target.force == filter.force
                            or target.force.name == filter.force) then
                        return target
                    end
                end
            else
                cursor.items = nil
                if cursor.visited == cell_count then
                    restart(cursor)
                    if inspected > 0 or cells > 0 then return end
                end
                if cells == CELL_BUDGET then return end
                local left, top = (cx + cursor.x) * CELL_SIZE, (cy + cursor.y) * CELL_SIZE
                if cursor.x == cursor.y or (cursor.x < 0 and cursor.x == -cursor.y)
                    or (cursor.x > 0 and cursor.x == 1 - cursor.y) then
                    cursor.dx, cursor.dy = -cursor.dy, cursor.dx
                end
                cursor.x, cursor.y = cursor.x + cursor.dx, cursor.y + cursor.dy
                cursor.visited = cursor.visited + 1
                local x1, y1 = math.max(left, player.position.x - radius), math.max(top, player.position.y - radius)
                local x2, y2 = math.min(left + CELL_SIZE, player.position.x + radius), math.min(top + CELL_SIZE, player.position.y + radius)
                if x1 < x2 and y1 < y2 then
                    cells = cells + 1
                    filter.area = {{x1, y1}, {x2, y2}}
                    -- ponytail: one cell may contain many overlapping entities; subdivide only if native query cost becomes a problem.
                    cursor.items = tiles and player.surface.find_tiles_filtered(filter)
                        or player.surface.find_entities_filtered(filter)
                    cursor.next, cursor.left, cursor.top = 1, left, top
                end
            end
        end
    end
end

function scan.entities(player, state, key, filter)
    return iterate(player, state, key, filter, false)
end

function scan.tiles(player, state, key, filter)
    return iterate(player, state, key, filter, true)
end

return scan
