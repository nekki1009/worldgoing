extends "res://scripts/tests/site_siege_stone_contract_test.gd"
## Output-only: original paid gate + actual ballista releases, and a legal
## counterweight edge target whose original seeded release scatters out of Site.
## No direct HP hit, fabricated flight, changed flight goal or native/GPU claim.
var edge_groups := 0

func _edge(ok: bool, label: String, details: Variant = null) -> bool:
	if ok: return true
	push_error("SIEGE_GATE_BOUNDARY_FAIL " + label + " " + str(details))
	quit(2)
	return false

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(3))
	for part: String in ["leaf:left", "leaf:right", "frame:left", "frame:right"]:
		if not _gate_part(part): return
	if not _real_scattered_site_exit(): return
	if not _edge(edge_groups == 5, "every original part and actual boundary flight completed"): return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_GATE_BOUNDARY_EDGES_PASS: four independent paid wood-gate parts destroyed by the same original ballista; one real paid counterweight RNG/scatter flight ends at the Site boundary; headless owner/trajectory only")
	quit(0)

func _gate_part(part_id: String) -> bool:
	var context: Dictionary = _ballista_fixture()
	var data: TerrainData = context.data
	# Quarter1 exposes both leaves and the two frame rows to the same west gun.
	var feature_id: String = _build(data, "gate", Vector2i(38, 19), Vector2i.ONE, {"quarter": 1, "material": "wood"})
	var feature: Dictionary = data.site.features[feature_id]
	var geometry: Dictionary = SiteRuntime.feature_geometry(data, feature)
	var target := {"type": "structure", "feature_id": feature_id, "part_id": part_id}
	if not _edge(geometry.parts.has(part_id) and context.lab.siege_fire_preview(context.vehicle, target).ok, "original completed gate part is in the original firing arc", target): return false
	var before: Dictionary = feature.parts.duplicate(true)
	var holder: Dictionary = context.vehicle.holder
	var cargo: Dictionary = context.vehicle.cargo
	var ids: Array[int] = []
	for index in range(context.fixture.army.combat_units.size()): ids.append(context.fixture.army.combat_identity(index))
	# Original depot transaction fills only remaining magazine capacity; no
	# repeated free ammo reset or oversized cargo is used during the attack.
	var fill := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, holder, cargo,
		{"siege_bolt": 16}, [], int(data.site.depot_items.version), int(holder.version), 20)
	if not _edge(fill.ok and int(cargo.siege_bolt) == 20, "original gate fixture has twenty conserved original bolts", fill): return false
	var version := int(holder.version)
	var sequence := int(context.vehicle.next_attack_seq)
	var hp := float(feature.parts[part_id].hp)
	var per_hit := SiteCombatRules.structure_damage("", "wood", "ballista")
	var rounds := ceili(hp / per_hit)
	var order: Dictionary = context.controller.vehicles.order_siege(context.key, "attack", target, int(context.commander), true)
	if not _edge(order.ok, "same original ballista attacks each distinct real gate part", order): return false
	for ordinal in range(rounds):
		var previous := float(feature.parts[part_id].hp)
		_tick(context, 8.0)
		if not _edge(is_equal_approx(float(feature.parts[part_id].hp), maxf(0.0, previous - per_hit))
			and context.lab.siege_shots == ordinal + 1 and int(context.vehicle.next_attack_seq) == sequence + ordinal + 1
			and int(holder.version) == version + ordinal + 1 and int(cargo.siege_bolt) == 20 - ordinal - 1,
			"one actual release/contact changes only the intended round's HP/ammo/sequence", {"part": part_id, "round": ordinal + 1, "parts": feature.parts}): return false
	if not _edge(float(feature.parts[part_id].hp) == 0.0 and context.lab.siege_projectiles.is_empty(), "actual original target part reached HP0 and every released bolt settled", part_id): return false
	if not _edge(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok, "stop after actual part destruction"): return false
	_tick(context, 1.0)
	var cascade := "leaf:" + part_id.get_slice(":", 1) if part_id.begins_with("frame:") else ""
	for other: String in before:
		if other == part_id: continue
		var expected := 0.0 if other == cascade else float(before[other].hp)
		if not _edge(float(feature.parts[other].hp) == expected, "separate opposite part is conserved; only original destroyed-frame leaf cascade is allowed", {"target": part_id, "other": other, "expected": expected, "actual": feature.parts[other].hp}): return false
	geometry = SiteRuntime.feature_geometry(data, feature)
	for value: int in geometry.parts[part_id].cells:
		if not _edge(data.is_walkable(data.cell_from_index(value)), "original destroyed part releases its actual passage cells", value): return false
	for index in range(ids.size()):
		if not _edge(context.fixture.army.combat_identity(index) == ids[index], "gate destruction retains each original crew identity", index): return false
	if not _edge(is_same(context.vehicle.holder, holder) and is_same(context.vehicle.cargo, cargo), "actual gate attack retains original cargo/holder owners"): return false
	_close_ballista(context)
	edge_groups += 1
	return true

func _real_scattered_site_exit() -> bool:
	var context: Dictionary = _stone_fixture("counterweight_trebuchet")
	var vehicle: Dictionary = context.vehicle
	# Genesis RNG35's existing two LCG draws yield (+0.70499,-0.69875).
	# The legal last-column target scatters beyond x72 on original release.
	vehicle.rng_state = 35
	var rng_before := int(vehicle.rng_state)
	var version := int(vehicle.holder.version)
	var target := {"type": "ground", "cell": [71, 20]}
	if not _edge(context.data.contains(Vector2i(71, 20)) and context.lab.siege_fire_preview(vehicle, target).ok, "original edge target remains legal before scatter"): return false
	var order: Dictionary = context.controller.vehicles.order_siege(context.key, "attack", target, int(context.commander), true)
	if not _edge(order.ok, "actual original counterweight edge shot starts", order): return false
	_stone_tick(context, 19.0)
	if not _edge(context.lab.siege_projectiles.size() == 1 and context.lab.siege_shots == 1 and int(vehicle.cargo.siege_stone) == 3
		and int(vehicle.holder.version) == version + 1 and int(vehicle.next_attack_seq) == 2 and int(vehicle.rng_state) != rng_before,
		"real RNG release debits exactly one original stone"): return false
	var flight: Dictionary = context.lab.siege_projectiles[0]
	if not _edge(float(flight.goal.x) > float(context.data.size.x) and float(flight.origin.x) < float(context.data.size.x), "original release rather than test mutation produces an out-of-Site flight", flight.goal): return false
	var expected_fraction := (float(context.data.size.x) - float(flight.origin.x)) / (float(flight.goal.x) - float(flight.origin.x))
	if not _edge(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok, "stop preserves the released boundary stone"): return false
	# A single deliberately low-frame flight slice must catch the first Site
	# boundary; it may not finish at the out-of-Site target or lose the event.
	_stone_tick(context, float(flight.total) + 0.02, float(flight.total) + 0.02)
	if not _edge(bool(flight.ended) and context.lab.siege_projectiles.is_empty()
		and absf(float(flight.get("stop_fraction", -1.0)) - expected_fraction) < 0.000001
		and flight.people.is_empty() and flight.parts.is_empty() and context.lab.siege_contacts == 0,
		"actual low-frame first boundary ends flight at exact original x72, without fabricated hit", flight): return false
	_stone_tick(context, 1.0)
	if not _edge(context.lab.siege_save_guard().ok and context.lab.siege_shots == 1 and int(vehicle.cargo.siege_stone) == 3, "boundary flight and committed recovery settle without another ammo debit"): return false
	_close_stone(context)
	edge_groups += 1
	return true
