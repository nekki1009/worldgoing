extends SceneTree
## STAGED SOURCE-HOOK CHECK. Copy to a .gd path only after shared hooks merge.
## Original Actor/Army/Lab methods run; OfferProbe observes call timing only.
## Positive case requires canonical visual mode: original contact rigs load real
## GLTF meshes/materials. This is a source-hook check, not GPU image acceptance.
## No AudioServer playback, listener, ConfigFile, battle/clock replacement,
## physical-flight admission, GPU, listening or performance acceptance.
## Default: positive paths. -- --case=preflight_refusal|prepare_refusal|finish_refusal
## runs one intentional original ERROR branch. Those modes are expected canonical
## FAIL receipts despite EXPECTED_REFUSAL/exit 0; never mask or fold into normal PASS.

class OfferProbe extends SiteAudioView:
	var calls: Array[Dictionary] = []
	var finish_query: Callable
	func offer(kind: StringName, ground: Vector2, event_key: String, person_id: int = 0,
			duration: float = 0.0, mounted: bool = false) -> bool:
		calls.append({"kind": kind, "ground": ground, "key": event_key, "person_id": person_id,
			"duration": duration, "mounted": mounted,
			"finishes": int(finish_query.call()) if finish_query.is_valid() else 0})
		return true # Caller observation only; presenter admission has its own test.

class HookActor extends TerrainTestCharacter:
	var preparations := 0
	var contacts := 0
	var finishes := 0
	var refuse_prepare := false
	var break_partner_before_finish: TerrainTestCharacter
	func exchange_batch_prepare(other_cell: Vector2i, outcome: Dictionary) -> Dictionary:
		preparations += 1
		return {} if refuse_prepare else super.exchange_batch_prepare(other_cell, outcome)
	func exchange_batch_contact(outcome: Dictionary) -> void:
		super.exchange_batch_contact(outcome)
		contacts += 1
		if is_instance_valid(break_partner_before_finish):
			# Deliberate stale original identity AFTER the last contact, so the true
			# Lab finish phase guard refuses. No alternate settlement implementation.
			break_partner_before_finish.person_id += 900000
	func exchange_batch_finish(other_cell: Vector2i, outcome: Dictionary, prepared: Dictionary) -> void:
		super.exchange_batch_finish(other_cell, outcome, prepared)
		finishes += 1

var checks := 0
var mode := "positive"
var completed := false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			mode = argument.trim_prefix("--case=")
	create_timer(20.0, true, false, true).timeout.connect(func() -> void:
		if not completed:
			push_error("Source hook test exceeded its 20-second deadline")
			quit(1))
	_run.call_deferred()


func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		push_error("SOURCE_HOOK_CHECK: " + label)
	return value


func _run() -> void:
	if mode == "positive" and DisplayServer.get_name() == "headless":
		print("SOURCE_HOOK_TEST_BLOCKED_DUMMY_RENDERER: positive source hooks require canonical visual mode; original 770A headless FAIL remains preserved")
		completed = true
		quit(2)
		return
	var sample_lab := TerrainLab.new()
	var sample_actor := TerrainTestCharacter.new()
	var sample_army := TerrainArmy.new()
	var merged := sample_lab.has_method("_audio_step_completed") and sample_lab.has_method("_audio_exchange_snapshot") \
		and sample_lab.has_method("_audio_exchange_take") and sample_lab.has_method("_audio_ranged_contact") \
		and sample_actor.has_method("clear_audio_step_sources") and sample_army.has_method("clear_audio_step_sources")
	var material_argument := false
	for method: Dictionary in sample_lab.get_method_list():
		if str(method.name) == "_audio_ranged_contact":
			material_argument = (method.args as Array).size() >= 6
	sample_actor.free()
	sample_army.free()
	sample_lab.free()
	if not merged or not material_argument:
		print("SOURCE_HOOK_TEST_BLOCKED_MISSING_SHARED_HOOKS: requires MOVEMENT_HOOKS + final SHARED_HOOK_PACKET/material argument; no source-hook PASS")
		completed = true
		quit(2)
		return
	if mode in ["preflight_refusal", "prepare_refusal", "finish_refusal"]:
		_finish(_negative_refusal(mode), true)
		return
	if mode != "positive":
		push_error("Unknown source hook case: " + mode)
		_finish(false)
		return
	if not _actor_steps() or not _army_step() or not _exchange_success() or not _queue_same_frame() \
			or not _queue_epoch_change() or not _queued_top64() or not _material_dispatch():
		_finish(false)
		return
	_finish(await _queue_cross_frame())


func _map() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(48, 48))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(data.size.x * data.size.y)
	data.feature_at.resize(data.size.x * data.size.y)
	data.water_kind.resize(data.size.x * data.size.y)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0}
	return data


func _fixture() -> Dictionary:
	var lab := TerrainLab.new()
	lab.terrain = _map()
	var probe := OfferProbe.new()
	lab.set("audio_view", probe)
	var actors: Array[TerrainTestCharacter] = []
	lab.combat_actors = actors
	probe.finish_query = func() -> int:
		var count := 0
		for actor: HookActor in lab.combat_actors:
			count += actor.finishes
		return count
	return {"lab": lab, "probe": probe, "actors": actors}


func _actor(fixture: Dictionary, identity: int, cell: Vector2i, faction: int = 0) -> HookActor:
	var lab: TerrainLab = fixture.lab
	var actor := HookActor.new()
	actor.data = lab.terrain
	actor.person_id = identity
	actor.faction_id = faction
	actor.exchange_enabled = true
	actor._saved_appearance = {"parts": {"weapon": "longsword_01", "armor": "armor_light_leather_01", "shield": "none"}}
	lab.combat_actors.append(actor)
	actor.combatants = func() -> Array[TerrainTestCharacter]: return lab.combat_actors
	actor.combat_target_query = lab._combat_target
	actor.set("audio_step_sink", Callable(lab, "_audio_step_completed"))
	assert(actor.place(cell, true), "Original actor fixture placement must be legal")
	if lab.character == null:
		lab.character = actor
	return actor


func _drop(fixture: Dictionary) -> void:
	for actor: TerrainTestCharacter in fixture.lab.combat_actors:
		actor.combatants = Callable()
		actor.combat_target_query = Callable()
		actor.free()
	for team: TerrainArmy in fixture.lab.combat_armies:
		team.free()
	fixture.probe.free()
	fixture.lab.free()


func _actor_steps() -> bool:
	var fixture := _fixture()
	var actor := _actor(fixture, 1, Vector2i(15, 15))
	var probe: OfferProbe = fixture.probe
	var okay := true
	for running: bool in [false, true]:
		actor.reset_combat()
		assert(actor.place(Vector2i(15, 15), true))
		probe.calls.clear()
		var duration := actor.get_move_interval(running)
		okay = _check(actor.step(Vector2i.RIGHT, running), "real Actor.step admitted walk/run") and okay
		actor._advance_movement(duration * 0.5)
		okay = _check(probe.calls.is_empty(), "Actor does not offer before the actual movement endpoint") and okay
		actor._advance_movement(duration * 0.5 + 0.000001)
		actor._advance_movement(duration)
		okay = _check(probe.calls.size() == 1, "one real step endpoint offers exactly once") and okay
		if probe.calls.size() == 1:
			var row: Dictionary = probe.calls[0]
			okay = _check(row.kind == (&"step_grass_run" if running else &"step_grass_walk") \
				and int(row.person_id) == actor.person_id and row.ground == actor.position \
				and is_equal_approx(float(row.duration), duration), "Actor hook carries original person/ground/duration/gait") and okay
	actor.reset_combat()
	probe.calls.clear()
	assert(actor.place(Vector2i(15, 15), true) and actor.place(Vector2i(16, 15), false))
	actor._advance_movement(10.0)
	okay = _check(probe.calls.is_empty(), "plain animated place is not a legal step source") and okay
	assert(actor.place(Vector2i(15, 15), true))
	var outcome := {"role": "loser", "kind": "big", "knockback": true, "hp": 0.0, "stun": 0.0, "stagger": 0.0, "fatigue": 0.0}
	var prepared := actor.exchange_batch_prepare(Vector2i(14, 15), outcome)
	actor.exchange_batch_knockback(Vector2i(14, 15), outcome, prepared)
	okay = _check(actor.is_moving(), "true original knockback reserved an animated displacement") and okay
	actor._advance_movement(10.0)
	okay = _check(probe.calls.is_empty(), "knockback completion is not a footstep") and okay
	for refusal: String in ["cancel", "KO", "dead", "epoch"]:
		actor.reset_combat()
		assert(actor.place(Vector2i(15, 15), true) and actor.step(Vector2i.RIGHT))
		probe.calls.clear()
		match refusal:
			"cancel": actor.cancel_invalid_structure_step({actor.data.index(actor.movement_from_cell): true})
			"KO": actor.knockout_left = 100.0
			"dead": actor.hp = 0.0
			"epoch": actor.call("clear_audio_step_sources")
		actor._advance_movement(10.0)
		okay = _check(probe.calls.is_empty(), "real Actor %s source does not offer a footstep" % refusal) and okay
	_drop(fixture)
	return okay


func _army_step() -> bool:
	var fixture := _fixture()
	_actor(fixture, 1, Vector2i(15, 15))
	var lab: TerrainLab = fixture.lab
	var probe: OfferProbe = fixture.probe
	var team := TerrainArmy.new()
	team.team_id = 7
	team.faction_id = 0
	team.exchange_enabled = true
	team.shared_fatigue_enabled = false
	team.roster_size = 2
	# Native editor _ready builds its UI before original deploy opens the rig.
	# Only this test driver supplies ticks; movement/contact owners stay original.
	team.set_process(false)
	root.add_child(team)
	var cells: Array[Vector2i] = [Vector2i(17, 15), Vector2i(18, 15)]
	if not _check(team.deploy_at(lab.terrain, null, null, cells) and team.enable_combat(false), "existing two-member original Army fixture deploys"):
		team.free()
		_drop(fixture)
		return false
	lab.combat_armies.append(team)
	team.set("audio_step_sink", Callable(lab, "_audio_step_completed"))
	var identity := team.combat_identity(1)
	var destination := cells[1] + Vector2i.UP
	var okay := _check(team._reserve_combat_step(1, destination), "true Army owner reserves a legal step")
	var duration := float(team.move_duration[1])
	team.prepare_combat(duration * 0.5)
	okay = _check(probe.calls.is_empty(), "Army source does not offer before completion") and okay
	team.prepare_combat(duration * 0.5 + 0.000001)
	okay = _check(team.cells[1] == destination and probe.calls.size() == 1, "real Army completion offers once after the original cell commit") and okay
	if probe.calls.size() == 1:
		okay = _check(int(probe.calls[0].person_id) == identity and probe.calls[0].ground == team.combat_ground(1) \
			and is_equal_approx(float(probe.calls[0].duration), duration), "Army hook uses the original committed person/ground/duration") and okay
	probe.calls.clear()
	okay = _check(team._reserve_combat_step(1, destination + Vector2i.UP), "Army second legal reservation") and okay
	team.combat_hot_set(1, &"ko", 100.0)
	team.prepare_combat(duration + 0.000001)
	okay = _check(probe.calls.is_empty(), "KO during real Army movement suppresses its footstep") and okay
	_drop(fixture)
	return okay


func _pair(a: HookActor, b: HookActor) -> Dictionary:
	var stats_a := a.exchange_stats()
	var stats_b := b.exchange_stats()
	stats_a.facility = 0.0
	stats_b.facility = 0.0
	return {"a": {"owner": a, "unit": -1, "id": a.person_id, "cell": a.terrain_cell},
		"b": {"owner": b, "unit": -1, "id": b.person_id, "cell": b.terrain_cell},
		"stats_a": stats_a, "stats_b": stats_b, "result": SiteCombatRules.exchange_result(stats_a, stats_b)}


func _two() -> Dictionary:
	var fixture := _fixture()
	var a := _actor(fixture, 1, Vector2i(15, 15), 0)
	var b := _actor(fixture, 2, Vector2i(16, 15), 1)
	var pending: Array[Dictionary] = [_pair(a, b)]
	fixture.pending = pending
	fixture.a = a
	fixture.b = b
	return fixture


func _exchange_success() -> bool:
	var fixture := _two()
	var lab: TerrainLab = fixture.lab
	lab._exchange_round = 17
	var okay := _check(lab._settle_exchange_batch(fixture.pending), "actual Lab settles a successful original batch")
	okay = _check(not fixture.probe.calls.is_empty(), "successful final finish reaches the source offer hook") and okay
	for row: Dictionary in fixture.probe.calls:
		okay = _check(int(row.finishes) == 2 and str(row.key).begins_with("pair:17:1:2"), "every exchange offer happens after both original finish methods") and okay
	_drop(fixture)
	return okay


func _queue(fixture: Dictionary, source_round: int) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	lab._exchange_round = source_round
	lab._region_point_pending = {"interval_complete": true}
	assert(lab._settle_exchange_batch(fixture.pending))
	assert(lab._region_point_contacts.size() == 1)
	return lab._region_point_contacts[0]


func _consume(fixture: Dictionary, event: Dictionary) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	lab._region_point_consuming = true
	var result := lab._region_point_effect(event)
	lab._region_point_consuming = false
	return result


func _queue_same_frame() -> bool:
	var fixture := _two()
	var event := _queue(fixture, 31)
	var lab: TerrainLab = fixture.lab
	var okay := _check(fixture.probe.calls.is_empty() and fixture.a.preparations == 0, "real Region queue is not a successful offer or body settlement")
	lab._exchange_round = 77
	okay = _check(bool(_consume(fixture, event).ok), "actual queued endpoint settles within this display frame") and okay
	okay = _check(not fixture.probe.calls.is_empty(), "same-frame queued success reaches offer") and okay
	for row: Dictionary in fixture.probe.calls:
		okay = _check(str(row.key).begins_with("pair:31:1:2") and int(row.finishes) == 2, "queue retains source round and waits for all original finishes") and okay
	_drop(fixture)
	return okay


func _queue_cross_frame() -> bool:
	var fixture := _two()
	var event := _queue(fixture, 41)
	var source_frame := Engine.get_process_frames()
	await process_frame
	await process_frame
	var okay := _check(Engine.get_process_frames() > source_frame, "cross-frame queue test advanced the actual display frame")
	okay = _check(bool(_consume(fixture, event).ok) and fixture.a.finishes == 1 and fixture.b.finishes == 1, "expired audio does not cancel the original endpoint settlement") and okay
	okay = _check(fixture.probe.calls.is_empty(), "queued source audio from a prior display frame is discarded") and okay
	_drop(fixture)
	return okay


func _queue_epoch_change() -> bool:
	var fixture := _two()
	var event := _queue(fixture, 43)
	fixture.probe.invalidate_epoch()
	var okay := _check(bool(_consume(fixture, event).ok) and fixture.probe.calls.is_empty(), "epoch change drops queued source offers without changing original body settlement")
	_drop(fixture)
	return okay


func _queued_top64() -> bool:
	var fixture := _fixture()
	var lab: TerrainLab = fixture.lab
	var probe: OfferProbe = fixture.probe
	var listener := _actor(fixture, 1, Vector2i(20, 20))
	var far: Array[Dictionary] = []
	var identity := 2
	for y in range(11, 30):
		for x in range(11, 29, 2):
			var point := Vector2(float(x + 1), float(y) + 0.5) * 64.0
			var distance := point.distance_to(listener.position)
			if far.size() >= 65 or distance < 256.0 or distance >= 640.0:
				continue
			var a := _actor(fixture, identity, Vector2i(x, y), 0)
			var b := _actor(fixture, identity + 1, Vector2i(x + 1, y), 1)
			identity += 2
			far.append(_pair(a, b))
	var a := _actor(fixture, identity, Vector2i(21, 20), 0)
	var b := _actor(fixture, identity + 1, Vector2i(22, 20), 1)
	var near: Array[Dictionary] = [_pair(a, b)]
	var all_pairs: Array[Dictionary] = far.duplicate()
	all_pairs.append_array(near)
	lab._exchange_round = 47
	var rows: Array[Dictionary] = lab.call("_audio_exchange_snapshot", all_pairs, 47)
	var near_key := "pair:47:%d:%d" % [identity, identity + 1]
	var okay := _check(far.size() == 65 and rows.size() == 64, "actual snapshot has a bounded 64-row pool after 66 admitted original pairs")
	var found := false
	for row: Dictionary in rows:
		found = found or str(row.key) == near_key
	okay = _check(found, "closer final original pair replaces weaker first-64 source candidates") and okay
	lab._region_point_pending = {"interval_complete": true}
	okay = _check(lab._settle_exchange_batch(far) and lab._settle_exchange_batch(near), "two true batches enter the original queue") and okay
	okay = _check(probe.calls.is_empty() and lab._region_point_contacts.size() == 2, "queued Top64 retains no premature source offers") and okay
	for event: Dictionary in lab._region_point_contacts:
		okay = _check(bool(_consume(fixture, event).ok), "original queued Top64 body endpoint succeeds") and okay
	found = false
	for row: Dictionary in probe.calls:
		found = found or str(row.key) == near_key
		okay = _check(int(row.finishes) >= 130, "queued source offers follow every finish in their own original batch") and okay
	okay = _check(probe.calls.size() == 64 and found, "queued aggregate stays Top64 and retains the late nearby pair") and okay
	_drop(fixture)
	return okay


func _material_dispatch() -> bool:
	var fixture := _two()
	var lab: TerrainLab = fixture.lab
	var probe: OfferProbe = fixture.probe
	# Pure caller dispatch table, deliberately not a constructed flight/impact.
	for row: Dictionary in [{"material": "", "shield": false, "kind": &"impact_ground"},
		{"material": "wood", "shield": false, "kind": &"impact_wood"},
		{"material": "metal", "shield": false, "kind": &"impact_metal"},
		{"material": "wood", "shield": true, "kind": &"shield"}]:
		probe.calls.clear()
		lab.call("_audio_ranged_contact", fixture.a.position, "dispatch:test", {"kind": "hit", "hp": 0.0}, 0, row.shield, row.material)
		if not _check(probe.calls.size() == 1 and probe.calls[0].kind == row.kind, "true Lab source material/shield dispatch table"):
			_drop(fixture)
			return false
	probe.calls.clear()
	lab.call("_audio_ranged_contact", fixture.a.position, "dispatch:miss", {"kind": "miss", "hp": 0.0}, 0, false, "wood")
	var okay := _check(probe.calls.is_empty(), "source miss dispatch has no contact offer")
	_drop(fixture)
	return okay


func _negative_refusal(which: String) -> bool:
	var fixture := _two()
	match which:
		"preflight_refusal": fixture.pending[0].a.id += 900000
		"prepare_refusal": fixture.b.refuse_prepare = true
		"finish_refusal": fixture.b.break_partner_before_finish = fixture.a
	var refused: bool = not fixture.lab._settle_exchange_batch(fixture.pending)
	var okay := _check(refused and fixture.probe.calls.is_empty(), "true Lab %s returns false without any source offer" % which)
	okay = _check(fixture.a.finishes == 0 and fixture.b.finishes == 0, "refused batch never reaches successful original finish completion") and okay
	if which == "preflight_refusal":
		okay = _check(fixture.a.preparations == 0 and fixture.b.preparations == 0, "preflight failure charges/prepares no owner") and okay
	elif which == "prepare_refusal":
		okay = _check(fixture.a.contacts == 0 and fixture.b.contacts == 0, "prepare refusal reaches no contact phase") and okay
	else:
		okay = _check(fixture.a.contacts == 1 and fixture.b.contacts == 1, "finish refusal occurs after the actual original contact phase") and okay
	print("EXPECTED_REFUSAL: ", which, " asserted=", okay, "; original ERROR is preserved; expected canonical FAIL receipt")
	_drop(fixture)
	return okay


func _finish(okay: bool, negative: bool = false) -> void:
	completed = true
	print("SITE_AUDIO_SOURCE_HOOK_", "EXPECTED_REFUSAL_CHECK" if negative else "PASS" if okay else "FAIL",
		" case=", mode, " checks=", checks, " okay=", okay,
		"; original source hooks only; no real audio, full Region/shared-clock/Native admission, GPU, performance or listening claim")
	quit(0 if okay else 1)
