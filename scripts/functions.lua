-- Factorio base
local crash_site = require("crash-site")
local util = require("util")

local functions = {}

-- Function to append lines to log file (path is scripts-output/freeplay-forces.log)
functions.append_localized_string_to_log = function(message)
    game.write_file("freeplay-forces.log", message, true)
    game.write_file("freeplay-forces.log", "\n", true)
end

-- Function to validate if cmd issuer is admin
functions.check_admin = function(cmd_player, name)
    if cmd_player.admin then
        return true
    else
        cmd_player.print({"cant-run-command-not-admin", name})
        return false
    end
end

-- Function to validate + parse command arguments
functions.check_args = function(cmd_event)
    local args = cmd_event.parameter
    if not args then
        return false
    else
        -- Separate the first space-separated argument from the rest of the 
        -- arguments
        local force_name, force_players = args:match("(%S+)%s*(.*)")
        -- force_name is required at a minimum
        if not force_name then
            return false
        else
            -- Build a table of player names from the string of space-separated 
            -- player names
            local force_players_table = nil
            if force_players then
                force_players_table = {}
                for player_name in force_players:gmatch("%S+") do
                    table.insert(force_players_table, player_name)
                end
            end
            local data = {force_name, force_players_table}
            return data
        end
    end
end

-- Function to check if cmd_player is a force admin
functions.check_force_admin = function(cmd_player)
    local cmd_player_force_name = cmd_player.force.name
    local cmd_player_force_admin = nil
    if global.ff_admin[cmd_player_force_name] then
        for admin_name, status in pairs(global.ff_admin[cmd_player_force_name]) do
            if admin_name == cmd_player.name and status then
                cmd_player_force_admin = status
            end
        end
    end
    return cmd_player_force_admin
end

-- Function to check if force players have cutscene
functions.check_force_players_cutscene =
    function(force_players_converted)
        global.crash_site_cutscene_active = nil
        for _, player in pairs(force_players_converted) do
            if player.controller_type == defines.controllers.cutscene then
                player.exit_cutscene()
            end
            if player.gui.screen.skip_cutscene_label then
                player.gui.screen.skip_cutscene_label.destroy()
            end
        end
    end

-- Function to check if the player's "character" is valid
functions.check_if_player_character = function(player)
    if not player.character then return false end
    if not player.character.name then return false end
    if not player.character.valid then return false end
    return true
end

-- Function to chart the starting area (straight up ripped from Vanilla freeplay.lua,
-- with some adjustments)
functions.chart_starting_area = function(force, surface)
    local r = global.chart_distance or 200
    local origin = force.get_spawn_position(surface)
    force.chart(surface,
                {{origin.x - r, origin.y - r}, {origin.x + r, origin.y + r}})
end

-- Function to clear of any cliffs from radius global.chart_distance or 200
functions.clear_cliffs = function(position, surface)
    -- Define our radius
    local r = global.chart_distance or 200
    local area = {
        {position.x - r, position.y - r}, {position.x + r, position.y + r}
    }
    local cliffs = surface.find_entities_filtered({area = area, type = "cliff"})
    for _, cliff in pairs(cliffs) do
        -- Destroy the cliff
        cliff.destroy()
    end
    functions.append_localized_string_to_log({
        "message.cliffs-cleared", r, position.x .. ", " .. position.y,
        surface.name
    })
end

-- Function to clear of any hostiles from radius global.chart_distance or 200
functions.clear_hostiles = function(position, surface)
    -- Define our radius
    local r = global.chart_distance or 200
    local area = {
        {position.x - r, position.y - r}, {position.x + r, position.y + r}
    }
    local enemies = surface.find_entities_filtered({
        area = area,
        force = "enemy"
    })
    for _, enemy in pairs(enemies) do
        -- Destroy the enemy
        enemy.destroy()
    end
    functions.append_localized_string_to_log({
        "message.hostiles-cleared", r, position.x .. ", " .. position.y,
        surface.name
    })
end

-- Function to clear all inventories of all players in a force
functions.clear_player_inventories = function(force_players_converted)
    -- Iterate over all the array of players
    for _, player in pairs(force_players_converted) do
        if player.character then
            -- Iterate over each inventory slot
            local inventories = {
                defines.inventory.character_main,
                defines.inventory.character_guns,
                defines.inventory.character_ammo,
                defines.inventory.character_armor,
                defines.inventory.character_trash
            }
            for _, inv_id in pairs(inventories) do
                local inventory = player.get_inventory(inv_id)
                if inventory then
                    -- Clear the inventory
                    inventory.clear()
                end
            end
        end
    end
end

-- Function to generate random coordinates within a variable min/max.
-- Optionally take a position to adjust the base instead of 0,0
functions.create_random_coordinates = function(range, position)
    local x, y
    -- ensure that the position is greater than or equal to half of the range
    repeat
        x = math.random(-range, range)
        y = math.random(-range, range)
    until math.sqrt(x * x + y * y) >= range / 2
    -- If a position is provided, adjust the coordinates
    if position then
        x = x + position.x
        y = y + position.y
    end
    return {x = x, y = y}
end

-- Function to ensure "standard" ore spawn around a force's starting radius
functions.ensure_ore_spawn = function(position, radius, surface)
    local area = {
        {position.x - radius, position.y - radius},
        {position.x + radius, position.y + radius}
    }
    -- List of standard ores
    local ores = {"iron-ore", "copper-ore", "coal", "stone"}
    local found_ores = {}
    -- Check for each ore type in the area
    for _, ore_name in pairs(ores) do
        local ore_patch = surface.find_entities_filtered {
            area = area,
            name = ore_name
        }
        if next(ore_patch) ~= nil then found_ores[ore_name] = true end
    end
    -- Spawn missing ores
    for _, ore_name in pairs(ores) do
        if not found_ores[ore_name] then
            -- Calculate spawn position
            local spawn_position = functions.create_random_coordinates(radius,
                                                                       position)
            local size = 10
            local density = 15
            local ore = nil
            -- Taken from the Wiki
            -- https://wiki.factorio.com/Console#Add_new_resource_patch
            -- Calculate ore amount
            local amount = 0
            for y = -size, size do
                for x = -size, size do
                    local a = (size + 1 - math.abs(x)) * 10
                    local b = (size + 1 - math.abs(y)) * 10
                    if a < b then
                        ore = math.random(a * density - a * (density - 8),
                                          a * density + a * (density - 8))
                    end
                    if b < a then
                        ore = math.random(b * density - b * (density - 8),
                                          b * density + b * (density - 8))
                    end
                    local tile_x = spawn_position.x + x
                    local tile_y = spawn_position.y + y
                    if surface.get_tile(tile_x, tile_y).collides_with(
                        "ground-tile") then
                        if ore and ore > 0 then
                            amount = amount + ore
                        end
                        surface.create_entity({
                            name = ore_name,
                            amount = ore,
                            position = {tile_x, tile_y}
                        })
                    end
                end
            end

            -- Print message
            local message = {
                "message.spawning-ore", ore_name, amount,
                spawn_position.x .. ", " .. spawn_position.y, surface.name
            }
            functions.append_localized_string_to_log(message)
        end
    end
end

-- Function to find a suitable location for a team to crash at
functions.find_suitable_location = function(cmd_player, surface, range,
                                            attempts, check_crash_site_compat,
                                            clear_cliffs, clear_hostiles)
    -- Set check_crash_site_compat to false by default
    check_crash_site_compat = check_crash_site_compat or false

    -- Function to check if the position is suitable
    local function is_suitable_position(position)
        -- If we want to check crash site compatibility
        if check_crash_site_compat then
            -- Check if the position can fit a crash site
            if not surface.can_place_entity({
                name = "crash-site-spaceship",
                position = position
            }) then return false end
        end
        -- Define the area to check around the position
        local area = {
            {position.x - 10, position.y - 10},
            {position.x + 10, position.y + 10}
        }
        -- Check for water tiles and biter nests
        local tiles = surface.find_tiles_filtered({area = area})
        local water = 0
        -- Check each tile to see if it's water
        for _, tile in pairs(tiles) do
            if water ~= 0 then break end
            if tile and tile.valid then
                -- Check if the tile's collision mask includes "water-tile"
                if tile.prototype.collision_mask["water-tile"] then
                    water = water + 1
                end
            end
        end
        local enemies = surface.find_entities_filtered({
            area = area,
            type = {"unit", "unit-spawner"}
        })
        return water == 0 and #enemies == 0
    end

    -- Attempt to find a suitable location (max tries = attempts)
    for i = 1, attempts do
        local position = functions.create_random_coordinates(range)
        -- Request and force generate chunks
        surface.request_to_generate_chunks(position, 7)
        surface.force_generate_chunk_requests()
        local fail_message = {
            "message.no-suitable-location", i, position.x, position.y
        }
        local success_message = {
            "message.suitable-location", i, position.x, position.y
        }
        -- Check if the position is suitable
        if is_suitable_position(position) then
            -- Return the position if it is suitable
            cmd_player.print(success_message)
            functions.append_localized_string_to_log(success_message)
            -- Clear any cliffs if specified
            if clear_cliffs then
                functions.clear_cliffs(position, surface)
            end
            -- Clear any hostiles if specified
            if clear_hostiles then
                functions.clear_hostiles(position, surface)
            end
            -- If the user wants to ensure standard ores are spawned
            if settings.startup["ff-ensure-ore-spawn"].value then
                -- Ensure standard ores are spawned
                functions.ensure_ore_spawn(position, 200, surface)
            end
            return position
        else
            functions.append_localized_string_to_log(fail_message)
            -- Delete the chunk if it is not suitable
            surface.delete_chunk(position)
        end
    end
    -- Return nil if no suitable location is found
    return nil
end

-- Function to free chunks from a force on a given surface
functions.free_chunks_for_force = function(cmd_player, surface, force)
    for chunk in surface.get_chunks() do
        if force.is_chunk_charted(surface, chunk) then
            local chunk_charted_by_another_force = false
            -- Loop through the game's forces
            for _, iter_force in pairs(game.forces) do
                -- Check if the iter_force is not force
                if iter_force ~= force then
                    -- Ensure iter_force has not charted the chunk
                    if iter_force.is_chunk_charted(surface, chunk) then
                        chunk_charted_by_another_force = true
                        break
                    end
                end
            end
            -- If the chunk has not been charted by another force
            if not chunk_charted_by_another_force then
                -- Delete the chunk
                surface.delete_chunk(chunk)
                local message = {
                    "message.removed-force-chunk", force.name, chunk.x, chunk.y
                }
                cmd_player.print(message)
                functions.append_localized_string_to_log(message)
            end
        end
    end
end

-- Function to give player Freeplay respawn_items
functions.give_fp_respawn_items = function(player)
    -- Get respawn_items from Freeplay and insert into player
    local respawn_items = remote.call("freeplay", "get_respawn_items")
    util.insert_safe(player, respawn_items)
end

-- Function to notify all online force administrators of a localized string
functions.notify_all_force_admins = function(ff_admin, force, message)
    if ff_admin[force.name] then
        for admin_name, status in pairs(ff_admin[force.name]) do
            local force_admin = game.get_player(admin_name)
            if force_admin and force_admin.connected and status then
                force_admin.print(message)
            end
        end
        functions.append_localized_string_to_log(message)
    end
end

-- Function to reproduce a vanilla crash site from Freeplay scenario
functions.reproduce_crash_site = function(cmd_player, force_players_converted,
                                          position, force_surface)
    -- Retrieve the Freeplay crash site items from the scenario interface
    local fp_crashed_debris_items = remote.call("freeplay", "get_debris_items")
    local fp_created_items = remote.call("freeplay", "get_created_items")
    local fp_crashed_ship_items = remote.call("freeplay", "get_ship_items")
    local fp_crashed_ship_parts = remote.call("freeplay", "get_ship_parts")
    -- If startup settings says to give to everybody
    if settings.startup["ff-give-to-entire-force"].value then
        -- Loop over all players in the force
        for _, force_player in pairs(force_players_converted) do
            -- Add created player items to player's inventory
            util.insert_safe(force_player, fp_created_items)
            -- Remove debris/crashed ship items from player's inventory
            util.remove_safe(force_player, fp_crashed_debris_items)
            util.remove_safe(force_player, fp_crashed_ship_items)
            force_player.get_main_inventory().sort_and_merge()
        end
    else
        -- Otherwise, add created player items to the primary force player's inventory
        util.insert_safe(force_players_converted[1], fp_created_items)
        -- Remove debris/crashed ship items from the primary force player's inventory
        util.remove_safe(force_players_converted[1], fp_crashed_debris_items)
        util.remove_safe(force_players_converted[1], fp_crashed_ship_items)
        force_players_converted[1].get_main_inventory().sort_and_merge()
    end
    -- Create the crash site and mark as active
    crash_site.create_crash_site(force_surface, position,
                                 util.copy(fp_crashed_ship_items),
                                 util.copy(fp_crashed_debris_items),
                                 util.copy(fp_crashed_ship_parts))
    global.crash_site_cutscene_active = true
    -- Teleport players of the newly created force to the specified position,
    -- try to avoid collisions
    for _, force_player in pairs(force_players_converted) do
        if force_player.character then
            force_player.character.destructible = false
            local safe_teleport_position =
                force_surface.find_non_colliding_position(
                    force_player.character.name, position, 32, 1) or position
            force_player.teleport(safe_teleport_position)
            crash_site.create_cutscene(force_player, {
                safe_teleport_position.x, safe_teleport_position.y
            })
            local message = {
                "message.tp-force-players", force_player.name,
                safe_teleport_position.x, safe_teleport_position.y,
                force_surface.name
            }
            cmd_player.print(message)
            functions.append_localized_string_to_log(message)
        end
    end
    -- Merge the keys from the 4 dictionaries above which start with "fp_" into
    -- a single array of the keys
    local fp_scenario_entities = {}
    for k, _ in pairs(fp_crashed_debris_items) do
        table.insert(fp_scenario_entities, k)
    end
    for k, _ in pairs(fp_crashed_ship_items) do
        table.insert(fp_scenario_entities, k)
    end
    for k, _ in pairs(fp_created_items) do
        table.insert(fp_scenario_entities, k)
    end
    for _, v in pairs(fp_crashed_ship_parts) do
        table.insert(fp_scenario_entities, v["name"])
    end
    -- Manually add 'crash-site-spaceship' to the list of entities
    table.insert(fp_scenario_entities, "crash-site-spaceship")
    -- Iterate through each Freeplay scenario item type
    for _, item_type in ipairs(fp_scenario_entities) do
        -- Find entities of the item type within a 100 radius
        local entities = force_surface.find_entities_filtered({
            name = item_type,
            position = position,
            radius = 100
        })
        -- Set the force of each entity found to force_players_converted[1]'s force
        for _, entity in pairs(entities) do
            entity.force = force_players_converted[1].force
        end
    end
    -- Print intro message
    force_players_converted[1].force.print(
        global.custom_intro_message or {"msg-intro"})
end

-- Remove the player from the force
functions.reset_player_force = function(player)
    player.clear_console()
    player.force = game.forces["player"]
end

-- Teleport the player back to Nauvis
functions.return_player_to_nauvis = function(cmd_player, player)
    local nauvis = game.surfaces[1]
    local force_spawn_position = game.forces["player"]
                                     .get_spawn_position(nauvis)
    local safe_teleport_position = nauvis.find_non_colliding_position(
                                       player.character.name,
                                       force_spawn_position, 32, 1) or
                                       force_spawn_position
    player.teleport(safe_teleport_position, nauvis)
    -- If a cmd_player was supplied, notify them of teleportation
    if cmd_player then
        local message = {
            "message.tp-force-players", player.name, safe_teleport_position.x,
            safe_teleport_position.y, nauvis.name
        }
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
    end
end

-- Function to return players to Nauvis
functions.return_players_to_nauvis = function(cmd_player,
                                              force_players_converted)
    -- Spill the player' inventories
    functions.spill_player_inventories(force_players_converted)
    -- Iterate over all the array of players and validate + tp them to Nauvis
    for _, player in pairs(force_players_converted) do
        if player.connected then
            -- If the player is connected, teleport them back to Nauvis
            functions.reset_player_force(player)
            functions.return_player_to_nauvis(cmd_player, player)
        else
            -- If the player isn't connected, mark them to be teleported
            -- back to Nauvis on next join
            table.insert(global.ff_migrants, player.name)
            local message = {"message.migrant-player-tracked", player.name}
            if cmd_player then cmd_player.print(message) end
        end
    end
end

-- Function to make all players in a force to drop all items in front of them
functions.spill_player_inventories = function(force_players_converted)
    -- Iterate over all the array of players
    for _, player in pairs(force_players_converted) do
        if player.character then
            -- Get the position in front of the player
            local drop_position = player.position
            drop_position.x = drop_position.x + 1

            -- Iterate over each inventory slot and spill the items
            local inventories = {
                defines.inventory.character_main,
                defines.inventory.character_guns,
                defines.inventory.character_ammo,
                defines.inventory.character_armor,
                defines.inventory.character_trash
            }
            for _, inv_id in pairs(inventories) do
                local inventory = player.get_inventory(inv_id)
                if inventory then
                    -- Spill the contents of the inventory
                    for name, count in pairs(inventory.get_contents()) do
                        player.surface.spill_item_stack(drop_position, {
                            name = name,
                            count = count
                        }, true, player.force, false)
                    end
                end
            end
        end
    end
    -- Clear all inventories, we don't want duplicated entities
    functions.clear_player_inventories(force_players_converted)
end

-- Function to validate a list of player names, returning a table with the actual
-- player objects belonging to a force
functions.validate_players = function(force_players)
    local players = {}
    for _, player_name in pairs(force_players) do
        local player = game.get_player(player_name)
        if player then
            table.insert(players, player)
        else
            return false
        end
    end
    return players
end

return functions
