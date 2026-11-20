extends SceneTree
## CIV-A4 平民裝 (Nekki 2026-11-20 A; scripts/terrain_lab/civilian_dress.gd), headless and pure. Checks:
## - the four civilian looks (男女 × 斗笠) are the civilian atlas catalog looks (Atlas.plan admits each);
## - SiteRuntime.equipment_appearance keeps an unarmed dressed person's clothes and dyes, so the projected look is still
##   an atlas look; an undressed look projects as before (every equipment slot none);
## - any equipped item drops the clothes (the gear look);
## - only farming and gathering households wear the straw hat.
## Output: CIVILIAN_DRESS_PASS on success; quit(1) on failure.

const Dress = preload("res://scripts/terrain_lab/civilian_dress.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_civilian_atlas.gd")
const Rider = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("CIVILIAN_DRESS OK ", checks, ": ", message)
		return true
	push_error("CIVILIAN_DRESS_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	for body: int in 2:
		for hatted: bool in [false, true]:
			var look := Dress.look(body, hatted)
			if not _ok(not Atlas.plan(look).is_empty() and Dress.is_dressed(look) and Dress.is_hatted(look) == hatted, "body %d hat %s is a civilian atlas look" % [body, hatted], look): return
	var data := TerrainData.new()
	data.allocate(Vector2i(4, 4))
	data.site = {"id": "dress-test", "inventory": {}}
	if not _ok(SiteRuntime.initialize_item_storage(data.site).ok, "item storage"): return
	var unarmed := SiteRuntime.new_item_state("person:5")
	var hatted := Dress.look(1, true)
	var projected := SiteRuntime.equipment_appearance(data, unarmed, hatted)
	if not _ok(projected.parts == hatted.parts and projected.get("equipment_dyes", {}) == hatted.equipment_dyes and not Atlas.plan(projected).is_empty(),
		"an unarmed dressed person keeps his clothes, dyes and atlas look", [projected, hatted]): return
	var plain := SiteRuntime.equipment_appearance(data, unarmed, Rider.appearance(0))
	var none := true
	for slot: String in SiteRuntime.APPEARANCE_EQUIPMENT_SLOTS: none = none and str(plain.parts[slot]) == "none"
	if not _ok(none and not Dress.is_dressed(plain), "an undressed look projects as before: every equipment slot none", plain.parts): return
	var armed := {}
	if not _ok(SiteRuntime.seed_person_equipment(data, armed, 6, Rider.appearance(0)).ok and not armed.equipped.is_empty(), "a person with an issued cloth kit", armed): return
	var geared := SiteRuntime.equipment_appearance(data, armed, hatted)
	if not _ok(not Dress.is_dressed(geared) and str(geared.parts.boots) == "boots_medieval_chinese_01" and Atlas.plan(geared).is_empty(), "any equipped item drops the civilian clothes (the gear look)", geared.parts): return
	if not _ok(Dress.outdoor_line("farming") and Dress.outdoor_line("gathering") and not Dress.outdoor_line("craft") and not Dress.outdoor_line(""), "only farming and gathering households wear the straw hat"): return
	print("CIVILIAN_DRESS_PASS checks=", checks)
	quit(0)
