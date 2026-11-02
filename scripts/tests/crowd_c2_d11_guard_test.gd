extends SceneTree
## D11 original-owner fixture; only initial captivity/feeding is authored.
## ESCAPED must arrive from the real native event stream, never an injected event.
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var controller: SiteController
var site: Node
var checks: Array[Dictionary] = []
var events: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var failed: bool = false
var out_dir: String = ""
var current_case: String = ""
var target_id: int = -1
var captor_id: int = -1
var guard_id: int = -1
var home_team: int = -1
var captor_team: int = -1
var guard_team: int = -1
var original_row: Dictionary = {}
var original_holder: Dictionary = {}
var original_cargo: Dictionary = {}
var sealed_id: String = ""
var sealed_before: Dictionary = {}
var initial_items: int = 0
var original_ids: Array[int] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"ok": ok, "case": current_case, "check": label, "details": details})
	print("D11 ", "OK " if ok else "FAIL ", current_case, " ", label, " ", str(details) if details != null else "")
	if not ok:
		failed = true
		_write()
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _write() -> void:
	if out_dir.is_empty(): return
	var file: FileAccess = FileAccess.open(out_dir.path_join("d11_guard.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "checks": checks, "events": events, "samples": samples,
		"setup": "Formal TerrainLab starts ordinary, with original NPC and three original manual Army teams. Initial captivity is a declared fixture using original supply preflight/commit, original sealed-item transaction, and original person records. Production deployment imports those original people. guard_team uses distinct original captor and guard Army owners. outside_ko/outside_escape use the original NPC omitted from native membership. No ESCAPED event or escape transition is injected.",
		"not_covered": ["full DR battle lifecycle", "large scene performance", "combining a different Army guard and an absent native guard in one person"]}, "\t", true, true))
	file.close()

func _on_events(batch: PackedInt64Array) -> void:
	for offset in range(0, batch.size(), 4):
		events.append({"case": current_case, "kind": int(batch[offset]), "person": int(batch[offset + 1]),
			"other": int(batch[offset + 2]), "formation": int(batch[offset + 3]), "tick": int(site.crowd.stats()[36])})

func _escape_count() -> int:
	var count: int = 0
	for event: Dictionary in events:
		if event.case == current_case and int(event.kind) == 5 and int(event.person) == target_id: count += 1
	return count

func _hot() -> Dictionary:
	return site.soldier_state(int(site.crowd.soldier_index(target_id)))

func _feeding(identity: int) -> String:
	var index: Dictionary = controller.captivity_supply.feeding_index()
	return str(index.owners.get(identity, "")) if index.duplicate_ids.is_empty() else "DUPLICATE"

func _original_person() -> Dictionary:
	return controller.person_actions._person(target_id)

func _unique(label: String) -> bool:
	var identities: Dictionary = {}
	var holders: Array = [lab.terrain.site.depot_items]
	for actor: TerrainTestCharacter in lab.combat_actors: holders.append(actor.item_state)
	for identity: int in original_ids:
		var person: Dictionary = controller.person_actions._person(identity)
		if person.is_empty(): return _check(false, label + " original person disappeared", identity)
		holders.append(person.holder)
	if site != null and site.active:
		for identity: int in site._records:
			if not original_ids.has(identity): holders.append(site._records[identity].item_state)
	else:
		for team: TerrainArmy in lab.combat_armies:
			if not team.combat_enabled: continue
			for row: Dictionary in team.combat_units:
				if not original_ids.has(int(row.person_id)): holders.append(row.item_state)
	for container: Dictionary in lab.terrain.site.ground_loot.values(): holders.append(container)
	for holder: Dictionary in holders:
		for identity: String in holder.item_ids:
			if identities.has(identity): return _check(false, label + " duplicate original item", identity)
			identities[identity] = holder.holder
			if str(lab.terrain.site.item_records[identity].holder) != str(holder.holder): return _check(false, label + " item holder disagrees", identity)
	var person: Dictionary = _original_person()
	return _check(identities.size() == initial_items and lab.terrain.site.item_records.size() == initial_items and is_same(person.body, original_row) and is_same(person.holder, original_holder) and is_same(person.cargo, original_cargo) and lab.terrain.site.ground_loot[sealed_id] == sealed_before,
		label + " original person/holder/cargo references, sealed contents and every item remain unique", {"items": identities.size(), "expected": initial_items})

func _fixture_captive(team: TerrainArmy, index: int, ko: float) -> bool:
	var person: Dictionary = controller.person_actions._person(target_id)
	var original: Dictionary = controller.person_actions._person(captor_id)
	var prepared: Dictionary = controller.captivity_supply.change_guard(target_id, captor_id, true)
	if not _check(prepared.ok, "original supply owner admits initial declared captivity fixture", prepared): return false
	var selection: Dictionary = controller.person_actions._sealed_selection(person)
	var sealed: Dictionary = Runtime.leave_ground_loot(lab.terrain, person.holder, person.cargo, target_id, person.cell, "sealed", selection.resources, selection.item_ids, int(person.holder.version))
	if not _check(sealed.ok, "original equipped items enter the original sealed container transaction", sealed): return false
	sealed_id = str(sealed.container_id)
	lab.terrain.site.captivity[str(target_id)] = {"version": 1, "captor_id": captor_id, "guard_id": guard_id,
		"captor_faction": int(original.faction), "sealed_container": sealed_id}
	team.combat_hot_set(index, &"captive", true)
	team.combat_hot_set(index, &"ko", ko)
	team.combat_hot_set(index, &"pose", "unconscious")
	team.combat_hot_set(index, &"age", 0.0)
	team.combat_hot_set(index, &"attack", false)
	person.holder.version = int(person.holder.version) + 1
	controller.captivity_supply.commit_change(target_id, captor_id, true)
	controller._captivity_changed(target_id, captor_id, true)
	# Complete the original owner's presence projection after the authored
	# captivity transition, just as its next command update would do.
	team._refresh_command_presence()
	sealed_before = lab.terrain.site.ground_loot[sealed_id].duplicate(true)
	return _check(_feeding(target_id) == "team:%d" % captor_team, "initial captured person is fed by captor Army, independent of guard", {"feeding": _feeding(target_id), "captor_team": captor_team, "guard_team": guard_team})

func _setup(case_name: String) -> bool:
	current_case = case_name
	original_ids.clear()
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	controller._auto_save_blocked = true
	var sides: Array[Dictionary] = [{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 3, "attack": false, "ai_enabled": false, "entry": "east"},
		{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "north"}]
	var deployed: Dictionary = lab.deploy_trial_armies(sides)
	if not _check(deployed.ok and lab.crowd_site == null, "formal original ordinary rosters deployed before native import", deployed): return false
	var homes: Array[TerrainArmy] = []
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		homes.append(team)
		for index in range(team.combat_units.size()): original_ids.append(team.combat_identity(index))
		var feeding: Dictionary = controller.captivity_supply.enable_team(team)
		if not _check(feeding.ok, "original Army supply cohorts enabled", feeding): return false
		lab.terrain.site.team_supply[str(team.team_id)].inventory.grain = 1000
	if not _check(homes.size() == 3, "three distinct original Army owners exist"): return false
	var captor: TerrainArmy = homes[0]
	var home: TerrainArmy = homes[1]
	var guard: TerrainArmy = homes[2]
	target_id = home.combat_identity(1)
	captor_id = captor.combat_identity(0)
	guard_id = guard.combat_identity(0) if case_name == "guard_team" else lab.npc.person_id
	home_team = home.team_id
	captor_team = captor.team_id
	guard_team = guard.team_id if case_name == "guard_team" else -1
	original_row = home.combat_units[1]
	original_holder = original_row.item_state
	original_cargo = original_row.cargo
	if not _fixture_captive(home, 1, 4.0 if case_name == "outside_escape" else 1200.0): return false
	var captured: Dictionary = controller._capture_for_save()
	var valid: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site)
	if not _check(captured.ok and valid.ok, "original ordinary Site with fixture passes full Store validation", valid): return false
	lab.crowd_site = Crowd.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "south"}])
	if not _check(imported.ok, "production deployment imports original captive and all ordinary rosters", imported): return false
	site = lab.crowd_site
	site.events_received.connect(_on_events)
	initial_items = lab.terrain.site.item_records.size()
	var hot: Dictionary = _hot()
	var expected_guard: int = guard_id if case_name == "guard_team" else -1
	if not _check(bool(hot.captive) and float(hot.ko) > 0.0 and int(hot.captor_person) == expected_guard and int(lab.terrain.site.captivity[str(target_id)].guard_id) == guard_id and int(lab.terrain.site.captivity[str(target_id)].captor_id) == captor_id,
		"native guard follows original guard while Site captor and guard remain separate", {"native_guard": hot.captor_person, "captor": captor_id, "guard": guard_id}): return false
	if case_name == "guard_team":
		if not _check(site.person_owner(captor_id).team_id != site.person_owner(guard_id).team_id and _feeding(target_id) == "team:%d" % captor_team,
			"different captor and guard Army teams retain captor feeding ownership"): return false
	else:
		if not _check(not site.contains_person(guard_id) and not controller.person_actions._person(guard_id).is_empty(), "outside guard remains the original NPC and is absent from native membership"): return false
	return _unique("after original import")

func _ko_clear() -> bool:
	var relation: Dictionary = lab.terrain.site.captivity[str(target_id)].duplicate(true)
	for tick in range(3):
		lab._advance_action_time(DT)
		var hot: Dictionary = _hot()
		if not _check(bool(hot.captive) and float(hot.ko) > 0.0 and float(hot.escape_t) == 0.0 and _escape_count() == 0 and _feeding(target_id) == "team:%d" % captor_team,
			"native KO prevents escape and never changes captor supply", hot): return false
	var cleared: Dictionary = site.clear()
	if not _check(cleared.ok and not site.active and lab.terrain.site.captivity[str(target_id)] == relation,
		"production KO clear preserves exact original captor/guard/sealed relation", cleared): return false
	var person: Dictionary = _original_person()
	if not _check(person.owner is TerrainArmy and bool(person.owner.combat_hot_get(int(person.unit), &"captive")) and float(person.owner.combat_hot_get(int(person.unit), &"ko")) > 0.0 and _feeding(target_id) == "team:%d" % captor_team,
		"KO captive returns to the original Army and remains fed by captor"): return false
	var captured: Dictionary = controller._capture_for_save()
	var custody: Dictionary = Store._validate_captivity(lab.terrain, lab.terrain.site)
	var valid: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site)
	if not _check(captured.ok and custody.ok and valid.ok, "ordinary Store and captivity validation accept the preserved original guard", {"captivity": custody, "state": valid}): return false
	return _unique("after KO clear")

func _natural_escape() -> bool:
	var saw_ko: bool = false
	var saw_getup: bool = false
	var boundary: Dictionary = {}
	for tick in range(900):
		var before: Dictionary = _hot()
		lab._advance_action_time(DT)
		var after: Dictionary = _hot()
		var game_delta: float = float(site.crowd.stats()[34])
		saw_ko = saw_ko or float(before.ko) > 0.0
		saw_getup = saw_getup or float(after.getup) > 0.0
		if float(after.ko) > 0.0 or float(after.getup) > 0.0:
			if not bool(after.captive) or float(after.escape_t) != 0.0: return _check(false, "KO and get-up cannot count unguarded escape seconds", after)
		if tick % 10 == 0: samples.append({"case": current_case, "tick": tick, "ko": after.ko, "getup": after.getup, "escape_t": after.escape_t, "game_delta": game_delta, "feeding": _feeding(target_id)})
		if _escape_count() > 0:
			boundary = {"before": before.escape_t, "game_delta": game_delta, "after": after.escape_t}
			break
		if tick % 30 == 0: await process_frame
	if not _check(saw_ko and saw_getup and _escape_count() == 1 and not bool(_hot().captive) and not boundary.is_empty() and float(boundary.before) < 30.0 and float(boundary.before) + float(boundary.game_delta) >= 30.0 - 0.000001,
		"real ESCAPED occurs after KO, get-up and the first qualifying 30-game-second boundary", boundary): return false
	for tick in range(3):
		if site.pending_captivity.is_empty(): break
		lab._advance_action_time(DT)
	if not _check(site.pending_captivity.is_empty() and not lab.terrain.site.captivity.has(str(target_id)) and _feeding(target_id) == "team:%d" % home_team,
		"real escape commits original custody removal and returns original feeding home within three steps", {"feeding": _feeding(target_id), "error": site.last_event_error}): return false
	var captured: Dictionary = controller._capture_for_save()
	var custody: Dictionary = Store._validate_captivity(lab.terrain, lab.terrain.site)
	var supplies: Dictionary = Store._validate_supply(lab.terrain.site)
	if not _check(captured.ok and custody.ok and supplies.ok and site.crowd.validate(), "original Site custody/supply and native validators accept natural escape", {"captivity": custody, "supply": supplies}): return false
	return _unique("after real escape")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not _check(args.has("--crowd-test") and args.has("--grid"), "named isolated grid startup is required"): return
	out_dir = "res://output/crowd_c2_c3_20261001/d11_guard_%s_%d" % [Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_"), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore: FileAccess = FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(180.0).timeout.connect(func() -> void:
		failed = true
		_write()
		printerr("GATE FAIL: D11 deadline")
		quit(3))
	var cases: Array[String] = ["guard_team", "outside_ko", "outside_escape"]
	var selected: int = args.find("--d11-case")
	if selected >= 0 and selected + 1 < args.size(): cases.assign([str(args[selected + 1])])
	for case_name: String in cases:
		if not _check(case_name in ["guard_team", "outside_ko", "outside_escape"], "known D11 case", case_name): return
		if not _setup(case_name): return
		if case_name == "outside_escape":
			if not await _natural_escape(): return
		elif not _ko_clear(): return
		lab.queue_free()
		await process_frame
		lab = null
		controller = null
		site = null
	_write()
	print("GATE OK: D11 original guard checks=", checks.size())
	quit(0)