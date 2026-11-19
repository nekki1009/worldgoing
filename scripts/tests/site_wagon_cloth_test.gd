extends "res://scripts/tests/site_vehicle_route_review_test.gd"
## Fixed cloth is a mounted-only presentation, never an equipment transaction.
## Crowd port (Nekki 2026-11-14 "都照建議"): the data rules only. Two crowd sides with wagons keep their real
## standard gear; the fixed rider cloth frame is a pure presentation of every real kit; a failed late append rolls back;
## Store/bind keeps every rider and item; dismount and a different person's take-over never issue, remove or recolour an item.
## The retired grid Sprite rider-frame checks are not ported. Run: --crowd --crowd-test <run_id>.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Recipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")
const Rider = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const CLOTH_OUT := "res://output/site_wagon_rider_display_20260918/runtime"
const DT := 1.0 / 30.0
var checks := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 240000
	_run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	if not ok:
		printerr("WAGON CLOTH FAIL ", checks, ": ", label, " ", str(details).left(600))
		quit(1)
	return ok

func _lab() -> TerrainLab:
	var lab: TerrainLab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	return lab

func _tick(lab: TerrainLab, count: int) -> void:
	for step in range(count): lab.crowd_site.step(DT, DT, 0.0)

func _people(lab: TerrainLab) -> Array[int]:
	var ids: Array[int] = []
	for index in range(int(lab.crowd_site.crowd.soldier_count())):
		var id := int(lab.crowd_site.soldier_state(index).get("person_id", -1))
		if id > 0: ids.append(id)
	ids.sort()
	return ids

func _gear(lab: TerrainLab) -> Dictionary:
	var people := {}
	for id: int in _people(lab):
		var person: Dictionary = lab.site_controller.person_actions._person(id)
		people[id] = person.get("holder", {}).duplicate(true)
	return {"people": people, "items": lab.terrain.site.item_records.duplicate(true),
		"definitions": lab.terrain.site.item_definitions.duplicate(true), "next_item": lab.terrain.site.next_item}

func _fixed_frame(actual: Dictionary) -> bool:
	var before := actual.duplicate(true)
	var cloth := Recipe.appearance(int(actual.body))
	var sprite := Sprite2D.new()
	root.add_child(sprite)
	var ok := true
	for direction: String in ["down", "left", "up", "right"]:
		for moving: bool in [false, true]:
			for sample in range(8 if moving else 1):
				var progress := float(sample) / 8.0
				var displayed := Rider.frame(actual, direction, moving, progress)
				var fixed := Rider.frame(cloth, direction, moving, progress)
				ok = ok and not displayed.is_empty() and not fixed.is_empty() and displayed.texture == fixed.texture \
					and displayed.anchor == fixed.anchor and displayed.horse_offset == fixed.horse_offset
				for slot: String in Rider.DyeAtlas.Dye.SLOTS: sprite.set_instance_shader_parameter(slot + "_dye", Vector4.ONE)
				ok = ok and Rider.apply(sprite, actual, displayed)
				if sprite.material != null:
					for slot: String in Rider.DyeAtlas.Dye.SLOTS: ok = ok and sprite.get_instance_shader_parameter(slot + "_dye") == Vector4.ZERO
	sprite.queue_free()
	return ok and actual == before

func _actual(lab: TerrainLab, owner: CrowdPersonOwner, index: int) -> Dictionary:
	var row: Dictionary = owner.combat_units[index]
	return SiteRuntime.equipment_appearance(lab.terrain, row.item_state, row.appearance)

func _roundtrip(lab: TerrainLab, name: String) -> Dictionary:
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.get("ok", false) == true, "the crowd Site captures for save", captured): return {}
	var path := CLOTH_OUT + "/" + name + ".json"
	var saved: Dictionary = Store.save(lab.terrain, path, lab.crowd_site.crowd)
	if not _check(saved.get("ok", false) == true, "the crowd Site saves", saved): return {}
	var loaded: Dictionary = Store.load_site(path, Callable(), 1, false)
	if not _check(loaded.get("ok", false) == true, "the crowd Site loads", loaded): return {}
	return loaded

func _run() -> void:
	if not _check(DisplayServer.get_name() == "headless", "headless data test"): return
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required (--crowd --crowd-test <run_id>)"): return
	DirAccess.make_dir_recursive_absolute(CLOTH_OUT)
	var lab := _lab()
	var ui := lab.site_controller
	var transport: SiteVehicleTransport = ui.vehicles
	var old_items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var setup := {"friendly_role": "logistics", "friendly_count": 3, "friendly_wagon_count": 1,
		"enemy_role": "logistics", "enemy_count": 3, "enemy_wagon_count": 1,
		"third_role": "logistics", "third_count": 3, "third_wagon_count": 1,
		"friendly_female_percent": 50, "enemy_female_percent": 50, "third_female_percent": 50,
		"friendly_faction": 0, "enemy_faction": 1, "third_faction": 2}
	var started := lab.start_melee_trial(setup)
	if not _check(started.ok and lab.crowd_site != null and lab.crowd_site.active, "two logistics sides with wagons start on the crowd", started): return
	if not _check(transport.records().size() == 2, "one wagon per starting side", transport.records().keys()): return
	for item: String in old_items:
		if not _check(lab.terrain.site.item_records.get(item) == old_items[item], "pre-existing items stay untouched", item): return
	var equipment_before := _gear(lab)
	# A late append that cannot allocate items rolls back without touching gear, items or vehicles.
	var next_item := int(lab.terrain.site.next_item)
	var site_alias := lab.terrain.site
	var cars_before: Dictionary = transport.records().duplicate(true)
	lab.terrain.site.next_item = 2147483646
	var failed: Dictionary = lab.add_melee_trial_team(setup)
	lab.terrain.site.next_item = next_item
	if not _check(not failed.ok, "a late append without item ids is refused", failed): return
	if not _check(is_same(site_alias, lab.terrain.site) and _gear(lab) == equipment_before and transport.records() == cars_before,
		"the refused append preserves gear, items and vehicles"): return
	# The crowd trial has no late third side (add_melee_trial_team is a GD Army slot API and refuses); the two wagon
	# sides carry the presentation rules below.
	# Every real kit of every wagon side shows the same fixed cloth frame while riding; the kit itself is never changed.
	var bodies := {}
	for id: String in transport.records():
		var wagon: Dictionary = transport.records()[id]
		var owner: Variant = transport._convoy_owner(wagon)
		if not _check(owner is CrowdPersonOwner and int(wagon.get("operator_id", 0)) > 0, "each wagon has a crowd operator", wagon): return
		for index: int in owner.combat_units.keys():
			var actual := _actual(lab, owner, index)
			if not _check(not Recipe.matches(actual) and Rider.supports(actual), "a real standard kit, never the cloth recipe", actual.get("parts")): return
			if not _check(_fixed_frame(actual), "the fixed cloth frame is a pure presentation of this real kit", owner.combat_identity(index)): return
			bodies[int(actual.body)] = true
	if not _check(bodies.has(0) and bodies.has(1), "both genders ride with the fixed cloth", bodies.keys()): return
	equipment_before = _gear(lab)
	# Store/bind keeps every rider, item and holder while mounted.
	var vehicle_id: String = transport.records().keys()[0]
	var wagon: Dictionary = transport.records()[vehicle_id]
	var rider_id := int(wagon.operator_id)
	var cars: Dictionary = transport.records().duplicate(true)
	var loaded := _roundtrip(lab, "mounted_display_two_factions_crowd")
	if loaded.is_empty(): return
	var site: Dictionary = loaded.data.site
	if not _check(site.item_records == equipment_before.items and site.item_definitions == equipment_before.definitions, "Store keeps every item and definition"): return
	if not _check(int(site.vehicles[vehicle_id].operator_id) == rider_id and site.vehicles.size() == cars.size(), "Store keeps every rider and wagon"): return
	# Dismount is never an equipment transaction.
	var owner: CrowdPersonOwner = transport._convoy_owner(wagon)
	var horse: Vector2i = transport.operator_cell(wagon)
	var released: Dictionary = transport.unassign_operator(vehicle_id, rider_id, true)
	if not _check(released.get("ok", false) == true, "the rider dismounts", released): return
	_tick(lab, 30)
	if not _check(int(wagon.operator_id) == 0 and _gear(lab) == equipment_before, "dismount issues, removes or recolours nothing"): return
	# A different real person of the same crowd team takes the wagon over (Nekki 2026-11-14 「要做換人上馬」): standing on a
	# legal cell beside the horse (a placement), the original command makes it the operator and
	# the native convoy steers it onto the rider slot. Boarding is never an equipment transaction either.
	# The dismounted rider walks back to its formation slot; a living non-crew body on the wagon's cells rightly blocks the
	# native convoy body, so the take-over waits until the wagon stands clear.
	var rider_index := owner.index_for_identity(rider_id)
	var cells: Array = SiteVehicleTransport.footprint(lab.terrain, wagon)
	for tick in range(900):
		if not cells.has(owner.person(rider_index, false).get("cell")) and not owner.is_walking(rider_index): break
		_tick(lab, 1)
	if not _check(not cells.has(owner.person(rider_index, false).get("cell")), "the dismounted rider stands clear of the wagon", owner.person(rider_index, false).get("cell")): return
	var replacement_id := -1
	for index: int in owner.combat_units.keys():
		var id := owner.combat_identity(index)
		if id != rider_id and id > 0 and not transport.is_operator(id): replacement_id = id; break
	if not _check(replacement_id > 0, "a different person of the same crowd team exists"): return
	var replacement_index := owner.index_for_identity(replacement_id)
	var beside := TerrainArmy.INVALID_CELL
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell := horse + direction
		if lab.terrain.is_walkable(cell) and lab.terrain.can_step(cell, horse) and not SiteVehicleTransport.footprint(lab.terrain, wagon).has(cell) and cell != owner.person(rider_index, false).get("cell"): beside = cell; break
	var native := int(lab.crowd_site.crowd.soldier_index(replacement_id))
	if not _check(beside != TerrainArmy.INVALID_CELL and lab.crowd_site.set_soldier_fields(native, {"px": beside.x + 0.5, "py": beside.y + 0.5}), "the replacement is placed beside the horse", {"horse": horse, "beside": beside}): return
	# Placement only, then the command at once: no siege station hold (a siege group cannot join a convoy crew natively).
	_tick(lab, 1)
	var commander := int(lab.crowd_site.formation_state(int(owner.formation_index)).get("current_person", replacement_id))
	var boarded: Dictionary = transport.assign_operator(vehicle_id, replacement_id, commander, true)
	if not _check(boarded.get("ok", false) == true and int(wagon.operator_id) == replacement_id, "the different real person takes the wagon over",
		{"result": boarded, "cell": owner.person(replacement_index, false).get("cell"), "beside": beside, "walking": owner.is_walking(replacement_index)}): return
	for tick in range(300):
		if not transport.rider_state(replacement_id).is_empty(): break
		_tick(lab, 1)
	if not _check(int(wagon.operator_id) == replacement_id and int(wagon.get("convoy_id", 0)) > 0 and not transport.rider_state(replacement_id).is_empty(),
		"the native convoy carries the new rider", {"operator": wagon.operator_id, "convoy": wagon.get("convoy_id"), "rider": transport.rider_state(replacement_id)}): return
	if not _check(_gear(lab) == equipment_before, "a different person's boarding changes no real item or holder"): return
	if not _check(_fixed_frame(_actual(lab, owner, replacement_index)), "the new rider's real kit shows the fixed cloth frame"): return
	var reloaded := _roundtrip(lab, "mounted_takeover_crowd")
	if reloaded.is_empty(): return
	if not _check(int(reloaded.data.site.vehicles[vehicle_id].operator_id) == replacement_id and reloaded.data.site.item_records == equipment_before.items, "Store keeps the new rider and every item"): return
	lab.queue_free()
	await process_frame
	print("SITE_WAGON_CLOTH_PASS checks=", checks, ": crowd two-faction standard gear untouched; both genders display fixed cloth only while riding; late append rollback; Store keeps items and riders; dismount and a different person's take-over change no item")
	quit(0)
