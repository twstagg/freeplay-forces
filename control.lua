---@diagnostic disable: undefined-doc-name, undefined-field
-- Dependency scripts
local ff_commands = require("scripts.commands")
local functions = require("scripts.functions")
local load = require("scripts.load")

-- Support skipping cutscene for players who are in active crash site
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

-- Load ensure we've got the right items if Krastorio2 is loaded, and that we have
-- the bare minimum global.ff_* tables set up for the things we need to track
script.on_configuration_changed(function()
    load.ff_fix_items()
    load.head_start()
    load.tables()
end)

-- 1) Call initial head_start() setup for any additionally configured crash site items
-- 2) Create force SE systems table in global if it doesn't already exist on the start
-- of the scenario if SE is installed. We should always at least have Nauvis
script.on_event(defines.events.on_game_created_from_scenario, function()
    load.head_start()
    load.tables()
end)

-- Teleport players who were removed from a force while offline back to nauvis when they
-- reconnect to the server next
script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    if not player.connected then return end
    for index, name in pairs(global.ff_migrants) do
        if name == player.name then
            functions.reset_player_force(player)
            functions.return_players_to_nauvis(false, {player})
            local message = {"message.migrant-player-reconnected"}
            player.print(message)
            -- Remove the player from the table
            table.remove(global.ff_migrants, index)
        end
    end
end)

-- Log to file and setup on_init
script.on_init(function()
    local message = {"message.on_init"}
    game.write_file("freeplay-forces.log", message, false)
    game.write_file("freeplay-forces.log", "\n", true)
    load.head_start()
    load.tables()
end)

-- List of commands to be added to the game
local COMMANDS_LIST = {
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["create-force"] = function(cmd_event, cmd_player)
        ff_commands.create_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["demote-force"] = function(cmd_event, cmd_player)
        ff_commands.demote_force(cmd_event, cmd_player)
    end,
    --- @param cmd_player LuaPlayer
    ["force-admins"] = function(cmd_event, cmd_player)
        ff_commands.force_admins(cmd_event, cmd_player)
    end,
    ["force-commands"] = function() end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["invite-force"] = function(cmd_event, cmd_player)
        ff_commands.invite_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["join-force"] = function(cmd_event, cmd_player)
        ff_commands.join_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["kick-force"] = function(cmd_event, cmd_player)
        ff_commands.kick_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["leave-force"] = function(cmd_event, cmd_player)
        ff_commands.leave_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["promote-force"] = function(cmd_event, cmd_player)
        ff_commands.promote_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["remove-force"] = function(cmd_event, cmd_player)
        ff_commands.remove_force(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["show-forces"] = function(cmd_event, cmd_player)
        ff_commands.show_forces(cmd_event, cmd_player)
    end,
    --- @param cmd_event CustomCommandData
    --- @param cmd_player LuaPlayer
    ["spawn"] = function(cmd_event, cmd_player)
        ff_commands.spawn(cmd_event, cmd_player)
    end
}

-- Add /ff-commands to our COMMANDS_LIST, so that we can easily print the mod's commands
-- @param cmd_player LuaPlayer
COMMANDS_LIST["ff-commands"] = function(cmd_event, cmd_player)
    local cmd_name = cmd_event.name
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

-- Loop through all of our commands and add them to the game
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
-- Add /ff-fix-items as a workaround
-- commands.add_command("ff-fix-items", {"command-help.ff-fix-items"},
--                      function() load.ff_fix_items() end)
