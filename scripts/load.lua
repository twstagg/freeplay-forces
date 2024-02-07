local head_start = require("scripts.head-start")
local space_exploration = require("scripts.space-exploration")

local load = {}

load.ff_fix_items = function()
    -- Check if Head Start is enabled
    if settings.startup["ff-give-head-start"].value then
        -- If Krastorio2 is enabled & active, then loop through the buffer and
        -- remove the inverse ammunition from the buffer and set it again
        local is_krastorio2 = script.active_mods["Krastorio2"]
        local fp_created_items_buffer = remote.call("freeplay",
                                                    "get_created_items")
        local fp_respawn_items_buffer = remote.call("freeplay",
                                                    "get_respawn_items")
        if not is_krastorio2 then
            for name, _ in pairs(fp_created_items_buffer) do
                if name == "armor-piercing-rifle-magazine" then
                    fp_created_items_buffer[name] = nil
                    fp_created_items_buffer["piercing-rounds-magazine"] = 49
                end
            end
        else
            for name, _ in pairs(fp_created_items_buffer) do
                if name == "piercing-rounds-magazine" then
                    fp_created_items_buffer[name] = nil
                    fp_created_items_buffer["armor-piercing-rifle-magazine"] =
                        49
                end
            end
        end
        -- If Krastorio2 is enabled & active, then loop through the respawn items
        -- buffer and remove the inverse ammunition from the buffer and set it again
        if not is_krastorio2 then
            for name, _ in pairs(fp_respawn_items_buffer) do
                if name == "armor-piercing-rifle-magazine" then
                    fp_respawn_items_buffer[name] = nil
                    fp_respawn_items_buffer["piercing-rounds-magazine"] = 49
                end
            end
        else
            for name, _ in pairs(fp_respawn_items_buffer) do
                if name == "piercing-rounds-magazine" then
                    fp_respawn_items_buffer[name] = nil
                    fp_respawn_items_buffer["armor-piercing-rifle-magazine"] =
                        49
                end
            end
        end
        -- Remove light armor if it exists in the buffer
        if is_krastorio2 and settings.startup["kr-bonus-items"].value then
            for name, _ in pairs(fp_created_items_buffer) do
                if name == "light-armor" then
                    fp_created_items_buffer[name] = nil
                end
            end
            for name, _ in pairs(fp_respawn_items_buffer) do
                if name == "light-armor" then
                    fp_respawn_items_buffer[name] = nil
                end
            end
        else
            -- Add light armor if not Krastorio2
            fp_created_items_buffer["light-armor"] = 1
            fp_respawn_items_buffer["light-armor"] = 1
        end
        remote.call("freeplay", "set_created_items", fp_created_items_buffer)
        remote.call("freeplay", "set_respawn_items", fp_respawn_items_buffer)
    end
end

load.head_start = function()
    -- Give head start if user preference
    if settings.startup["ff-give-head-start"].value then
        head_start.give_items()
    end
    head_start.shuffle()
end

load.tables = function()
    -- Create force admin table in global if it doesn't already exist
    if not global.ff_admin then global.ff_admin = {} end
    -- Create force invite table in global if it doesn't already exist
    if not global.ff_invites then global.ff_invites = {} end
    -- Create force migrant table in global if it doesn't already exist
    if not global.ff_migrants then global.ff_migrants = {} end
    -- Create force SE systems table in global if SE and it doesn't already exist
    if remote.interfaces["space-exploration"] then
        -- Get the parent_name of the surface "nauvis" from SE universe
        local parent_name = space_exploration.se_get_nauvis_parent_name()
        -- Ensure global.ff_systems is not empty
        if not global.ff_systems or next(global.ff_systems) == nil then
            -- Create force SE systems table in global if it doesn't already exist
            global.ff_systems = {}
            if parent_name and parent_name ~= "" then
                global.ff_systems = {[parent_name] = {["nauvis"] = {"player"}}}
            end
        end
    end
end

return load
