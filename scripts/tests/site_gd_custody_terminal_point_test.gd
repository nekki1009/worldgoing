extends "res://scripts/tests/fixtures/site_terminal_first_error_test.gd"
## Warm original custody transactions. Inherited authored building ground and
## explicit incapacitation/recovery are physical inputs, not geography proof.
## Capture/unbind/prison use actual shared ACTION_STEPs. Ransom below is an
## honest original work-pool/PA endpoint component, with no main-clock claim.

const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Social = preload("res://scripts/terrain_lab/person_social.gd")

func _initialize() -> void:
	_install_terminal_guard()
	deadline = Time.get_ticks_msec() + 180000
	if not _guard(): return
	_run.call_deferred()
	if not _guard(): return

func _custody_bytes(lab: TerrainLab) -> PackedByteArray:
	var teams: Array = []
	for team: TerrainArmy in lab.combat_armies:
		if not _guard(): return PackedByteArray()
		teams.append(team.capture_combat_state())
		if not _guard(): return PackedByteArray()
	return var_to_bytes([lab.terrain.site, lab.character.capture_state(), lab.npc.capture_state(), teams])

func _actual_custody_job(lab: TerrainLab, identity: int) -> float:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var game_seconds: float = 0.0
	for tick: int in range(6000):
		if not _guard(): return -1.0
		var _terminal_check_1: bool = Time.get_ticks_msec() < deadline
		if not _must(_terminal_check_1, "C36 custody _actual_custody_job:25 original assertion"): return -1.0
		assert(_terminal_check_1, "C36 custody _actual_custody_job:25 original assertion")
		if not actions.is_busy(identity): return game_seconds
		var point: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		if not _guard(): return -1.0
		var _terminal_check_2: bool = point.ok and point.get("completed", false) and float(point.game_seconds) > 0.0
		if not _must(_terminal_check_2, str(point)): return -1.0
		assert(_terminal_check_2, str(point))
		game_seconds += float(point.game_seconds)
		if not _guard(): return -1.0
	var _terminal_check_3: bool = false
	if not _must(_terminal_check_3, "Original custody job must terminate in a bounded actual point run"): return -1.0
	assert(_terminal_check_3, "Original custody job must terminate in a bounded actual point run")
	return game_seconds

func _capture_candidate_refusals(lab: TerrainLab) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var job: Dictionary = actions._jobs[str(lab.character.person_id)]
	if not _guard(): return false
	var before: PackedByteArray = _custody_bytes(lab)
	if not _guard(): return false
	var _terminal_check_4: bool = not actions.prepare_gd_custody_terminal(job).ok and float(job.elapsed) == 0.0
	if not _must(_terminal_check_4, "C36 custody _capture_candidate_refusals:37 original assertion"): return false
	assert(_terminal_check_4, "C36 custody _capture_candidate_refusals:37 original assertion")
	var source: Dictionary = actions.prepare_gd_custody_terminal(job, true)
	if not _guard(): return false
	var _terminal_check_5: bool = source.ok and source.source_only and actions.validate_gd_custody_terminal(source).ok
	if not _must(_terminal_check_5, "C36 custody _capture_candidate_refusals:39 original assertion"): return false
	assert(_terminal_check_5, "C36 custody _capture_candidate_refusals:39 original assertion")
	var _terminal_check_6: bool = _custody_bytes(lab) == before
	if not _must(_terminal_check_6, "True current source preview cannot create time, loot, captivity or supply history"): return false
	assert(_terminal_check_6, "True current source preview cannot create time, loot, captivity or supply history")
	var forged: Dictionary = source.duplicate(false)
	if not _guard(): return false
	forged.source_only = false
	var _terminal_check_7: bool = not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before
	if not _must(_terminal_check_7, "C36 custody _capture_candidate_refusals:43 original assertion"): return false
	assert(_terminal_check_7, "C36 custody _capture_candidate_refusals:43 original assertion")
	forged = source.duplicate(false)
	if not _guard(): return false
	forged.next_relation = source.next_relation.duplicate(true)
	if not _guard(): return false
	forged.next_relation.episode = "other-site:999"
	var _terminal_check_8: bool = not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before
	if not _must(_terminal_check_8, "C36 custody _capture_candidate_refusals:47 original assertion"): return false
	assert(_terminal_check_8, "C36 custody _capture_candidate_refusals:47 original assertion")
	var holder: Dictionary = lab.npc.item_state
	lab.npc.item_state = holder.duplicate(true)
	if not _guard(): return false
	var _terminal_check_9: bool = not actions.validate_gd_custody_terminal(source).ok
	if not _must(_terminal_check_9, "Equal replacement holder cannot impersonate this current original target"): return false
	assert(_terminal_check_9, "Equal replacement holder cannot impersonate this current original target")
	lab.npc.item_state = holder
	var _terminal_check_10: bool = _custody_bytes(lab) == before
	if not _must(_terminal_check_10, "C36 custody _capture_candidate_refusals:52 original assertion"): return false
	assert(_terminal_check_10, "C36 custody _capture_candidate_refusals:52 original assertion")
	var guard: Callable = actions.captivity_change_guard
	actions.captivity_change_guard = func(_target: int, _captor: int, _capturing: bool) -> Dictionary: return Runtime.fail("TEST_SUPPLY")
	if not _guard(): return false
	var _terminal_check_11: bool = not actions.prepare_gd_custody_terminal(job, true).ok and _custody_bytes(lab) == before
	if not _must(_terminal_check_11, "C36 custody _capture_candidate_refusals:55 original assertion"): return false
	assert(_terminal_check_11, "C36 custody _capture_candidate_refusals:55 original assertion")
	actions.captivity_change_guard = guard
	var _terminal_check_12: bool = actions.validate_gd_custody_terminal(source).ok
	if not _must(_terminal_check_12, "C36 custody _capture_candidate_refusals:57 original assertion"): return false
	assert(_terminal_check_12, "C36 custody _capture_candidate_refusals:57 original assertion")
	return true

func _actual_capture_release(prison: bool) -> bool:
	var data: TerrainData = _building_fixture()
	if not _guard(): return false
	data.site.worker.cargo = {"arrow": 2} # Explicit finite original target cargo.
	var lab: TerrainLab = _building_lab(data)
	if not _guard(): return false
	var actions: SitePersonActions = lab.site_controller.person_actions
	var prison_id: String = _formal_feature(data, "prison", Vector2i(35, 35)) if prison else ""
	var _terminal_check_13: bool = lab.character.place(Vector2i(35, 38), true) and lab.npc.place(Vector2i(34, 38), true)
	if not _must(_terminal_check_13, "C36 custody _actual_capture_release:65 original assertion"): return false
	assert(_terminal_check_13, "C36 custody _actual_capture_release:65 original assertion")
	lab.npc.faction_id = 2 if prison else 1
	lab.npc.knockout_left = 60.0 # Named original incapacitated physical input.
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	if not _guard(): return false
	var target_id: int = lab.npc.person_id
	var guard_id: int = lab.character.person_id
	var holder: Dictionary = lab.npc.item_state
	var cargo: Dictionary = data.site.worker.cargo
	var sealed: Dictionary = actions._sealed_selection(actions._person(target_id))
	if not _guard(): return false
	var _terminal_check_14: bool = sealed.resources.get("arrow", 0) == 2
	if not _must(_terminal_check_14, "C36 custody _actual_capture_release:74 original assertion"): return false
	assert(_terminal_check_14, "C36 custody _actual_capture_release:74 original assertion")
	var next_loot: int = int(data.site.next_loot)
	if not _guard(): return false
	var sequence: int = int(data.site.get("capture_episode_next", 1))
	if not _guard(): return false
	var person_sequence: int = int(Social.read(lab.npc).get("capture_seq", 0))
	if not _guard(): return false
	var version: int = int(holder.version)
	if not _guard(): return false
	var fatigue_before: float = lab.character.fatigue
	var _terminal_check_15: bool = actions.begin_capture(guard_id, target_id, guard_id).ok
	if not _must(_terminal_check_15, "C36 custody _actual_capture_release:80 original assertion"): return false
	assert(_terminal_check_15, "C36 custody _actual_capture_release:80 original assertion")
	if not _capture_candidate_refusals(lab): return false
	var _terminal_check_16: bool = _actual_custody_job(lab, guard_id) >= SitePersonActions.BIND_SECONDS - 0.0001
	if not _must(_terminal_check_16, "C36 custody _actual_capture_release:82 original assertion"): return false
	assert(_terminal_check_16, "C36 custody _actual_capture_release:82 original assertion")
	var _terminal_check_17: bool = lab.npc.captive and data.site.captivity.has(str(target_id)) and lab.character.fatigue > fatigue_before
	if not _must(_terminal_check_17, "C36 custody _actual_capture_release:83 original assertion"): return false
	assert(_terminal_check_17, "C36 custody _actual_capture_release:83 original assertion")
	var relation: Dictionary = data.site.captivity[str(target_id)]
	if not _guard(): return false
	var _terminal_check_18: bool = relation.version == 3 and relation.episode == {"site_id": str(data.site.id), "person_id": target_id, "seq": person_sequence + 1} and int(data.site.capture_episode_next) == sequence + 1
	if not _must(_terminal_check_18, "C36 custody _actual_capture_release:85 original assertion"): return false
	assert(_terminal_check_18, "C36 custody _actual_capture_release:85 original assertion")
	var _terminal_check_19: bool = int(Social.read(lab.npc).capture_seq) == person_sequence + 1
	if not _must(_terminal_check_19, "Capture increments the original person sequence exactly once"): return false
	assert(_terminal_check_19, "Capture increments the original person sequence exactly once")
	var _terminal_check_20: bool = relation.captured_at_game_seconds <= Runtime.now(data) * 60.0 and relation.admitted_at_game_seconds == -1.0
	if not _must(_terminal_check_20, "C36 custody _actual_capture_release:87 original assertion"): return false
	assert(_terminal_check_20, "C36 custody _actual_capture_release:87 original assertion")
	var _terminal_check_21: bool = relation.sealed_container == str(next_loot) and int(data.site.next_loot) == next_loot + 1 and int(holder.version) == version + 2
	if not _must(_terminal_check_21, "C36 custody _actual_capture_release:88 original assertion"): return false
	assert(_terminal_check_21, "C36 custody _actual_capture_release:88 original assertion")
	var ground: Dictionary = data.site.ground_loot[str(next_loot)]
	if not _guard(): return false
	var _terminal_check_22: bool = ground.original_owner == target_id and ground.kind == "sealed" and ground.cargo.get("arrow", 0) == 2
	if not _must(_terminal_check_22, "C36 custody _actual_capture_release:90 original assertion"): return false
	assert(_terminal_check_22, "C36 custody _actual_capture_release:90 original assertion")
	var _terminal_check_23: bool = ground.item_ids == sealed.item_ids and ground.equipped.is_empty() and is_same(lab.npc.item_state, holder) and is_same(data.site.worker.cargo, cargo)
	if not _must(_terminal_check_23, "C36 custody _actual_capture_release:91 original assertion"): return false
	assert(_terminal_check_23, "C36 custody _actual_capture_release:91 original assertion")
	# Explicit physical recovery lets original admission/release predicates run;
	# neither the capture transaction nor these checks claim healing mechanics.
	lab.npc.knockout_left = 0.0
	lab.npc.stun = 0.0
	lab.npc._getting_up = false
	lab.npc.action_time = 0.0
	if prison:
		var layout: Dictionary = Runtime.prison_layout(data, prison_id)
		if not _guard(): return false
		var _terminal_check_24: bool = layout.ok and layout.slots.size() == 1
		if not _must(_terminal_check_24, "C36 custody _actual_capture_release:100 original assertion"): return false
		assert(_terminal_check_24, "C36 custody _actual_capture_release:100 original assertion")
		var slot: Dictionary = layout.slots[0]
		var _terminal_check_25: bool = lab.site_controller.captive_escort.begin_prison(guard_id, guard_id, prison_id).ok
		if not _must(_terminal_check_25, "C36 custody _actual_capture_release:102 original assertion"): return false
		assert(_terminal_check_25, "C36 custody _actual_capture_release:102 original assertion")
		var arrived: bool = false
		for tick: int in range(6000):
			if not _guard(): return false
			var _terminal_check_26: bool = Time.get_ticks_msec() < deadline
			if not _must(_terminal_check_26, "C36 custody _actual_capture_release:105 original assertion"): return false
			assert(_terminal_check_26, "C36 custody _actual_capture_release:105 original assertion")
			if lab.npc.terrain_cell == slot.cell and lab.character.terrain_cell == slot.contact_cell \
				and actions._prison_stopped(actions._person(target_id)) and actions._prison_stopped(actions._person(guard_id)):
				arrived = true
				break
			var point: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
			if not _guard(): return false
			var _terminal_check_27: bool = point.ok and point.get("completed", false)
			if not _must(_terminal_check_27, str(point)): return false
			assert(_terminal_check_27, str(point))
		var _terminal_check_28: bool = arrived and actions.admit_prison(guard_id, target_id, prison_id).ok
		if not _must(_terminal_check_28, "C36 custody _actual_capture_release:112 original assertion"): return false
		assert(_terminal_check_28, "C36 custody _actual_capture_release:112 original assertion")
		var _terminal_check_29: bool = lab.site_controller.captive_escort.cancel(guard_id).ok and actions.prison_slot(target_id).ok
		if not _must(_terminal_check_29, "C36 custody _actual_capture_release:113 original assertion"): return false
		assert(_terminal_check_29, "C36 custody _actual_capture_release:113 original assertion")
	var hp: float = lab.npc.hp
	var ko: float = lab.npc.knockout_left
	var cell: Vector2i = lab.npc.terrain_cell
	version = int(holder.version)
	if not _guard(): return false
	if not prison:
		if not _must(actions.is_guarding(guard_id), "The true captor still guards this original outdoor captive"): return false
		var release_before: PackedByteArray = _custody_bytes(lab)
		var release_action_time: float = lab.character.action_time
		lab.character.action_time = 0.1 # Negative actual body lock; restore before checking the refusal.
		var locked_release: Dictionary = actions.begin_unbind(guard_id, target_id)
		lab.character.action_time = release_action_time
		if not _must(not locked_release.ok and locked_release.get("code") == "BUSY" and _custody_bytes(lab) == release_before,
			"Own-guard release never bypasses the original stopped/action lock or changes custody on refusal"): return false
	var release_begin: Dictionary = actions.begin_prison_release(guard_id, target_id) if prison else actions.begin_unbind(guard_id, target_id)
	if not _guard(): return false
	print("DIAG_ONLY C36_RELEASE_BEGIN ", {"prison": prison, "result": release_begin,
		"guard_busy": actions.is_busy(guard_id), "guard_can_act": lab.character.can_act(),
		"guard_cell": lab.character.terrain_cell, "target_cell": lab.npc.terrain_cell,
		"guard_faction": lab.character.faction_id, "target_faction": lab.npc.faction_id,
		"guard_action_time": lab.character.action_time, "target_captive": lab.npc.captive})
	if not _guard(): return false
	var _terminal_check_30: bool = release_begin.ok
	if not _must(_terminal_check_30, str(release_begin)): return false
	assert(_terminal_check_30, str(release_begin))
	var job: Dictionary = actions._jobs[str(guard_id)]
	if not _guard(): return false
	var source: Dictionary = actions.prepare_gd_custody_terminal(job, true)
	if not _guard(): return false
	var _terminal_check_31: bool = source.ok and source.loot.is_empty() and _actual_custody_job(lab, guard_id) >= SitePersonActions.BIND_SECONDS - 0.0001
	if not _must(_terminal_check_31, "C36 custody _actual_capture_release:127 original assertion"): return false
	assert(_terminal_check_31, "C36 custody _actual_capture_release:127 original assertion")
	var _terminal_check_32: bool = not lab.npc.captive and not data.site.captivity.has(str(target_id)) and int(holder.version) == version + 1
	if not _must(_terminal_check_32, "C36 custody _actual_capture_release:128 original assertion"): return false
	assert(_terminal_check_32, "C36 custody _actual_capture_release:128 original assertion")
	var _terminal_check_33: bool = lab.npc.hp == hp and lab.npc.knockout_left == ko and lab.npc.terrain_cell == cell and is_same(holder, lab.npc.item_state)
	if not _must(_terminal_check_33, "C36 custody _actual_capture_release:129 original assertion"): return false
	assert(_terminal_check_33, "C36 custody _actual_capture_release:129 original assertion")
	var _terminal_check_34: bool = not actions.validate_gd_custody_terminal(source).ok and int(data.site.next_loot) == next_loot + 1
	if not _must(_terminal_check_34, "C36 custody _actual_capture_release:130 original assertion"): return false
	assert(_terminal_check_34, "C36 custody _actual_capture_release:130 original assertion")
	var before: PackedByteArray = _custody_bytes(lab)
	if not _guard(): return false
	var _terminal_check_35: bool = actions.settle_after_contacts().is_empty() and _custody_bytes(lab) == before
	if not _must(_terminal_check_35, "C36 custody _actual_capture_release:132 original assertion"): return false
	assert(_terminal_check_35, "C36 custody _actual_capture_release:132 original assertion")
	lab.free()
	if not _guard(): return false
	return true

func _ransom_component() -> bool:
	var data: TerrainData = _building_fixture()
	if not _guard(): return false
	var lab: TerrainLab = _building_lab(data)
	if not _guard(): return false
	var actions: SitePersonActions = lab.site_controller.person_actions
	var controller: SiteController = lab.site_controller
	for team: TerrainArmy in [lab.army, lab.opposing_army]:
		if not _guard(): return false
		team.roster_size = 40
		var cells: Array[Vector2i] = []
		var origin: Vector2i = Vector2i(16, 16) if team == lab.army else Vector2i(22, 24)
		if not _guard(): return false
		for index: int in range(40): cells.append(origin + Vector2i(index % 8, floori(float(index) / 8.0)))
		cells[0] = Vector2i(21, 23) if team == lab.army else Vector2i(22, 23)
		if not _guard(): return false
		var _terminal_check_36: bool = team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false)
		if not _must(_terminal_check_36, "C36 custody _ransom_component:146 original assertion"): return false
		assert(_terminal_check_36, "C36 custody _ransom_component:146 original assertion")
		team.set_process(false)
		if not _guard(): return false
		team.faction_id = 1 if team == lab.army else 2
		team.settle_combat_command()
		if not _guard(): return false
	var payer: int = lab.army.combat_identity(lab.army.current_commander)
	if not _guard(): return false
	var representative: int = lab.opposing_army.combat_identity(lab.opposing_army.current_commander)
	if not _guard(): return false
	var target: Dictionary = lab.army.combat_units[1]
	var target_id: int = int(target.person_id)
	if not _guard(): return false
	target.ko = 100.0 # Named original captured initial physical input.
	var helper: Variant = controller.captivity_supply
	var _terminal_check_37: bool = helper.change_guard(target_id, representative, true).ok
	if not _must(_terminal_check_37, "C36 custody _ransom_component:156 original assertion"): return false
	assert(_terminal_check_37, "C36 custody _ransom_component:156 original assertion")
	var relation: Dictionary = {"version": 3, "captor_id": representative, "guard_id": representative, "captor_faction": 2, "sealed_container": "", "prison_id": ""}
	# D replaced Tech's static new_capture_fields(data) with SitePersonActions.capture_fields(target_id, target).
	if not _guard(): return false
	relation.merge(controller.person_actions.capture_fields(target_id, controller.person_actions._person(target_id)))
	if not _guard(): return false
	data.site.captivity[str(target_id)] = relation
	if not _guard(): return false
	target.captive = true
	helper.commit_change(target_id, representative, true)
	if not _guard(): return false
	var source: Dictionary = controller._supply_entry(lab.army)
	if not _guard(): return false
	var destination: Dictionary = controller._supply_entry(lab.opposing_army)
	if not _guard(): return false
	source.inventory = {"grain": 100} # Finite original-team initial ransom stock.
	destination.inventory = {}
	var original_revision: int = int(source.revision)
	if not _guard(): return false
	source.revision = 2147483647
	var before: PackedByteArray = _custody_bytes(lab)
	if not _guard(): return false
	var _terminal_check_38: bool = not helper.change_guard(target_id, representative, false).ok and _custody_bytes(lab) == before
	if not _must(_terminal_check_38, "A legal maximum original team revision refuses before membership cost"): return false
	assert(_terminal_check_38, "A legal maximum original team revision refuses before membership cost")
	source.revision = original_revision
	assert(controller._control_family_person(null, payer).ok) # Original fixture selection, no inheritance claim.
	var _terminal_check_39: bool = actions.begin_ransom(payer, target_id, representative).ok
	if not _must(_terminal_check_39, "C36 custody _ransom_component:173 original assertion"): return false
	assert(_terminal_check_39, "C36 custody _ransom_component:173 original assertion")
	var job: Dictionary = actions._jobs[str(payer)]
	if not _guard(): return false
	var upper: Dictionary = actions.prepare_gd_custody_terminal(job, true)
	if not _guard(): return false
	var _terminal_check_40: bool = upper.ok and upper.query.source == {"grain": 100}
	if not _must(_terminal_check_40, "C36 custody _ransom_component:176 original assertion"): return false
	assert(_terminal_check_40, "C36 custody _ransom_component:176 original assertion")
	before = _custody_bytes(lab)
	if not _guard(): return false
	var other_id: int = int(lab.army.combat_units[2].person_id)
	if not _guard(): return false
	var _terminal_check_41: bool = other_id != target_id and not actions._person(other_id).is_empty()
	if not _must(_terminal_check_41, "C36 custody _ransom_component:179 original assertion"): return false
	assert(_terminal_check_41, "C36 custody _ransom_component:179 original assertion")
	var forged: Dictionary = upper.duplicate(false)
	if not _guard(): return false
	forged.target = upper.target.duplicate(false)
	if not _guard(): return false
	forged.target.unit = 2 # Another genuine row cannot replace this held target.
	var _terminal_check_42: bool = not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before
	if not _must(_terminal_check_42, "C36 custody _ransom_component:183 original assertion"): return false
	assert(_terminal_check_42, "C36 custody _ransom_component:183 original assertion")
	forged = upper.duplicate(false)
	if not _guard(): return false
	forged.people = []
	var _terminal_check_43: bool = not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before
	if not _must(_terminal_check_43, "C36 custody _ransom_component:186 original assertion"): return false
	assert(_terminal_check_43, "C36 custody _ransom_component:186 original assertion")
	forged = upper.duplicate(false)
	if not _guard(): return false
	forged.people = upper.people.duplicate(false)
	if not _guard(): return false
	forged.people[1] = actions._gd_custody_person_snapshot(actions._person(other_id))
	if not _guard(): return false
	var _terminal_check_44: bool = not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before
	if not _must(_terminal_check_44, "C36 custody _ransom_component:190 original assertion"): return false
	assert(_terminal_check_44, "C36 custody _ransom_component:190 original assertion")
	# Genuine original PA work requests and original pool debit create the due
	# endpoint. This component does not publish a fake Site/World clock.
	var requests: Array[Dictionary] = actions.work_requests(float(job.duration))
	if not _guard(): return false
	var plan: Dictionary = Fatigue.plan_work_interval(requests, float(job.duration))
	if not _guard(): return false
	var _terminal_check_45: bool = plan.ok
	if not _must(_terminal_check_45, "C36 custody _ransom_component:195 original assertion"): return false
	assert(_terminal_check_45, "C36 custody _ransom_component:195 original assertion")
	lab._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	controller._shared_work_plan = plan
	var at: float = Runtime.now(data) * 60.0
	if not _guard(): return false
	lab._commit_shared_work_pools()
	if not _guard(): return false
	var progress: Dictionary = actions.advance(float(job.duration), {"jobs": plan.jobs.get("person_actions", {})})
	if not _guard(): return false
	var _terminal_check_46: bool = progress.handled_seconds.has(payer) and Runtime.now(data) * 60.0 == at
	if not _must(_terminal_check_46, "C36 custody _ransom_component:202 original assertion"): return false
	assert(_terminal_check_46, "C36 custody _ransom_component:202 original assertion")
	lab._clear_shared_work_step()
	if not _guard(): return false
	var _terminal_check_47: bool = float(job.elapsed) == float(job.duration)
	if not _must(_terminal_check_47, "C36 custody _ransom_component:204 original assertion"): return false
	assert(_terminal_check_47, "C36 custody _ransom_component:204 original assertion")
	var prepared: Dictionary = actions.prepare_gd_custody_terminal(job)
	if not _guard(): return false
	var _terminal_check_48: bool = prepared.ok and actions.validate_gd_custody_terminal(prepared).ok
	if not _must(_terminal_check_48, "C36 custody _ransom_component:206 original assertion"): return false
	assert(_terminal_check_48, "C36 custody _ransom_component:206 original assertion")
	var source_revision: int = int(source.revision)
	if not _guard(): return false
	var destination_revision: int = int(destination.revision)
	if not _guard(): return false
	var _terminal_check_49: bool = actions.publish_gd_custody_terminal(prepared).ok
	if not _must(_terminal_check_49, "C36 custody _ransom_component:209 original assertion"): return false
	assert(_terminal_check_49, "C36 custody _ransom_component:209 original assertion")
	var _terminal_check_50: bool = source.inventory.is_empty() and destination.inventory == {"grain": 100} and not target.captive and not data.site.captivity.has(str(target_id))
	if not _must(_terminal_check_50, "C36 custody _ransom_component:210 original assertion"): return false
	assert(_terminal_check_50, "C36 custody _ransom_component:210 original assertion")
	var _terminal_check_51: bool = source.revision == source_revision + 2 and destination.revision == destination_revision + 2 and not actions.validate_gd_custody_terminal(prepared).ok
	if not _must(_terminal_check_51, "C36 custody _ransom_component:211 original assertion"): return false
	assert(_terminal_check_51, "C36 custody _ransom_component:211 original assertion")
	var _terminal_check_52: bool = actions.cancel(payer).ok
	if not _must(_terminal_check_52, "C36 custody _ransom_component:212 original assertion"): return false
	assert(_terminal_check_52, "C36 custody _ransom_component:212 original assertion")
	lab.free()
	if not _guard(): return false
	return true

func _run() -> void:
	if not _actual_capture_release(false): return
	if not _actual_capture_release(true): return
	if not _ransom_component(): return
	TerrainArmy.release_contact_source()
	if not _guard(): return
	await _finish_terminal_pass("GD_CUSTODY_TRUE_POINT_TERMINAL_PASS: actual shared capture/unbind/escorted prison release and original sealed goods; finite source-only/forged/current holder/supply refusal; original 100-ration ransom true work-pool endpoint component only; once original custody/supply/serial; warm authored geometry and named incapacitation/recovery, no Native/contact/cold/World claim")
