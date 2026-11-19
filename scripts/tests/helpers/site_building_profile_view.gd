extends "res://scripts/terrain_lab/site_resource_view.gd"
## Original render commands and cache methods, without replacement geometry or renderers.
var building_probe: RefCounted

func refresh() -> void:
	var started: int = Time.get_ticks_usec()
	super.refresh()
	if building_probe != null: building_probe.add("view.refresh_inclusive", started)

func _rebuild_building_draws() -> void:
	var started: int = Time.get_ticks_usec()
	super._rebuild_building_draws()
	if building_probe != null: building_probe.add("building.rebuild", started)

func _draw_buildings(canvas: Node2D, row: int, foreground: bool) -> void:
	var started: int = Time.get_ticks_usec()
	super._draw_buildings(canvas, row, foreground)
	if building_probe != null: building_probe.add("building.art_submit", started)

func _draw_feature(canvas: Node2D, feature: Dictionary, row_index: int = -1) -> void:
	var started: int = Time.get_ticks_usec()
	super._draw_feature(canvas, feature, row_index)
	if building_probe != null: building_probe.add("building.prop_submit", started)
