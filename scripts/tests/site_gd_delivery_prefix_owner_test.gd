extends "res://scripts/tests/site_workflow_test.gd"
## Original delivery owner / original fixed ACTION_STEP caller. Canonical visual.
## Explicit stationary starting geometry/finite food/fatigue inputs; no movement,
## fixed World birth, Native, real-contact or release-performance claim.
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _near(actual: float, expected: float, label: String) -> void:
	assert(absf(actual - expected) < 0.000001, "%s %.12f != %.12f" % [label, actual, expected])

func _delivery_lab() -> Dictionary:
	var lab := TerrainLab.new()
	lab.exchange_enabled = false
	lab.pause_when_unfocused = false
	root.add_child(lab)
	for owner: Node in [lab, lab.character, lab.npc, lab.site_controller, lab.army, lab.opposing_army]: owner.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data: TerrainData = _fixture()
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	lab.npc.faction_id = lab.character.faction_id
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	assert(lab.character.place(Vector2i(21, 22), true) and lab.npc.place(Vector2i(35, 35), true))
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(22, 22), Vector2i(23, 22), Vector2i(22, 23), Vector2i(23, 23)]
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	data.site.army_next_team = team.team_id + 1 # Explicit deployment's original allocator checkpoint.
	var controller: SiteController = lab.site_controller
	controller.initialize_team_items(team)
	data.site.manual.cargo.clear()
	Runtime.add_items(data.site.manual.cargo, {"grain": 8}) # Finite starting private food only.
	var receiver: int = team.combat_identity(0)
	assert(lab.controlled_person_id() == lab.character.person_id)
	Fatigue.write(lab.character, "fatigue", 40.0)
	Fatigue.write(team.combat_units[0], "fatigue", 40.003)
	var begun: Dictionary = controller.begin_team_food(team, 4, receiver)
	assert(begun.ok, str(begun))
	var entry: Dictionary = controller._supply_entry(team)
	assert(entry.delivery.player_id == lab.character.person_id and entry.delivery.representative_id == receiver)
	assert(is_same(entry.delivery.source_cargo, data.site.manual.cargo) and is_same(entry.delivery.receiver_body, team.combat_units[0]))
	return {"lab": lab, "data": data, "controller": controller, "team": team, "entry": entry, "job": entry.delivery, "receiver": receiver}

func _close(f: Dictionary) -> void:
	assert(f.lab._region_point_pending.is_empty() and f.lab._shared_work_plan.is_empty())
	f.controller.work_team.discard_prepared_interval()
	f.lab.free()

func _digest(f: Dictionary) -> Dictionary:
	return {"source": f.data.site.manual.cargo.duplicate(true), "stock": f.controller._supply_stock(f.entry).duplicate(true),
		"state": f.entry.sustain.duplicate(true), "revision": int(f.entry.revision), "player_fatigue": Fatigue.read(f.lab.character),
		"team_fatigue": Fatigue.read(f.team.combat_units[0]), "at": Runtime.now(f.data), "remaining": f.entry.delivery.duplicate(true)}

func _case(chunks: Array) -> Dictionary:
	var f: Dictionary = _delivery_lab()
	var source: PackedByteArray = var_to_bytes([f.data.site.manual.cargo, f.entry, f.team.capture_combat_state()])
	var projected: Dictionary = f.controller.food_delivery.prepare_completion(f.team, f.entry)
	assert(projected.ok and f.controller.food_delivery.validate_prepared_completion(projected))
	assert(var_to_bytes([f.data.site.manual.cargo, f.entry, f.team.capture_combat_state()]) == source, "Original resupply preparation changes no food/life/job/pool")
	assert(f.controller.food_delivery.prepare_completion(f.team, f.entry, true).code == "INCOMPLETE", "A source projection is no completed timer witness")
	var forged: Dictionary = projected.duplicate(false)
	forged.state = projected.state.duplicate(true)
	forged.state.morale = float(forged.state.morale) + 1.0
	assert(not f.controller.food_delivery.validate_prepared_completion(forged) and var_to_bytes([f.data.site.manual.cargo, f.entry, f.team.capture_combat_state()]) == source)
	forged = projected.duplicate(false)
	forged.entry = f.entry.duplicate(false)
	assert(not f.controller.food_delivery.validate_prepared_completion(forged), "Equal amount entry clones are not the original supply owner")
	var before: float = Runtime.now(f.data)
	for seconds: float in chunks:
		f.lab._advance_action_time(seconds)
		assert(f.controller.original_step_fault_guard().ok and f.lab._region_point_pending.is_empty(), "Original complete point leaves no fault/pending checkpoint")
	assert(f.entry.delivery.is_empty() and f.data.site.manual.cargo.grain == 4)
	assert(not f.controller.food_delivery.validate_prepared_completion(projected), "Original transfer changed the source/version; prospective old candidate cannot be replayed")
	_near((Runtime.now(f.data) - before) * 60.0, 6.0, "Original peace clock consumes .1 actual seconds once")
	var result: Dictionary = _digest(f)
	var repeated: PackedByteArray = var_to_bytes([f.data.site.manual.cargo, f.entry])
	f.controller.settle_supply_deliveries()
	assert(var_to_bytes([f.data.site.manual.cargo, f.entry]) == repeated, "Actual original terminal repeats with no food/revision effects")
	_close(f)
	return result

func _run() -> void:
	var whole: Dictionary = _case([0.1])
	var split: Dictionary = _case([0.04, 0.06])
	assert(whole.source == split.source and whole.stock == split.stock and whole.state == split.state and whole.revision == split.revision and whole.remaining.is_empty() and split.remaining.is_empty())
	_near(float(whole.player_fatigue), float(split.player_fatigue), "Source person's real once fatigue is partition invariant")
	_near(float(whole.team_fatigue), float(split.team_fatigue), "Receiver's original shared pool is partition invariant")
	_near(float(whole.at), float(split.at), "Once common Site timer")
	var cancelled: Dictionary = _delivery_lab()
	cancelled.lab._advance_action_time(TerrainLab.ACTION_STEP)
	assert(not cancelled.entry.delivery.is_empty() and float(cancelled.entry.delivery.left) < 2.8 and cancelled.data.site.manual.cargo.grain == 8)
	assert(cancelled.controller.cancel_team_food().ok)
	cancelled.lab._advance_action_time(0.1)
	assert(cancelled.entry.delivery.is_empty() and cancelled.data.site.manual.cargo.grain == 8, "True cancel consumes no food and never creates a replacement delivery")
	_close(cancelled)
	TerrainArmy.release_contact_source()
	print("GD_CONTACT_DELIVERY_OWNER_PASS scope=original_finite_source_projection_real_joint_maincaller_partition_cancel_once_only contact_native_world_not_claimed")
	quit(0)
