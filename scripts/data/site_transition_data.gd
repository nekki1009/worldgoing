class_name SiteTransitionData
extends RefCounted

enum Kind {
	STAIR,
	RAMP,
	BRIDGE,
	DOCK,
}

var from_cell: Vector2i = Vector2i.ZERO
var to_cell: Vector2i = Vector2i.ZERO
var from_level: int = 0
var to_level: int = 0
var kind: int = Kind.STAIR
var width_cells: int = 1

func _init(
		p_from_cell: Vector2i = Vector2i.ZERO,
		p_to_cell: Vector2i = Vector2i.ZERO,
		p_from_level: int = 0,
		p_to_level: int = 0,
		p_kind: int = Kind.STAIR,
		p_width_cells: int = 1
	) -> void:
	from_cell = p_from_cell
	to_cell = p_to_cell
	from_level = p_from_level
	to_level = p_to_level
	kind = p_kind
	width_cells = maxi(p_width_cells, 1)

func connects(from: Vector2i, to: Vector2i) -> bool:
	return (from_cell == from and to_cell == to) or (from_cell == to and to_cell == from)

func height_delta() -> int:
	return absi(to_level - from_level)

func copy() -> SiteTransitionData:
	return SiteTransitionData.new(
		from_cell,
		to_cell,
		from_level,
		to_level,
		kind,
		width_cells
	)
