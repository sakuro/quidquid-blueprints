-- Quidquid dispatches an action by candidate type and input name, so sharing a key
-- sequence with Quidquid's own inputs is safe: none of its actions apply to blueprints.
-- The names are the ones these inputs had inside Quidquid, so a rebound key survives
-- the move.
data:extend({
  { type = "custom-input", name = "quidquid-hold-blueprint", key_sequence = "mouse-button-1" },
  { type = "custom-input", name = "quidquid-copy-blueprint", key_sequence = "ALT + mouse-button-2" },
  { type = "custom-input", name = "quidquid-export-blueprint", key_sequence = "COMMAND + mouse-button-1" },
})
