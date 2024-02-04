local functions = require("functions")

local space_exploration = {}

-- Function to get the force's homeworld from ff_systems
space_exploration.se_get_force_homeworld =
    function(ff_systems, force_name)
        -- Retrieve the force's homeworld from ff_systems if it exists
        local homeworld_found = false
        for _, used_zones in pairs(ff_systems) do
            if homeworld_found then break end
            for surface_name, forces in pairs(used_zones) do
                for _, active_force in pairs(forces) do
                    if active_force == force_name and
                        game.surfaces[surface_name] then
                        homeworld_found = true
                        return game.surfaces[surface_name]
                    end
                end
            end
        end
        -- If we can't find the homeworld, return nil
        return nil
    end

-- Function to get and optionally print out the elements of the SE Universe to the log
space_exploration.se_get_universe = function()
    local universe = remote.call("space-exploration", "get_zone_index", {})
    -- Return the universe
    return universe
end

-- Function to get the parent_name of the surface "nauvis" from SE universe
space_exploration.se_get_nauvis_parent_name = function()
    local universe = space_exploration.se_get_universe()
    -- Return the parent_name
    local parent_name = nil
    for _, element in pairs(universe) do
        if element.name == "Nauvis" then
            parent_name = universe[element.parent_index]["name"]
            break
        end
    end
    return parent_name
end

-- Function to check for re-usable SE systems
space_exploration.se_setup_multiplayer_check =
    function(cmd_player, ff_systems)
        -- Ensure ff_systems is not empty
        local homeworld_without_forces = nil
        if ff_systems and next(ff_systems) ~= nil then
            -- Try to find a parent system that has no active forces
            for parent_name, used_zones in pairs(ff_systems) do
                local message = {"message.se-checking-system", parent_name}
                cmd_player.print(message)
                log(message)
                -- Loop through the surfaces in the system
                for surface_name, forces in pairs(used_zones) do
                    -- Check if any forces are actively assigned
                    if forces and next(forces) ~= nil then
                        local message = {
                            "message.se-system-has-active-forces", parent_name,
                            table.concat(forces, ", "), surface_name
                        }
                        cmd_player.print(message)
                        log(message)
                    else
                        local message = {
                            "message.se-system-has-no-active-forces",
                            parent_name, surface_name
                        }
                        cmd_player.print(message)
                        log(message)
                        homeworld_without_forces = surface_name
                        break
                    end
                end
                -- If we found a homeworld without forces, break
                if homeworld_without_forces ~= nil then break end
            end
            -- Return homeworld_without_forces
            return homeworld_without_forces
        end
    end

-- Function to manually join a player to an SE force
space_exploration.se_setup_multiplayer_join =
    function(cmd_player, ff_systems, force_name)
        local surface = space_exploration.se_get_force_homeworld(ff_systems,
                                                                 force_name)
        -- Teleport the player to the force's homeworld if found
        if surface then
            local force_spawn_position =
                game.forces[force_name].get_spawn_position(surface)
            local safe_teleport_position =
                surface.find_non_colliding_position(
                    cmd_player.character.name, force_spawn_position, 32, 1) or
                    force_spawn_position
            cmd_player.teleport(safe_teleport_position, surface)
        else
            local message = {"message.se-homeworld-not-found", force_name}
            log(message)
            return
        end
    end

-- Function to manually call SE multiplayer procedure
space_exploration.se_setup_multiplayer_manually =
    function(cmd_player, force_name, force_players, force_players_converted,
             homeworld_without_forces, position)
        -- If the force does not exist, create it
        if game.forces[force_name] == nil then
            game.create_force(force_name)
        end
        local message = {
            "message.se-setup-multiplayer-manually", force_name,
            table.concat(force_players, ", "), homeworld_without_forces
        }
        cmd_player.print(message)
        log(message)
        remote.call("space-exploration", "set_force_homeworld", {
            zone_name = homeworld_without_forces,
            force_name = force_name,
            spawn_position = position,
            reset_discoveries = true
        })
        -- Set the force of each player and teleport them to the parent system
        for _, player in pairs(force_players_converted) do
            remote.call("space-exploration", "teleport_to_zone",
                        {zone_name = homeworld_without_forces, player = player})
            player.force = game.forces[force_name]
        end
    end

-- Function to call SE setup_multiplayer_test
space_exploration.se_setup_multiplayer_test =
    function(cmd_player, force_name, force_players, force_players_converted)
        -- Call SE setup_multiplayer_test to handle the hard work
        local message = {
            "message.se-setup-multiplayer-test", force_name,
            table.concat(force_players, ", ")
        }
        cmd_player.print(message)
        log(message)
        remote.call("space-exploration", "setup_multiplayer_test", {
            force_name = force_name,
            players = force_players_converted,
            match_nauvis_seed = false
        })
    end

-- Function to toggle tracking a force as active for a se system
space_exploration.se_toggle_force_active =
    function(force_name, force_surface_name, active)
        local universe = space_exploration.se_get_universe()
        -- Loop through the universe
        for _, element in pairs(universe) do
            -- Match force surface name to a planet surface and check that
            -- it is_homeworld and has a special type of "homeworld"
            if element.is_homeworld and element.special_type == "homeworld" then
                -- Map the homeworld for later reference
                local parent_index = element.parent_index
                local parent_name = universe[parent_index]["name"]
                -- Map parent_name to an array if it doesn't already exist
                if not global.ff_systems[parent_name] then
                    global.ff_systems[parent_name] = {}
                end
                -- If this is our planet surface, map the state of the force
                if element.name == force_surface_name then
                    if not global.ff_systems[parent_name][force_surface_name] then
                        global.ff_systems[parent_name][force_surface_name] = {}
                    end
                    if active then
                        local message = {
                            "message.se-force-activated", force_name,
                            force_surface_name, parent_name
                        }
                        game.print(message)
                        log(message)
                        table.insert(
                            global.ff_systems[parent_name][force_surface_name],
                            force_name)
                    else
                        local message = {
                            "message.se-force-retiring", force_name,
                            force_surface_name, parent_name
                        }
                        game.print(message)
                        log(message)
                        -- Remove the force from the array of active forces 
                        -- in the zone if it exists
                        for index, active_force in pairs(
                                                       global.ff_systems[parent_name][force_surface_name]) do
                            if active_force == force_name then
                                table.remove(
                                    global.ff_systems[parent_name][force_surface_name],
                                    index)
                            end
                        end
                    end
                end
            end
        end
    end

return space_exploration
