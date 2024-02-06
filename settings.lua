-- -- FREEPLAY FORCES SETTINGS
-- Setting order "[a-z]NUMBER"
data:extend({
    {
        type = "bool-setting",
        name = "ff-allow-multiple-players-in-create",
        setting_type = "startup",
        default_value = false,
        order = "a1"
    }, {
        type = "bool-setting",
        name = "ff-se-cleanup-zone-after-remove",
        setting_type = "startup",
        default_value = false,
        order = "a2"
    }, {
        type = "bool-setting",
        name = "ff-delete-chunks-remove-force",
        setting_type = "startup",
        default_value = true,
        order = "a3"
    }, {
        type = "bool-setting",
        name = "ff-ensure-ore-spawn",
        setting_type = "startup",
        default_value = true,
        order = "a4"
    }, {
        type = "bool-setting",
        name = "ff-give-head-start",
        setting_type = "startup",
        default_value = true,
        order = "a5"
    }, {
        type = "bool-setting",
        name = "ff-give-to-entire-force",
        setting_type = "startup",
        default_value = true,
        order = "a6"
    }, {
        type = "bool-setting",
        name = "ff-spawn-car",
        setting_type = "startup",
        default_value = true,
        order = "a7"
    }, {
        type = "bool-setting",
        name = "ff-respawn-items",
        setting_type = "startup",
        default_value = true,
        order = "a8"
    }
})
