class_name SpecialCharacterAppearance
extends RefCounted

enum HairVisibilityMode { FULL, HIDDEN_BY_HELMET, SHORT_VARIANT }

var body_id: StringName = &"human_body_01"
var head_id: StringName = &"head_01"
var hair_id: StringName = &"hair_short_01"
var armor_id: StringName = &""
var helmet_id: StringName = &""
var weapon_id: StringName = &"sword_01"
var shield_id: StringName = &""
var hair_visibility_mode: int = HairVisibilityMode.FULL
var material_variant: int = 0

func duplicate_data() -> SpecialCharacterAppearance:
	var copy := SpecialCharacterAppearance.new()
	copy.body_id = body_id
	copy.head_id = head_id
	copy.hair_id = hair_id
	copy.armor_id = armor_id
	copy.helmet_id = helmet_id
	copy.weapon_id = weapon_id
	copy.shield_id = shield_id
	copy.hair_visibility_mode = hair_visibility_mode
	copy.material_variant = material_variant
	return copy

func key() -> String:
	return "%s|%s|%s|%s|%s|%s|%s|hair=%d|mat=%d" % [
		body_id, head_id, hair_id, armor_id, helmet_id, weapon_id, shield_id,
		hair_visibility_mode, material_variant
	]
