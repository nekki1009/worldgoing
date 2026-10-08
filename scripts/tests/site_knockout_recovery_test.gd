extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: quit(1))
	if "--duel-only" in OS.get_cmdline_user_args():
		_test_commandless_duel()
		return
	var data := TerrainData.new()
	data.allocate(Vector2i(12, 12))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(144)
	data.feature_at.resize(144)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0}
	var actor := TerrainTestCharacter.new()
	actor.data = data
	actor.person_id = 1
	assert(actor.place(Vector2i(5, 5), true))
	actor.apply_contact({"shield": false, "result": {"hp": 1.0, "stun": 110.0, "guard_break": false}})
	if not is_equal_approx(actor.knockout_left, 14400.0):
		push_error("A real KO must start at four game hours; got " + str(actor.knockout_left))
		actor.free()
		quit(1)
		return
	actor.advance_combat(3.0, false, 3.0) # Finish down and enter the repeating unconscious pose.
	actor.advance_combat(61.0, false, 61.0) # The loop itself now exceeds the old 60-second save ceiling.
	var saved := actor.capture_state()
	if not TerrainTestCharacter.valid_state(saved, data) or saved.pose_time > 60.0 or saved.schema != 2 or saved.knockout_left != 14336.0:
		_fail("Long no-editor unconscious pose must save with exact schema-2 KO")
		return
	var legacy := saved.duplicate(true)
	legacy.schema = 1
	legacy.knockout_left = 17.0
	if not TerrainTestCharacter.valid_state(legacy, data) or TerrainTestCharacter.normalize_saved_state(legacy).knockout_left != 8160.0 or legacy.knockout_left != 17.0:
		_fail("Legacy Actor KO must validate before one proportional migration")
		return
	var roundtrip := TerrainTestCharacter.normalize_saved_state(legacy)
	if TerrainTestCharacter.normalize_saved_state(roundtrip).knockout_left != 8160.0:
		_fail("Actor KO must not multiply twice")
		return
	for invalid_schema: Variant in [0, 3, 1.5]:
		var invalid := saved.duplicate(true)
		invalid.schema = invalid_schema
		if TerrainTestCharacter.valid_state(invalid, data):
			_fail("Unknown Actor schema was accepted")
			return
	legacy.knockout_left = 31.0
	if TerrainTestCharacter.valid_state(legacy, data):
		_fail("Legacy Actor KO above 30 action seconds was accepted")
		return
	for bad: Variant in [-1.0, 14401.0, INF, NAN]:
		var invalid := saved.duplicate(true)
		invalid.knockout_left = bad
		if TerrainTestCharacter.valid_state(invalid, data):
			_fail("Invalid schema-2 Actor KO was accepted: " + str(bad))
			return
	actor.advance_combat(0.1, false, 14336.0)
	if not actor._getting_up or actor.can_act() or actor.action_time != 2.2:
		_fail("Natural wake must enter original 2.2 action-second get-up")
		return
	actor.advance_combat(2.2)
	if not actor.can_act():
		_fail("Actor should act only after the full get-up")
		return
	actor.free()
	if not _test_lab_clock():
		return
	if not _test_cross_owner_rescue():
		return
	if not _test_native_clock():
		return
	print("SITE_KNOCKOUT_RECOVERY_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _test_lab_clock() -> bool:
	var data := TerrainData.new()
	data.allocate(Vector2i(12, 12))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "knockout-game-clock")
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.static_blocked.fill(0)
	var lab := TerrainLab.new()
	lab.terrain = data
	var actor := TerrainTestCharacter.new()
	actor.data = data
	actor.person_id = 1
	actor.exchange_enabled = true
	actor.combat_driven_by_lab = true
	actor.place(Vector2i(5, 5), true)
	lab.character = actor
	lab.combat_actors.assign([actor])
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		for combat_clock: float in [0.0, 1.0, 0.05]:
			actor.knockout_left = 10000.0
			actor.visual_state.animation_id = &"unconscious"
			lab.simulation_speed = speed
			lab._advance_combat(0.1, combat_clock)
			var expected := 10000.0 - SiteRuntime.game_seconds(0.1, combat_clock) * speed
			if absf(actor.knockout_left - expected) > 0.001:
				_fail("Lab KO clock differs from Site time: speed=" + str(speed) + " clock=" + str(combat_clock) + " got=" + str(actor.knockout_left))
				return false
	data.site.paused = true
	var before := actor.knockout_left
	lab._advance_combat(0.1, 0.0)
	if actor.knockout_left != before:
		_fail("Pause must freeze KO")
		return false
	data.site.paused = false
	lab.simulation_speed = 1.0
	actor.knockout_left = 10000.0
	lab._advance_combat(0.1, 0.05)
	var unsplit := actor.knockout_left
	actor.knockout_left = 10000.0
	lab._advance_combat(0.05, 0.05)
	lab._advance_combat(0.05, 0.0)
	if absf(actor.knockout_left - unsplit) > 0.001:
		_fail("Peace/combat boundary consumes different KO time when the same step is split")
		return false
	actor.knockout_left = 6.0
	lab._advance_combat(0.1, 0.0)
	if not actor._getting_up or actor.can_act() or absf(actor.action_time - 2.2) > 0.001:
		_fail("Lab calendar completion must start original get-up lock")
		return false
	lab._advance_combat(0.1, 0.0)
	if absf(actor.action_time - 2.1) > 0.001:
		_fail("Get-up must consume action seconds, not accelerated game seconds")
		return false
	lab.combat_actors.clear()
	lab.character = null
	actor.free()
	lab.free()
	return true

func _test_cross_owner_rescue() -> bool:
	var data := TerrainData.new()
	data.allocate(Vector2i(20, 20))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "knockout-cross-owner-rescue")
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.static_blocked.fill(0)
	var actor := TerrainTestCharacter.new()
	actor.data = data
	actor.person_id = 1
	actor.faction_id = 0
	actor.place(Vector2i(9, 10), true)
	var peer := TerrainTestCharacter.new()
	peer.data = data
	peer.person_id = 2
	peer.faction_id = 0
	peer.place(Vector2i(8, 10), true)
	peer.apply_contact({"shield": false, "result": {"hp": 1.0, "stun": 110.0, "guard_break": false}})
	if not actor.start_rescue(peer):
		_fail("Actor-to-Actor rescue must start across a legal neighboring cell")
		return false
	actor.advance_combat(1.0)
	var helping: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_state()))
	var patient: Dictionary = JSON.parse_string(JSON.stringify(peer.capture_state()))
	if not TerrainTestCharacter.valid_state(helping, data) or not TerrainTestCharacter.valid_state(patient, data):
		_fail("Mid-rescue Actor and long-KO patient must both save")
		return false
	actor.restore_state(helping)
	peer.restore_state(patient)
	actor.restore_links(helping, {actor.person_id: actor, peer.person_id: peer})
	if actor._rescue_left != 3.0 or peer._rescuer != actor or peer.knockout_left != SiteCombatRules.KNOCKOUT_GAME_SECONDS:
		_fail("Mid-rescue Actor load must resume exact action and game clocks")
		return false
	actor.advance_combat(3.0)
	if peer.knockout_left != SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS or peer._getting_up or actor.start_rescue(peer):
		_fail("Actor-to-Actor rescue must cap waiting without immediate wake or repeat aid")
		return false
	peer.advance_combat(0.1, false, SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
	if not peer._getting_up or peer.can_act():
		_fail("Actor-to-Actor patient must naturally wake into get-up")
		return false
	peer.free()
	var team := TerrainArmy.new()
	team.team_id = 1
	team.faction_id = 0
	team.roster_size = 1
	team.exchange_enabled = true
	root.add_child(team)
	team.set_process(false)
	var selected: Array[Vector2i] = [Vector2i(10, 10)]
	if not team.deploy_at(data, actor, null, selected) or not team.enable_combat(false):
		_fail("Cross-owner rescue team deployment failed")
		return false
	actor._saved_appearance = team.combat_units[0].appearance.duplicate(true)
	if not SiteRuntime.seed_person_equipment(data, actor.item_state, actor.person_id, actor._saved_appearance).ok:
		_fail("Cross-owner Actor equipment seed failed")
		return false
	team.apply_unit_contact(0, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
	if not actor.start_rescue_unit(team, 0):
		_fail("Original Actor must rescue adjacent original Army member")
		return false
	actor.advance_combat(4.0)
	if team.combat_units[0].ko != SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS or team.combat_units[0].pose == "get_up" or actor._rescue_left != 0.0 or actor.start_rescue_unit(team, 0):
		_fail("Actor-to-Army rescue must leave one game hour without repeat aid")
		return false
	team.prepare_combat(0.1, SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
	team.prepare_combat(2.2)
	if not team.combat_can_act(0):
		_fail("Army patient must finish original get-up before acting")
		return false
	if not team.join_player(actor).ok:
		_fail("Original player membership failed for Army-to-player rescue")
		return false
	actor.apply_contact({"shield": false, "result": {"hp": 1.0, "stun": 110.0, "guard_break": false}})
	if not team.start_unit_rescue(0, TerrainArmy.PLAYER_MEMBER):
		_fail("Original Army member must rescue joined player")
		return false
	team.prepare_combat(4.0)
	if actor.knockout_left != SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS or actor._getting_up or team.start_unit_rescue(0, TerrainArmy.PLAYER_MEMBER):
		_fail("Army-to-player rescue must leave one game hour without repeat aid")
		return false
	actor.advance_combat(0.1, false, SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
	if not actor._getting_up or actor.can_act():
		_fail("Player natural wake must keep get-up lock")
		return false
	team.clear()
	team.free()
	actor.free()
	return true

func _test_native_clock() -> bool:
	var data := TerrainData.new()
	data.allocate(Vector2i(20, 20))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "knockout-native-clock")
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.static_blocked.fill(0)
	var team := TerrainArmy.new()
	team.team_id = 1
	team.roster_size = 2
	team.exchange_enabled = true
	root.add_child(team)
	team.set_process(false)
	var selected: Array[Vector2i] = [Vector2i(9, 10), Vector2i(10, 10)]
	if not team.deploy_at(data, null, null, selected) or not team.enable_combat(false):
		_fail("Could not deploy native clock fixture")
		return false
	if not team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK).ok:
		_fail("Native clock fixture requires a real attack order")
		return false
	team.apply_unit_contact(1, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
	team.prepare_combat(3.0, 3.0) # Down is a GD exception; inspect the unconscious row on the next step.
	if team.combat_units[1].pose != "unconscious":
		_fail("Native fixture did not reach the eligible unconscious pose")
		return false
	team.native_recovery_rows = 0
	team.combat_units[1].exchange_cooldown = 10.0
	team.prepare_combat(0.1, 0.1)
	if team.native_recovery_rows != 2 or absf(float(team.combat_units[1].ko) - 14396.9) > 0.001:
		_fail("Equal clocks must retain native recovery with exact KO consumption")
		return false
	team.native_recovery_rows = 0
	team.combat_units[1].ko = 10000.0
	team.combat_units[1].exchange_cooldown = 10.0
	team.prepare_combat(0.1, 6.0)
	if team.native_recovery_rows != 0 or absf(float(team.combat_units[1].ko) - 9994.0) > 0.001 or absf(float(team.combat_units[1].exchange_cooldown) - 9.9) > 0.001:
		_fail("Unequal clocks must use GD KO while cooldown stays on action seconds")
		return false
	team.clear()
	team.free()
	return true

func _test_commandless_duel() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(20, 20))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "knockout-commandless-duel")
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.static_blocked.fill(0)
	var lab := TerrainLab.new()
	lab.terrain = data
	var armies: Array[TerrainArmy] = []
	for side in range(2):
		var team := TerrainArmy.new()
		team.team_id = side + 1
		team.faction_id = side
		team.roster_size = 1
		team.exchange_enabled = true
		root.add_child(team)
		team.set_process(false)
		var selected: Array[Vector2i] = [Vector2i(9 + side, 10)]
		if not team.deploy_at(data, null, null, selected) or not team.enable_combat(false):
			_fail("Could not deploy two original Army owners")
			return
		armies.append(team)
	lab.combat_armies = armies
	armies[0].external_blocker = armies[1].blocks_cell
	armies[1].external_blocker = armies[0].blocks_cell
	lab._resolve_exchanges()
	if lab.exchange_count != 0:
		_fail("Initial peaceful HOLD cannot duel")
		return
	for team: TerrainArmy in armies:
		team.apply_unit_contact(0, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
		team.settle_combat_command()
		if team.current_commander != -1 or not team.needs_attack_order or team.combat_attacking or team.combat_order != TerrainArmy.CombatOrder.HOLD:
			_fail("Real KO must cause commandless HOLD")
			return
		var saved: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
		if saved.schema != 2 or saved.units[0].ko != SiteCombatRules.KNOCKOUT_GAME_SECONDS or not TerrainArmy.valid_combat_state(saved, data):
			_fail("New Army KO snapshot must keep exact game seconds")
			return
		var legacy := saved.duplicate(true)
		legacy.schema = 1
		legacy.units[0].ko = 17.0
		var migrated := TerrainArmy.normalize_roster_snapshot(legacy)
		if not TerrainArmy.valid_combat_state(legacy, data) or migrated.schema != 2 or migrated.units[0].ko != 8160.0 or TerrainArmy.normalize_roster_snapshot(migrated).units[0].ko != 8160.0 or legacy.units[0].ko != 17.0:
			_fail("Legacy Army KO must migrate exactly once without changing the input")
			return
		legacy.units[0].ko = 31.0
		if TerrainArmy.valid_combat_state(legacy, data):
			_fail("Legacy Army KO above 30 action seconds was accepted")
			return
		for invalid_schema: Variant in [0, 3, 1.5]:
			var invalid := saved.duplicate(true)
			invalid.schema = invalid_schema
			if TerrainArmy.valid_combat_state(invalid, data):
				_fail("Unknown Army schema was accepted")
				return
		for bad: Variant in [-1.0, 14401.0, INF, NAN]:
			var invalid := saved.duplicate(true)
			invalid.units[0].ko = bad
			if TerrainArmy.valid_combat_state(invalid, data):
				_fail("Invalid Army KO was accepted: " + str(bad))
				return
		team.prepare_combat(0.1, 14400.0)
		team.prepare_combat(2.2)
		team.settle_combat_command()
		if not team.combat_can_act(0) or not team.exchange_ready(0) or not team.exchange_can_receive(0) or not team.needs_attack_order or team.combat_order != TerrainArmy.CombatOrder.HOLD:
			_fail("Woken soldier must be ready but still waiting for attack order")
			return
		var enemy_id := armies[1 - armies.find(team)].combat_identity(0)
		if not team.exchange_initiates(0, enemy_id, true) or team.exchange_initiates(0, enemy_id):
			_fail("Commandless HOLD may initiate only adjacent melee")
			return
		team.combat_units[0].work_task = {"duty": "test"}
		if team.exchange_initiates(0, enemy_id, true):
			_fail("A member with an original work task cannot auto-defend")
			return
		team.combat_units[0].work_task = {}
		team.person_busy_query = func(_person_id: int) -> bool: return true
		if team.exchange_initiates(0, enemy_id, true):
			_fail("A callback-busy member cannot auto-defend")
			return
		team.person_busy_query = Callable()
		team.controlled_person_query = func() -> int: return team.combat_identity(0)
		if team.exchange_initiates(0, enemy_id, true):
			_fail("A controlled soldier needs an explicit personal target")
			return
		team.controlled_person_query = Callable()
		team.combat_units[0].member = false
		if team.exchange_initiates(0, enemy_id, true):
			_fail("A nonmember cannot use commandless team defense")
			return
		team.combat_units[0].member = true
		team.sustain_routed_query = func(_owner: TerrainArmy) -> bool: return true
		if team.exchange_initiates(0, enemy_id, true):
			_fail("A routed team cannot use commandless melee initiation")
			return
		team.sustain_routed_query = Callable()
		team.combat_order = TerrainArmy.CombatOrder.RETREAT
		if team.exchange_initiates(0, enemy_id, true):
			_fail("Retreat cannot use the commandless HOLD gate")
			return
		team.combat_order = TerrainArmy.CombatOrder.HOLD
		team.combat_units[0].pose = "get_up"
		if team.exchange_ready(0):
			_fail("Unfinished get-up cannot initiate a melee exchange")
			return
		team.combat_units[0].pose = "idle"
		team.combat_units[0].captive = true
		if team.exchange_ready(0):
			_fail("A captive cannot initiate a melee exchange")
			return
		team.combat_units[0].captive = false
	lab._resolve_exchanges()
	if lab.exchange_count != 1:
		_fail("Woken adjacent commandless soldiers remain idle; exchange_count=" + str(lab.exchange_count))
		return
	for team: TerrainArmy in armies:
		team.external_blocker = Callable()
		team.clear()
		team.free()
	lab.combat_armies.clear()
	lab.free()
	print("SITE_KNOCKOUT_DUEL_PASS")
	quit(0)
