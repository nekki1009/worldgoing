class_name SoldierVisualArchetype
extends RefCounted

var id: int = -1
var visual_id: StringName = &""
var display_name: String = ""
var visual_tier: int = CharacterVisualTier.Tier.REGULAR
var base_color: Color = Color.WHITE
var equipment_color: Color = Color.WHITE
var body_width: float = 0.46
var body_height: float = 0.78
var body_depth: float = 0.30
var head_size: float = 0.30
var weapon_kind: StringName = &"sword"
var weapon_length: float = 0.75
var has_shield: bool = false
var shield_width: float = 0.40
var shield_height: float = 0.52
var equipment_variant_count: int = 2
var mid_mesh: ArrayMesh
var far_mesh: ArrayMesh

func _init(
	new_id: int,
	new_visual_id: StringName,
	new_display_name: String,
	new_base_color: Color,
	new_equipment_color: Color
) -> void:
	id = new_id
	visual_id = new_visual_id
	display_name = new_display_name
	base_color = new_base_color
	equipment_color = new_equipment_color
