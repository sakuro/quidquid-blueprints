-- Quidquid's public API cannot load under busted, and this spec tests the extension's
-- own logic, not Quidquid's; Quidquid specs its API. The mock matches by plain
-- case-insensitive substring and records what goes through the rich-text helpers.
local rich_text_calls = { searchable = {}, map_ranges = {} }

package.preload["__quidquid__.lib.api"] = function()
  local Matcher = {}
  Matcher.__index = Matcher

  local function ranges_of(query, value)
    if value == nil or query == "" then
      return nil
    end
    local start_byte, end_byte = value:lower():find(query:lower(), 1, true)
    if start_byte == nil then
      return nil
    end
    return { { start_byte = start_byte, end_byte = end_byte } }
  end

  function Matcher:match(_namespace, _id, fields)
    local display = ranges_of(self.query, fields.display)
    local internal = ranges_of(self.query, fields.internal)
    if display == nil and internal == nil then
      return nil
    end
    -- The mock has no real scores to break a tie with, so display wins whenever it
    -- matches -- mirroring the real Matcher:match, which only ever hands ranges back
    -- for the field that won.
    if display ~= nil then
      return { score = 1, display_ranges = display, internal_ranges = {} }
    end
    return { score = 1, display_ranges = {}, internal_ranges = internal }
  end

  return {
    matcher = function(query)
      return setmetatable({ query = query }, Matcher)
    end,
    rich_text = {
      searchable = function(value)
        table.insert(rich_text_calls.searchable, value)
        -- `source` lets a test tell which value (label vs. book path) a set of
        -- origins came from, without reproducing real byte-origin tracking.
        local origins = { source = value }
        for i = 1, #value do
          origins[i] = i
        end
        return value, origins
      end,
      map_ranges = function(ranges, origins)
        table.insert(rich_text_calls.map_ranges, { ranges = ranges, origins = origins })
        local mapped = {}
        for _, range in ipairs(ranges or {}) do
          table.insert(mapped, { start_byte = range.start_byte, end_byte = range.end_byte, mapped = true })
        end
        return mapped
      end,
    },
  }
end

local BlueprintLogic = require("lib.blueprint_logic")

local ITEM_MAIN = 1

local function record(fields)
  fields.valid = fields.valid ~= false
  return fields
end

local function stack(fields)
  fields.valid_for_read = fields.valid_for_read ~= false
  return fields
end

local function book_stack(label, inner)
  return stack({
    is_blueprint_book = true,
    name = "blueprint-book",
    label = label,
    preview_icons = {},
    blueprint_description = "",
    get_inventory = function(index)
      assert.are.equal(ITEM_MAIN, index)
      return inner
    end,
  })
end

-- Reproduces the runtime fact that reading default_icons on a blank blueprint raises
-- ("Given blueprint is empty."); the explicit fields still take precedence over the
-- metatable, since __index only fires for absent keys.
local function with_raising_default_icons(fields)
  return setmetatable(fields, {
    __index = function(_, key)
      if key == "default_icons" then
        error("Given blueprint is empty.")
      end
    end,
  })
end

describe("BlueprintLogic", function()
  describe(".sprite_path", function()
    it("treats a missing type as item", function()
      assert.are.equal("item/rail", BlueprintLogic.sprite_path({ name = "rail" }))
    end)

    it("maps virtual to virtual-signal", function()
      assert.are.equal(
        "virtual-signal/signal-input",
        BlueprintLogic.sprite_path({ type = "virtual", name = "signal-input" })
      )
    end)

    it("uses other types as they are", function()
      assert.are.equal("fluid/water", BlueprintLogic.sprite_path({ type = "fluid", name = "water" }))
      assert.are.equal(
        "space-location/nauvis",
        BlueprintLogic.sprite_path({ type = "space-location", name = "nauvis" })
      )
    end)

    it("returns nil for a signal without a name", function()
      assert.is_nil(BlueprintLogic.sprite_path({ type = "virtual" }))
      assert.is_nil(BlueprintLogic.sprite_path(nil))
    end)
  end)

  describe(".icon_caption", function()
    local function always_valid()
      return true
    end

    it("joins icons in index order as img tags", function()
      local icons = {
        { index = 2, signal = { type = "virtual", name = "shape-t" } },
        { index = 1, signal = { name = "rail" } },
      }

      assert.are.equal("[img=item/rail][img=virtual-signal/shape-t]", BlueprintLogic.icon_caption(icons, always_valid))
    end)

    it("replaces an invalid sprite with the missing icon", function()
      local icons = { { index = 1, signal = { name = "gone" } }, { index = 2, signal = { name = "rail" } } }
      local function valid(path)
        return path ~= "item/gone"
      end

      assert.are.equal("[img=utility/missing_icon][img=item/rail]", BlueprintLogic.icon_caption(icons, valid))
    end)

    it("returns nil when there are no icons", function()
      assert.is_nil(BlueprintLogic.icon_caption({}, always_valid))
      assert.is_nil(BlueprintLogic.icon_caption(nil, always_valid))
    end)
  end)

  describe("ids", function()
    it("round-trips location and indices", function()
      local id = BlueprintLogic.format_id("my", { 3, 5, 2 })

      assert.are.equal("my/3/5/2", id)
      local location, indices = BlueprintLogic.parse_id(id)
      assert.are.equal("my", location)
      assert.are.same({ 3, 5, 2 }, indices)
    end)

    it("accepts the inventory location", function()
      local location, indices = BlueprintLogic.parse_id("inv/12")

      assert.are.equal("inv", location)
      assert.are.same({ 12 }, indices)
    end)

    it("rejects an unknown location or malformed id", function()
      assert.is_nil(BlueprintLogic.parse_id("other/1"))
      assert.is_nil(BlueprintLogic.parse_id("game/"))
      assert.is_nil(BlueprintLogic.parse_id("game/1/x"))
      assert.is_nil(BlueprintLogic.parse_id("game/1//2"))
      assert.is_nil(BlueprintLogic.parse_id("inv/0"))
      assert.is_nil(BlueprintLogic.parse_id("game/1/0"))
      assert.is_nil(BlueprintLogic.parse_id("my/01"))
    end)
  end)

  describe(".abbreviate", function()
    it("keeps a leading icon tag", function()
      assert.are.equal("[item=rail]", BlueprintLogic.abbreviate("[item=rail]鉄道"))
    end)

    it("skips a leading color tag and takes the first character", function()
      assert.are.equal("赤", BlueprintLogic.abbreviate("[color=red]赤い本[/color]"))
    end)

    it("takes the first UTF-8 character of plain text", function()
      assert.are.equal("鉄", BlueprintLogic.abbreviate("鉄道"))
      assert.are.equal("M", BlueprintLogic.abbreviate("Mall"))
    end)

    it("returns an empty string when nothing remains", function()
      assert.are.equal("", BlueprintLogic.abbreviate("[color=red][/color]"))
    end)
  end)

  describe(".book_path", function()
    it("returns nil for no books", function()
      assert.is_nil(BlueprintLogic.book_path({}))
    end)

    it("shows a single book in full", function()
      local path = BlueprintLogic.book_path({ "Mall" })

      assert.are.equal("Mall", path.full)
      assert.are.equal("Mall", path.display)
      assert.are.equal(1, path.full_start)
      assert.are.equal(1, path.display_start)
    end)

    it("abbreviates every book but the nearest", function()
      local path = BlueprintLogic.book_path({ "[item=rail]鉄道", "Stations", "Inbound" })

      assert.are.equal("[item=rail]鉄道 › Stations › Inbound", path.full)
      assert.are.equal("[item=rail] › S › Inbound", path.display)
      assert.are.equal(#"[item=rail]鉄道 › Stations › " + 1, path.full_start)
      assert.are.equal(#"[item=rail] › S › " + 1, path.display_start)
    end)

    it("drops a book that abbreviates to nothing", function()
      local path = BlueprintLogic.book_path({ "[color=red][/color]", "Inbound" })

      assert.are.equal("Inbound", path.display)
    end)
  end)

  describe(".to_nodes", function()
    it("converts records, sorted by key, walking books", function()
      local records = {
        [2] = record({
          type = "blueprint",
          label = "b",
          preview_icons = {},
          default_icons = { "d" },
          blueprint_description = "",
          is_blueprint_setup = function()
            return true
          end,
        }),
        [1] = record({
          type = "blueprint-book",
          label = "book",
          preview_icons = { "p" },
          blueprint_description = "desc",
          is_preview = false,
          contents = {
            [4] = record({ type = "upgrade-planner", label = "u", preview_icons = {}, planner_description = "pd" }),
          },
        }),
      }

      local nodes = BlueprintLogic.to_nodes(records)

      assert.are.same({
        {
          key = 1,
          type = "blueprint-book",
          label = "book",
          icons = { "p" },
          description = "desc",
          children = {
            { key = 4, type = "upgrade-planner", label = "u", icons = {}, description = "pd" },
          },
        },
        { key = 2, type = "blueprint", label = "b", icons = { "d" }, description = "" },
      }, nodes)
    end)

    it("does not walk a preview book or read default icons of a preview blueprint", function()
      local records = {
        record({ type = "blueprint-book", label = "p", preview_icons = {}, is_preview = true }),
        record({ type = "blueprint", label = "q", preview_icons = {}, is_preview = true }),
      }

      local nodes = BlueprintLogic.to_nodes(records)

      assert.is_nil(nodes[1].children)
      assert.are.same({}, nodes[2].icons)
      assert.is_nil(nodes[2].description)
    end)

    it("skips invalid records", function()
      assert.are.same({}, BlueprintLogic.to_nodes({ record({ valid = false, type = "blueprint" }) }))
    end)

    it("converts a labelled blank blueprint record without reading default_icons", function()
      local blank = with_raising_default_icons(record({
        type = "blueprint",
        label = "Blank",
        preview_icons = {},
        blueprint_description = "",
        is_blueprint_setup = function()
          return false
        end,
      }))

      local nodes = BlueprintLogic.to_nodes({ blank })

      assert.are.same({}, nodes[1].icons)
    end)

    it("converts an unlabelled blank blueprint record without reading default_icons", function()
      local blank = with_raising_default_icons(record({
        type = "blueprint",
        label = "",
        preview_icons = {},
        blueprint_description = "",
        is_blueprint_setup = function()
          return false
        end,
      }))

      assert.has_no.errors(function()
        BlueprintLogic.to_nodes({ blank })
      end)
    end)
  end)

  describe(".item_kind", function()
    it("names each blueprint-like item with the record type vocabulary", function()
      assert.are.equal("blueprint", BlueprintLogic.item_kind({ is_blueprint = true }))
      assert.are.equal("blueprint-book", BlueprintLogic.item_kind({ is_blueprint_book = true }))
      assert.are.equal("deconstruction-planner", BlueprintLogic.item_kind({ is_deconstruction_item = true }))
      assert.are.equal("upgrade-planner", BlueprintLogic.item_kind({ is_upgrade_item = true }))
      assert.is_nil(BlueprintLogic.item_kind({}))
    end)
  end)

  describe(".item_nodes", function()
    it("converts blueprint-like items, walking book items and skipping everything else", function()
      local inner = {
        stack({ valid_for_read = false }),
        stack({
          is_upgrade_item = true,
          name = "upgrade-planner",
          label = "u",
          preview_icons = {},
          planner_description = "",
        }),
      }
      local inventory = {
        stack({
          is_blueprint = true,
          name = "mod-blueprint",
          label = "a",
          preview_icons = {},
          default_icons = { "d" },
          blueprint_description = "x",
          is_blueprint_setup = function()
            return true
          end,
        }),
        stack({ name = "iron-plate" }),
        stack({ valid_for_read = false }),
        book_stack("b", inner),
      }

      assert.are.same({
        { key = 1, type = "blueprint", item_name = "mod-blueprint", label = "a", icons = { "d" }, description = "x" },
        {
          key = 4,
          type = "blueprint-book",
          item_name = "blueprint-book",
          label = "b",
          icons = {},
          description = "",
          children = {
            {
              key = 2,
              type = "upgrade-planner",
              item_name = "upgrade-planner",
              label = "u",
              icons = {},
              description = "",
            },
          },
        },
      }, BlueprintLogic.item_nodes(inventory, ITEM_MAIN))
    end)

    it("converts a labelled blank blueprint item without reading default_icons", function()
      local blank = with_raising_default_icons(stack({
        is_blueprint = true,
        name = "blueprint",
        label = "Blank",
        preview_icons = {},
        blueprint_description = "",
        is_blueprint_setup = function()
          return false
        end,
      }))

      local nodes = BlueprintLogic.item_nodes({ blank }, ITEM_MAIN)

      assert.are.same({}, nodes[1].icons)
    end)

    it("converts an unlabelled blank blueprint item without reading default_icons", function()
      local blank = with_raising_default_icons(stack({
        is_blueprint = true,
        name = "blueprint",
        label = "",
        preview_icons = {},
        blueprint_description = "",
        is_blueprint_setup = function()
          return false
        end,
      }))

      assert.has_no.errors(function()
        BlueprintLogic.item_nodes({ blank }, ITEM_MAIN)
      end)
    end)
  end)

  describe(".resolve", function()
    local leaf = record({ type = "blueprint", label = "leaf", is_preview = false })
    local roots = {
      record({ type = "blueprint-book", label = "book", is_preview = false, contents = { [3] = leaf } }),
    }

    it("walks books by index and checks type and label", function()
      assert.are.equal(leaf, BlueprintLogic.resolve(roots, { 1, 3 }, "blueprint", "leaf"))
    end)

    it("returns nil when the record changed", function()
      assert.is_nil(BlueprintLogic.resolve(roots, { 1, 3 }, "blueprint", "renamed"))
      assert.is_nil(BlueprintLogic.resolve(roots, { 1, 3 }, "deconstruction-planner", "leaf"))
      assert.is_nil(BlueprintLogic.resolve(roots, { 1, 9 }, "blueprint", "leaf"))
      assert.is_nil(BlueprintLogic.resolve(roots, { 2 }, "blueprint", "leaf"))
    end)

    it("returns nil for a preview record or a path through a preview book", function()
      local preview_roots = {
        record({ type = "blueprint-book", label = "book", is_preview = true, contents = { [1] = leaf } }),
        record({ type = "blueprint", label = "p", is_preview = true }),
      }

      assert.is_nil(BlueprintLogic.resolve(preview_roots, { 1, 1 }, "blueprint", "leaf"))
      assert.is_nil(BlueprintLogic.resolve(preview_roots, { 2 }, "blueprint", "p"))
    end)
  end)

  describe(".resolve_item", function()
    local leaf = stack({ is_blueprint = true, name = "blueprint", label = "leaf" })
    local inventory = { stack({ valid_for_read = false }), book_stack("book", { leaf }) }

    it("walks book items by slot and checks kind and label", function()
      assert.are.equal(leaf, BlueprintLogic.resolve_item(inventory, { 2, 1 }, ITEM_MAIN, "blueprint", "leaf"))
    end)

    it("returns nil for an emptied slot, a changed item or an out-of-range slot", function()
      assert.is_nil(BlueprintLogic.resolve_item(inventory, { 1 }, ITEM_MAIN, "blueprint", "leaf"))
      assert.is_nil(BlueprintLogic.resolve_item(inventory, { 2, 1 }, ITEM_MAIN, "blueprint", "renamed"))
      assert.is_nil(BlueprintLogic.resolve_item(inventory, { 2, 1 }, ITEM_MAIN, "upgrade-planner", "leaf"))
      assert.is_nil(BlueprintLogic.resolve_item(inventory, { 2, 5 }, ITEM_MAIN, "blueprint", "leaf"))
      assert.is_nil(BlueprintLogic.resolve_item(inventory, { 9 }, ITEM_MAIN, "blueprint", "leaf"))
    end)

    it("returns nil when an intermediate index does not point at a book", function()
      assert.is_nil(BlueprintLogic.resolve_item({ leaf }, { 1, 1 }, ITEM_MAIN, "blueprint", "leaf"))
    end)
  end)

  describe(".build_candidates", function()
    before_each(function()
      rich_text_calls.searchable = {}
      rich_text_calls.map_ranges = {}
    end)

    local function always_valid()
      return true
    end

    local function node(fields)
      fields.icons = fields.icons or {}
      fields.description = fields.description or ""
      return fields
    end

    local locations = {
      {
        name = "game",
        nodes = {
          node({
            key = 1,
            type = "blueprint-book",
            label = "[item=rail]鉄道",
            description = "grid",
            children = {
              node({
                key = 2,
                type = "blueprint-book",
                label = "Stations",
                children = {
                  node({
                    key = 7,
                    type = "blueprint",
                    label = "[virtual-signal=signal-input]Inbound",
                    icons = { { index = 1, signal = { type = "virtual", name = "signal-input" } } },
                    description = "place first",
                  }),
                },
              }),
              node({ key = 3, type = "blueprint", label = "" }),
            },
          }),
          node({
            key = 5,
            type = "blueprint-book",
            label = "",
            children = {
              node({ key = 6, type = "blueprint", label = "Loose" }),
            },
          }),
        },
      },
      { name = "my", nodes = { node({ key = 1, type = "deconstruction-planner", label = "Trees" }) } },
      {
        name = "inv",
        nodes = { node({ key = 4, type = "blueprint", item_name = "mod-blueprint", label = "Mine" }) },
      },
    }

    local function by_id(candidates)
      local result = {}
      for _, candidate in ipairs(candidates) do
        result[candidate.id] = candidate
      end
      return result
    end

    it("builds a candidate from a nested blueprint", function()
      local candidate = by_id(BlueprintLogic.build_candidates("inbound", locations, always_valid))["game/1/2/7"]

      assert.are.equal("blueprint", candidate.type)
      assert.are.equal("blueprint", candidate.record_type)
      assert.are.equal("[virtual-signal=signal-input]Inbound", candidate.label)
      assert.are.equal("item/blueprint", candidate.icon)
      assert.are.equal("[virtual-signal=signal-input]Inbound", candidate.search_display_name)
      assert.are.equal("[item=rail] › Stations", candidate.search_internal_name)
      assert.are.same(
        { "", { "gui-blueprint-library.game-blueprints-title" }, " › " },
        candidate.search_internal_prefix
      )
      assert.are.same({
        caption = "[img=virtual-signal/signal-input]",
        tooltip = "[item=rail]鉄道 › Stations\nplace first",
      }, candidate.annotation)
    end)

    it("searches the label and the book path through rich_text.searchable", function()
      BlueprintLogic.build_candidates("inbound", locations, always_valid)

      local seen = {}
      for _, value in ipairs(rich_text_calls.searchable) do
        seen[value] = true
      end
      assert.is_true(seen["[virtual-signal=signal-input]Inbound"])
      assert.is_true(seen["[item=rail]鉄道 › Stations"])
    end)

    it("takes the label's ranges from rich_text.map_ranges", function()
      local candidate = by_id(BlueprintLogic.build_candidates("inbound", locations, always_valid))["game/1/2/7"]

      assert.is_true(#candidate.search_display_ranges > 0)
      for _, range in ipairs(candidate.search_display_ranges) do
        assert.is_true(range.mapped)
      end
    end)

    it("finds records through an abbreviated book and leaves that part unhighlighted", function()
      local candidates = by_id(BlueprintLogic.build_candidates("鉄道", locations, always_valid))
      local candidate = candidates["game/1/2/7"]

      assert.is_not_nil(candidate)
      assert.are.same({}, candidate.search_internal_ranges)
    end)

    it("highlights the nearest book in the displayed path", function()
      local candidate = by_id(BlueprintLogic.build_candidates("stations", locations, always_valid))["game/1/2/7"]
      local shown = candidate.search_internal_name

      assert.is_true(#candidate.search_internal_ranges > 0)
      local highlighted = {}
      for _, range in ipairs(candidate.search_internal_ranges) do
        table.insert(highlighted, shown:sub(range.start_byte, range.end_byte))
      end
      assert.are.equal("Stations", table.concat(highlighted))
    end)

    it("lists books and planners, and skips unlabelled records", function()
      local candidates = by_id(BlueprintLogic.build_candidates("t", locations, always_valid))

      assert.are.equal("item/deconstruction-planner", candidates["my/1"].icon)
      assert.is_nil(candidates["my/1"].search_internal_name)
      assert.is_nil(candidates["game/1/3"])
    end)

    it("finds a labelled blueprint through an unlabelled book, leaving that book out of the path", function()
      local candidate = by_id(BlueprintLogic.build_candidates("loose", locations, always_valid))["game/5/6"]

      assert.is_not_nil(candidate)
      assert.is_nil(candidate.search_internal_name)
    end)

    it("puts only the description in the tooltip of a top-level book", function()
      local candidate = by_id(BlueprintLogic.build_candidates("rail", locations, always_valid))["game/1"]

      assert.are.same({ tooltip = "grid" }, candidate.annotation)
    end)

    it("uses an inventory item's own name for its icon", function()
      local candidate = by_id(BlueprintLogic.build_candidates("mine", locations, always_valid))["inv/4"]

      assert.are.equal("item/mod-blueprint", candidate.icon)
      assert.are.equal("blueprint", candidate.record_type)
    end)

    it("returns nothing for an empty query", function()
      assert.are.same({}, BlueprintLogic.build_candidates("", locations, always_valid))
    end)

    it("shows Inventory as the second line of a top-level inventory candidate", function()
      local inv_locations = { { name = "inv", nodes = { node({ key = 1, type = "blueprint", label = "Solo" }) } } }
      local candidate = by_id(BlueprintLogic.build_candidates("solo", inv_locations, always_valid))["inv/1"]

      assert.are.same({ "gui.inventory" }, candidate.secondary_text)
      assert.is_nil(candidate.search_internal_name)
    end)

    it("gives each top-level library candidate its own location as the secondary line", function()
      local top_level_locations = {
        { name = "my", nodes = { node({ key = 1, type = "blueprint", label = "Solo" }) } },
        { name = "game", nodes = { node({ key = 2, type = "blueprint", label = "Solo" }) } },
      }
      local candidates = by_id(BlueprintLogic.build_candidates("solo", top_level_locations, always_valid))

      assert.are.same({ "gui-blueprint-library.private-shelf" }, candidates["my/1"].secondary_text)
      assert.is_nil(candidates["my/1"].search_internal_name)
      assert.are.same({ "gui-blueprint-library.game-blueprints-title" }, candidates["game/2"].secondary_text)
      assert.is_nil(candidates["game/2"].search_internal_name)
    end)

    it("prefixes an inventory candidate's book path with its location instead of a secondary line", function()
      local inv_book_locations = {
        {
          name = "inv",
          nodes = {
            node({
              key = 1,
              type = "blueprint-book",
              label = "Book",
              children = { node({ key = 2, type = "blueprint", label = "Solo" }) },
            }),
          },
        },
      }
      local candidate = by_id(BlueprintLogic.build_candidates("solo", inv_book_locations, always_valid))["inv/1/2"]

      assert.are.equal("Book", candidate.search_internal_name)
      assert.are.same({ "", { "gui.inventory" }, " › " }, candidate.search_internal_prefix)
      assert.is_nil(candidate.secondary_text)
    end)

    -- Distinguishes the map_ranges call made for a candidate's label from the one
    -- made for its book path, since the mock's searchable stamps origins.source with
    -- the exact value it was given.
    local function map_ranges_call_for(source)
      for _, call in ipairs(rich_text_calls.map_ranges) do
        if call.origins.source == source then
          return call
        end
      end
      return nil
    end

    it("pairs each map_ranges call with the origins of the field that matched", function()
      BlueprintLogic.build_candidates("stations", locations, always_valid)
      local internal_call = map_ranges_call_for("[item=rail]鉄道 › Stations")

      assert.is_not_nil(internal_call)
      assert.is_true(#internal_call.ranges > 0)

      rich_text_calls.map_ranges = {}
      BlueprintLogic.build_candidates("inbound", locations, always_valid)
      local display_call = map_ranges_call_for("[virtual-signal=signal-input]Inbound")

      assert.is_not_nil(display_call)
      assert.is_true(#display_call.ranges > 0)
    end)
  end)
end)
