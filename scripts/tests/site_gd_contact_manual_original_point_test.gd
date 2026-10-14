extends "res://scripts/tests/fixtures/site_terminal_first_error_test.gd"
## canonicalVisual. Authored starting station/input only; no route/World-birth claim.
## All attack, geometry packets, work/pools, clock and interruption use real owners.
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
var _original_lab: TerrainLab
var _original_enemy: TerrainArmy
var _original_sink: Callable
var _packets: Array[Dictionary] = []
var _positive_prefix := false
var _done := false
var _failures: Array[String] = []

func _initialize() -> void:
	_install_terminal_guard()
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not _guard(): return false
	if not _done and Time.get_ticks_msec() > deadline: _finish("Actual manual/contact point deadline")
	return false

func _require(ok: bool, message: String, detail: Variant = null) -> bool:
	if not _guard(): return false
	if ok: return true
	_failures.append(message + (" " + str(detail) if detail != null else ""))
	_finish()
	return false

func _contact_probe(phase: String, controller: SiteController, data: TerrainData, packet: Dictionary = {}) -> void:
	var priors: Array = []
	for candidate: Dictionary in controller._gd_contact_runtime_capture.get("priors", []):
		var prefix: Dictionary = candidate.get("prefix_ref", {})
		priors.append({"actual_seconds": prefix.get("actual_seconds"), "progress": candidate.get("progress"), "prior_progress": candidate.get("prior_progress")})
	print("DIAG_ONLY C36_MANUAL_CONTACT ", {"phase": phase, "fraction": packet.get("fraction"),
		"manual_target": data.site.manual.target, "manual_progress": data.site.manual.progress,
		"manual_status": data.site.manual.get("status", ""), "priors": priors, "positive_prefix": _positive_prefix})

func _station(data: TerrainData) -> Dictionary:
	# Keep the original generated resource, terrain edge and work cells. This
	# fixture's inherited clear building plot is not used as a fake resource.
	var keys: Array = data.resource_base.keys()
	keys.sort()
	for raw: Variant in keys:
		var key := str(raw)
		var resource: Dictionary = Env.resource(data, key)
		if resource.is_empty() or bool(resource.cleared) or int(resource.remaining) <= 0: continue
		var action := "harvest" if bool(resource.discovered) else "survey"
		for cell: Vector2i in Env.work_cells(data, key):
			if cell == Vector2i(10, 9) or not data.is_walkable(cell): continue
			var admitted: Dictionary = Runtime.harvest(data, key, cell, data.site.manual.cargo, action, true)
			if not admitted.ok: continue
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var attacker := cell + direction
				if attacker == Vector2i(10, 9) or not data.is_walkable(attacker) \
					or not data.can_attack_across(attacker, cell) or not SiteCombatRules.terrain_line_clear(data, attacker, cell): continue
				return {"key": key, "cell": cell, "attacker": attacker, "action": action}
	return {}

func _manual_lab(data: TerrainData) -> TerrainLab:
	var lab: TerrainLab = TerrainLab.new()
	lab.exchange_enabled = false # This isolated test requires original GD mesh contacts before owner setup.
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	assert(lab.character.place(Vector2i(10, 10), true))
	assert(lab.npc.place(Vector2i(10, 9), true))
	lab.site_controller.release_worker()
	return lab


func _run() -> void:
	var data: TerrainData = _building_fixture()
	if not _guard(): return
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 0
	data.site.inventory.tools = 8 # Explicit finite original depot input, no payment mock.
	data.site.capacity = 64
	var station: Dictionary = _station(data)
	if not _guard(): return
	if not _require(not station.is_empty(), "Generated source supplies legal original work/contact stations"): return
	if station.is_empty(): _finish(); return
	_original_lab = _manual_lab(data)
	if not _guard(): return
	var lab: TerrainLab = _original_lab
	var controller: SiteController = lab.site_controller
	if not _require(lab.controlled_person_id() == 1 and lab.crowd_site == null and not lab.exchange_enabled,
		"Real controlled original Actor and exclusive GD mesh branch"): return
	if not _require(lab.character.place(station.cell, true), "Explicit legal starting Actor station, no movement proof"): return
	_original_enemy = lab.third_army # The real Lab already registered source/sink/life hooks.
	var enemy: TerrainArmy = _original_enemy
	enemy.roster_size = 1
	if not _require(enemy.deploy_at(data, lab.character, lab.npc, [Vector2i(station.attacker)]), "Original formation deploy at actual free terrain"): return
	if not _require(enemy.enable_combat(false), "Original equipment/appearance/contact bake enable; visual mode required"): return
	if not _require(enemy.combat_units.size() == 1 and enemy.ranged_profile(0).is_empty() and enemy.faction_id != lab.character.faction_id,
		"Actual enemy melee equipment and distinct faction"): return
	if not _failures.is_empty(): _finish(); return
	_original_sink = enemy.contact_sink
	if not _require(_original_sink.is_valid(), "Original registered ContactSource sink"): return
	if not _original_sink.is_valid(): _finish(); return
	enemy.contact_sink = func(packet: Dictionary) -> void:
		if not _guard(): return
		if is_same(packet.get("target"), lab.character): _packets.append(packet)
		print("DIAG_ONLY C36_FIRST_CONTACT_GEOMETRY ", {"packet": packet, "attack_clip": enemy.attack_clip(0),
			"age": enemy.combat_hot_get(0, &"age"), "events": TerrainArmy.CombatTimings.events(enemy.attack_clip(0)),
			"sample": TerrainArmy.CombatTimings.sample_time(enemy.attack_clip(0), float(enemy.combat_hot_get(0, &"age")), float(enemy.combat_units[0].attack_reduction), float(enemy.combat_units[0].attack_fatigue)),
			"previous_shapes": enemy.combat_units[0].previous.size(), "mesh_point": {"seconds": lab._gd_mesh_work_point.get("seconds"), "elapsed": lab._gd_mesh_work_point.get("elapsed"), "published_priors": lab._gd_mesh_work_point.get("published_priors", []).size()}})
		_contact_probe("before_original_sink", controller, data, packet)
		_original_sink.call(packet) # Observation only; SAME complete original packet.
		if not _guard(): return
		_contact_probe("after_original_sink", controller, data, packet)
	lab.character.combat_event.connect(func(_grace: float) -> void:
		if not _guard(): return
		for candidate: Dictionary in controller._gd_contact_runtime_capture.get("priors", []):
			if is_same(candidate.task, data.site.manual) and float(candidate.prefix_ref.actual_seconds) > 0.0 \
				and float(candidate.progress) > float(candidate.prior_progress): _positive_prefix = true
	)
	if not _guard(): return
	# Original attack BEGIN emits mark_combat and clears any previous manual
	# task first. Public manual_work then captures the true new source intent.
	if not _require(enemy.start_unit_attack(0, lab.character.terrain_cell, 1), "True original attack BEGIN before new manual work"): return
	controller.source_key = str(station.key)
	controller.manual_work(str(station.action))
	if not _guard(): return
	if not _require(str(data.site.manual.target) == str(station.key), "Original public manual_work admits actual controlled Actor"): return
	if not _failures.is_empty(): _finish(); return
	var observed := {}
	for point: int in 1200:
		if not _packets.is_empty(): break
		var before_fatigue: float = Fatigue.read(lab.character)
		var before_now: float = Runtime.now(data)
		var before_hits: int = int(controller.person_actions._person(1).hit)
		var before_count: int = _packets.size()
		var stepped: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		if not _guard(): return
		if not _require(stepped.ok and stepped.get("completed", false), "Actual shared main caller completes once", stepped): return
		if not stepped.ok or not stepped.get("completed", false): break
		if not _require(absf((Runtime.now(data) - before_now) * 60.0 - float(stepped.game_seconds)) < 0.0000001,
			"One original accepted minute clock, no replay or second Runtime.advance", stepped): return
		if _packets.size() > before_count:
			var packet: Dictionary = _packets.back()
			observed = {"fraction": float(packet.fraction), "game_seconds": float(stepped.game_seconds),
				"fatigue_begin": before_fatigue, "fatigue_end": Fatigue.read(lab.character), "before_hits": before_hits}
	if not _require(not observed.is_empty() and _positive_prefix, "Real contact observes positive admitted manual work; zero-work THREAT is not this proof", observed): return
	if not observed.is_empty():
		var fraction: float = float(observed.fraction)
		if not _require(fraction > 0.0 and fraction < 1.0, "Real first impact is strictly inside this original point", observed): return
		var expected: float = float(observed.game_seconds) * fraction * Fatigue.effort_rate(lab.character)
		if not _require(absf(float(observed.fatigue_end) - float(observed.fatigue_begin) - expected) < 0.0000001,
			"Actual single Actor pool charges only the real pre-impact work prefix once", observed): return
		if not _require(int(controller.person_actions._person(1).hit) > int(observed.before_hits), "Original apply_contact changes real hit revision"): return
	if not _require(str(data.site.manual.target).is_empty() and float(data.site.manual.progress) == 0.0,
		"True contact mark_combat retains original manual cancellation; old captured progress is not republished"): return
	if not _require(data.site.manual.cargo.is_empty() and int(data.site.inventory.tools) == 8,
		"Interrupted pre-completion manual work produces no resource and consumes no harvest payment"): return
	_finish()

func _finish(reason: String = "") -> void:
	if _done: return
	_done = true
	if not reason.is_empty(): _failures.append(reason)
	if is_instance_valid(_original_enemy) and _original_sink.is_valid(): _original_enemy.contact_sink = _original_sink
	if is_instance_valid(_original_lab): _original_lab.free()
	_original_lab = null
	_original_enemy = null
	_original_sink = Callable()
	_packets.clear() # Release SAME packet owner refs after actual scene teardown.
	TerrainArmy.release_contact_source()
	if not _guard(): return
	if _failures.is_empty(): print("GD_CONTACT_MANUAL_ORIGINAL_POINT PASS source_fixture_runtime_only_not_fixed_world")
	else:
		for failure: String in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)
