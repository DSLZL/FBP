data:extend({
  {
    type = "int-setting",
    name = "fbp-speed",
    setting_type = "runtime-per-user",
    default_value = 30,
    minimum_value = 1,
    maximum_value = 600,
    order = "a"
  },
  {
    type = "bool-setting",
    name = "fbp-deconstruct",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "b"
  },
  {
    type = "bool-setting",
    name = "fbp-allow-others",
    setting_type = "runtime-global",
    default_value = false,
    order = "c"
  },
  {
    type = "bool-setting",
    name = "fbp-debug-mode",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "d"
  }
})
