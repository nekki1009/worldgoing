extends RefCounted
## Visual/equipment catalogue, not a second inventory or material balance system.
## Existing IDs remain iron. WoodAxe means logging axe, never a material.
## OPTIONS is JSON-compatible so Blender consumes this exact same catalogue.
const OPTIONS := [
	{"id":"longsword_01","label":"鐵製｜長劍","prefixes":["Weapon_Longsword_01"],"base":"longsword_01","material":"iron","category":"weapon"},
	{"id":"spear_01","label":"鐵製｜長槍","prefixes":["Weapon_Spear_01"],"base":"spear_01","material":"iron","category":"weapon"},
	{"id":"axe_01","label":"鐵製｜戰斧","prefixes":["Weapon_Axe_01"],"base":"axe_01","material":"iron","category":"weapon"},
	{"id":"wood_axe_01","label":"鐵製｜伐木斧","prefixes":["Weapon_WoodAxe_01"],"base":"wood_axe_01","material":"iron","category":"tool"},
	{"id":"hammer_01","label":"鐵製｜戰鎚","prefixes":["Weapon_Hammer_01"],"base":"hammer_01","material":"iron","category":"weapon"},
	{"id":"dagger_01","label":"鐵製｜匕首","prefixes":["Weapon_Dagger_01"],"base":"dagger_01","material":"iron","category":"weapon"},
	{"id":"bow_01","label":"鐵製｜長弓（鐵箭頭）","prefixes":["Weapon_Bow_01"],"base":"bow_01","material":"iron","category":"weapon"},
	{"id":"crossbow_01","label":"鐵製｜十字弩（鐵箭頭）","prefixes":["Weapon_Crossbow_01"],"base":"crossbow_01","material":"iron","category":"weapon"},
	{"id":"pickaxe_01","label":"鐵製｜鎬","prefixes":["Weapon_Pickaxe_Iron_01"],"base":"pickaxe_01","material":"iron","category":"tool"},
	{"id":"tool_hammer_01","label":"鐵製｜工具錘","prefixes":["Weapon_ToolHammer_Iron_01"],"base":"tool_hammer_01","material":"iron","category":"tool"},
	{"id":"shovel_01","label":"鐵製｜鏟","prefixes":["Weapon_Shovel_Iron_01"],"base":"shovel_01","material":"iron","category":"tool"},
	{"id":"longsword_01_wood","label":"木製｜長劍","prefixes":["Weapon_Longsword_Wood_01"],"base":"longsword_01","material":"wood","category":"weapon"},
	{"id":"spear_01_wood","label":"木製｜長槍","prefixes":["Weapon_Spear_Wood_01"],"base":"spear_01","material":"wood","category":"weapon"},
	{"id":"axe_01_wood","label":"木製｜戰斧","prefixes":["Weapon_Axe_Wood_01"],"base":"axe_01","material":"wood","category":"weapon"},
	{"id":"wood_axe_01_wood","label":"木製｜伐木斧","prefixes":["Weapon_WoodAxe_Wood_01"],"base":"wood_axe_01","material":"wood","category":"tool"},
	{"id":"hammer_01_wood","label":"木製｜戰鎚","prefixes":["Weapon_Hammer_Wood_01"],"base":"hammer_01","material":"wood","category":"weapon"},
	{"id":"dagger_01_wood","label":"木製｜匕首","prefixes":["Weapon_Dagger_Wood_01"],"base":"dagger_01","material":"wood","category":"weapon"},
	{"id":"bow_01_wood","label":"木製｜長弓（木箭頭）","prefixes":["Weapon_Bow_Wood_01"],"base":"bow_01","material":"wood","category":"weapon"},
	{"id":"crossbow_01_wood","label":"木製｜十字弩（木箭頭）","prefixes":["Weapon_Crossbow_Wood_01"],"base":"crossbow_01","material":"wood","category":"weapon"},
	{"id":"pickaxe_01_wood","label":"木製｜鎬","prefixes":["Weapon_Pickaxe_Wood_01"],"base":"pickaxe_01","material":"wood","category":"tool"},
	{"id":"tool_hammer_01_wood","label":"木製｜工具錘","prefixes":["Weapon_ToolHammer_Wood_01"],"base":"tool_hammer_01","material":"wood","category":"tool"},
	{"id":"shovel_01_wood","label":"木製｜鏟","prefixes":["Weapon_Shovel_Wood_01"],"base":"shovel_01","material":"wood","category":"tool"},
	{"id":"longsword_01_stone","label":"石製｜長劍","prefixes":["Weapon_Longsword_Stone_01"],"base":"longsword_01","material":"stone","category":"weapon"},
	{"id":"spear_01_stone","label":"石製｜長槍","prefixes":["Weapon_Spear_Stone_01"],"base":"spear_01","material":"stone","category":"weapon"},
	{"id":"axe_01_stone","label":"石製｜戰斧","prefixes":["Weapon_Axe_Stone_01"],"base":"axe_01","material":"stone","category":"weapon"},
	{"id":"wood_axe_01_stone","label":"石製｜伐木斧","prefixes":["Weapon_WoodAxe_Stone_01"],"base":"wood_axe_01","material":"stone","category":"tool"},
	{"id":"hammer_01_stone","label":"石製｜戰鎚","prefixes":["Weapon_Hammer_Stone_01"],"base":"hammer_01","material":"stone","category":"weapon"},
	{"id":"dagger_01_stone","label":"石製｜匕首","prefixes":["Weapon_Dagger_Stone_01"],"base":"dagger_01","material":"stone","category":"weapon"},
	{"id":"bow_01_stone","label":"石製｜長弓（石箭頭）","prefixes":["Weapon_Bow_Stone_01"],"base":"bow_01","material":"stone","category":"weapon"},
	{"id":"crossbow_01_stone","label":"石製｜十字弩（石箭頭）","prefixes":["Weapon_Crossbow_Stone_01"],"base":"crossbow_01","material":"stone","category":"weapon"},
	{"id":"pickaxe_01_stone","label":"石製｜鎬","prefixes":["Weapon_Pickaxe_Stone_01"],"base":"pickaxe_01","material":"stone","category":"tool"},
	{"id":"tool_hammer_01_stone","label":"石製｜工具錘","prefixes":["Weapon_ToolHammer_Stone_01"],"base":"tool_hammer_01","material":"stone","category":"tool"},
	{"id":"shovel_01_stone","label":"石製｜鏟","prefixes":["Weapon_Shovel_Stone_01"],"base":"shovel_01","material":"stone","category":"tool"},
	{"id":"longsword_01_steel","label":"鋼製｜長劍","prefixes":["Weapon_Longsword_Steel_01"],"base":"longsword_01","material":"steel","category":"weapon"},
	{"id":"spear_01_steel","label":"鋼製｜長槍","prefixes":["Weapon_Spear_Steel_01"],"base":"spear_01","material":"steel","category":"weapon"},
	{"id":"axe_01_steel","label":"鋼製｜戰斧","prefixes":["Weapon_Axe_Steel_01"],"base":"axe_01","material":"steel","category":"weapon"},
	{"id":"wood_axe_01_steel","label":"鋼製｜伐木斧","prefixes":["Weapon_WoodAxe_Steel_01"],"base":"wood_axe_01","material":"steel","category":"tool"},
	{"id":"hammer_01_steel","label":"鋼製｜戰鎚","prefixes":["Weapon_Hammer_Steel_01"],"base":"hammer_01","material":"steel","category":"weapon"},
	{"id":"dagger_01_steel","label":"鋼製｜匕首","prefixes":["Weapon_Dagger_Steel_01"],"base":"dagger_01","material":"steel","category":"weapon"},
	{"id":"bow_01_steel","label":"鋼製｜長弓（鋼箭頭）","prefixes":["Weapon_Bow_Steel_01"],"base":"bow_01","material":"steel","category":"weapon"},
	{"id":"crossbow_01_steel","label":"鋼製｜十字弩（鋼箭頭）","prefixes":["Weapon_Crossbow_Steel_01"],"base":"crossbow_01","material":"steel","category":"weapon"},
	{"id":"pickaxe_01_steel","label":"鋼製｜鎬","prefixes":["Weapon_Pickaxe_Steel_01"],"base":"pickaxe_01","material":"steel","category":"tool"},
	{"id":"tool_hammer_01_steel","label":"鋼製｜工具錘","prefixes":["Weapon_ToolHammer_Steel_01"],"base":"tool_hammer_01","material":"steel","category":"tool"},
	{"id":"shovel_01_steel","label":"鋼製｜鏟","prefixes":["Weapon_Shovel_Steel_01"],"base":"shovel_01","material":"steel","category":"tool"},
	{"id":"none","label":"None / 無","prefixes":[]}
]

const ATTACKS := {
	&"longsword_01": &"walk_slash",
	&"spear_01": &"attack_spear",
	&"axe_01": &"attack_axe",
	&"wood_axe_01": &"attack_axe",
	&"hammer_01": &"attack_hammer",
	&"dagger_01": &"attack_dagger",
	&"bow_01": &"attack_bow",
	&"crossbow_01": &"attack_crossbow",
	&"pickaxe_01": &"attack_axe",
	&"tool_hammer_01": &"attack_hammer",
	&"shovel_01": &"attack_spear",
	&"none": &"attack_unarmed",
}

static func family(asset: StringName) -> StringName:
	if ATTACKS.has(asset):
		return asset
	for material_id: String in ["wood", "stone", "steel"]:
		var base := StringName(str(asset).trim_suffix("_" + material_id))
		if base != asset and ATTACKS.has(base):
			return base
	return &"none"

static func material(asset: StringName) -> String:
	if asset == &"none" or family(asset) == &"none": return ""
	return "iron" if ATTACKS.has(asset) else str(asset).get_slice("_", str(asset).get_slice_count("_") - 1)

static func is_polearm(asset: StringName) -> bool:
	return family(asset) in [&"spear_01", &"shovel_01"]

static func is_ranged(asset: StringName) -> bool:
	return family(asset) in [&"bow_01", &"crossbow_01"]

static func apply_ammo_material(props: Node3D, asset: StringName) -> void:
	# The existing props owner still positions the arrow, bolt and quiver contents.
	# Only their head surfaces change; iron restores the exact original mesh.
	var kind := material(asset) if is_ranged(asset) else "iron"
	if props.get_meta("weapon_material", "iron") == kind: return
	props.set_meta("weapon_material", kind)
	for node: Node in props.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not part.has_meta("original_ammo_mesh"): part.set_meta("original_ammo_mesh", part.mesh)
		var original := part.get_meta("original_ammo_mesh") as ArrayMesh
		if original == null: continue
		if kind == "iron":
			part.mesh = original
			continue
		var changed := ArrayMesh.new()
		for surface in original.get_surface_count():
			var source := original.surface_get_material(surface) as BaseMaterial3D
			var arrays := original.surface_get_arrays(surface)
			var replacement: Material = source
			if source != null and source.resource_name.contains("CombatProp_Steel"):
				var head := source.duplicate() as BaseMaterial3D
				head.albedo_color = {"wood": Color("a37136"), "stone": Color("424f58"), "steel": Color("b2c6d6")}[kind]
				head.metallic = 0.92 if kind == "steel" else 0.0
				head.roughness = 0.24 if kind == "steel" else 0.82
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var center := Vector3.ZERO
				for point in points: center += point
				center /= maxf(1.0, points.size())
				for index in points.size():
					points[index].x = center.x + (points[index].x - center.x) * (1.4 if kind == "stone" else 1.0)
					points[index].y = center.y + (points[index].y - center.y) * (1.4 if kind == "stone" else 1.0)
				arrays[Mesh.ARRAY_VERTEX] = points
				replacement = head
			changed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			changed.surface_set_material(surface, replacement)
		part.mesh = changed
