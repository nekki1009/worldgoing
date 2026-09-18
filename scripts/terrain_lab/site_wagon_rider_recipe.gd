extends RefCounted
## One real cloth kit, shared by the existing item initializer and both bakers.
## No inventory, person, vehicle or animation state lives here.
static func appearance(body: int) -> Dictionary:
	if body not in [0, 1]: return {}
	var result := HumanCharacter3DEditor.default_appearance(body)
	result.body = float(body) # Same canonical number type as the atlas/save JSON.
	result.parts.helmet = "helmet_cloth_chinese_01"
	result.parts.armor = "outfit_medieval_chinese_01"
	result.parts.boots = "boots_medieval_chinese_01"
	result.parts.outfit = "outfit_underlayer_01"
	for slot: String in ["cape", "weapon", "shield"]: result.parts[slot] = "none"
	result.equipment_dyes = {} # Explicit standard original colours, not faction dye.
	return result

static func matches(value: Dictionary) -> bool:
	if not HumanCharacter3DEditor.valid_appearance(value) or not value.get("equipment_dyes", {}).is_empty(): return false
	var geometry := HumanCharacter3DEditor.EquipmentDye.geometry_appearance(value)
	geometry.body = float(geometry.body) # The live editor returns int; JSON returns float.
	return geometry == HumanCharacter3DEditor.EquipmentDye.geometry_appearance(appearance(int(value.body)))
