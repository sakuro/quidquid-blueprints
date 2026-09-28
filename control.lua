local BlueprintSource = require("lib.blueprint_source")
local BlueprintAction = require("lib.blueprint_action")
local BlueprintExportWindow = require("lib.blueprint_export_window")

BlueprintAction.init(BlueprintExportWindow)
BlueprintSource.add_interface()
BlueprintAction.add_interface()

script.on_event(defines.events.on_gui_closed, BlueprintExportWindow.on_gui_closed)
script.on_event(defines.events.on_gui_click, BlueprintExportWindow.on_gui_click)
