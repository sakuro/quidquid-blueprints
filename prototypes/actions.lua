local function action(name, input_name, interface)
  return {
    type = "mod-data",
    name = "quidquid-blueprints-" .. name,
    data_type = "quidquid.action",
    data = {
      contract_version = 3,
      types = { "blueprint" },
      label = { "quidquid-blueprints.action-" .. name .. "-blueprint" },
      hint = { "quidquid-blueprints.action-" .. name .. "-blueprint-hint" },
      input_name = input_name,
      interface = interface,
    },
  }
end

data:extend({
  action("hold", "quidquid-hold-blueprint", "quidquid-blueprints.hold"),
  action("copy", "quidquid-copy-blueprint", "quidquid-blueprints.copy"),
  action("export", "quidquid-export-blueprint", "quidquid-blueprints.export"),
})
