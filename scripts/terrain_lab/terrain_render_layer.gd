extends Node2D

# Four original layers; the isolated geography viewer may retain bounded row slices.
var renderer: Node2D
var kind: int = 0
var row_start := -1
var row_end := -1
var column_start := -1
var column_end := -1
var cliff_pass := -1
var paint_enabled := true
var generation := -1
var submitted_generation := -1

func _draw() -> void:
	if is_instance_valid(renderer) and paint_enabled:
		if row_start < 0:
			renderer.call("draw_layer", self, kind)
		else:
			var started := Time.get_ticks_usec()
			renderer.call("draw_layer", self, kind, row_start, row_end, cliff_pass, column_start, column_end)
			renderer.call("slice_submitted", self, generation, Time.get_ticks_usec() - started)
