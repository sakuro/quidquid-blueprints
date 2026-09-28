local BlueprintExportWindow = {}

local FRAME_NAME = "quidquid-blueprints-export-frame"
local TEXT_BOX_NAME = "quidquid-blueprints-export-text"
local TEXT_BOX_WIDTH = 400
local TEXT_BOX_HEIGHT = 240

local function get_frame(player)
  return player.gui.screen[FRAME_NAME]
end

--- Destroys the window if it is open. Safe to call when it is not.
---@param player LuaPlayer
function BlueprintExportWindow.close(player)
  local frame = get_frame(player)
  if frame ~= nil then
    frame.destroy()
  end
end

--- Shows an export string, selected, for the player to copy.
---
--- No API writes to the OS clipboard (LuaPlayer.add_to_clipboard only feeds the
--- in-game paste queue), so copying is left to the player; selecting everything
--- up front makes it a single keystroke.
---@param player LuaPlayer
---@param export_string string
function BlueprintExportWindow.open(player, export_string)
  BlueprintExportWindow.close(player)
  local frame = player.gui.screen.add({ type = "frame", name = FRAME_NAME, direction = "vertical" })
  frame.auto_center = true

  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({
    type = "label",
    style = "frame_title",
    caption = { "gui.export-to-string" },
    ignored_by_interaction = true,
  })
  local filler =
    titlebar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  titlebar.add({
    type = "sprite-button",
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = { "quidquid-blueprints.cancel-tooltip" },
    tags = { quidquid_blueprints_export_close = true },
  })

  local content = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  content.add({ type = "label", caption = { "quidquid-blueprints.blueprint-export-copy-hint" } })
  local text_box = content.add({ type = "text-box", name = TEXT_BOX_NAME, text = export_string })
  text_box.read_only = true
  text_box.word_wrap = true
  text_box.style.width = TEXT_BOX_WIDTH
  text_box.style.height = TEXT_BOX_HEIGHT

  local button_row = content.add({ type = "flow", direction = "horizontal" })
  button_row.style.horizontally_stretchable = true
  local left_spacer = button_row.add({ type = "empty-widget" })
  left_spacer.style.horizontally_stretchable = true
  button_row.add({
    type = "button",
    style = "green_button",
    caption = { "gui.close" },
    tags = { quidquid_blueprints_export_close = true },
  })
  local right_spacer = button_row.add({ type = "empty-widget" })
  right_spacer.style.horizontally_stretchable = true

  player.opened = frame
  text_box.focus()
  text_box.select_all()
end

--- Destroys the window when Factorio closes it, e.g. on Escape.
---@param event table  on_gui_closed; ignored unless it is this window's frame
function BlueprintExportWindow.on_gui_closed(event)
  if event.element == nil or not event.element.valid or event.element.name ~= FRAME_NAME then
    return
  end
  local player = game.get_player(event.player_index)
  if player ~= nil then
    BlueprintExportWindow.close(player)
  end
end

--- Closes the window from its titlebar close button.
---@param event table  on_gui_click; ignored unless the element carries the close tag
function BlueprintExportWindow.on_gui_click(event)
  local element = event.element
  if element == nil or not element.valid or element.tags.quidquid_blueprints_export_close == nil then
    return
  end
  local player = game.get_player(event.player_index)
  if player == nil then
    return
  end
  -- Closing through player.opened raises on_gui_closed, which destroys the frame here
  -- and lets Quidquid take player.opened back for a pinned palette; destroying the
  -- frame directly would skip both, since this window belongs to another mod.
  if player.opened == get_frame(player) then
    player.opened = nil
  else
    BlueprintExportWindow.close(player)
  end
end

return BlueprintExportWindow
