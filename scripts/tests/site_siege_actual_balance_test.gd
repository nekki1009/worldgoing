extends "res://scripts/tests/site_siege_native_integration_test.gd"
## Candidate shares only the small formal fixture and original clock helpers.
## Each run selects one material and one attacker. Ordinary destruction is
## actually completed. RAM and both stone engines continue until the original
## targeted part really reaches HP0. Ballista remains a two-shot measurement.

var balance_material := "wood"
var balance_native := false

func _new_formal_lab() -> bool:
	if not super._new_formal_lab(): return false
	if case_name in ["ballista", "traction", "counterweight"]:
		var kind := "traction_trebuchet" if case_name == "traction" else ("counterweight_trebuchet" if case_name == "counterweight" else "ballista")
		var original_pose := {"kind": kind, "cell": lab.terrain.index(Vector2i(20, 41)), "facing": [1, 0]}
		var station := SiteRuntime.siege_crew_cell(lab.terrain, original_pose, "0")
		# Initial real depot beside the original crew station. Subsequent refills
		# require this person's actual arrival and the original transfer guards.
		lab.terrain.site.depot_cell = lab.terrain.index(station + Vector2i.UP)
		lab.terrain.site.inventory[str(SiteRuntime.SIEGE_DEFINITIONS[kind].ammo)] = 1000
	return true

func _initialize() -> void:
	suite = "balance"
	case_name = "ordinary"
	output_root = "res://output/site_siege_close_20261004/actual_balance"
	super._initialize()
	var args := OS.get_cmdline_user_args()
	var at := args.find("--siege-material")
	if at >= 0 and at + 1 < args.size(): balance_material = args[at + 1]
	balance_native = args.has("--siege-balance-native")
	suite = "balance_" + balance_material + ("_native" if balance_native else "_gd")

func _run() -> void:
	create_timer(600.0).timeout.connect(func() -> void:
		failed = true; _write_result(); printerr("SIEGE BALANCE FAIL: deadline"); quit(3))
	if not _check(balance_material in ["wood", "stone"], "one actual material case", balance_material): return
	if not _check(case_name in ["ordinary", "ram_min", "ram_full", "ballista", "traction", "counterweight"], "one actual attacker case", case_name): return
	if not _preflight(): return
	var measured: Dictionary = await _ordinary_balance() if case_name == "ordinary" else await _engine_balance()
	if failed: return
	if not _check(not measured.is_empty(), "actual balance measured", measured): return
	_write_result()
	await _close_lab()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_ACTUAL_BALANCE_PASS: ", case_name, " / ", balance_material, " / ", "native" if balance_native else "GD", "; actual original HP/timers/contacts; RAM and stone engines destroy the original targeted part")
	quit(0)

func _ordinary_balance() -> Dictionary:
	var context := _make_context("ordinary", 0, balance_native, balance_material)
	if failed: return {}
	var person: Dictionary = lab.site_controller.person_actions._person(int(context.commander))
	var weapon_id := str(person.holder.equipped.weapon)
	var weapon := str(lab.terrain.site.item_definitions[str(lab.terrain.site.item_records[weapon_id].definition)].asset)
	var initial_hp := _part_hp(context.target)
	var expected_damage := SiteCombatRules.structure_damage(weapon, balance_material)
	var expected_rounds := ceili(initial_hp / expected_damage)
	var rounds := 0
	var first_contact := -1.0
	var begun := action_seconds
	while _part_hp(context.target) > EPS and rounds < expected_rounds + 1:
		var before := _part_hp(context.target)
		var start := action_seconds
		var attack: Dictionary = lab.site_controller.person_actions.begin_structure_attack(int(context.commander), str(context.target.feature_id), str(context.target.part_id))
		if not _check(attack.ok, "actual ordinary attack uses original held melee weapon", {"round": rounds + 1, "weapon_id": weapon_id, "result": attack}): return {}
		if not await _until(func() -> bool: return not lab.site_controller.person_actions.is_busy(int(context.commander)), 2.0, "actual original ordinary strike settles on its own action clock"): return {}
		var damage := before - _part_hp(context.target)
		if not _check(absf(action_seconds - start - 1.0) <= DT + EPS and absf(damage - minf(expected_damage, before)) <= EPS,
			"actual ordinary one-second round applies actual material HP once", {"round": rounds + 1, "elapsed": action_seconds - start, "damage": damage, "hp": _part_hp(context.target)}): return {}
		if first_contact < 0.0: first_contact = action_seconds - begun
		rounds += 1
		if rounds % 20 == 0: await process_frame
	var measured := {"attacker": "ordinary", "material": balance_material, "weapon": weapon, "weapon_id": weapon_id,
		"initial_hp": initial_hp, "actual_damage_per_round": expected_damage, "actual_rounds": rounds,
		"first_contact_action_seconds": first_contact, "actual_destroy_action_seconds": action_seconds - begun,
		"actual_final_hp": _part_hp(context.target)}
	if not _check(_part_hp(context.target) <= EPS and rounds == expected_rounds, "actual ordinary destruction completes at measured round count", measured): return {}
	return measured

func _engine_balance() -> Dictionary:
	var kind := "ram" if case_name.begins_with("ram_") else ("traction_trebuchet" if case_name == "traction" else ("counterweight_trebuchet" if case_name == "counterweight" else "ballista"))
	var count := 2 if case_name == "ram_min" else int(SiteRuntime.SIEGE_DEFINITIONS[kind].standard_crew)
	var context := _make_context(kind, count, balance_native, balance_material)
	if failed: return {}
	var vehicle := _vehicle(context)
	if not await _until(func() -> bool: return lab.site_controller.vehicles.crew_ready(vehicle), 40.0, "actual engine crew occupies original stations"): return {}
	if kind == "ram":
		var moved: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [context.goal.x, context.goal.y]}, int(context.commander), true)
		if not _check(moved.ok, "actual RAM route toward its original material part", moved): return {}
		if not await _until(func() -> bool: return vehicle.move.is_empty() and int(vehicle.cell) == lab.terrain.index(context.goal), 40.0, "actual RAM approach/compound reaches real front contact pose"): return {}
		if balance_native and not await _settled_native_crew(context, "actual Native RAM crew settles after original pose acknowledgment"): return {}
	var rule := SiteCombatRules.siege_attack(kind)
	var initial_hp := _part_hp(context.target)
	var nominal_damage := SiteCombatRules.structure_damage("", balance_material, kind)
	var full_destruction := kind != "ballista"
	var limit := 64 if full_destruction else mini(2, ceili(initial_hp / nominal_damage))
	var multiplier: float = lab.site_controller.vehicles.crew_multiplier(vehicle)
	var refills: Array[Dictionary] = []
	if not str(rule.ammo).is_empty():
		var first_refill := _refill_original_magazine(context, rule)
		if failed: return {}
		if not first_refill.is_empty(): refills.append(first_refill)
	var sequence := int(vehicle.next_attack_seq)
	var version := int(vehicle.holder.version)
	var rng := int(vehicle.rng_state)
	var releases: Array[float] = []
	var contacts: Array[Dictionary] = []
	var goals: Array = []
	var initial_parts := _feature_hp(str(context.target.feature_id))
	var destroyed_at: Variant = null
	var stopped := false
	var started := action_seconds
	var ordered: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "attack", context.target, int(context.commander), true)
	if not _check(ordered.ok, "actual original engine attack begins", ordered): return {}
	var cycle := (float(rule.get("preparing", 0.0)) + float(rule.get("collision", 0.0)) + float(rule.get("loading", 0.0)) + float(rule.get("aiming", 0.0)) + float(rule.recovering)) / multiplier
	var maximum := float(limit) * (cycle + 8.0) + 20.0
	for step in range(ceili(maximum / DT)):
		if not stopped and not str(rule.ammo).is_empty() and int(vehicle.cargo.get(str(rule.ammo), 0)) == 0 and vehicle.action.is_empty():
			var refill := _refill_original_magazine(context, rule)
			if failed: return {}
			refill.action_seconds = action_seconds - started
			refills.append(refill)
		var before := _feature_hp(str(context.target.feature_id))
		if not _step(): return {}
		var after := _feature_hp(str(context.target.feature_id))
		var changes := {}
		for part: String in before:
			var damage := float(before[part]) - float(after.get(part, 0.0))
			if damage > EPS: changes[part] = {"damage": damage, "hp": after.get(part, 0.0)}
		if not changes.is_empty(): contacts.append({"action_seconds": action_seconds - started, "parts": changes, "target_hp": _part_hp(context.target)})
		if destroyed_at == null and _part_hp(context.target) <= EPS: destroyed_at = action_seconds - started
		if int(vehicle.next_attack_seq) > sequence + releases.size():
			releases.append(action_seconds - started)
			if not lab.siege_projectiles.is_empty(): goals.append(lab.siege_projectiles.back().goal)
		if not stopped and (destroyed_at != null or releases.size() >= limit):
			var stop: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
			if not _check(stop.ok, "stop keeps the actually committed final impact/flight", stop): return {}
			stopped = true
		if stopped and vehicle.action.is_empty() and lab.siege_projectiles.is_empty(): break
		if step % 120 == 0: await process_frame
	if not _check(not releases.is_empty() and stopped and vehicle.action.is_empty() and lab.siege_projectiles.is_empty(), "bounded real engine releases and actual flights all settle", {"releases": releases, "contacts": contacts}): return {}
	if full_destruction and not _check(destroyed_at != null and _part_hp(context.target) <= EPS, "actual RAM/stone engine targeted part destruction completes", {"maximum_cycles": limit, "actual_cycles": releases.size(), "target_hp": _part_hp(context.target), "contacts": contacts}): return {}
	if not full_destruction and not _check(releases.size() == limit, "ballista measures exactly the declared two actual shots", releases): return {}
	if not full_destruction:
		var expected_final_hp := maxf(0.0, initial_hp - nominal_damage * 2.0)
		if not _check(limit == 2 and contacts.size() == 2 and absf(_part_hp(context.target) - expected_final_hp) <= EPS,
			"two actual ballista hit slices damage the original intended material target", {"contacts": contacts, "target": context.target, "actual_hp": _part_hp(context.target), "expected_hp": expected_final_hp}): return {}
		var remaining_hp := initial_hp
		for contact: Dictionary in contacts:
			var intended: Dictionary = contact.parts.get(str(context.target.part_id), {})
			var expected_damage := minf(nominal_damage, remaining_hp)
			remaining_hp = maxf(0.0, remaining_hp - expected_damage)
			if not _check(not intended.is_empty() and absf(float(intended.get("damage", -1.0)) - expected_damage) <= EPS
				and absf(float(intended.get("hp", -1.0)) - remaining_hp) <= EPS and absf(float(contact.target_hp) - remaining_hp) <= EPS,
				"each actual ballista contact commits tuned min-remaining damage to that original target once", {"target": context.target, "contact": contact, "expected_damage": expected_damage, "expected_hp": remaining_hp}): return {}
	var original_feature: Dictionary = lab.terrain.site.features[str(context.target.feature_id)]
	var geometry := SiteRuntime.feature_geometry(lab.terrain, original_feature)
	for contact: Dictionary in contacts:
		for part: String in contact.parts:
			var actual_material := "wood" if str(geometry.parts[part].role) == "leaf" else str(original_feature.material)
			var part_damage := SiteCombatRules.structure_damage("", actual_material, kind)
			if not _check(float(contact.parts[part].damage) <= part_damage + EPS
				and (absf(float(contact.parts[part].damage) - part_damage) <= EPS or float(contact.parts[part].hp) <= EPS),
				"actual contact damages that real material by the tuned amount once", {"part": part, "actual_material": actual_material, "damage": contact.parts[part]}): return {}
	if kind != "ram":
		var expected_prepare := (float(rule.loading) + float(rule.aiming)) / multiplier
		var later_refills := maxi(0, refills.size() - 1)
		var initial_loaded := int(refills[0].cargo_after) if not refills.is_empty() else 1
		var loaded_total := initial_loaded
		for refill_index in range(1, refills.size()): loaded_total += int(refills[refill_index].transferred)
		if not _check(absf(releases[0] - expected_prepare) <= DT + EPS and int(vehicle.holder.version) == version + releases.size() + later_refills and int(vehicle.cargo.get(str(rule.ammo), 0)) == loaded_total - releases.size(),
			"actual prepare timer / magazine debit / version match released shots", {"times": releases, "version": vehicle.holder.version}): return {}
		if kind != "ballista":
			for _shot in range(releases.size()): rng = int(_stone_rng(rng).rng)
			if not _check(int(vehicle.rng_state) == rng, "all measured stone shots consume actual original RNG", vehicle.rng_state): return {}
	for release_index in range(1, releases.size()):
		if not _check(absf(releases[release_index] - releases[release_index - 1] - cycle) <= DT * 2.0 + EPS, "actual consecutive-release cadence follows real loading/collision/recovery timer", {"cycle": release_index + 1, "actual": releases[release_index] - releases[release_index - 1], "expected": cycle}): return {}
	return {"attacker": kind, "material": balance_material, "crew": count, "crew_multiplier": multiplier,
		"initial_hp": initial_hp, "actual_target_final_hp": _part_hp(context.target), "actual_releases_action_seconds": releases,
		"actual_contacts": contacts, "actual_scattered_goals": goals, "actual_part_damage_per_contact": nominal_damage,
		"actual_cycles": releases.size(), "actual_hit_slices": contacts.size(), "actual_destroy_action_seconds": destroyed_at,
		"actual_settled_action_seconds": action_seconds - started, "original_target": context.target,
		"initial_all_part_hp": initial_parts, "actual_final_all_part_hp": _feature_hp(str(context.target.feature_id)),
		"actual_magazine_refills": refills, "original_magazine_capacity": SiteRuntime.SIEGE_DEFINITIONS[kind].capacity,
		"rounds_to_destroy_estimate": ceili(initial_hp / nominal_damage), "cycle_action_seconds": cycle,
		"estimate_scope": "RAM and stone engines prove actual targeted-part HP0; ballista full destruction remains untested unless actual_destroy_action_seconds is present"}

func _refill_original_magazine(context: Dictionary, rule: Dictionary) -> Dictionary:
	var vehicle := _vehicle(context)
	var ammo := str(rule.ammo)
	var capacity := int(SiteRuntime.SIEGE_DEFINITIONS[str(vehicle.kind)].capacity)
	var before := int(vehicle.cargo.get(ammo, 0))
	var amount := capacity - before
	if amount <= 0: return {}
	var source: Dictionary = lab.terrain.site.depot_items
	var source_before := int(lab.terrain.site.inventory.get(ammo, 0))
	var source_version := int(source.version)
	var destination_version := int(vehicle.holder.version)
	var person_id := int(context.crew[0])
	var person: Dictionary = lab.site_controller.person_actions._person(person_id)
	var depot_cell := lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
	if not _check(not person.is_empty() and person.cell == SiteRuntime.siege_crew_cell(lab.terrain, vehicle, "0")
		and absi(person.cell.x - depot_cell.x) + absi(person.cell.y - depot_cell.y) == 1,
		"original real crew arrived beside its original supply depot", {"person_id": person_id, "person_cell": person.get("cell"), "depot_cell": depot_cell}): return {}
	var result: Dictionary = lab.site_controller.vehicles.transfer("depot", str(context.key), {ammo: amount}, [], source_version, destination_version, person_id, true)
	if not _check(result.ok and int(vehicle.cargo.get(ammo, 0)) == capacity
		and int(lab.terrain.site.inventory.get(ammo, 0)) == source_before - amount
		and int(source.version) == source_version + 1 and int(vehicle.holder.version) == destination_version + 1,
		"original spatially authorized transfer refills real magazine with conserved stock and versions", {"result": result, "transferred": amount, "capacity": capacity}): return {}
	return {"executor_person_id": person_id, "transferred": amount, "cargo_before": before, "cargo_after": capacity,
		"source_before": source_before, "source_after": source_before - amount,
		"source_version_before": source_version, "source_version_after": source.version,
		"destination_version_before": destination_version, "destination_version_after": vehicle.holder.version}

func _feature_hp(key: String) -> Dictionary:
	var result := {}
	for part: String in lab.terrain.site.features[key].parts: result[part] = float(lab.terrain.site.features[key].parts[part].hp)
	return result
