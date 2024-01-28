-- Dependency scripts
local functions = require("scripts.functions")
local head_start = require("scripts.head-start")
local space_exploration = require("scripts.space-exploration")

-- Function to validate if cmd issuer is admin
local _check_admin = function(cmd_player, name)
    if cmd_player.admin then
        return true
    else
        cmd_player.print({"cant-run-command-not-admin", name})
        return false
    end
end

-- Function to validate + parse command arguments
local _check_args = function(cmd_event)
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
local _check_force_admin = function(cmd_player)
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
local _check_force_players_cutscene = function(force_players_converted)
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

-- Function to create ff_systems if it does not already exist
local _create_ff_systems = function()
    -- Create force SE systems table in global if SE and it doesn't already exist
    if remote.interfaces["space-exploration"] and not global.ff_systems then
        -- Get the parent_name of the surface "nauvis" from SE universe
        local parent_name = space_exploration.se_get_nauvis_parent_name()
        -- Ensure global.ff_systems is not empty
        if not global.ff_systems or next(global.ff_systems) == nil then
            global.ff_systems = {[parent_name] = {["nauvis"] = {"player"}}}
        end
    end
end

-- Function that is returned when the command /create-force is called
local _create_force = function(cmd_event, cmd_player)
    -- This command is for admin only
    if not _check_admin(cmd_player, "create-force") then return end
    -- Process arguments from the event
    local args = _check_args(cmd_event)
    -- If args is false, or if ff-allow-multiple-players-in-create is true,
    -- and the 2nd element of args isn't nil
    if not args or
        (settings.startup["ff-allow-multiple-players-in-create"].value and
            args[2] == nil) then
        local parameter = cmd_event.parameter
        if not parameter then parameter = "nil" end
        local message = {"message.invalid-command-syntax", parameter}
        cmd_player.print(message)
        return
    end
    local force_name = args[1]
    local force_players = args[2]
    local force_players_converted = nil
    if settings.startup["ff-allow-multiple-players-in-create"].value then
        -- Convert the player names into actual player objects
        force_players_converted = functions.validate_players(force_players)
    else
        -- Use cmd_player as the only player
        force_players = {cmd_player.name}
        force_players_converted = {cmd_player}
    end
    -- If this returns false, it means that one of the players supplied is
    -- not in the game, or something worse.
    if not force_players_converted then
        local message = {
            "message.player-or-players-invalid",
            table.concat(force_players, ", ")
        }
        cmd_player.print(message)
        return
    end
    -- Ensure crash site is not already active for any force players
    _check_force_players_cutscene(force_players_converted)
    -- Check that the force does not already exist
    if game.forces[force_name] == nil then
        -- Check for Space Exploration interface, if it doesn't exist,
        -- we assume "Vanilla" Freeplay scenario
        if not remote.interfaces["space-exploration"] then
            -- Define Nauvis surface
            local nauvis = game.surfaces[1]
            -- Generate coordinates within a range of 2500 from 0,0
            local safe_crash_position = functions.find_suitable_location(
                                            cmd_player, nauvis, 1250, 10, true,
                                            true, true)
            -- Spill the items of all players in the force
            functions.spill_player_inventories(force_players_converted)
            -- Create the new force
            game.create_force(force_name)
            -- Define our new force
            local force = game.forces[force_name]
            -- None-check in case Factorio failed to create the force
            if not force then
                local message = {"message.game-create-force-failed", force_name}
                cmd_player.print(message)
                functions.append_localized_string_to_log(message)
                return
            end
            -- Add players to the newly created force
            for _, player in pairs(force_players_converted) do
                -- Clear the player's console
                player.clear_console()
                -- Add the player to the force
                player.force = force
            end
            -- Recreate Freeplay scenario crash site at the generated coordinates
            functions.reproduce_crash_site(cmd_player, force_players_converted,
                                           safe_crash_position, nauvis)
            -- Set the new force's starting position
            force.set_spawn_position(safe_crash_position, nauvis)
            -- Chart the starting area
            functions.chart_starting_area(force, nauvis)
            -- Otherwise, we are using the Space Exploration interface for 
            -- managing planets
        else
            -- Spill the items of all players in the force
            functions.spill_player_inventories(force_players_converted)
            -- Clear the console of all of the players of our new force
            for _, player in pairs(force_players_converted) do
                player.clear_console()
            end
            -- Check for re-usable systems
            local homeworld_without_forces =
                space_exploration.se_setup_multiplayer_check(cmd_player,
                                                             global.ff_systems)
            local result, success = nil, nil
            while not success do
                success, result = pcall(function()
                    -- If we found a parent system without forces for re-use
                    if homeworld_without_forces then
                        space_exploration.se_setup_multiplayer_manually(
                            cmd_player, force_name, force_players,
                            force_players_converted, homeworld_without_forces)
                    else
                        -- Assume we're not tracking any existing worlds that have
                        -- forces active
                        space_exploration.se_setup_multiplayer_test(cmd_player,
                                                                    force_name,
                                                                    force_players,
                                                                    force_players_converted)
                    end
                end)
                if not success and result ~= nil then
                    -- Check if the error message matches the specific pattern
                    local error_string = "Homeworld %((.-)%) has no surface"
                    local problematic_surface =
                        string.match(result, error_string)
                    if problematic_surface then
                        remote.call("space-exploration",
                                    "zone_get_make_surface", {
                            zone_index = remote.call("space-exploration",
                                                     "get_zone_from_name", {
                                zone_name = problematic_surface
                            }).index
                        })
                        homeworld_without_forces = problematic_surface
                    end
                end
            end
            -- Define our new force
            local force = game.forces[force_name]
            -- None-check in case SE failed to create the force
            if not force then
                local message = {"message.se-create-force-failed", force_name}
                cmd_player.print(message)
                functions.append_localized_string_to_log(message)
                return
            end
            -- Retrieve the current surface of the force
            local force_surface = force_players_converted[1].surface
            -- Retrieve the surface name
            local force_surface_name = force_surface.name
            -- Mark the new force's homesystem as active
            space_exploration.se_toggle_force_active(force_name,
                                                     force_surface_name, true)
            -- Chart the starting area for the new force
            functions.chart_starting_area(force, force_surface)
            -- Generate coordinates within a range of 10 from 0,0 (or 0,0 if
            -- we run out of attempts)
            local safe_crash_position = functions.find_suitable_location(
                                            cmd_player, force_surface, 32, 10,
                                            true, true, true)
            -- Recreate crash site at the force's current position
            functions.reproduce_crash_site(cmd_player, force_players_converted,
                                           safe_crash_position, force_surface)
            -- Set the new force's starting position
            force.set_spawn_position(safe_crash_position, force_surface)
        end
        -- Set the first player of the force to be the admin of the force
        if not global.ff_admin[force_name] then
            global.ff_admin[force_name] = {}
        end
        global.ff_admin[force_name][cmd_player.name] = true
        -- Notify the player we just promoted to force admin of that change
        local message = {
            "message.promoted-to-force-admin", force_players_converted[1].name,
            force_name
        }
        local force = game.forces[force_name]
        force.print(message)
        functions.append_localized_string_to_log(message)
        -- Notify the entire game that a new force has been created
        local message = {
            "message.force-created", cmd_player.name, force_name,
            table.concat(force_players, ", ")
        }
        game.print(message)
        functions.append_localized_string_to_log(message)
    else
        -- Otherwise, notify the issuing player that the force already exists
        local message = {"message.force-exists", force_name}
        cmd_player.print(message)
    end
end

-- Function that is returned when the command /demote-force is called
local _demote_force = function(cmd_event, cmd_player)
    -- Process argument from the event
    local force_name = cmd_player.force.name
    -- Check if the force exists
    local force = game.forces[force_name]
    if not force then
        local message = {"message.force-doesnt-exist", force_name}
        cmd_player.print(message)
    end
    local player_name = cmd_event.parameter
    -- This command is for force admin only
    local is_force_admin = _check_force_admin(cmd_player)
    if not is_force_admin then
        local message = {
            "message.cant-run-not-force-admin", cmd_player.name, "demote-force",
            force_name
        }
        -- Notify all online force administrators of this force of the
        -- occurence.
        functions.notify_all_force_admins(global.ff_admin, force, message)
        return
    end
    -- Check if the demoter is "player" force, or if the player doesn't exist,
    -- or if the player is a member of the demoter's force.
    if force_name == "player" or not game.get_player(player_name) or
        game.get_player(player_name).force.name ~= force_name then
        local message = {
            "message.force-demotion-failed", player_name, force_name
        }
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
        return
    end
    -- Remove the player from the force admin list if they are in it
    if global.ff_admin[force_name] then
        if global.ff_admin[force_name][player_name] then
            global.ff_admin[force_name][player_name] = nil
        end
    end
    -- Notify the player that they have been demoted from force admin
    local message = {
        "message.demoted-from-force-admin", player_name, force_name
    }
    force.print(message)
    functions.append_localized_string_to_log(message)
end

-- Function that is returned when the command /invite-force is called
local _invite_force = function(cmd_event, cmd_player)
    -- Process argument from the event
    local force_name = cmd_player.force.name
    -- Check if the force exists
    local force = game.forces[force_name]
    if not force then
        local message = {"message.force-doesnt-exist", force_name}
        cmd_player.print(message)
    end
    -- Check if the inviter is "player" force, or if the player exists, 
    -- or if the player is not already joined to the force.
    local player_name = cmd_event.parameter
    if force_name == "player" or not game.get_player(player_name) or
        game.get_player(player_name).force.name == force_name then
        local message = {"message.force-invite-failed", player_name, force_name}
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
        return
    end
    -- Add the player to the force's invite list if they are not already in it
    if not global.ff_invites[force_name] then
        global.ff_invites[force_name] = {}
    end
    if not global.ff_invites[force_name][player_name] then
        global.ff_invites[force_name][player_name] = true
    end
    -- Notify the force that they the player has been invited to join
    local force = game.forces[force_name]
    local force_message = {
        "message.force-invited-to-join", player_name, force_name,
        cmd_player.name
    }
    force.print(force_message)
    -- Notify the player that they have been invited to join the force
    functions.append_localized_string_to_log(force_message)
    local player = game.get_player(player_name)
    local player_message = {"message.invited-to-join-force", force_name}
    player.print(player_message)
end

-- Function that is returned when the command /join-force is called
local _join_force = function(cmd_event, cmd_player)
    -- Process argument from the event
    local force_name = cmd_event.parameter
    local player_name = cmd_player.name
    -- Check if the force exists
    local force = game.forces[force_name]
    if not force then
        local message = {"message.force-doesnt-exist", force_name}
        cmd_player.print(message)
    end
    -- Check if the force specified is "player", or if the player is invited
    if force_name == "player" or not global.ff_invites[force_name] or
        not global.ff_invites[force_name][player_name] then
        local message = {"message.force-join-failed", player_name, force_name}
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
        return
    end
    -- Spill the player's inventory
    local force_players_converted = {}
    table.insert(force_players_converted, cmd_player)
    functions.spill_player_inventories(force_players_converted)
    cmd_player.clear_console()
    -- Add the player to the force if they are not already in it
    if cmd_player.force.name ~= force_name then
        cmd_player.force = game.forces[force_name]
    end
    -- Give the player respawn_items
    functions.give_fp_respawn_items(cmd_player)
    -- If Vanilla, teleport the player to their new force's spawn
    if not remote.interfaces["space-exploration"] then
        local nauvis = game.surfaces[1]
        local force_spawn_position = game.forces[force_name].get_spawn_position(
                                         nauvis)
        local safe_teleport_position = nauvis.find_non_colliding_position(
                                           cmd_player.character.name,
                                           force_spawn_position, 32, 1)
        player.teleport(safe_teleport_position or force_spawn_position)
    else
        -- Otherwise, use the Space Exploration interface
        space_exploration.se_setup_multiplayer_join(cmd_player,
                                                    global.ff_systems,
                                                    force_name)
    end
    -- Remove the player from the force's invite list
    global.ff_invites[force_name][player_name] = nil
    -- Notify the player that they have joined the force
    local player_message = {"message.joined-force", force_name}
    cmd_player.print(player_message)
    -- Notify the force that the player has joined the force
    local force_message = {
        "message.player-joined-force", player_name, force_name
    }
    force.print(force_message)
    functions.append_localized_string_to_log(force_message)
end

-- Function that is returned when the command /kick-force is called
local _kick_force = function(cmd_event, cmd_player)
    -- Process argument from the event
    local force_name = cmd_player.force.name
    -- Check if the force exists
    local force = game.forces[force_name]
    if not force then
        local message = {"message.force-doesnt-exist", force_name}
        cmd_player.print(message)
    end
    local player_name = cmd_event.parameter
    -- This command is for force admin only
    local is_force_admin = _check_force_admin(cmd_player)
    if not is_force_admin then
        local message = {
            "message.cant-run-not-force-admin", cmd_player.name, "kick-force",
            force_name
        }
        -- Notify all online force administrators of this force of the occurence.
        functions.notify_all_force_admins(global.ff_admin, force, message)
        return
    end
    -- If the force is player, or the player is not in the force, then 
    -- notify and return
    if force_name == "player" or not game.get_player(player_name).force.name ==
        force_name then
        local message = {"message.force-kick-failed", player_name, force_name}
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
        return
    end
    -- Remove the player from the force and return to Nauvis
    functions.return_players_to_nauvis({game.get_player(player_name)})
    -- Notify the force that the player has been kicked
    local message = {
        "message.player-kicked-from-force", player_name, force_name
    }
    force.print(message)
    functions.append_localized_string_to_log(message)
    -- Notify the player that they have been kicked
    local player_message = {
        "message.player-kicked", force_name, cmd_player.name
    }
    player.print(player_message)
end

-- Function that is returned when the command /leave-force is called
local _leave_force = function(cmd_event, cmd_player)
    -- Process argument from the event
    local force_name = cmd_event.parameter
    -- Check if the force exists
    local force = game.forces[force_name]
    if not force then
        local message = {"message.force-doesnt-exist", force_name}
        cmd_player.print(message)
    end
    -- Check if the player is in the "player" force or if the player is not in
    -- the specified force
    if force_name == "player" or cmd_player.force.name ~= force_name then
        local message = {"message.cant-run-not-in-force", force_name}
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
        return
    end
    -- Remove the player from the force and return to Nauvis
    local player_name = cmd_player.name
    functions.return_players_to_nauvis({game.get_player(player_name)})
    -- Notify the force that the player has left the force
    local force_message = {
        "message.force-player-left-force", cmd_player.name, force_name
    }
    force.print(force_message)
    functions.append_localized_string_to_log(force_message)
    -- Notify the player that they have left the force
    local player_message = {"message.player-left-force", force_name}
    cmd_player.print(player_message)
end

-- Function that is returned when the command /promote-force is called
local _promote_force = function(cmd_event, cmd_player)
    -- Process argument from the event
    local force_name = cmd_player.force.name
    -- Check if the force exists
    local force = game.forces[force_name]
    if not force then
        local message = {"message.force-doesnt-exist", force_name}
        cmd_player.print(message)
    end
    local player_name = cmd_event.parameter
    -- This command is for force admin only
    local is_force_admin = _check_force_admin(cmd_player)
    if not is_force_admin then
        local message = {
            "message.cant-run-not-force-admin", cmd_player.name,
            "promote-force", force_name
        }
        -- Notify all online force administrators of this force of the occurence.
        functions.notify_all_force_admins(global.ff_admin, force, message)
        return
    end
    -- If the force is player, or the player does not exist,
    -- then notify and return
    if force_name == "player" or not game.get_player(player_name) then
        local message = {
            "message.force-promotion-failed", player_name, force_name
        }
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
        return
    end
    -- Add the player to the force admin list if they are not already in it
    if not global.ff_admin[force_name] then global.ff_admin[force_name] = {} end
    if not global.ff_admin[force_name][player_name] then
        global.ff_admin[force_name][player_name] = true
    end
    -- Notify the force that they have been promoted to force admin
    local message = {"message.promoted-to-force-admin", player_name, force_name}
    force.print(message)
    functions.append_localized_string_to_log(message)
end

-- Function that is returned when the command /remove-force is called
local _remove_force = function(cmd_event, cmd_player)
    -- This command is for admin only
    if not _check_admin(cmd_player, "remove-force") then return end
    -- Process argument from the event
    local force_name = cmd_event.parameter
    if force_name == "player" then
        local message = {"message.force-removal-failed", force_name}
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
        return
    end
    local force = game.forces[force_name]
    -- None-check in case Factorio failed to remove the force
    if not force then
        local message = {"message.force-doesnt-exist", force_name}
        cmd_player.print(message)
        return
    end
    -- Ensure crash site is not already active for any force players
    _check_force_players_cutscene(force.players)
    -- Define the force's surface
    local force_surface = force.players[1].surface
    local force_surface_name = force_surface.name
    -- Remove the player from the force and return to Nauvis
    functions.return_players_to_nauvis(force.players)
    -- Send notifications for each player
    for _, player in pairs(force.players) do
        local message = {
            "message.tp-force-players", player.name, safe_teleport_position.x,
            safe_teleport_position.y, nauvis.name
        }
        cmd_player.print(message)
        functions.append_localized_string_to_log(message)
        -- Notify each player in the force that it has been removed
        player.print({"message.force-removed-player", force_name})
    end
    -- Loop through all surfaces in the game
    for _, surface in pairs(game.surfaces) do
        -- Neutralize all entities owned by the force being removed
        for _, entity in pairs(surface.find_entities_filtered({force = force})) do
            -- Set the force of each entity found to the "neutral" force
            entity.force = "neutral"
        end
        -- Additionally, reset any chunks that have been generated by the
        -- force not charted by another force if the setting is enabled
        if settings.startup["ff-delete-chunks-remove-force"].value then
            cmd_player.print("Resetting chunks owned by " .. force_name)
            functions.free_chunks_for_force(cmd_player, surface, force)
        end
    end
    -- Finally, if we are running SE
    if remote.interfaces["space-exploration"] then
        space_exploration.se_toggle_force_active(force_name, force_surface_name,
                                                 false)
        -- If the setting is enabled, clear the planet surface
        if settings.startup["ff-se-cleanup-zone-after-remove"].value then
            -- Mark the force's homesystem as inactive for the force
            force_surface.clear()
            local message = {"message.se-planet-cleared", force_surface_name}
            functions.append_localized_string_to_log(message)
        end
    end
    -- Check for and remove force from the ff_admin table
    if global.ff_admin[force_name] then global.ff_admin[force_name] = nil end
    -- Merge the force into the neutral force
    game.merge_forces(force, "neutral")
    -- Notify the entire game that a force has been removed
    local message = {"message.force-removed-game", force_name, cmd_player.name}
    game.print(message)
    functions.append_localized_string_to_log(message)
end

-- Function that is returned when the command /forces is called
local _show_forces = function(cmd_event, cmd_player)
    -- Notify the player of all forces
    if not remote.interfaces["space-exploration"] then
        -- Loop through all forces and print players if not SE
        for _, force in pairs(game.forces) do
            -- If the force is not enemy of neutral
            if force.name ~= "enemy" and force.name ~= "neutral" then
                local force_name = force.name
                local players = {}
                for _, player in pairs(force.players) do
                    table.insert(players, player.name)
                end
                local name_message = {"message.show-force-name", force_name}
                cmd_player.print(name_message)
                local players_message = {
                    "message.show-force-players", table.concat(players, ", ")
                }
                cmd_player.print(players_message)
            end
        end
    else
        -- Otherwise, Loop through all force systems and print force name,
        -- players, surface, system
        for parent_name, used_zones in pairs(global.ff_systems) do
            local system_message = {"message.se-show-force-system", parent_name}
            cmd_player.print(system_message)
            for surface_name, forces in pairs(used_zones) do
                local surface_message = {
                    "message.se-show-force-surface", surface_name
                }
                cmd_player.print(surface_message)
                if next(forces) ~= nil then
                    for _, force_name in pairs(forces) do
                        local force_message = {
                            "message.show-force-name", force_name
                        }
                        cmd_player.print(force_message)
                        local force = game.forces[force_name]
                        local players = {}
                        if force then
                            for _, player in pairs(force.players) do
                                table.insert(players, player.name)
                            end
                        else
                            local message = {
                                "message.force-not-found", force_name
                            }
                            cmd_player.print(message)
                        end
                        local players_message = {
                            "message.show-force-players",
                            table.concat(players, ", ")
                        }
                        cmd_player.print(players_message)
                    end
                end
            end
        end
    end
end

-- Function to safely teleport a player to their force's spawn position
local _spawn = function(cmd_event, cmd_player)
    -- Check if the player has a character
    if cmd_player.character and cmd_player.character.name then
        -- Grab the force and surface from the player
        local force_name = cmd_player.force.name
        local surface = space_exploration.se_get_force_homeworld(
                            global.ff_systems, force_name)
        local spawn_position = game.forces[force_name].get_spawn_position(
                                   surface)
        local safe_teleport_position = surface.find_non_colliding_position(
                                           cmd_player.character.name,
                                           spawn_position, 32, 1)
        cmd_player.teleport(safe_teleport_position or spawn_position, surface)
    end
end

-- Create force SE systems table in global if it doesn't already exist
-- on on_configuration_changed, and if SE is installed
script.on_configuration_changed(function(event) _create_ff_systems() end)

-- Support skipping cutscene
local _on_cs_skip_cutscene = function(event)
    if not global.crash_site_cutscene_active then return end
    if event.player_index ~= 1 then return end
    local player = game.get_player(event.player_index)
    if player.controller_type == defines.controllers.cutscene then
        player.exit_cutscene()
    end
end
script.on_event("crash-site-skip-cutscene", _on_cs_skip_cutscene)
local _on_cutscene_cancelled = function(event)
    if not global.crash_site_cutscene_active then return end
    if event.player_index ~= 1 then return end
    global.crash_site_cutscene_active = nil
    local player = game.get_player(event.player_index)
    if player.gui.screen.skip_cutscene_label then
        player.gui.screen.skip_cutscene_label.destroy()
    end
    if player.character then player.character.destructible = true end
    player.zoom = 1.5
end
script.on_event(defines.events.on_cutscene_cancelled, _on_cutscene_cancelled)

-- Create force SE systems table in global if it doesn't already exist
-- on the start of the scenario if SE is installed
script.on_event(defines.events.on_game_created_from_scenario,
                function(event) _create_ff_systems() end)

-- Give additional items on startup if user preference
script.on_init(function(e)
    -- Log to file
    local message = {"message.on_init"}
    game.write_file("freeplay-forces.log", message, false)
    game.write_file("freeplay-forces.log", "\n", true)
    -- Create force admin table in global if it doesn't already exist
    if not global.ff_admin then global.ff_admin = {} end
    -- Create force invite table in global if it doesn't already exist
    if not global.ff_invites then global.ff_invites = {} end
    -- Give head start if user preference
    if settings.startup["ff-give-head-start"].value then
        head_start.give_items()
    end
end)

-- List of commands to be added to the game
local COMMANDS_LIST = {
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["create-force"] = function(cmd_event, cmd_player)
        _create_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["demote-force"] = function(cmd_event, cmd_player)
        _demote_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["invite-force"] = function(cmd_event, cmd_player)
        _invite_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["join-force"] = function(cmd_event, cmd_player)
        _join_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["kick-force"] = function(cmd_event, cmd_player)
        _kick_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["leave-force"] = function(cmd_event, cmd_player)
        _leave_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["promote-force"] = function(cmd_event, cmd_player)
        _promote_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["remove-force"] = function(cmd_event, cmd_player)
        _remove_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["show-forces"] = function(cmd_event, cmd_player)
        _show_forces(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["spawn"] = function(cmd_event, cmd_player) _spawn(cmd_event, cmd_player) end
}

-- Function that is returned when the command /ff-commands is called
local _ff_commands = function(cmd_event)
    -- Retrieve the player who issued the command
    local cmd_owner = cmd_event.player_index
    local cmd_player = game.get_player(cmd_owner) --[[@as LuaPlayer]]
    -- Loop through commands
    for name, _ in pairs(COMMANDS_LIST) do
        -- Change create-force command name if user preference
        local _name
        if name == "create-force" then
            if settings.startup["ff-allow-multiple-players-in-create"].value then
                _name = "create-force-multiple"
            else
                _name = "create-force-single"
            end
        else
            _name = name
        end
        -- Print command to the player
        cmd_player.print({"command-help." .. _name})
    end
end

-- Loop through commands
for name, func in pairs(COMMANDS_LIST) do
    -- Change create-force command name if user preference
    local _name
    if name == "create-force" then
        if settings.startup["ff-allow-multiple-players-in-create"].value then
            _name = "create-force-multiple"
        else
            _name = "create-force-single"
        end
    else
        _name = name
    end
    -- Add command to the game
    commands.add_command(name, {"command-help." .. _name}, function(cmd_event)
        -- Retrieve the player who issued the command
        local cmd_owner = cmd_event.player_index
        local cmd_player = game.get_player(cmd_owner) --[[@as LuaPlayer]]
        -- Check for scenario
        if not remote.interfaces["freeplay"] then
            cmd_player.print("message.no-freeplay-scenario")
            functions.append_localized_string_to_log({
                "message.no-freeplay-scenario"
            })
        else
            func(cmd_event, cmd_player)
        end
    end)
end

-- Add /ff-commands to game
commands.add_command("ff-commands", {"command-help.ff-commands"},
                     function(cmd_event)
    -- Run the function
    _ff_commands(cmd_event)
end)
