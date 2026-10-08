# Quidquid: Blueprints

[![Downloads](https://img.shields.io/badge/dynamic/json.svg?label=Downloads&url=https%3A%2F%2Fmods.factorio.com%2Fapi%2Fmods%2Fquidquid-blueprints&query=%24.downloads_count)](https://mods.factorio.com/mod/quidquid-blueprints)

Adds blueprint search to the [Quidquid](https://mods.factorio.com/mod/quidquid) palette.

By default, blueprints appear in the palette's search along with everything else. Type `b ` or `blueprint ` to restrict the search to them. Turning off "Include blueprints in the default search" leaves them to the restricted search only.

Search blueprints, blueprint books, deconstruction planners and upgrade planners in your main inventory and in the blueprint library, both "My blueprints" and "Game blueprints". Books are searched into, at any depth.

| Key | Action |
| --- | --- |
| Left click | Hold the blueprint |
| `Ctrl/Cmd` + left click | Show the export string |
| `Alt` + right click | Copy into the inventory |

A top-level inventory item is picked up itself and goes back to its slot on `Q`; an item inside a book item is taken out of the book instead, with no slot to return to. A library entry is held as a copy (no mod can put the entry itself in the cursor); clearing the cursor discards the copy, and placing it in a slot keeps it. Copying an inventory item into the inventory makes a duplicate.
The export string is shown selected, ready to copy with `Ctrl/Cmd + C`; a mod cannot write to the clipboard itself.

Icons written into a name, such as `[item=rail]`, are searchable by what they show (`rail`) but never highlighted. A record without a name is not listed.
The second line shows where the entry is (inventory, My blueprints or Game blueprints), then the enclosing books, all but the nearest shortened to an icon or first character. The tooltip shows the full path.
