local api = require("__quidquid__.lib.api")
local BlueprintLogic = require("lib.blueprint_logic")

local BlueprintAction = {}

local UNAVAILABLE = "quidquid-blueprints.action-blueprint-unavailable"

-- Injected from control.lua (see BlueprintAction.init) rather than required directly:
-- this module stays loadable without the GUI one.
local export_window = nil

local function resolve(candidate, player)
  local location, indices = BlueprintLogic.parse_id(candidate.id)
  if location == nil then
    return nil, UNAVAILABLE
  end
  if location == "inv" then
    local inventory = player.get_main_inventory()
    local stack = inventory ~= nil
        and BlueprintLogic.resolve_item(
          inventory,
          indices,
          defines.inventory.item_main,
          candidate.record_type,
          candidate.label
        )
      or nil
    if stack == nil then
      return nil, UNAVAILABLE
    end
    return { stack = stack, inventory = inventory, slot = #indices == 1 and indices[1] or nil }, nil
  end
  local roots = location == "my" and player.blueprints or game.blueprints
  local record = BlueprintLogic.resolve(roots, indices, candidate.record_type, candidate.label)
  if record == nil then
    return nil, UNAVAILABLE
  end
  return { record = record }, nil
end

local function export_string(target)
  if target.record ~= nil then
    return target.record.export_record()
  end
  return target.stack.export_stack()
end

-- A library record cannot itself go in the cursor (cursor_record is read-only), so
-- holding one gives an imported copy marked temporary: clearing the cursor discards it
-- as it would a library pick, while placing it in a slot by hand keeps it. An inventory
-- item is moved into the cursor itself, as clicking its slot would; hand_location then
-- sends it back to that slot on Q. An item taken out of a book item has no slot of its
-- own to return to, so it gets no hand location.
local function hold(candidate, player_index)
  return api.run_action(candidate, player_index, resolve, function(target, selected_candidate, player)
    if player.cursor_stack == nil or not player.clear_cursor() then
      return { "quidquid-blueprints.action-blueprint-cursor-busy" }
    end
    if target.stack ~= nil then
      -- clear_cursor() can insert the cursor's former contents into this same main
      -- inventory and shift slots, so the target resolved before it may no longer be
      -- the right stack; resolve again against the post-clear inventory.
      local fresh_target = resolve(selected_candidate, player)
      if fresh_target == nil then
        return { UNAVAILABLE }
      end
      if not player.cursor_stack.swap_stack(fresh_target.stack) then
        return { "quidquid-blueprints.action-blueprint-hold-failed" }
      end
      if fresh_target.slot ~= nil then
        player.hand_location = { inventory = fresh_target.inventory.index, slot = fresh_target.slot }
      end
      return { "quidquid-blueprints.action-blueprint-held" }
    end
    if player.cursor_stack.import_stack(export_string(target)) == -1 then
      player.cursor_stack.clear()
      return { "quidquid-blueprints.action-blueprint-import-failed" }
    end
    player.cursor_stack_temporary = true
    return { "quidquid-blueprints.action-blueprint-held" }
  end)
end

local function copy_to_inventory(candidate, player_index)
  return api.run_action(candidate, player_index, resolve, function(target, _selected_candidate, player)
    local inventory = player.get_main_inventory()
    if inventory == nil then
      return { "quidquid-blueprints.action-blueprint-no-inventory" }
    end
    local stack = inventory.find_empty_stack()
    if stack == nil then
      return { "quidquid-blueprints.action-blueprint-inventory-full" }
    end
    if stack.import_stack(export_string(target)) == -1 then
      stack.clear()
      return { "quidquid-blueprints.action-blueprint-import-failed" }
    end
    return { "quidquid-blueprints.action-blueprint-copied" }
  end)
end

--- Hands in the export window module.
---
--- Injected rather than required so this module stays loadable without the GUI one.
---@param window table  lib/blueprint_export_window.lua
function BlueprintAction.init(window)
  export_window = window
end

local function export(candidate, player_index)
  return api.run_action(candidate, player_index, resolve, function(target, _selected_candidate, player)
    export_window.open(player, export_string(target))
  end)
end

--- Adds the blueprint actions' remote interfaces, named by their declarations in
--- prototypes/actions.lua.
function BlueprintAction.add_interface()
  remote.add_interface("quidquid-blueprints.hold", { execute = hold })
  remote.add_interface("quidquid-blueprints.copy", { execute = copy_to_inventory })
  remote.add_interface("quidquid-blueprints.export", { execute = export })
end

return BlueprintAction
