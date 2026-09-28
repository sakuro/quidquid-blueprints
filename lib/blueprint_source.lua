local BlueprintLogic = require("lib.blueprint_logic")

local BlueprintSource = {}

local function is_valid_sprite_path(path)
  return helpers.is_valid_sprite_path(path)
end

-- Walked afresh on every search: measured at about 2 µs per library record on a
-- real save, so a cache would cost more in invalidation than it saves.
local function search(query, player_index)
  local player = game.get_player(player_index)
  if player == nil then
    return {}
  end
  local locations = {}
  local inventory = player.get_main_inventory()
  if inventory ~= nil then
    table.insert(locations, { name = "inv", nodes = BlueprintLogic.item_nodes(inventory, defines.inventory.item_main) })
  end
  table.insert(locations, { name = "my", nodes = BlueprintLogic.to_nodes(player.blueprints) })
  table.insert(locations, { name = "game", nodes = BlueprintLogic.to_nodes(game.blueprints) })
  return BlueprintLogic.build_candidates(query, player.locale, locations, is_valid_sprite_path)
end

--- Adds this source's remote interface, named by its declaration in prototypes/sources.lua.
function BlueprintSource.add_interface()
  remote.add_interface("quidquid-blueprints.source", { search = search })
end

return BlueprintSource
