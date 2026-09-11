extends Node2D

# Four canvas batches, never one node per cell. Parent owns this presentation.
var renderer: Node2D
var kind: int = 0

func _draw() -> void:
	if is_instance_valid(renderer):
		renderer.call("draw_layer", self, kind)
