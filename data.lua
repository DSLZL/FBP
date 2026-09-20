data:extend({
  {
    type = "shortcut",
    name = "fbp-toggle",
    order = "a",
    action = "lua",
    toggleable = true,
    icon = "__Factorio_Blueprint_Printer__/graphics/icons/icon_placement.png",
    icon_size = 64,
    small_icon = "__Factorio_Blueprint_Printer__/graphics/icons/icon_placement.png",
    small_icon_size = 64
  },
  {
    type = "shortcut",
    name = "fbp-deconstruct-toggle",
    order = "b",
    action = "lua",
    toggleable = true,
    icon = "__Factorio_Blueprint_Printer__/graphics/icons/icon_deconstruction.png",
    icon_size = 64,
    small_icon = "__Factorio_Blueprint_Printer__/graphics/icons/icon_deconstruction.png",
    small_icon_size = 64
  },
  {
    type = "custom-input",
    name = "fbp-open-config",
    key_sequence = "SHIFT + mouse-button-1",
    action = "lua"
  }
})
