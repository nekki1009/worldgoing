extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(1))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	assert(lab.start_melee_trial({"friendly_count": 6, "enemy_count": 6,
		"friendly_female_percent": 0, "enemy_female_percent": 0,
		"friendly_attack": false, "enemy_attack": false}).ok)
	var team := lab.army
	var other := lab.opposing_army
	other.faction_id = team.faction_id
	var controller := lab.site_controller
	var row: Dictionary = team.combat_units[1]
	var identity := team.combat_identity(1)
	var bow: Dictionary = row.appearance.duplicate(true)
	bow.parts.weapon = "bow_01"
	bow.parts.shield = "none"
	assert(team.single_troop_equipment_guard(1, bow).code == "MIXED_TROOP")
	assert(team.single_troop_equipment_guard(0, bow).ok, "Formal captain is exempt")
	for weapon: String in ["longsword_01_wood", "longsword_01_steel", "spear_01", "hammer_01", "none"]:
		var changed: Dictionary = row.appearance.duplicate(true)
		changed.parts.weapon = weapon
		assert(team.single_troop_equipment_guard(1, changed).ok, "Melee tier/family changes and disarming do not introduce ranged classes")
	team.command_abilities[1] = {"tactics": 80, "leadership": 80, "coach": 80}
	assert(team.single_troop_equipment_guard(1, bow).code == "MIXED_TROOP", "Remembered abilities are not an officer appointment")
	assert(team.record_officer_service([1], true).ok)
	assert(team.single_troop_equipment_guard(1, bow).ok, "Real current officer is exempt")
	assert(team.record_officer_service([1], false).ok)
	var created := SiteRuntime.create_equipment(lab.terrain, row.item_state, "test:bow", {
		"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, identity)
	assert(created.ok)
	var proposed: Dictionary = row.item_state.equipped.duplicate()
	proposed.weapon = created.item_id
	proposed.erase("shield")
	var before := JSON.stringify([row.item_state, lab.terrain.site.item_records])
	assert(controller.equipment_apply_guard(identity, proposed).code == "MIXED_TROOP")
	assert(JSON.stringify([row.item_state, lab.terrain.site.item_records]) == before, "Rejected equipment must not move or spend a real item")
	var legacy_shape := team.capture_combat_state()
	legacy_shape.erase("visual_version")
	legacy_shape.erase("roster_version")
	while legacy_shape.units.size() < TerrainArmy.SOLDIER_COUNT:
		legacy_shape.units.append(legacy_shape.units[0].duplicate(true))
	for malformed: Variant in [null, [], "bad", {"body": []}, {"body": {}}, {"body": INF}]:
		legacy_shape.units[0].appearance = malformed
		assert(not TerrainArmy.valid_combat_state(legacy_shape, lab.terrain), "Malformed legacy appearance must reject without a script error")
	for malformed: Variant in [[], "bad", null]:
		var bad_ledger: Dictionary = lab.terrain.site.duplicate(true)
		bad_ledger.item_records = malformed
		assert(TerrainArmy.single_troop_class(team.combat_units, lab.terrain, team._troop_exempt_ids(), {}, {}, bad_ledger) == &"", "Troop read is safe before the item validator rejects malformed ledgers")
	# Use real item metadata to prove saved templates cannot conceal mixed gear.
	var old_weapon := str(row.item_state.equipped.weapon)
	row.item_state.equipped.weapon = created.item_id
	var snapshot := team.capture_combat_state()
	assert(snapshot.units[1].appearance.parts.weapon == "longsword_01")
	assert(not TerrainArmy.valid_combat_state(snapshot, lab.terrain), "Actual item weapon beats saved appearance template")
	assert(team.record_officer_service([1], true).ok)
	assert(TerrainArmy.valid_combat_state(team.capture_combat_state(), lab.terrain))
	assert(team.record_officer_service([1], false).code == "MIXED_TROOP", "Demotion cannot silently mix ordinary ranks")
	assert(team.officer_order.has(1))
	row.item_state.equipped.weapon = old_weapon
	assert(team.record_officer_service([1], false).ok)
	# Same snapshot checked against supplied load-state, not the old map's ledger.
	var incoming_state: Dictionary = lab.terrain.site.duplicate(true)
	incoming_state.item_records[old_weapon].definition = "test:bow"
	assert(not TerrainArmy.valid_combat_state(team.capture_combat_state(), lab.terrain, {}, incoming_state))
	assert(TerrainArmy.valid_combat_state(team.capture_combat_state(), lab.terrain))
	# Rejoining a former row must be rejected before its feeding hook is called.
	row.member = false
	row.item_state.equipped.weapon = created.item_id
	team.controlled_person_query = func() -> int: return identity
	assert(team.join_row(identity).code == "MIXED_TROOP")
	assert(not row.member)
	row.item_state.equipped.weapon = old_weapon
	assert(team.join_row(identity).ok)
	# The original player is not a special loophole in the ordinary roster.
	var player_weapon: Variant = lab.character.item_state.equipped.get("weapon")
	var player_bow := SiteRuntime.create_equipment(lab.terrain, lab.character.item_state, "test:player-bow", {
		"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, lab.character.person_id)
	assert(player_bow.ok)
	lab.character.item_state.equipped.weapon = player_bow.item_id
	assert(team.join_player(lab.character).code == "MIXED_TROOP")
	assert(team.player_member == null)
	if player_weapon == null: lab.character.item_state.equipped.erase("weapon")
	else: lab.character.item_state.equipped.weapon = player_weapon
	# Bow/crossbow remain supported as separate homogeneous original teams.
	for current: Dictionary in other.combat_units:
		_set_weapon_definition(lab.terrain, current, "bow_01")
	assert(TerrainArmy.single_troop_class(other.combat_units, lab.terrain, other._troop_exempt_ids()) == &"bow")
	assert(TerrainArmy.valid_combat_state(other.capture_combat_state(), lab.terrain))
	var team_before := team.capture_combat_state()
	var other_before := other.capture_combat_state()
	var item_before := JSON.stringify(lab.terrain.site.item_records)
	assert(other.transfer_members_to(team, [other.combat_identity(1)], other.current_commander, team.current_commander).code == "MIXED_TROOP")
	assert(other.merge_into(team, other.current_commander, team.current_commander).code == "MIXED_TROOP")
	assert(team.capture_combat_state() == team_before and other.capture_combat_state() == other_before)
	assert(JSON.stringify(lab.terrain.site.item_records) == item_before)
	_set_weapon_definition(lab.terrain, other.combat_units[1], "crossbow_01")
	assert(not TerrainArmy.valid_combat_state(other.capture_combat_state(), lab.terrain))
	for current: Dictionary in other.combat_units: _set_weapon_definition(lab.terrain, current, "crossbow_01")
	assert(TerrainArmy.valid_combat_state(other.capture_combat_state(), lab.terrain))
	assert(TerrainArmy.single_troop_class(other.combat_units, lab.terrain, other._troop_exempt_ids()) == &"crossbow")
	# A live presenter does not exempt a former captain after merging.
	for current: Dictionary in other.combat_units: _set_weapon_definition(lab.terrain, current, "longsword_01")
	_set_weapon_definition(lab.terrain, other.combat_units[0], "bow_01")
	assert(other.merge_into(team, other.current_commander, team.current_commander).code == "MIXED_TROOP")
	_set_weapon_definition(lab.terrain, other.combat_units[0], "longsword_01")
	var original_row: Dictionary = other.combat_units[1]
	var original_id := other.combat_identity(1)
	assert(other.transfer_members_to(team, [original_id], other.current_commander, team.current_commander).ok)
	assert(is_same(team.combat_units[team.index_for_identity(original_id)], original_row), "Allowed transfer moves the original person, never a clone")
	lab.queue_free()
	await process_frame
	print("SITE SINGLE TROOP CONTRACT PASS: actual item family; no-spend equipment rejection; formal roles; demotion; row/player join; atomic transfer/merge; actual-ledger and alternate-load-state snapshot validation; uniform melee/bow/crossbow")
	quit(0)

func _set_weapon_definition(data: TerrainData, row: Dictionary, weapon: String) -> void:
	var key := "test:troop:" + weapon
	data.site.item_definitions[key] = {"slot": "weapon", "asset": weapon, "tint": [1.0, 1.0, 1.0, 1.0]}
	data.site.item_records[row.item_state.equipped.weapon].definition = key
