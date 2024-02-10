local head_start = {}

-- Function to add additional items to the start of a Freeplay scenario
-- Optionally migrate any cars/AAI vehicle miners from FP scenario created items to ship debris
head_start.give_items = function()
    -- Check for Freeplay scenario
    if not remote.interfaces["freeplay"] then return end
    -- Define additional created items
    local additional_created_items = {
        -- Logistics
        {name = "transport-belt", count = 200},
        {name = "underground-belt", count = 100},
        {name = "splitter", count = 10}, {name = "pipe-to-ground", count = 10},
        {name = "pipe", count = 25}, {name = "inserter", count = 48},
        {name = "long-handed-inserter", count = 48},
        {name = "iron-chest", count = 25}, -- Materials
        {name = "coal", count = 100}, {name = "iron-plate", count = 250},
        {name = "copper-plate", count = 150},
        {name = "iron-gear-wheel", count = 50},
        {name = "electronic-circuit", count = 75}, -- Production
        {name = "stone-furnace", count = 48},
        {name = "assembling-machine-1", count = 20},
        {name = "electric-mining-drill", count = 50}, -- Utilities
        {name = "small-electric-pole", count = 100},
        {name = "medium-electric-pole", count = 50},
        {name = "big-electric-pole", count = 25}, {name = "boiler", count = 5},
        {name = "steam-engine", count = 10}, {name = "offshore-pump", count = 1}
    }
    -- Define additional respawn items
    local additional_respawn_items = {
        -- Armor/weapons
        {name = "submachine-gun", count = 1}
    }
    -- Adjust ammo if Krastorio2
    local is_krastorio2 = script.active_mods["Krastorio2"]
    if not is_krastorio2 then
        table.insert(additional_respawn_items,
                     {name = "piercing-rounds-magazine", count = 49})
    else
        table.insert(additional_respawn_items,
                     {name = "armor-piercing-rifle-magazine", count = 49})
    end
    -- Add light armor if Krastorio2 mod isn't loaded or if kr-bonus-items
    -- setting isn't on
    if not is_krastorio2 or not settings.startup["kr-bonus-items"].value then
        table.insert(additional_respawn_items, {name = "light-armor", count = 1})
    end
    -- Give player additional created items
    local fp_created_items_buffer = remote.call("freeplay", "get_created_items")
    -- Add additional_created_items
    for _, item in pairs(additional_created_items) do
        if game.item_prototypes[item.name] then
            fp_created_items_buffer[item.name] = item.count
        end
    end
    -- Add additional_respawn_items
    for _, item in pairs(additional_respawn_items) do
        if game.item_prototypes[item.name] then
            fp_created_items_buffer[item.name] = item.count
        end
    end
    remote.call("freeplay", "set_created_items", fp_created_items_buffer)
    -- If startup preference is to also add respawn items, then add them
    if settings.startup["ff-respawn-items"].value then
        -- Give player additional respawn items
        local fp_respawn_items_buffer = remote.call("freeplay",
                                                    "get_respawn_items")
        for _, item in pairs(additional_respawn_items) do
            if game.item_prototypes[item.name] then
                fp_respawn_items_buffer[item.name] = item.count
            end
        end
        remote.call("freeplay", "set_respawn_items", fp_respawn_items_buffer)
    end
    -- Define additional ship items
    -- local additional_ship_items = {

    -- }
    -- Give ship some additional starting items
    -- local fp_ship_items_buffer = remote.call("freeplay", "get_ship_items")
    -- for _, item in pairs(additional_ship_items) do
    --     if game.item_prototypes[item.name] then
    --         fp_ship_items_buffer[item.name] = item.count
    --     end
    -- end
    -- remote.call("freeplay", "set_ship_items", fp_ship_items_buffer)
    -- Add additional ship parts
    -- local fp_ship_parts_buffer = remote.call("freeplay", "get_ship_parts")
    -- remote.call("freeplay", "set_ship_parts", fp_ship_parts_buffer)
end

-- Function to perform any shuffling desired during the Freeplay scenario init
function head_start.shuffle()
    -- If startup preference is to spawn the car, then check if created_items already has one,
    -- because some mods add the car to created_items
    local fp_car_removed_from_created_items = false
    local fp_vehicle_miner_removed_from_created_items = false
    local fp_created_items_buffer = remote.call("freeplay", "get_created_items")
    -- Remove the key from the table if found, flag to be reinserted with the ship parts
    if fp_created_items_buffer["car"] then
        fp_created_items_buffer["car"] = nil
        fp_car_removed_from_created_items = true
    end
    remote.call("freeplay", "set_created_items", fp_created_items_buffer)
    -- If startup preference is to migrate the miner, then remove from ship items
    local fp_ship_items_buffer = remote.call("freeplay", "get_ship_items")
    -- Remove the key from the table if found, flag to be reinserted with the ship parts
    local is_aai_vehicles = script.active_mods["aai-vehicles-miner"]
    if is_aai_vehicles and fp_ship_items_buffer["vehicle-miner"] then
        fp_ship_items_buffer["vehicle-miner"] = nil
        fp_vehicle_miner_removed_from_created_items = true
    end
    remote.call("freeplay", "set_ship_items", fp_ship_items_buffer)
    -- Add additional ship parts
    local fp_ship_parts_buffer = remote.call("freeplay", "get_ship_parts")
    -- If startup preference is to spawn the car, then add to parts
    if settings.startup["ff-spawn-car"].value or
        fp_car_removed_from_created_items then
        fp_ship_parts_buffer[#fp_ship_parts_buffer + 1] = {
            name = "car",
            repeat_count = 1,
            angle_deviation = 0.7,
            max_distance = 5
        }
    end
    -- If startup preference is to migrate the miner, then add from to parts
    if is_aai_vehicles and fp_vehicle_miner_removed_from_created_items then
        fp_ship_parts_buffer[#fp_ship_parts_buffer + 1] = {
            name = "vehicle-miner",
            repeat_count = 1,
            angle_deviation = 0.7,
            max_distance = 5
        }
    end
    remote.call("freeplay", "set_ship_parts", fp_ship_parts_buffer)
end

return head_start
