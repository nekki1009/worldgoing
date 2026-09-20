extends SceneTree
## Run only after formal publication/import and original atlas recertification.
## Real owners/guards/holders; headless model-state proof, never pixel proof.
const OUT := "res://output/equipment_limits_20260919/cape_role/live_roundtrip"
const CUSTOM := {"helmet": "123456ff", "armor": "76a92dff", "boots": "8453b1ff", "cape": "a83467ff", "outfit": "f4ca78ff"}
const SETS := [
	{"helmet": "helmet_japanese_steel_01", "armor": "armor_japanese_steel_01", "boots": "boots_japanese_steel_01", "shield": "shield_japanese_steel_01", "cape": "cape_japanese_01"},
	{"helmet": "helmet_japanese_iron_01", "armor": "armor_japanese_steel_01", "boots": "boots_japanese_leather_01", "shield": "shield_japanese_steel_01", "cape": "cape_japanese_01"},
]
const WESTERN_MODELS := {"helmet": "helmet_western_steel_01", "armor": "armor_western_steel_01", "boots": "boots_western_steel_01", "shield": "shield_western_steel_01"}
var lab: TerrainLab
var controller: SiteController
var orders: SiteEquipmentOrders
var captains: Array[int] = []
var people: Array[int] = []
var issued: Array[Dictionary] = []
var ordinary := -1
var run_dir := ""
var started := 0
var report := {"status": "RUNNING", "checks": 0, "stage": "setup", "proof": "headless real model/holder state; no pixels"}

func _initialize() -> void:
	started = Time.get_ticks_msec()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 110000:
		_check(false, "internal 110-second deadline")
		quit(1)
	return false

func _run() -> void:
	run_dir = OUT + "/run_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(run_dir) != OK:
		push_error("EQUIPMENT_MATRIX_LIVE: cannot create evidence directory")
		quit(1)
		return
	_write_report()
	var passed := _setup() and _exercise()
	report.status = "PASS" if passed else "FAIL"
	report.elapsed_msec = Time.get_ticks_msec() - started
	_write_report()
	if is_instance_valid(lab): lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	if passed:
		print("SITE EQUIPMENT MATRIX LIVE ROUNDTRIP PASS: original male/female commanders, fixed Japanese nation/mixed materials/new steel armor + cloth cape, Western native model groups, 16 NPC palettes, controlled-head custom, pure missing-atlas refusal/pending/cancel, SiteStore restore; headless model state only; evidence=", run_dir)
	quit(0 if passed else 1)

func _check(condition: bool, label: String, detail: Variant = null) -> bool:
	report.checks = int(report.checks) + 1
	if condition and Time.get_ticks_msec() - started <= 110000: return true
	report.status = "FAIL"
	report.failure = label
	if detail != null: report.detail = str(detail)
	_write_report()
	push_error("EQUIPMENT_MATRIX_LIVE: " + label + ("; " + str(detail) if detail != null else ""))
	return false

func _write_report() -> void:
	if run_dir.is_empty(): return
	var file := FileAccess.open(run_dir + "/report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))

func _freeze_simulation() -> void:
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)

func _setup() -> bool:
	if not _check(DisplayServer.get_name() == "headless", "headless-only test"): return false
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	_freeze_simulation()
	controller = lab.site_controller
	orders = controller.equipment_orders
	# Explicit fixture placement only, on unchanged legal terrain. Both original
	# squads are allies, so real NPC threat checks remain enabled during work.
	var cells: Array[Vector2i] = []
	for index in range(lab.terrain.size.x * lab.terrain.size.y):
		var depot := lab.terrain.cell_from_index(index)
		if not lab.terrain.is_walkable(depot): continue
		if lab.character.occupies_cell(depot) or lab.npc.occupies_cell(depot): continue
		cells.clear()
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var cell := depot + direction
			if lab.terrain.can_step(depot, cell) and not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell): cells.append(cell)
		if cells.size() >= 3:
			lab.terrain.site.depot_cell = index
			break
	if not _check(cells.size() >= 3, "three legal adjacent depot fixture cells"): return false
	var male := lab._trial_side_settings({"friendly_count": 2, "friendly_female_percent": 0, "friendly_attack": false}, "friendly")
	var female := lab._trial_side_settings({"third_count": 1, "third_female_percent": 100, "third_attack": false, "third_faction": 0}, "third")
	if not _check(male.ok and female.ok, "original trial settings", [male, female]): return false
	var male_cells: Array[Vector2i] = [cells[0], cells[1]]
	var female_cells: Array[Vector2i] = [cells[2]]
	var deployed := lab._deploy_trial_teams([male.side, female.side], [male_cells, female_cells], 0)
	if not _check(deployed.ok, "original deployment/strict baseline atlas readiness", deployed): return false
	people.assign([lab.character.person_id, lab.npc.person_id])
	for body in range(2):
		var team: TerrainArmy = lab.combat_armies[body]
		var identity := team.combat_identity(0)
		if not _check(team.formal_commander == 0 and team.current_commander == 0 and team._uses_live_presenter(0) and int(team.combat_units[0].appearance.body) == body and controller.person_can_wear_cape(identity), "original deployment grants actual commander office before any nation fixture"): return false
		captains.append(identity)
		for row in range(team.combat_units.size()): people.append(team.combat_identity(row))
		# Production intentionally omits presenters in headless mode. Attach ONLY
		# this existing live row's original factory product; no atlas role is changed.
		if not _check(team._unit_editor(0) == null, "headless begins without a live source"): return false
		var editor: HumanCharacter3DEditor = team._create_visual_source(body, "ArmyPerson_%d" % identity)
		team._live_presenters[identity] = editor
		team._visual_sources_owned = true
		editor.set_process(false)
		var records: Dictionary = lab.terrain.site.item_records.duplicate(true)
		controller.initialize_team_items(team) # Original holder-derived restore and bound callbacks.
		if not _check(lab.terrain.site.item_records == records and editor.part_selection_request.is_valid() and editor.equipment_dye_request.is_valid(), "binding existing live source cannot mint items"): return false
		if not _models_available(editor, SETS[body]): return false
		if not _models_available(editor, WESTERN_MODELS): return false
	ordinary = lab.army.combat_identity(1)
	if not _check(not lab.army._uses_live_presenter(1) and not controller.person_can_wear_cape(ordinary), "ordinary row stays atlas/non-officer"): return false
	if not _check(lab.army.supports_equipment_recipe(controller.person_appearance(ordinary)), "negative control starts with an admitted ordinary atlas recipe"): return false
	# Original political schema, tied to already-created people. Equipment never
	# creates offices: the two cape wearers already proved actual Army command.
	lab.terrain.site.equipment_nations = {"matrix": {"military_head": captains[0], "members": people.duplicate(), "standards": {}}}
	if not _check(orders.set_nation_culture(captains[0], "matrix", "japanese").ok, "original national head explicitly fixes future issue culture"): return false
	lab.terrain.site.capacity = maxi(int(lab.terrain.site.capacity), SiteRuntime.inventory_size(lab.terrain.site.inventory) + 40)
	for body in range(2):
		var items := _stock_set(SETS[body])
		if items.is_empty(): return false
		issued.append(items)
		var result := orders.set_standard(captains[0], "matrix", "set_%d" % body, "Published steel set %d" % body, _requirements(SETS[body]), "blue")
		if not _check(result.ok, "NPC head authors real depot requirements", result): return false
	report.identities = {"male_commander": captains[0], "female_commander": captains[1], "ordinary_atlas": ordinary}
	report.new_sets = SETS
	report.formal_pack_sha256 = {
		"male": FileAccess.get_sha256(HumanCharacter3DEditor.MALE_MODEL_PATH),
		"female": FileAccess.get_sha256(HumanCharacter3DEditor.FEMALE_MODEL_PATH)}
	_write_report()
	return true

func _requirements(parts: Dictionary) -> Dictionary:
	var slots := {}
	for slot: String in parts: slots[slot] = {"definition": slot + ":" + str(parts[slot])}
	return slots

func _stock_set(parts: Dictionary) -> Dictionary:
	var items := {}
	for slot: String in parts:
		var asset := str(parts[slot])
		var result := SiteRuntime.create_equipment(lab.terrain, lab.terrain.site.depot_items, slot + ":" + asset,
			{"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, lab.character.person_id)
		if not _check(result.ok, "explicit fixture stock via original registry", result): return {}
		items[slot] = str(result.item_id)
	return items

func _models_available(editor: HumanCharacter3DEditor, parts: Dictionary, worn: bool = false) -> bool:
	if not _check(editor.model_root != null, "published native-sex model exists"): return false
	for slot: String in parts:
		var component := editor._component_definition(StringName(slot), StringName(parts[slot]))
		if not _check(not component.is_empty() and editor._component_has_nodes(component), "actual native-sex component: " + str(parts[slot])): return false
		if slot == "cape" and not _check(component.get("material") == "cloth" and component.get("officer_only") == true, "Japanese cape remains cloth/officer-only"): return false
		var meshes := 0
		for node: Node3D in editor._find_component_nodes(component.prefixes):
			var mesh := node as MeshInstance3D
			if mesh != null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0 and (not worn or mesh.is_visible_in_tree()): meshes += 1
		if not _check(meshes > 0, "real nonempty %s meshes: %s" % ["visible" if worn else "native", parts[slot]]): return false
	return true

func _exercise() -> bool:
	report.stage = "original timed issue"
	for body in range(2):
		var identity := captains[body]
		var person := controller.person_actions._person(identity)
		if not _check(not bool(person.player), "new-set wearer is an NPC during issue"): return false
		var before: Dictionary = person.holder.duplicate(true)
		var records: Dictionary = lab.terrain.site.item_records.duplicate(true)
		var cargo: Dictionary = person.cargo
		var prepared := orders.prepare(identity, {"mode": "issue", "nation_id": "matrix", "standard_id": "set_%d" % body})
		if not _check(prepared.ok, "real prepare accepts published complete set", prepared): return false
		var result := orders.begin_issue(identity, "matrix", "set_%d" % body)
		if not _check(result.ok and float(result.get("seconds", 0)) == 5.0, "original 5s order", result): return false
		controller.person_actions.advance(4.999)
		if not _check(controller.person_actions.settle_after_contacts().is_empty() and person.holder == before and lab.terrain.site.item_records == records, "no early inventory commit"): return false
		controller.person_actions.advance(0.001)
		var settled := controller.person_actions.settle_after_contacts()
		if not _check(settled.size() == 1 and bool(settled[0].ok), "original post-contact commit", settled): return false
		if not _check(is_same(person.holder, controller.person_actions._person(identity).holder) and is_same(cargo, person.cargo) and int(person.holder.version) == int(before.version) + 1 and lab.terrain.site.item_records.size() == records.size(), "same real holder/cargo, single version increment, no fabricated items"): return false
		for slot: String in issued[body]:
			if not _check(person.holder.equipped.get(slot) == issued[body][slot], "equipped exact stocked item ID: " + slot): return false
		for item_id: String in records:
			var expected: Dictionary = records[item_id].duplicate(true)
			if prepared.order.take.has(item_id): expected.holder = str(person.holder.holder)
			if prepared.order["return"].has(item_id): expected.holder = "depot"
			if not _check(lab.terrain.site.item_records[item_id] == expected, "every old/new record preserves owner/dye; only declared holder transfer: " + item_id): return false
		if not _check(orders.apply_standard_dyes(captains[0], identity, "matrix", "set_%d" % body).ok, "NPC standard dyes use original transaction"): return false
		if not _live_matches(body): return false
	if not _palette_policy() or not _atlas_refusal(): return false
	return _round_trip()

func _live_matches(body: int) -> bool:
	var identity := captains[body]
	var person := controller.person_actions._person(identity)
	var desired := SiteRuntime.equipment_appearance(lab.terrain, person.holder, person.body.appearance)
	var editor: HumanCharacter3DEditor = person.owner._unit_editor(int(person.unit))
	if not _check(editor != null and controller.person_can_wear_cape(identity), "same actual officer live presenter"): return false
	var actual := editor.capture_appearance()
	if not _check(actual.body == body and actual.parts == desired.parts and actual.get("equipment_dyes", {}) == desired.get("equipment_dyes", {}) and controller.person_appearance(identity) == desired, "original callback publishes holder-derived native-sex parts/dyes", {"actual": actual, "desired": desired}): return false
	for slot: String in SETS[body]:
		if not _check(actual.parts[slot] == SETS[body][slot] and person.holder.equipped.get(slot) == issued[body][slot], "new set retained: " + slot): return false
	return _models_available(editor, SETS[body], true)

func _palette_policy() -> bool:
	report.stage = "NPC 16 / controlled-head custom"
	var seen := {}
	for index in range(16):
		var palette := SiteEquipmentOrders.npc_palette_id(index)
		seen[palette] = true
		var before := _inventory_snapshot()
		var result := orders.set_standard(captains[0], "matrix", "set_0", palette, _requirements(SETS[0]), palette)
		if not _check(result.ok and _inventory_snapshot() == before, "standard edits are future-only: " + palette, result): return false
		for body in range(2):
			if not _check(orders.apply_standard_dyes(captains[0], captains[body], "matrix", "set_0").ok, "NPC applies preset: " + palette): return false
			if not _check(controller.person_appearance(captains[body]).equipment_dyes == SiteRuntime.EquipmentDye.PRESETS[palette].colors, "all five preset slots remain exact"): return false
			if not _live_matches(body): return false
	if not _check(seen.size() == 16, "16 distinct NPC palettes"): return false
	var before := _inventory_snapshot()
	var nation: Dictionary = lab.terrain.site.equipment_nations.duplicate(true)
	if not _check(orders.set_standard(captains[0], "matrix", "set_0", "NPC cannot author custom", _requirements(SETS[0]), CUSTOM).code == "INVALID" and orders.dye_person(captains[0], captains[1], CUSTOM).code == "INVALID", "NPC rejects arbitrary colours"): return false
	if not _check(orders.set_standard(ordinary, "matrix", "set_0", "Not a head", _requirements(SETS[0]), "red").code == "NO_AUTHORITY" and lab.terrain.site.equipment_nations == nation and _inventory_snapshot() == before, "non-head/invalid dyes change nothing"): return false
	var original_control := lab.controlled_person_id()
	if not _check(controller._control_family_person(null, captains[0]).ok, "control existing head through original callback"): return false
	if not _check(orders.set_standard(captains[0], "matrix", "set_0", "Player-authored custom", _requirements(SETS[0]), CUSTOM).ok, "actual controlled head may author custom"): return false
	if not _check(controller._control_family_person(null, original_control).ok, "return control without creating rank"): return false
	for body in range(2):
		if not _check(orders.apply_standard_dyes(captains[0], captains[body], "matrix", "set_0").ok and controller.person_appearance(captains[body]).equipment_dyes == CUSTOM, "NPC retains and applies already-authored custom standard"): return false
		if not _live_matches(body): return false
	report.palettes = seen.keys()
	return true

func _inventory_snapshot() -> String:
	var holders := []
	for identity: int in people:
		var person := controller.person_actions._person(identity)
		holders.append([identity, person.holder, person.cargo, controller.person_appearance(identity)])
	var sources := []
	for team: TerrainArmy in lab.combat_armies:
		var roles := []
		for row: Dictionary in team.combat_units: roles.append([row.person_id, row.visual_role])
		sources.append([roles, team.active_3d_source_count(), team.formal_commander, team.current_commander, team.officer_order, team.officer_service])
	return JSON.stringify([lab.terrain.site.item_records, lab.terrain.site.item_definitions, lab.terrain.site.next_item, lab.terrain.site.depot_items, lab.terrain.site.inventory, holders, sources], "", true, true)

func _atlas_refusal() -> bool:
	report.stage = "ordinary atlas rejection"
	var parts: Dictionary = SETS[0].duplicate()
	parts.erase("cape") # Prove atlas rejection, not the earlier cape role gate.
	if _stock_set(parts).is_empty(): return false
	var result := orders.set_standard(captains[0], "matrix", "unbaked", "No unpublished atlas substitute", _requirements(parts), "blue")
	if not _check(result.ok, "real stock and valid ordinary standard", result): return false
	var person := controller.person_actions._person(ordinary)
	if not _check(orders._ready(person).ok and orders._at_depot(person) and not person.holder.equipped.has("cape"), "ordinary negative control ready/adjacent/capeless"): return false
	var appearance := controller.person_appearance(ordinary).duplicate(true)
	for slot: String in parts: appearance.parts[slot] = parts[slot]
	if not _check(not lab.army.supports_equipment_recipe(appearance), "new ordinary recipe really remains unbaked"): return false
	var before := _inventory_snapshot()
	result = orders.prepare(ordinary, {"mode": "issue", "nation_id": "matrix", "standard_id": "unbaked"})
	if not _check(result.code == "ATLAS_REQUIRED" and result.has("order"), "pure prepare still rejects unbaked atlas and preserves the validated original order", result): return false
	# Preflight depot pieces still belong to the depot, so a committed-holder
	# renderer correctly refuses them. Independently check the proposed dyes
	# against the real records, without simulating an ownership transfer.
	appearance.erase("equipment_dyes")
	for slot: String in result.order.planned:
		var record: Dictionary = lab.terrain.site.item_records[str(result.order.planned[slot])]
		var definition: Dictionary = lab.terrain.site.item_definitions[str(record.definition)]
		var dye := SiteRuntime.item_dye(record, definition)
		if not dye.is_empty():
			if not appearance.has("equipment_dyes"): appearance.equipment_dyes = {}
			appearance.equipment_dyes[slot] = dye
	if not _check(result.appearance == appearance, "missing appearance includes only dyes on actual planned items, not returned gear", {"result": result, "expected": appearance}): return false
	if not _check(orders.commit(result.order).code == "ATLAS_REQUIRED" and _inventory_snapshot() == before, "missing atlas cannot commit or mutate any held item"): return false
	result = orders.begin_issue(ordinary, "matrix", "unbaked")
	if not _check(result.ok and result.get("preparing", false) and controller.person_actions.is_busy(ordinary) and not controller.person_actions.save_guard().ok and _inventory_snapshot() == before and lab.army._unit_editor(1) == null, "original job prepares without holder/version/dye/source/office changes", result): return false
	if not _check(controller.person_actions.save_guard().code == "BUSY", "pending atlas preparation blocks save through the original job guard"): return false
	var original_executor := controller.person_executor_id
	controller.person_executor_id = ordinary
	controller.update_ui()
	if not _check(controller.details.text.contains("正在準備共用裝備外觀；完成後開始五秒換裝，可取消") and not controller.details.text.contains("PREPARING_ATLAS"), "actual pending-job details explain preparation before the five-second clock"): return false
	var canceled := controller.person_actions.cancel(ordinary)
	if not _check(canceled.ok and controller.person_actions.save_guard().ok and not controller.person_actions.is_busy(ordinary) and _inventory_snapshot() == before and lab.army._unit_editor(1) == null, "explicit cancel clears pending job without inventory change or per-person 3D", canceled): return false
	controller.update_ui()
	if not _check(not controller.details.text.contains("正在準備共用裝備外觀"), "actual details clear the preparation message after explicit cancel"): return false
	controller.person_executor_id = original_executor
	report.atlas_rejection = {"query": "ATLAS_REQUIRED", "begin": result, "cancel": canceled,
		"proof": "pure guard/pending savebusy/explicit cancel only; no capture attempted and no permanent unsupported claim"}
	return true

func _round_trip() -> bool:
	report.stage = "SiteStore save/load and original bind"
	if not _check(controller.supply_save_guard().ok, "original save guard"): return false
	controller._capture_positions()
	var records: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var nation: Dictionary = lab.terrain.site.equipment_nations.duplicate(true)
	var holders := []
	var appearances := []
	for identity: int in captains:
		holders.append(controller.person_actions._person(identity).holder.duplicate(true))
		appearances.append(controller.person_appearance(identity).duplicate(true))
	var path := run_dir + "/published_sets.json"
	var saved := SiteStore.save(lab.terrain, path)
	if not _check(saved.ok, "real SiteStore.save", saved): return false
	# Change via the same original dye owner after saving. Loading must restore
	# the saved colours, not merely leave already-correct presenter state alone.
	if not _check(orders.set_standard(captains[0], "matrix", "temporary", "Unsaved preset", _requirements(SETS[0]), "red").ok, "unsaved preset setup"): return false
	for body in range(2):
		if not _check(orders.apply_standard_dyes(captains[0], captains[body], "matrix", "temporary").ok and controller.person_appearance(captains[body]).equipment_dyes != CUSTOM, "real pre-load state differs from saved state"): return false
		if not _live_matches(body): return false
	var loaded := SiteStore.load_site(path)
	if not _check(loaded.ok, "real SiteStore.load_site with original asset/fingerprint guards", loaded): return false
	lab.bind_terrain(loaded.data)
	_freeze_simulation()
	if not _check(is_same(lab.terrain, loaded.data) and lab.terrain.site.item_records == records and lab.terrain.site.equipment_nations == nation, "original bind restores exact records and standard; no mint/redye"): return false
	for body in range(2):
		var team: TerrainArmy = lab.combat_armies[body]
		if not _check(team.combat_identity(0) == captains[body] and team.formal_commander == 0 and team.current_commander == 0 and team.active_3d_source_count() == 1 and controller.person_actions._person(captains[body]).holder == holders[body] and controller.person_appearance(captains[body]) == appearances[body], "saved original identity/office/holder/body restored"): return false
		if not _live_matches(body): return false # No test-side restore after load.
	if not _check(lab.army.combat_identity(1) == ordinary and not lab.army._uses_live_presenter(1) and lab.army._unit_editor(1) == null and controller.cape_policy_guard().ok, "ordinary atlas and cape policy survive load"): return false
	controller._capture_positions()
	var resaved := SiteStore.save(lab.terrain, run_dir + "/restored_sets.json")
	if not _check(resaved.ok, "restored scene can save again", resaved): return false
	report.saved_path = path
	report.saved_sha256 = FileAccess.get_sha256(path)
	report.stage = "complete"
	return true
