local api = require("__quidquid__.lib.api")

local BlueprintLogic = {}

local MISSING_ICON = "utility/missing_icon"
local PATH_SEPARATOR = " › "
local LOCATIONS = { my = true, game = true, inv = true }
local NAMESPACE = "blueprint"

-- Vanilla's own wording for where a blueprint-like entry lives, matched so the second
-- line reads like the rest of the game rather than a Quidquid-specific label.
local LOCATION_NAMES = {
  inv = { "gui.inventory" },
  my = { "gui-blueprint-library.private-shelf" },
  game = { "gui-blueprint-library.game-blueprints-title" },
}

--- A signal's SpritePath.
---
--- SignalID reads `type` as nil for items, and names virtual signals `virtual` while
--- their sprite class is `virtual-signal`; every other SignalIDType is its own class.
---@param signal table|nil  a SignalID
---@return string|nil  nil for a missing signal or one without a name
function BlueprintLogic.sprite_path(signal)
  if signal == nil or signal.name == nil then
    return nil
  end
  local signal_type = signal.type or "item"
  if signal_type == "virtual" then
    signal_type = "virtual-signal"
  end
  return signal_type .. "/" .. signal.name
end

--- A record's preview icons as one rich text string, in the library's order.
---
--- An icon whose prototype no longer exists becomes the engine's own missing-icon
--- question mark rather than disappearing, so the count and order still match what
--- the library shows.
---@param icons table|nil  array of BlueprintSignalIcon
---@param is_valid_sprite_path function  (path) -> boolean; the runtime check
---@return string|nil  nil when there is nothing to show
function BlueprintLogic.icon_caption(icons, is_valid_sprite_path)
  local sorted = {}
  for _, icon in pairs(icons or {}) do
    table.insert(sorted, icon)
  end
  table.sort(sorted, function(a, b)
    return a.index < b.index
  end)
  local parts = {}
  for _, icon in ipairs(sorted) do
    local path = BlueprintLogic.sprite_path(icon.signal)
    if path ~= nil then
      if not is_valid_sprite_path(path) then
        path = MISSING_ICON
      end
      table.insert(parts, "[img=" .. path .. "]")
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts)
end

--- A candidate id: the location and the index path down to the entry.
---@param location string  "my", "game" or "inv"
---@param indices table  array of integers
---@return string
function BlueprintLogic.format_id(location, indices)
  local parts = { location }
  for _, index in ipairs(indices) do
    table.insert(parts, tostring(index))
  end
  return table.concat(parts, "/")
end

--- Splits a candidate id back into its location and index path.
---@param id string
---@return string|nil  the location, nil for a malformed id
---@return table|nil  array of integers
function BlueprintLogic.parse_id(id)
  local location, rest = id:match("^(%a+)/([%d/]+)$")
  if location == nil or not LOCATIONS[location] or rest:sub(-1) == "/" or rest:find("//", 1, true) then
    return nil, nil
  end
  local indices = {}
  for part in rest:gmatch("[^/]+") do
    if not part:match("^[1-9]%d*$") then
      return nil, nil
    end
    table.insert(indices, tonumber(part))
  end
  return location, indices
end

--- One book's label shrunk to a single unit, for the abbreviated part of a path.
---
--- A label that opens with an icon keeps that icon, which identifies the book better
--- than any one character would; color and font tags carry no identity, so they are
--- looked past.
---@param label string
---@return string  empty when the label has neither an icon nor text
function BlueprintLogic.abbreviate(label)
  local tag = label:match("^%b[]")
  if tag ~= nil then
    local name = tag:match("^%[([^=%]]*)")
    if name ~= "color" and name ~= "font" then
      return tag
    end
  end
  local stripped = label:gsub("%b[]", "")
  return stripped:match("^[\1-\127\194-\244][\128-\191]*") or ""
end

--- The enclosing books' labels as a full path and an abbreviated one for display.
---
--- Lua cannot measure rendered width, and the engine truncates an overflowing label
--- at its end -- which would cut off the nearest book first -- so the displayed path
--- is always abbreviated: the nearest book in full, each one before it as a single
--- unit. The two `_start` bytes locate the nearest book's label in each string, so
--- match ranges over the full path can be carried onto the displayed one.
---@param labels table  array of labels, outermost first
---@return table|nil  { full, display, full_start, display_start }; nil for no books
function BlueprintLogic.book_path(labels)
  if #labels == 0 then
    return nil
  end
  local nearest = labels[#labels]
  local units = {}
  for i = 1, #labels - 1 do
    local unit = BlueprintLogic.abbreviate(labels[i])
    if unit ~= "" then
      table.insert(units, unit)
    end
  end
  local full = table.concat(labels, PATH_SEPARATOR)
  local display_prefix = #units > 0 and (table.concat(units, PATH_SEPARATOR) .. PATH_SEPARATOR) or ""
  return {
    full = full,
    display = display_prefix .. nearest,
    full_start = #full - #nearest + 1,
    display_start = #display_prefix + 1,
  }
end

-- Fills in what records and blueprint-like items share under the same attribute
-- names. Each description attribute exists only on its own kinds. default_icons is
-- read only from a set-up blueprint: on one that is not (including a blank one),
-- the engine raises "Given blueprint is empty." instead of returning nil.
local function describe(node, source)
  if node.type == "blueprint" or node.type == "blueprint-book" then
    node.description = source.blueprint_description
  else
    node.description = source.planner_description
  end
  if node.type == "blueprint" and (node.icons == nil or next(node.icons) == nil) and source.is_blueprint_setup() then
    node.icons = source.default_icons
  end
end

local function record_node(key, record)
  local node = { key = key, type = record.type, label = record.label }
  -- An unlabelled record is never a candidate (build_candidates skips it), so its
  -- description and icons are left unread -- describe() would call default_icons,
  -- which raises for a blank blueprint. A preview record has not been downloaded
  -- yet; only what the library itself shows before download (label, preview icons)
  -- is read from it.
  local labelled = record.label ~= nil and record.label ~= ""
  if labelled then
    node.icons = record.preview_icons
    if not record.is_preview then
      describe(node, record)
    end
  end
  -- Books are walked regardless of label: an unlabelled book can still hold
  -- labelled candidates.
  if not record.is_preview and node.type == "blueprint-book" then
    node.children = BlueprintLogic.to_nodes(record.contents)
  end
  return node
end

--- Converts library records into plain nodes, walking books.
---
--- `contents` is a sparse array, so keys are collected with pairs and sorted rather
--- than read with `#`.
---@param records table  array or sparse table of LuaRecord
---@return table  array of { key, type, label, icons, description, children }
function BlueprintLogic.to_nodes(records)
  local nodes = {}
  for key, record in pairs(records) do
    if record.valid then
      table.insert(nodes, record_node(key, record))
    end
  end
  table.sort(nodes, function(a, b)
    return a.key < b.key
  end)
  return nodes
end

--- The record type a blueprint-like item corresponds to.
---
--- An item's `type` is its prototype type, which names planners
--- `deconstruction-item` and `upgrade-item`; the `is_*` flags are read instead so
--- inventory entries use the same vocabulary as library records.
---@param stack LuaItemStack  valid for read
---@return string|nil  nil for any other item
function BlueprintLogic.item_kind(stack)
  if stack.is_blueprint then
    return "blueprint"
  elseif stack.is_blueprint_book then
    return "blueprint-book"
  elseif stack.is_deconstruction_item then
    return "deconstruction-planner"
  elseif stack.is_upgrade_item then
    return "upgrade-planner"
  end
  return nil
end

--- Converts the blueprint-like items of an inventory into plain nodes, walking
--- book items through their inner inventory.
---@param inventory LuaInventory
---@param item_main defines.inventory  `defines.inventory.item_main`
---@return table  array of { key, type, item_name, label, icons, description, children }
function BlueprintLogic.item_nodes(inventory, item_main)
  local nodes = {}
  for slot = 1, #inventory do
    local stack = inventory[slot]
    if stack.valid_for_read then
      local kind = BlueprintLogic.item_kind(stack)
      if kind ~= nil then
        local node = { key = slot, type = kind, item_name = stack.name, label = stack.label }
        -- See record_node's comment: an unlabelled item is never a candidate, so its
        -- description and icons are left unread.
        if stack.label ~= nil and stack.label ~= "" then
          node.icons = stack.preview_icons
          describe(node, stack)
        end
        if kind == "blueprint-book" then
          local inner = stack.get_inventory(item_main)
          node.children = inner ~= nil and BlueprintLogic.item_nodes(inner, item_main) or {}
        end
        table.insert(nodes, node)
      end
    end
  end
  return nodes
end

--- Finds a library record again by its index path, for an action to run on.
---
--- The library can change between the search and the action, so the record must
--- still have the type and label the candidate was built from; a preview record is
--- refused because it cannot be exported yet.
---@param roots table  the shelf's top-level records
---@param indices table  array of integers
---@param record_type string
---@param label string
---@return LuaRecord|nil
function BlueprintLogic.resolve(roots, indices, record_type, label)
  local current = roots[indices[1]]
  for i = 2, #indices do
    if current == nil or not current.valid or current.type ~= "blueprint-book" or current.is_preview then
      return nil
    end
    current = current.contents[indices[i]]
  end
  if
    current == nil
    or not current.valid
    or current.is_preview
    or current.type ~= record_type
    or current.label ~= label
  then
    return nil
  end
  return current
end

--- Finds an inventory item again by its slot path, for an action to run on.
---
--- Slots are checked against the inventory size first: indexing a LuaInventory
--- past its end raises rather than returning nil.
---@param inventory LuaInventory
---@param indices table  array of slot numbers
---@param item_main defines.inventory  `defines.inventory.item_main`
---@param record_type string
---@param label string
---@return LuaItemStack|nil
function BlueprintLogic.resolve_item(inventory, indices, item_main, record_type, label)
  local current = inventory
  local found = nil
  for i, slot in ipairs(indices) do
    if i > 1 then
      if found.is_blueprint_book ~= true then
        return nil
      end
      current = found.get_inventory(item_main)
      if current == nil then
        return nil
      end
    end
    if slot > #current then
      return nil
    end
    found = current[slot]
    if not found.valid_for_read then
      return nil
    end
  end
  if found == nil or BlueprintLogic.item_kind(found) ~= record_type or found.label ~= label then
    return nil
  end
  return found
end

local function append(list, value)
  local copy = { table.unpack(list) }
  table.insert(copy, value)
  return copy
end

-- Carries ranges over the full path onto the displayed one. Only the nearest book is
-- displayed as written; a range in an abbreviated book has nothing to land on.
local function to_display_ranges(ranges, path)
  local shifted = {}
  local offset = path.display_start - path.full_start
  for _, range in ipairs(ranges) do
    local start_byte = math.max(range.start_byte, path.full_start)
    if start_byte <= range.end_byte then
      table.insert(shifted, { start_byte = start_byte + offset, end_byte = range.end_byte + offset })
    end
  end
  return shifted
end

local function annotation_for(node, path, is_valid_sprite_path)
  local caption = BlueprintLogic.icon_caption(node.icons, is_valid_sprite_path)
  local lines = {}
  if path ~= nil and path.display ~= path.full then
    table.insert(lines, path.full)
  end
  if node.description ~= nil and node.description ~= "" then
    table.insert(lines, node.description)
  end
  local tooltip = #lines > 0 and table.concat(lines, "\n") or nil
  if caption == nil and tooltip == nil then
    return nil
  end
  return { caption = caption, tooltip = tooltip }
end

local function build_candidate(matcher, node, id, ancestors, location_name, is_valid_sprite_path)
  local label_text, label_origins = api.rich_text.searchable(node.label)
  local path = BlueprintLogic.book_path(ancestors)
  local path_text, path_origins = nil, nil
  if path ~= nil then
    path_text, path_origins = api.rich_text.searchable(path.full)
  end
  local match = matcher:match(NAMESPACE, id, { display = label_text, internal = path_text })
  if match == nil then
    return nil
  end
  local location_label = LOCATION_NAMES[location_name]
  -- A top-level entry has no book path to show as the second line, so it names its
  -- location there instead -- entries with the same label from different locations
  -- (e.g. inventory vs. My blueprints) would otherwise be indistinguishable. A
  -- candidate inside a book already has the book path for that line, so its location
  -- is prefixed onto that path instead of taking the line for itself.
  local secondary_text = path == nil and location_label or nil
  return {
    type = "blueprint",
    id = id,
    record_type = node.type,
    label = node.label,
    -- An inventory item may be a mod's own blueprint-like item, whose icon is its own.
    icon = "item/" .. (node.item_name or node.type),
    search_display_name = node.label,
    search_display_ranges = api.rich_text.map_ranges(match.display_ranges, label_origins),
    search_internal_name = path and path.display or nil,
    search_internal_ranges = path
        and to_display_ranges(api.rich_text.map_ranges(match.internal_ranges, path_origins), path)
      or {},
    search_internal_prefix = path and { "", location_label, PATH_SEPARATOR } or nil,
    secondary_text = secondary_text,
    search_score = match.score,
    annotation = annotation_for(node, path, is_valid_sprite_path),
  }
end

--- Candidates for every labelled entry in the given locations that matches the query.
---
--- An unlabelled record is never a candidate (accepted: there is nothing to find it
--- by), but an unlabelled book is still walked and left out of its contents' path.
---@param query string
---@param locale string|nil  the player's locale, for display-name normalization
---@param locations table  array of { name, nodes }, nodes as `to_nodes` or `item_nodes` returns them
---@param is_valid_sprite_path function  (path) -> boolean; the runtime check
---@return table  candidates; see EXTENDING.md "Candidates"
function BlueprintLogic.build_candidates(query, locale, locations, is_valid_sprite_path)
  local matcher = api.matcher(query, locale)
  local candidates = {}
  local function visit(nodes, location_name, indices, ancestors)
    for _, node in ipairs(nodes) do
      local node_indices = append(indices, node.key)
      local labelled = node.label ~= nil and node.label ~= ""
      if labelled then
        local id = BlueprintLogic.format_id(location_name, node_indices)
        local candidate = build_candidate(matcher, node, id, ancestors, location_name, is_valid_sprite_path)
        if candidate ~= nil then
          table.insert(candidates, candidate)
        end
      end
      if node.children ~= nil then
        visit(node.children, location_name, node_indices, labelled and append(ancestors, node.label) or ancestors)
      end
    end
  end
  for _, location in ipairs(locations) do
    visit(location.nodes, location.name, {}, {})
  end
  return candidates
end

return BlueprintLogic
