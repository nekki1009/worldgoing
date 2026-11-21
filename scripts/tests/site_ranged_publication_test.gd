extends SceneTree
## Read-only native contract plus the original canonical Army caller.
## Default contract is owner-only; --live-commit adds a formal-scene round trip.
var checks := 0

class KernelProbe extends RefCounted:
	var actual: RefCounted
	var calls := 0
	var mode: Variant = "real"
	var expected_publications: Dictionary
	func publication_ranged_state(publications: Dictionary, classifier: Dictionary) -> Variant:
		calls += 1
		assert(is_same(publications, expected_publications), "Must borrow the current original dictionary")
		for option: Dictionary in SiteCombatRules.WeaponMaterials.OPTIONS:
			var weapon := str(option.id)
			assert(classifier.has(weapon) and typeof(classifier[weapon]) == TYPE_BOOL)
			assert(classifier[weapon] == (not SiteCombatRules.ranged_profile(weapon).is_empty()))
		if mode is String and mode == "real":
			return actual.call("publication_ranged_state", publications, classifier)
		return mode

class WeaponText extends RefCounted:
	var events: Array = []
	func _to_string() -> String:
		events.append("coerce")
		return "unknown_weapon"

func _initialize() -> void:
	_run.call_deferred()

func _classifier() -> Dictionary:
	var result := {}
	for option: Dictionary in SiteCombatRules.WeaponMaterials.OPTIONS:
		var weapon := str(option.id)
		result[weapon] = not SiteCombatRules.ranged_profile(weapon).is_empty()
	result["none"] = not SiteCombatRules.ranged_profile("none").is_empty()
	return result

func _appearance(weapon: Variant) -> Dictionary:
	return {"parts": {"weapon": weapon}}

func _expect(kernel: RefCounted, publications: Dictionary, classifier: Dictionary, expected: int) -> void:
	var before := var_to_bytes([publications, classifier])
	var value: Variant = kernel.call("publication_ranged_state", publications, classifier)
	assert(typeof(value) == TYPE_INT and value == expected)
	assert(before == var_to_bytes([publications, classifier]), "Input bytes must remain unchanged")
	checks += 1

func _fixture(publications: Dictionary, kind: String = "") -> Dictionary:
	var team := TerrainArmy.new()
	var controller := SiteController.new()
	var lab := TerrainLab.new()
	var events: Array = []
	controller._equipment_appearances = publications
	team.exchange_enabled = true
	team.combat_attacking = true
	team.combat_order = TerrainArmy.CombatOrder.ATTACK
	for identity: int in [101, 102]:
		team.combat_units.append({"person_id": identity, "member": true, "hp": 100.0, "ko": 0.0,
			"pose": "idle", "captive": false, "departed": false, "cargo": {}})
	team.equipment_appearance_query = controller.person_appearance
	team.equipment_appearance_batch_query = controller.person_appearance_batch
	team.controlled_person_query = lab.controlled_person_id
	if kind == "canonical_controlled":
		lab.terrain = TerrainData.new()
		lab.terrain.site["controlled_person_id"] = 101
	team.person_busy_query = func(identity: int) -> bool:
		events.append("busy:" + str(identity))
		return false
	team.ranged_tactics_query = func(_army: TerrainArmy) -> Dictionary:
		events.append("tactics")
		return {}
	if kind == "appearance":
		team.equipment_appearance_query = func(identity: int) -> Dictionary:
			events.append("appearance:" + str(identity))
			return controller.person_appearance(identity)
	elif kind == "batch":
		team.equipment_appearance_batch_query = func(query: Callable) -> Dictionary:
			events.append("batch")
			return controller.person_appearance_batch(query)
	elif kind == "controlled":
		team.controlled_person_query = func() -> int:
			events.append("controlled")
			return lab.controlled_person_id()
	elif kind == "bound_appearance":
		# Valid one-argument adapter; its bind/unbind metadata must not be ignored.
		team.equipment_appearance_query = controller.person_appearance.bind(101).unbind(1)
	elif kind == "bound_batch":
		team.equipment_appearance_batch_query = controller.person_appearance_batch.bind(controller.person_appearance).unbind(1)
	elif kind == "bound_controlled":
		team.controlled_person_query = lab.controlled_person_id.unbind(1).bind(0)
	return {"team": team, "controller": controller, "lab": lab, "events": events}

func _dispose(f: Dictionary) -> void:
	var team: TerrainArmy = f.team
	team.equipment_appearance_query = Callable()
	team.equipment_appearance_batch_query = Callable()
	team.controlled_person_query = Callable()
	team.person_busy_query = Callable()
	team.ranged_tactics_query = Callable()
	team.free()
	f.controller.free()
	f.lab.free()

func _review(publications: Dictionary, native_enabled: bool, kernel: RefCounted, kind: String = "", coercion: WeaponText = null) -> Array:
	var f := _fixture(publications, kind)
	var team: TerrainArmy = f.team
	if coercion != null: coercion.events = f.events
	team.native_queries_enabled = native_enabled
	TerrainArmy._idle_kernel = kernel
	TerrainArmy._idle_kernel_checked = true
	team._update_ranged_orders()
	var result := [var_to_bytes(team.combat_units), f.events.duplicate()]
	_dispose(f)
	return result

func _run() -> void:
	create_timer(120.0 if "--live-commit" in OS.get_cmdline_user_args() else 35.0).timeout.connect(func() -> void: quit(1))
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("publication_ranged_state"), "Build matching candidate DLL before this test")
	var classifier := _classifier()
	for count: int in [0, 1, 5000, 5001]:
		var publications := {}
		for i in range(count): publications[i] = _appearance("longsword_01")
		_expect(kernel, publications, classifier, 0)
		if count > 0:
			for weapon: String in ["bow_01", "crossbow_01_steel"]:
				for index: int in [0, count - 1]:
					publications[index] = _appearance(weapon)
					_expect(kernel, publications, classifier, 1)
					publications[index] = _appearance("longsword_01")
	for option: Dictionary in SiteCombatRules.WeaponMaterials.OPTIONS:
		var weapon := str(option.id)
		_expect(kernel, {101: _appearance(weapon)}, classifier, int(not SiteCombatRules.ranged_profile(weapon).is_empty()))
	_expect(kernel, {101: {}, 102: {"parts": {}}}, classifier, 0)
	for invalid: Variant in [null, [], 1, "not_an_appearance"]:
		_expect(kernel, {101: invalid}, classifier, -1)
		_expect(kernel, {101: {"parts": invalid}}, classifier, -1)
	for invalid: Variant in [null, 1, false, [], {}, &"bow_01", "unknown_weapon"]:
		_expect(kernel, {101: _appearance(invalid)}, classifier, -1)
	var typed_publications: Dictionary[int, Dictionary] = {101: _appearance("bow_01")}
	var typed_appearance: Dictionary[String, Dictionary] = {"parts": {"weapon": "bow_01"}}
	var typed_parts: Dictionary[String, String] = {"weapon": "bow_01"}
	var typed_classifier: Dictionary[String, bool] = {"none": false}
	_expect(kernel, typed_publications, classifier, -1)
	_expect(kernel, {101: typed_appearance}, classifier, -1)
	_expect(kernel, {101: {"parts": typed_parts}}, classifier, -1)
	_expect(kernel, {}, typed_classifier, -1)
	_expect(kernel, {}, {"none": 0}, -1)
	_expect(kernel, {}, {}, -1)
	_expect(kernel, {}, {"none": false, &"bow_01": true}, -1)
	# Short-circuit order must match the original values() insertion order.
	_expect(kernel, {101: _appearance("bow_01"), 102: null}, classifier, 1)
	_expect(kernel, {102: null, 101: _appearance("bow_01")}, classifier, -1)
	var frozen := _appearance("longsword_01")
	SiteController._freeze_appearance(frozen)
	_expect(kernel, {101: frozen}, classifier, 0)
	assert(frozen.is_read_only() and frozen.parts.is_read_only())
	var publications := {101: frozen, 102: _appearance("none")}
	var borrowed: Dictionary = publications
	_expect(kernel, borrowed, classifier, 0)
	publications[101] = _appearance("bow_01")
	_expect(kernel, borrowed, classifier, 1)
	var snapshot := publications.duplicate()
	publications.clear()
	_expect(kernel, borrowed, classifier, 0)
	publications.merge(snapshot)
	_expect(kernel, borrowed, classifier, 1)
	publications.erase(101)
	_expect(kernel, borrowed, classifier, 0)
	assert(is_same(publications, borrowed))

	var probe := KernelProbe.new()
	probe.actual = kernel
	for input: Dictionary in [{101: _appearance("longsword_01")}, {101: _appearance("bow_01"), 102: _appearance("crossbow_01")},
		{101: _appearance("unknown_weapon")}, {101: _appearance(&"bow_01")}, {101: {"parts": {}}}]:
		probe.expected_publications = input
		probe.calls = 0
		var reference := _review(input, false, kernel)
		assert(reference == _review(input, true, probe))
		assert(probe.calls == 1, "Exact canonical Army/Controller/Lab must hit the new bridge")
		checks += 1
	var coercion := WeaponText.new()
	var exceptional := {101: _appearance(coercion), 102: _appearance("bow_01")}
	assert(kernel.call("publication_ranged_state", exceptional, classifier) == -1)
	assert(coercion.events.is_empty(), "Native must never invoke weapon coercion")
	probe.expected_publications = exceptional
	var reference := _review(exceptional, false, kernel, "", coercion)
	assert(reference == _review(exceptional, true, probe, "", coercion))
	assert(reference[1] == ["coerce", "coerce", "busy:102"], "Unsupported must execute the full original guard")
	for invalid: Variant in [-1, null, false, true, 2, "0", 0.0]:
		probe.mode = invalid
		assert(reference == _review(exceptional, true, probe, "", coercion))
		checks += 1
	# A loaded old DLL with no method must preserve the same complete fallback.
	assert(reference == _review(exceptional, true, RefCounted.new(), "", coercion))
	assert(reference == _review(exceptional, true, null, "", coercion))
	probe.mode = "real"
	var mixed := {101: _appearance("bow_01"), 102: _appearance("none")}
	probe.expected_publications = mixed
	probe.calls = 0
	var controlled_reference := _review(mixed, false, kernel, "canonical_controlled")
	assert(controlled_reference == _review(mixed, true, probe, "canonical_controlled"))
	assert(probe.calls == 1 and controlled_reference[1].is_empty())
	for kind: String in ["appearance", "batch", "controlled", "bound_appearance", "bound_batch"]:
		probe.calls = 0
		assert(_review(mixed, false, kernel, kind) == _review(mixed, true, probe, kind))
		assert(probe.calls == 0, "Custom/argument-adapted readers must retain the original path: " + kind)
		checks += 1
	# Godot flattens this canceled unbind/bind pair to a zero-argument callable.
	var flattened := _fixture(mixed, "bound_controlled")
	assert(flattened.team.controlled_person_query.get_bound_arguments_count() == 0)
	assert(flattened.team.controlled_person_query.get_unbound_arguments_count() == 0)
	_dispose(flattened)
	probe.calls = 0
	assert(_review(mixed, false, kernel, "bound_controlled") == _review(mixed, true, probe, "bound_controlled"))
	assert(probe.calls == 1, "Flattened callable meets the original pure-reader guard")
	checks += 1
	# One live canonical owner, repeated reviews, including same-size replace and rollback.
	var f := _fixture(mixed)
	var team: TerrainArmy = f.team
	TerrainArmy._idle_kernel = probe
	probe.calls = 0
	team._update_ranged_orders()
	assert(probe.calls == 1 and team.combat_units[0].has("status"))
	team.combat_units[0].erase("status")
	mixed[101] = _appearance("none")
	team._update_ranged_orders()
	assert(probe.calls == 2 and not team.combat_units[0].has("status"))
	mixed.clear()
	mixed.merge({101: _appearance("crossbow_01"), 102: _appearance("none")})
	team._update_ranged_orders()
	assert(probe.calls == 3 and team.combat_units[0].has("status"))
	_dispose(f)
	TerrainArmy._idle_kernel = kernel
	if "--live-commit" in OS.get_cmdline_user_args(): await _live_commit_roundtrip(kernel)
	if "--benchmark" in OS.get_cmdline_user_args(): _benchmark(kernel)
	print("SITE_RANGED_PUBLICATION_PASS: ", checks, " direct/native/canonical/fallback contracts")
	quit(0)

func _live_review(team: TerrainArmy, controller: SiteController, kernel: RefCounted, expected_weapon: String, expected_state: int) -> void:
	var publications: Dictionary = controller.person_appearance_batch(controller.person_appearance)
	var identity := team.combat_identity(0)
	assert(is_same(publications, controller._equipment_appearances))
	assert(str(publications[identity].parts.weapon) == expected_weapon)
	assert(kernel.call("publication_ranged_state", publications, _classifier()) == expected_state)
	team.native_queries_enabled = false
	team._update_ranged_orders()
	var reference := var_to_bytes(team.combat_units)
	var probe := KernelProbe.new()
	probe.actual = kernel
	probe.expected_publications = publications
	TerrainArmy._idle_kernel = probe
	TerrainArmy._idle_kernel_checked = true
	team.native_queries_enabled = true
	team._update_ranged_orders()
	assert(probe.calls == 1, "Real bound readers must reach the native bridge")
	assert(var_to_bytes(team.combat_units) == reference, "Live native/legacy outcomes differ")
	TerrainArmy._idle_kernel = kernel
	checks += 1

func _live_commit_roundtrip(kernel: RefCounted) -> void:
	assert(DisplayServer.get_name() == "headless", "--live-commit uses the formal headless scene")
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var lab: TerrainLab = scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	var cell := TerrainArmy.INVALID_CELL
	for index in range(lab.terrain.size.x * lab.terrain.size.y):
		var depot := lab.terrain.cell_from_index(index)
		if not lab.terrain.is_walkable(depot) or lab.character.occupies_cell(depot) or (is_instance_valid(lab.npc) and lab.npc.occupies_cell(depot)): continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := depot + direction
			if lab.terrain.can_step(depot, next) and not lab.character.occupies_cell(next) and not (is_instance_valid(lab.npc) and lab.npc.occupies_cell(next)):
				lab.terrain.site.depot_cell = index
				cell = next
				break
		if cell != TerrainArmy.INVALID_CELL: break
	assert(cell != TerrainArmy.INVALID_CELL)
	var settings := lab._trial_side_settings({"friendly_count": 1, "friendly_female_percent": 0, "friendly_troop_type": "bow", "friendly_attack": false}, "friendly")
	assert(settings.ok)
	var formation: Array[Vector2i] = [cell]
	var deployed := lab._deploy_trial_teams([settings.side], [formation], 0)
	assert(deployed.ok, "Formal one-row bow deployment: " + str(deployed))
	var team: TerrainArmy = lab.army
	var controller: SiteController = lab.site_controller
	var identity := team.combat_identity(0)
	lab.terrain.site.controlled_person_id = identity
	team.combat_attacking = true
	team.combat_order = TerrainArmy.CombatOrder.ATTACK
	assert(team.exchange_enabled and team.ranged_tactics_query.is_valid() and not team.needs_attack_order)
	_live_review(team, controller, kernel, "bow_01", 1)
	var holder: Dictionary = controller.person_actions._person(identity).holder
	var definition: Dictionary = lab.terrain.site.item_definitions.get("weapon:crossbow_01", {"slot": "weapon", "asset": "crossbow_01", "tint": [1.0, 1.0, 1.0, 1.0]}).duplicate(true)
	var made := SiteRuntime.create_equipment(lab.terrain, holder, "weapon:crossbow_01", definition, identity)
	assert(made.ok, "Only an original owned loose item may be equipped")
	var cargo: Dictionary = controller.person_actions._person(identity).cargo
	assert(int(cargo.get("arrow", 0)) > 0)
	var supplied := SiteRuntime.transfer_items(lab.terrain, holder, cargo, lab.terrain.site.depot_items, lab.terrain.site.inventory, {"arrow": 1}, [], int(holder.version), int(lab.terrain.site.depot_items.version), int(lab.terrain.site.capacity))
	assert(supplied.ok, "Make one legal backpack slot with an original supply transfer: " + str(supplied))
	var before: Dictionary = controller.person_appearance(identity)
	var version := int(holder.version)
	var started := controller.equipment_orders.begin_personal(identity, "weapon", str(made.item_id))
	assert(started.ok and not bool(started.get("preparing", false)), "Published ranged recipe must admit the legal order: " + str(started))
	controller.person_actions.advance(4.999)
	assert(controller.person_actions.settle_after_contacts().is_empty() and int(holder.version) == version)
	controller.person_actions.advance(0.001)
	var settled := controller.person_actions.settle_after_contacts()
	assert(settled.size() == 1 and bool(settled[0].ok), "Original post-contact equipment commit: " + str(settled))
	assert(holder.equipped.weapon == str(made.item_id) and int(holder.version) == version + 1)
	assert(not is_same(before, controller.person_appearance(identity)) and before.is_read_only())
	_live_review(team, controller, kernel, "crossbow_01", 1)
	controller._capture_positions()
	var path := "res://output/site_army_5k_tail_close_20260927/p6_ranged_live/site_%d.json" % Time.get_ticks_usec()
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir()) == OK)
	assert(SiteStore.save(lab.terrain, path).ok)
	var loaded := SiteStore.load_site(path)
	assert(loaded.ok, "Original SiteStore load: " + str(loaded))
	lab.bind_terrain(loaded.data)
	lab.set_process(false)
	controller.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	team = lab.army
	team.combat_attacking = true
	team.combat_order = TerrainArmy.CombatOrder.ATTACK
	assert(team.combat_identity(0) == identity)
	assert(controller.person_actions._person(identity).holder.equipped.weapon == str(made.item_id))
	_live_review(team, controller, kernel, "crossbow_01", 1)
	print("SITE_RANGED_PUBLICATION_LIVE_PASS original commit and SiteStore restore: ", path)
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()

func _benchmark(kernel: RefCounted) -> void:
	# Complete existing caller, including per-review classifier construction.
	# CPU-only A/B/B/A samples, never an FPS or 300-second stability claim.
	TerrainArmy._idle_kernel = kernel
	for count: int in [1, 5000, 5001]:
		for position: String in ["melee", "first", "last"]:
			var publications := {}
			for i in range(count): publications[101 + i] = _appearance("longsword_01")
			if position != "melee": publications[101 if position == "first" else 100 + count] = _appearance("bow_01")
			var f := _fixture(publications)
			var team: TerrainArmy = f.team
			var samples: Array = []
			for enabled: bool in [false, true, true, false]:
				team.native_queries_enabled = enabled
				for warmup in range(4): team._update_ranged_orders()
				var started := Time.get_ticks_usec()
				for repeat in range(40): team._update_ranged_orders()
				samples.append({"native": enabled, "us_per_review": float(Time.get_ticks_usec() - started) / 40.0})
			print("RANGED_PUBLICATION_ABBA ", JSON.stringify({"publications": count, "position": position, "samples": samples}))
			_dispose(f)
