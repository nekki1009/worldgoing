extends SceneTree

var contact_calls := 0
var aim_calls := 0

func _initialize() -> void:
	call_deferred("run")

func _result(role: String, kind: String = "small") -> Dictionary:
	return {"role": role, "kind": "draw" if role == "draw" else kind,
		"hp": (2.0 if kind == "big" else 1.0) if role == "loser" else 0.0,
		"stun": (18.0 if kind == "big" else 8.0) if role == "loser" else 0.0,
		"stagger": (0.65 if kind == "big" else 0.35) if role == "loser" else (0.3 if role == "draw" else 0.0),
		"knockback": role == "loser" and kind == "big", "fatigue": 0.5,
		"other_identity": 9999, "skill": ""}

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "exchange-army-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	army.exchange_enabled = true
	var selected: Array[Vector2i] = []
	for index in range(100):
		selected.append(Vector2i(20 + index % 10, 20 + floori(float(index) / 10.0)))
	assert(army.deploy_at(data, null, null, selected) and army.enable_combat(false))
	assert(TerrainArmy._contact_source == null, "Exchange deployment must not require the old continuous geometry source")
	army.contact_query = func(_previous: Array, _current: Array, _cell: Vector2i, _position: Vector2, _owner: Variant, _unit: int) -> Array[Dictionary]:
		contact_calls += 1
		return []
	army.combat_target_query = func(_identity: int, _bodies: bool) -> Dictionary:
		aim_calls += 1
		return {}
	assert(army.start_unit_attack(0, army.cells[0] + Vector2i.UP, 9999))
	army.sample_combat()
	assert(contact_calls == 0 and aim_calls == 0 and not bool(army.combat_units[0].attack))
	assert(not army.start_unit_attack(0, army.cells[0] + Vector2i.UP * 2, 9999))
	army.apply_exchange(11, army.cells[11] + Vector2i.UP, _result("draw"))
	for _step in range(30):
		army.prepare_combat(1.0 / 30.0)
	assert(army.combat_units[11].exchange_cooldown == 0.0 and army.exchange_ready(11), "Thirty 30 Hz steps must complete one round, not leave an extra decision-tick lock")
	var combat_events: Array[float] = []
	var deaths: Array[int] = []
	army.combat_event.connect(func(seconds: float) -> void: combat_events.append(seconds))
	army.died.connect(func(identity: int) -> void: deaths.append(identity))
	# Inputs are already resolved by the Lab; this check exercises the original
	# row/HP/action/grid owner, not another pair-selection implementation.
	army.apply_exchange(1, army.cells[1] + Vector2i.DOWN, _result("loser"))
	assert(army.combat_units[1].hp == 99.0 and army.cells[1] == selected[1])
	assert(army.combat_units[1].pose == "hit" and army.combat_units[1].stun == 8.0)
	assert(army.combat_frame(1).clip == "hit")
	assert(army.moving_to[1] == TerrainArmy.INVALID_CELL and not army._reserve_combat_step(1, selected[1] + Vector2i.UP))
	assert(not army.exchange_ready(1) and army.combat_units[1].fatigue == 0.5)
	army.prepare_combat(0.35)
	assert(army._reserve_combat_step(1, selected[1] + Vector2i.UP), "Only the stagger, not the exchange cooldown, prevents voluntary movement")
	army.prepare_combat(TerrainArmy.MOVE_DURATION)
	assert(army.cells[1] == selected[1] + Vector2i.UP)
	army.apply_exchange(2, selected[2] + Vector2i.DOWN, _result("loser", "big"))
	assert(army.combat_units[2].hp == 98.0 and army.combat_units[2].pose == "knockback")
	assert(army.combat_frame(2).clip == "knockback")
	assert(army.cells[2] == selected[2] and army.moving_to[2] == selected[2] + Vector2i.UP)
	assert(army.blocks_cell(selected[2]) and army.blocks_cell(selected[2] + Vector2i.UP))
	army.prepare_combat(TerrainArmy.MOVE_DURATION)
	assert(army.cells[2] == selected[2] + Vector2i.UP and not army.blocks_cell(selected[2]))
	army.apply_exchange(3, selected[3] + Vector2i.DOWN, _result("draw"))
	assert(army.combat_units[3].hp == 100.0 and army.combat_units[3].pose == "guard")
	assert(army.combat_frame(3).clip == "guard")
	assert(not army._reserve_combat_step(3, selected[3] + Vector2i.UP))
	army.prepare_combat(0.3)
	assert(army.combat_units[3].pose == "idle" and army.cells[3] == selected[3])
	# A wall, a live ally and an ally's real in-flight destination each prevent
	# a push. No failed push changes the unit's cell or steals a reservation.
	var wall := selected[4] + Vector2i.UP
	data.static_blocked[data.index(wall)] = 1
	army.apply_exchange(4, selected[4] + Vector2i.DOWN, _result("loser", "big"))
	assert(army.moving_to[4] == TerrainArmy.INVALID_CELL and army.cells[4] == selected[4] and army.combat_units[4].hp == 98.0)
	data.static_blocked[data.index(wall)] = 0
	army.apply_exchange(5, selected[5] + Vector2i.LEFT, _result("loser", "big"))
	assert(army.moving_to[5] == TerrainArmy.INVALID_CELL and army.cells[5] == selected[5])
	army.prepare_combat(1.0)
	assert(army._reserve_combat_step(5, selected[5] + Vector2i.UP))
	army.prepare_combat(TerrainArmy.MOVE_DURATION)
	var claimed := selected[6] + Vector2i.UP
	assert(army._reserve_combat_step(5, claimed))
	army.apply_exchange(6, selected[6] + Vector2i.DOWN, _result("loser", "big"))
	assert(army.moving_to[6] == TerrainArmy.INVALID_CELL and army._reserved_cells[claimed] == 5)
	army.prepare_combat(TerrainArmy.MOVE_DURATION)
	army.apply_exchange(7, selected[7] + Vector2i.UP, _result("winner", "big"))
	assert(army.combat_units[7].hp == 100.0 and army.combat_units[7].exchange_stagger == 0.0)
	assert(army.combat_units[7].attack and army._reserve_combat_step(7, selected[7] + Vector2i.UP), "Winning attack presentation does not lock forward movement")
	army.prepare_combat(TerrainArmy.MOVE_DURATION)
	var committed_destination := army.cells[7] + Vector2i.UP
	assert(army._reserve_combat_step(7, committed_destination))
	army.prepare_combat(1.0)
	# Use a fresh original movement after the winner's round has expired.
	committed_destination = army.cells[7] + Vector2i.UP
	assert(army._reserve_combat_step(7, committed_destination))
	army.prepare_combat(0.1)
	assert(not army.exchange_ready(7) and army.exchange_can_receive(7), "Movement is not immunity from an incoming exchange")
	army.apply_exchange(7, army.cells[7] + Vector2i.RIGHT, _result("loser", "big"))
	assert(army.moving_to[7] == committed_destination and army.combat_units[7].hp == 98.0, "Incoming loss cannot replace the original committed destination")
	army.prepare_combat(TerrainArmy.MOVE_DURATION - 0.1)
	assert(army.cells[7] == committed_destination and absf(float(army.combat_units[7].exchange_stagger) - 0.65) < 0.000000001)
	assert(not army._reserve_combat_step(7, committed_destination + Vector2i.UP))
	army.prepare_combat(0.65)
	assert(army.combat_units[7].exchange_stagger == 0.0)
	army.prepare_combat(0.1)
	assert(army._reserve_combat_step(7, army.cells[7] + Vector2i.UP))
	army.apply_exchange(7, army.cells[7] + Vector2i.RIGHT, _result("loser", "big"))
	army.prepare_combat(1.0)
	assert(army.exchange_can_receive(7) and float(army.combat_units[7].exchange_stagger) > 0.0)
	var next_push := army.cells[7] + Vector2i.UP
	army.apply_exchange(7, army.cells[7] + Vector2i.DOWN, _result("loser", "big"))
	assert(army.moving_to[7] == next_push, "Previous recovery remainder cannot block this newly resolved legal push")
	army.prepare_combat(1.0)
	# Existing life resolution retains a dying/KO person's in-flight claim
	# until its legal endpoint, then frees occupancy without replacing the row.
	var death_identity := army.combat_identity(8)
	army.combat_units[8].hp = 2.0
	army.apply_exchange(8, selected[8] + Vector2i.DOWN, _result("loser", "big"))
	assert(army.combat_units[8].hp == 0.0 and army.combat_units[8].pose == "down" and deaths == [death_identity])
	assert(army.blocks_cell(selected[8]))
	army.combat_units[9].stun = 92.0
	army.apply_exchange(9, selected[9] + Vector2i.DOWN, _result("loser", "big"))
	assert(army.combat_units[9].hp == 98.0 and army.combat_units[9].ko == SiteCombatRules.KNOCKOUT_SECONDS)
	army.prepare_combat(TerrainArmy.MOVE_DURATION)
	assert(not army.blocks_cell(army.cells[8]) and not army.blocks_cell(army.cells[9]))
	assert(army.combat_identity(8) == death_identity and army.combat_units.size() == 100 and not combat_events.is_empty())
	army.apply_unit_contact(20, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	for role: String in ["draw", "winner", "loser"]:
		assert(army.start_unit_rescue(10, 20))
		assert(not army.exchange_ready(10) and army.exchange_can_receive(10), "Rescuers cannot initiate but remain valid defenders")
		army.apply_exchange(10, army.cells[10] + Vector2i.LEFT, _result(role))
		assert(not army._unit_rescues.has(10) and army.combat_units[20].ko > 0.0, "Every result cancels the original help relation without waking its patient")
		army.prepare_combat(1.0)
	# Skills are original captain/player authority; their cooldown starts when
	# consumed, so waiting with a queued skill cannot stockpile two uses.
	assert(not army.activate_exchange_skill(10, "power"))
	assert(army.activate_exchange_skill(0, "brace"))
	army.prepare_combat(9.0)
	assert(army.exchange_stats(0).skill == "brace" and not army.activate_exchange_skill(0, "power"))
	army.apply_exchange(0, army.cells[0] + Vector2i.UP, _result("draw"))
	assert(army.combat_units[0].exchange_skill_cooldown == 8.0 and army.exchange_stats(0).skill == "")
	assert(not army.activate_exchange_skill(0, "power"))
	army.prepare_combat(8.0)
	assert(army.activate_exchange_skill(0, "power"))
	army.combat_units[0].combat_ability = 67.0
	army.equipment_appearance_query = func(_identity: int) -> Dictionary: return {"parts": {"armor": "armor_steel", "shield": "shield_heater_01"}}
	assert(army.exchange_stats(0).ability == 67.0 and army.exchange_stats(0).armorbonus == 12.75)
	army.equipment_appearance_query = Callable()
	army.settle_combat_command()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(saved, data), "Original JSON validation admits bounded exchange state")
	for field: String in ["combat_ability", "exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "exchange_pose_duration"]:
		for invalid: Variant in [-1.0, 101.0, "0", null, INF, NAN]:
			var corrupt := saved.duplicate(true)
			corrupt.units[0][field] = invalid
			assert(not TerrainArmy.valid_combat_state(corrupt, data))
	var legacy := saved.duplicate(true)
	for row: Dictionary in legacy.units:
		for field: String in ["combat_ability", "exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "exchange_pose_duration", "exchange_skill"]:
			row.erase(field)
	assert(TerrainArmy.valid_combat_state(legacy, data))
	var restored := TerrainArmy.new()
	root.add_child(restored)
	restored.set_process(false)
	restored.exchange_enabled = true
	restored.restore_combat_state(legacy, data, null, null)
	assert(restored.exchange_stats(0).ability == 50.0 and restored.combat_units[8].hp == 0.0)
	assert(restored.cells == army.cells and restored.combat_identity(8) == death_identity)
	restored.prepare_combat(0.1)
	assert(contact_calls == 0 and aim_calls == 0)
	restored.clear()
	army.clear()
	restored.queue_free()
	army.queue_free()
	await process_frame
	print("SITE_EXCHANGE_ARMY_PASS: exact 1/2 HP, draw/hit/knockback locks, legal reservations, winner movement, original KO/death, consumed skill cooldown, JSON optional fields, no geometry queries")
	quit(0)
