extends SceneTree

class SummaryOverrideArmy:
	extends TerrainArmy
	var summary_reads := 0
	func combat_hot_get(index: int, field: StringName, default: Variant = null) -> Variant:
		summary_reads += 1
		return super.combat_hot_get(index, field, default)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(1))
	_classification_read_contract()
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
	assert(team.set_military_role(identity, "officer").ok)
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
	_summary_read_contract(lab, team, str(player_bow.item_id))
	lab.queue_free()
	await process_frame
	print("SITE SINGLE TROOP CONTRACT PASS: actual item family; no-spend equipment rejection; formal roles; demotion; row/player join; atomic transfer/merge; actual-ledger and alternate-load-state snapshot validation; uniform melee/bow/crossbow; hot/fallback summary parity without row materialization or mutation")
	quit(0)

func _set_weapon_definition(data: TerrainData, row: Dictionary, weapon: String) -> void:
	var key := "test:troop:" + weapon
	data.site.item_definitions[key] = {"slot": "weapon", "asset": weapon, "tint": [1.0, 1.0, 1.0, 1.0]}
	data.site.item_records[row.item_state.equipped.weapon].definition = key

func _legacy_appearance_class(appearance: Dictionary) -> StringName:
	var parts: Variant = appearance.get("parts", {})
	if not parts is Dictionary: return &""
	var weapon := StringName(str(parts.get("weapon", "none")))
	var family := HumanCharacter3DEditor.WeaponMaterials.family(weapon)
	if family == &"none": return &""
	if family == &"bow_01": return &"bow"
	if family == &"crossbow_01": return &"crossbow"
	return TerrainArmy.TROOP_TYPE_ID

func _legacy_row_class(row: Dictionary, state: Dictionary) -> StringName:
	if row.get("item_state") is Dictionary and row.item_state.has("equipped"):
		var held: Dictionary = row.item_state
		var equipped: Variant = held.get("equipped", {})
		var records: Variant = state.get("item_records", {})
		var definitions: Variant = state.get("item_definitions", {})
		if equipped is Dictionary and records is Dictionary and definitions is Dictionary:
			var record: Variant = records.get(str(equipped.get("weapon", "")), {})
			if record is Dictionary:
				var definition: Variant = definitions.get(str(record.get("definition", "")), {})
				if definition is Dictionary:
					return _legacy_appearance_class({"parts": {"weapon": str(definition.get("asset", "none"))}})
		return &""
	var appearance: Variant = row.get("appearance", {"parts": {"weapon": "longsword_01"}})
	return _legacy_appearance_class(appearance) if appearance is Dictionary else &""

func _classification_read_contract() -> void:
	assert(TerrainArmy._EMPTY_TROOP_DATA.is_read_only() and TerrainArmy._EMPTY_TROOP_DATA.is_empty())
	var classifier := TerrainArmy._combat_summary_classifier()
	assert(classifier.is_read_only() and classifier.size() == HumanCharacter3DEditor.WeaponMaterials.OPTIONS.size())
	for option: Dictionary in HumanCharacter3DEditor.WeaponMaterials.OPTIONS:
		assert(classifier[str(option.id)] == _legacy_appearance_class({"parts": {"weapon": option.id}}))
	var assets: Array = [&"bow_01", null, 0, true, [], {}, "unknown_wood", "none_steel"]
	for option: Dictionary in HumanCharacter3DEditor.WeaponMaterials.OPTIONS: assets.append(option.id)
	var row := {"item_state": {"equipped": {"weapon": "item"}}, "appearance": {"parts": {"weapon": "longsword_01"}}}
	var state := {"item_records": {"item": {"definition": "def"}}, "item_definitions": {"def": {}}}
	for asset: Variant in assets:
		var appearance := {"parts": {"weapon": asset}}
		assert(TerrainArmy.troop_class(appearance) == _legacy_appearance_class(appearance))
		state.item_definitions.def.asset = asset
		assert(TerrainArmy._troop_row_class(row, state) == _legacy_row_class(row, state))
	state.item_definitions.def.erase("asset")
	assert(TerrainArmy._troop_row_class(row, state) == _legacy_row_class(row, state))
	for appearance: Dictionary in [{}, {"parts": {}}, {"parts": null}, {"parts": []}, {"parts": "bad"}]:
		assert(TerrainArmy.troop_class(appearance) == _legacy_appearance_class(appearance))
		assert(TerrainArmy._troop_row_class({"appearance": appearance}, {}) == _legacy_row_class({"appearance": appearance}, {}))
	for absent: Dictionary in [{}, {"item_state": {}}, {"item_state": {"equipped": {}}}]:
		assert(TerrainArmy._troop_row_class(absent, state) == _legacy_row_class(absent, state))
	for malformed: Variant in [null, [], "bad"]:
		for holder: Dictionary in [{"item_state": malformed}, {"item_state": {"equipped": malformed}}]:
			assert(TerrainArmy._troop_row_class(holder, state) == _legacy_row_class(holder, state))
		for ledger: Dictionary in [
			{"item_records": malformed, "item_definitions": state.item_definitions},
			{"item_records": state.item_records, "item_definitions": malformed},
			{"item_records": {"item": malformed}, "item_definitions": state.item_definitions},
			{"item_records": state.item_records, "item_definitions": {"def": malformed}}]:
			assert(TerrainArmy._troop_row_class(row, ledger) == _legacy_row_class(row, ledger))
	# Empty defaults still flow into the original empty-string definition lookup.
	for ledger: Dictionary in [
		{"item_records": {}, "item_definitions": {"": {"asset": "bow_01"}}},
		{"item_definitions": {"": {"asset": "bow_01"}}},
		{"item_records": {"item": {}}, "item_definitions": {"": {"asset": "bow_01"}}}]:
		assert(_legacy_row_class(row, ledger) == &"bow")
		assert(TerrainArmy._troop_row_class(row, ledger) == _legacy_row_class(row, ledger))
	var empty_hand := {"item_state": {"equipped": {}}}
	var empty_key := {"item_records": {"": {"definition": ""}}, "item_definitions": {"": {"asset": "crossbow_01"}}}
	assert(_legacy_row_class(empty_hand, empty_key) == &"crossbow")
	assert(TerrainArmy._troop_row_class(empty_hand, empty_key) == _legacy_row_class(empty_hand, empty_key))
	assert(TerrainArmy._EMPTY_TROOP_DATA.is_read_only() and TerrainArmy._EMPTY_TROOP_DATA.is_empty())

func _legacy_summary(team: TerrainArmy) -> String:
	# Independent pre-fix presentation oracle: keep its full materialization here only.
	var alive := 0
	var knocked := 0
	var dead := 0
	var total_fatigue := 0.0
	var living := 0
	var tired := 0
	for index in range(team.combat_units.size()):
		var unit: Dictionary = team.combat_units[index]
		var hp := float(team.combat_hot_get(index, &"hp"))
		if hp > 0.0 and not bool(team.combat_hot_get(index, &"departed")):
			living += 1
			total_fatigue += PersonFatigue.read(unit)
			tired += int(PersonFatigue.read(unit) > PersonFatigue.THRESHOLD)
		if hp <= 0.0: dead += 1
		elif float(team.combat_hot_get(index, &"ko")) > 0.0: knocked += 1
		else: alive += 1
	if is_instance_valid(team.player_member) and team.player_member.hp > 0.0:
		living += 1
		total_fatigue += team.player_member.fatigue
		tired += int(team.player_member.fatigue > PersonFatigue.THRESHOLD)
	var fatigue_label := "平均疲勞" if team.team_fatigue.is_empty() else "隊伍共享疲勞"
	var displayed_fatigue := total_fatigue / maxi(1, living) if team.team_fatigue.is_empty() else float(team.team_fatigue.fatigue)
	var captain: Dictionary = team.command_abilities.get(team.formal_commander, {})
	var kind := &""
	var members := team.materialized_combat_rows()
	var actor := team._troop_actor(team.player_member)
	if not actor.is_empty(): members.append(actor)
	var exempt_ids := team._troop_exempt_ids()
	for row: Dictionary in members:
		if not bool(row.get("member", true)) or float(row.get("hp", 100.0)) <= 0.0 or bool(row.get("departed", false)) or exempt_ids.has(int(row.get("person_id", -1))): continue
		var current := _legacy_row_class(row, team.data.site)
		if current == &"": continue
		if kind != &"" and kind != current:
			kind = &"mixed"
			break
		kind = current
	var troop_name: String = {"melee_infantry": TerrainArmy.TROOP_TYPE_NAME, "bow": "弓兵", "crossbow": "弩兵", "mixed": "混合兵種（無法保存）"}.get(str(kind), "未持武器")
	return "兵種 %s（基礎武力 %.0f）\n可戰 %d / 昏迷 %d / 死亡 %d\n%s %.1f / 疲憊 %d 人\n正式隊長 %s / 當前指揮 %s\n隊長能力：戰術 %d / 領導 %d / 教練 %d\n%s\n%s" % [troop_name, TerrainArmy.TROOP_COMBAT_ABILITY, alive, knocked, dead, fatigue_label, displayed_fatigue, tired,
		str(team.combat_identity(team.formal_commander)) if team.formal_commander >= 0 else "空缺", str(team.combat_identity(team.current_commander)) if team.current_commander >= 0 else "空缺",
		int(captain.get("tactics", 0)), int(captain.get("leadership", 0)), int(captain.get("coach", 0)), team.command_status, team.command_notice]

func _check_summary(team: TerrainArmy, kind: String, expected_native: int = -1) -> void:
	var expected := _legacy_summary(team)
	assert(expected.begins_with("兵種 " + kind + "（"), "Fixture must exercise the expected class")
	var before := JSON.stringify([team.materialized_combat_rows(), team.data.site, team._troop_actor(team.player_member)])
	var diagnostics := team.combat_hot_diagnostics_enabled
	team.combat_hot_diagnostics_enabled = true
	team.combat_hot_reset_stats()
	for _call in range(3): assert(team.combat_summary() == expected, "Summary must match every old display field")
	assert(int(team.combat_hot_stats().materialized_rows) == 0, "UI must not capture/deep-copy original rows")
	if expected_native >= 0:
		assert(int(team.combat_hot_stats().native_calls) == 3 * expected_native, "Fixture must exercise the intended native/fallback summary path")
		assert(int(team.combat_hot_stats().native_rows) == 3 * expected_native * team.combat_units.size())
	assert(JSON.stringify([team.materialized_combat_rows(), team.data.site, team._troop_actor(team.player_member)]) == before, "Summary must not alter people, items or Site")
	team.combat_hot_diagnostics_enabled = diagnostics

func _summary_read_contract(lab: TerrainLab, team: TerrainArmy, player_weapon_id: String) -> void:
	var melee := TerrainArmy.TROOP_TYPE_NAME
	var mixed := "混合兵種（無法保存）"
	for hot: bool in [false, true]:
		team.native_hot_enabled = hot
		if hot: assert(team._try_install_combat_hot_store(), "Native summary cases must really enter the hot store")
		assert(team.combat_hot_active() == hot)
		if hot: assert(not team.combat_units[1].has("hp") and not team.combat_units[1].has("member"))
		for option: Dictionary in HumanCharacter3DEditor.WeaponMaterials.OPTIONS:
			var weapon := str(option.id)
			for row: Dictionary in team.combat_units: _set_weapon_definition(lab.terrain, row, weapon)
			var kind := _legacy_appearance_class({"parts": {"weapon": weapon}})
			_check_summary(team, {&"bow": "弓兵", &"crossbow": "弩兵", &"": "未持武器"}.get(kind, melee), int(hot))
		for row: Dictionary in team.combat_units: _set_weapon_definition(lab.terrain, row, "longsword_01")
		for purpose: String in ["work", "logistics", "combat"]:
			team.role = purpose
			_check_summary(team, melee)
		var row: Dictionary = team.combat_units[1]
		_set_weapon_definition(lab.terrain, row, "bow_01")
		assert(team.is_controlled_person(1))
		_check_summary(team, mixed) # Real bow beats the unchanged longsword appearance.
		for pair: Array in [[&"hp", 0.0], [&"member", false], [&"departed", true], [&"ko", 5.0], [&"captive", true], [&"site_exited", true], [&"surrender_pending", true]]:
			var prior: Variant = team.combat_hot_get(1, pair[0])
			team.combat_hot_set(1, pair[0], pair[1])
			_check_summary(team, melee if pair[0] in [&"hp", &"member", &"departed"] else mixed)
			team.combat_hot_set(1, pair[0], prior)
		team.combat_hot_erase(1, &"member")
		_check_summary(team, mixed) # Missing membership keeps the original true default.
		team.combat_hot_set(1, &"member", true)
		if hot:
			for pair: Array in [[&"hp", 0.0], [&"member", false], [&"departed", true], [&"ko", 5.0]]:
				var prior: Variant = team.combat_hot_get(1, pair[0])
				team.combat_hot_set(1, pair[0], pair[1])
				var expected := _legacy_summary(team)
				team.combat_hot_set(1, pair[0], prior)
				team._borrow_combat_hot_row(1)
				team.combat_hot_set(1, pair[0], pair[1])
				var before := JSON.stringify(team.combat_units[1])
				var diagnostics := team.combat_hot_diagnostics_enabled
				team.combat_hot_diagnostics_enabled = true
				team.combat_hot_reset_stats()
				assert(team.combat_summary() == expected, "The borrowed row must outrank stale native columns")
				assert(int(team.combat_hot_stats().materialized_rows) == 0 and int(team.combat_hot_stats().native_calls) == 0 and JSON.stringify(team.combat_units[1]) == before)
				team.combat_hot_diagnostics_enabled = diagnostics
				team.combat_hot_set(1, pair[0], prior)
				team._return_combat_hot_row()
		# v2 plan §3.2 (R1b): the exemption reads captain + cadre service (order ⊆ service).
		var officers := team.officer_order.duplicate()
		var service := team.officer_service.duplicate()
		team.officer_order.append(1)
		team.officer_service.append(1)
		_check_summary(team, melee)
		team.officer_order.assign(officers)
		team.officer_service.assign(service)
		_check_summary(team, mixed) # Historical abilities/control are not an appointment.
		var commander := team.formal_commander
		team.formal_commander = 1
		_check_summary(team, melee)
		_set_weapon_definition(lab.terrain, team.combat_units[commander], "bow_01")
		_check_summary(team, mixed) # The previous formal captain is now ordinary.
		_set_weapon_definition(lab.terrain, team.combat_units[commander], "longsword_01")
		team.formal_commander = commander
		var holder: Dictionary = row.item_state
		row.erase("item_state")
		_check_summary(team, melee) # Legacy appearance fallback only without the holder.
		row.item_state = holder
		var weapon_id := str(holder.equipped.weapon)
		holder.equipped.erase("weapon")
		_check_summary(team, melee) # Empty hand does not fall back to appearance.
		holder.equipped.weapon = "missing-item"
		_check_summary(team, melee)
		holder.equipped.weapon = weapon_id
		var records: Dictionary = lab.terrain.site.item_records
		for malformed: Variant in [null, [], "bad"]:
			lab.terrain.site.item_records = malformed
			_check_summary(team, "未持武器")
		lab.terrain.site.item_records = records
		_set_weapon_definition(lab.terrain, row, "longsword_01")
		var actor := lab.character
		actor.item_state.equipped.weapon = player_weapon_id
		_set_weapon_definition(lab.terrain, {"item_state": actor.item_state}, "bow_01")
		team.player_member = actor
		_check_summary(team, mixed)
		var hp := actor.hp
		actor.hp = 0.0
		_check_summary(team, melee)
		actor.hp = hp
		team.formal_commander = TerrainArmy.PLAYER_MEMBER
		_check_summary(team, melee)
		team.formal_commander = commander
		team.player_member = null
		_check_summary(team, melee)
		if hot:
			_native_summary_read_contract(team)
			team._release_combat_hot_store(true)

func _native_summary_read_contract(team: TerrainArmy) -> void:
	var melee := TerrainArmy.TROOP_TYPE_NAME
	var mixed := "混合兵種（無法保存）"
	var store: RefCounted = team._combat_hot_store
	assert(store.has_method("read_summary"), "Build the current ordinary HotStore; fallback alone is not native coverage")
	var classes := TerrainArmy._combat_summary_classifier()
	var state: Dictionary = team.data.site
	var records: Dictionary = state.item_records
	var definitions: Dictionary = state.item_definitions
	var exemptions := team._troop_exempt_ids()
	assert(store.read_summary([], records, definitions, exemptions, classes, PersonFatigue.THRESHOLD).is_empty(), "Row count mismatch rejects without a partial summary")
	assert(store.read_summary(team.combat_units, records, definitions, exemptions, {}, PersonFatigue.THRESHOLD).is_empty(), "Unknown asset classes reject")
	assert(store.read_summary(team.combat_units, records, definitions, exemptions, {"longsword_01": true}, PersonFatigue.THRESHOLD).is_empty(), "Unexpected classifier values reject")
	var empty_store: RefCounted = ClassDB.instantiate(&"ArmyCombatHot")
	assert(empty_store.load_rows([]))
	assert(empty_store.read_summary([], {}, {}, [], classes, PersonFatigue.THRESHOLD) == [0, 0, 0, 0.0, 0, 0, &""])
	var empty := TerrainArmy.new()
	empty.data = team.data
	_check_summary(empty, "未持武器", 0)
	empty.free()
	team.native_summary_enabled = false
	_check_summary(team, melee, 0)
	team.native_summary_enabled = true
	_check_summary(team, melee, 1)
	# The same dictionary identity may change between reads without a callback.
	var row: Dictionary = team.combat_units[1]
	var weapon_id := str(row.item_state.equipped.weapon)
	var record: Dictionary = records[weapon_id]
	var definition_id := str(record.definition)
	var definition: Dictionary = definitions[definition_id]
	var asset: Variant = definition.asset
	definition.asset = "bow_01"
	_check_summary(team, "弓兵", 1)
	definition.asset = asset
	var changed_definitions := definitions.duplicate(true)
	changed_definitions[definition_id].asset = "crossbow_01"
	state.item_definitions = changed_definitions
	_check_summary(team, "弩兵", 1)
	state.item_definitions = definitions
	var alternate := "test:summary:alternate"
	assert(not definitions.has(alternate))
	definitions[alternate] = {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}
	record.definition = alternate
	_check_summary(team, mixed, 1)
	record.definition = definition_id
	var changed_records := records.duplicate(true)
	changed_records[weapon_id].definition = alternate
	state.item_records = changed_records
	_check_summary(team, mixed, 1)
	state.item_records = records
	definitions.erase(alternate)
	for unusual: Variant in [&"bow_01", null, 0, true, [], {}, "unknown_wood", "none_steel"]:
		definition.asset = unusual
		_check_summary(team, "弓兵" if unusual is StringName else "未持武器", 0)
	definition.asset = asset
	row.item_state.equipped.erase("weapon")
	_check_summary(team, melee, 0)
	row.item_state.equipped.weapon = weapon_id
	# Living nonmembers remain in fatigue/tired totals, with either label branch.
	var old_member: Variant = team.combat_hot_get(1, &"member", true)
	var old_shared: Dictionary = team.team_fatigue
	var had_pool := row.has("_fatigue_pool")
	var old_pool: Variant = row.get("_fatigue_pool")
	var had_fatigue := row.has("fatigue")
	var old_fatigue: Variant = row.get("fatigue")
	row.erase("_fatigue_pool")
	row.fatigue = 31.5
	team.combat_hot_set(1, &"member", false)
	_check_summary(team, melee, 1)
	assert(team.combat_summary().contains("隊伍共享疲勞"))
	team.team_fatigue = {}
	_check_summary(team, melee, 1)
	assert(team.combat_summary().contains("平均疲勞"))
	row.fatigue = "42.5"
	_check_summary(team, melee, 0) # GD's float coercion is intentionally outside native admission.
	row.erase("fatigue")
	_check_summary(team, melee, 1) # Absent personal fatigue is zero.
	row.fatigue = 99.0
	row._fatigue_pool = {"fatigue": 47.0}
	_check_summary(team, melee, 1) # The pool wins even for this nonmember.
	row._fatigue_pool = null
	assert(store.read_summary(team.combat_units, records, definitions, exemptions, classes, PersonFatigue.THRESHOLD).is_empty())
	if had_pool: row._fatigue_pool = old_pool
	else: row.erase("_fatigue_pool")
	if had_fatigue: row.fatigue = old_fatigue
	else: row.erase("fatigue")
	team.team_fatigue = old_shared
	team.combat_hot_set(1, &"member", old_member)
	var immutable_row := row.duplicate(true)
	immutable_row.make_read_only()
	team.combat_units[1] = immutable_row
	_check_summary(team, melee, 1)
	assert(immutable_row.is_read_only())
	var typed_row: Dictionary[String, Variant] = {}
	for key: Variant in row: typed_row[str(key)] = row[key]
	team.combat_units[1] = typed_row
	_check_summary(team, melee, 0)
	team.combat_units[1] = row
	# A read-only subclass view proves the original getters are still dispatched.
	var custom := SummaryOverrideArmy.new()
	custom.data = team.data
	custom.combat_units.assign(team.combat_units)
	custom._combat_hot_store = store
	custom.team_fatigue = team.team_fatigue
	custom.formal_commander = team.formal_commander
	custom.officer_order.assign(team.officer_order)
	custom.combat_hot_diagnostics_enabled = true
	var expected := _legacy_summary(custom)
	custom.summary_reads = 0
	custom.combat_hot_reset_stats()
	assert(custom.combat_summary() == expected and custom.summary_reads > 0)
	assert(int(custom.combat_hot_stats().native_calls) == 0 and int(custom.combat_hot_stats().materialized_rows) == 0)
	custom._combat_hot_store = null
	custom.free()
	_check_summary(team, melee, 1)
	_native_summary_lookup_contract(team)
	_native_summary_same_call_reuse_contract(team)

func _native_summary_lookup_contract(team: TerrainArmy) -> void:
	var melee := TerrainArmy.TROOP_TYPE_NAME
	var mixed := "混合兵種（無法保存）"
	var store: RefCounted = team._combat_hot_store
	var state: Dictionary = team.data.site
	var records: Dictionary = state.item_records
	var definitions: Dictionary = state.item_definitions
	var classes := TerrainArmy._combat_summary_classifier()
	var exemptions := team._troop_exempt_ids()
	var expected: Array = store.read_summary(team.combat_units, records, definitions, exemptions, classes, PersonFatigue.THRESHOLD)
	assert(expected.size() == 7)
	# Read-only dictionaries remain supported at every lookup level.
	var frozen_rows := team.combat_units.duplicate(true)
	for row: Dictionary in frozen_rows:
		row.item_state.equipped.make_read_only()
		row.item_state.make_read_only()
		if row.has("_fatigue_pool"): row._fatigue_pool.make_read_only()
		row.make_read_only()
	frozen_rows.make_read_only()
	var frozen_records := records.duplicate(true)
	var frozen_definitions := definitions.duplicate(true)
	for value: Dictionary in frozen_records.values(): value.make_read_only()
	for value: Dictionary in frozen_definitions.values(): value.make_read_only()
	frozen_records.make_read_only()
	frozen_definitions.make_read_only()
	var frozen_before := var_to_bytes([frozen_rows, frozen_records, frozen_definitions])
	assert(var_to_bytes(store.read_summary(frozen_rows, frozen_records, frozen_definitions, exemptions, classes, PersonFatigue.THRESHOLD)) == var_to_bytes(expected))
	assert(var_to_bytes([frozen_rows, frozen_records, frozen_definitions]) == frozen_before)
	var row: Dictionary = team.combat_units[1]
	var weapon_id := str(row.item_state.equipped.weapon)
	var record: Dictionary = records[weapon_id]
	var definition_id := str(record.definition)
	var definition: Dictionary = definitions[definition_id]
	var asset: Variant = definition.asset
	var had_empty_definition := definitions.has("")
	var empty_definition: Variant = definitions.get("")
	definitions[""] = {"asset": "bow_01"}
	records.erase(weapon_id)
	_check_summary(team, mixed, 0) # Missing record reaches GD's empty-string definition.
	records[weapon_id] = null
	_check_summary(team, melee, 0) # Explicit NIL must not become a missing-record default.
	records[weapon_id] = record
	record.erase("definition")
	_check_summary(team, mixed, 0)
	record.definition = ""
	_check_summary(team, mixed, 1) # Explicit empty ID is a real original registry key.
	record.definition = null
	_check_summary(team, melee, 0)
	record.definition = definition_id
	if had_empty_definition: definitions[""] = empty_definition
	else: definitions.erase("")
	for key: Variant in ["definition", &"definition"]:
		records[weapon_id] = {key: definition_id}
		_check_summary(team, melee, 1)
	records[weapon_id] = record
	var typed_record: Dictionary[String, Variant] = {}
	for key: Variant in record: typed_record[str(key)] = record[key]
	records[weapon_id] = typed_record
	_check_summary(team, melee, 0)
	records[weapon_id] = record
	definition.erase("asset")
	_check_summary(team, "未持武器", 0)
	definition.asset = ""
	_check_summary(team, "未持武器", 0)
	definition.asset = asset
	var had_pool := row.has("_fatigue_pool")
	var old_pool: Variant = row.get("_fatigue_pool")
	var had_fatigue := row.has("fatigue")
	var old_fatigue: Variant = row.get("fatigue")
	row._fatigue_pool = {}
	row.fatigue = 31.5
	_check_summary(team, melee, 1) # Empty pool uses the original personal value.
	row._fatigue_pool = {"active": false}
	assert(store.read_summary(team.combat_units, records, definitions, exemptions, classes, PersonFatigue.THRESHOLD).is_empty(), "Nonempty pool missing fatigue must reject")
	row._fatigue_pool = {"fatigue": null}
	assert(store.read_summary(team.combat_units, records, definitions, exemptions, classes, PersonFatigue.THRESHOLD).is_empty(), "NIL fatigue must not become a missing personal default")
	if had_pool: row._fatigue_pool = old_pool
	else: row.erase("_fatigue_pool")
	if had_fatigue: row.fatigue = old_fatigue
	else: row.erase("fatigue")
	_check_summary(team, melee, 1)

func _native_summary_same_call_reuse_contract(team: TerrainArmy) -> void:
	var melee := TerrainArmy.TROOP_TYPE_NAME
	var records: Dictionary = team.data.site.item_records
	var definitions: Dictionary = team.data.site.item_definitions
	# The first ordinary row admits its original definition before this row.
	var row: Dictionary = team.combat_units[2]
	var record: Dictionary = records[row.item_state.equipped.weapon]
	var definition_id: String = record.definition
	var definition: Dictionary = definitions[definition_id]
	var alternate := "test:summary:later-definition"
	assert(not definitions.has(alternate))
	record.definition = alternate
	definitions[alternate] = definition.duplicate(true)
	_check_summary(team, melee, 1)
	definitions[alternate].asset = "bow_01"
	_check_summary(team, "混合兵種（無法保存）", 1)
	definitions[alternate].asset = null
	_check_summary(team, melee, 0)
	var typed_definition: Dictionary[String, Variant] = {}
	for key: Variant in definition: typed_definition[str(key)] = definition[key]
	definitions[alternate] = typed_definition
	_check_summary(team, melee, 0) # Equal content does not establish Dictionary identity.
	record.definition = definition_id
	definitions.erase(alternate)
	var had_pool := row.has("_fatigue_pool")
	var old_pool: Variant = row.get("_fatigue_pool")
	var typed_pool: Dictionary[String, Variant] = {}
	for key: Variant in team.team_fatigue: typed_pool[str(key)] = team.team_fatigue[key]
	row._fatigue_pool = typed_pool
	_check_summary(team, melee, 0) # A later pool must be admitted independently.
	row._fatigue_pool = {"fatigue": 31.25}
	_check_summary(team, melee, 1)
	var total := 0.0
	for i: int in team.combat_units.size():
		if float(team.combat_hot_get(i, &"hp", 0.0)) > 0.0 and not bool(team.combat_hot_get(i, &"departed", false)):
			total += PersonFatigue.read(team.combat_units[i])
	var summary: Array = team._combat_hot_store.read_summary(team.combat_units, records, definitions,
		team._troop_exempt_ids(), TerrainArmy._combat_summary_classifier(), PersonFatigue.THRESHOLD)
	assert(summary.size() == 7 and summary[3] == total, "Distinct and recurring pools keep the original row-order sum")
	if had_pool: row._fatigue_pool = old_pool
	else: row.erase("_fatigue_pool")
	_check_summary(team, melee, 1)
