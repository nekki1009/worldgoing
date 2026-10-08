extends SceneTree
## Real original Actor + Family owner contracts. The fixture collects only
## PersonActions requests; this is NOT TerrainLab's complete shared-clock close.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

class Fixture extends RefCounted:
	var terrain := TerrainData.new()
	var character := TerrainTestCharacter.new()
	var npc := TerrainTestNPC.new()
	var actions := SitePersonActions.new()
	var site_controller := SiteController.new()
	var combat_armies: Array[TerrainArmy] = []
	var crowd_site: Variant = null
	var controlled_id := 1
	var threatened_ids: Array[int] = []
	var old_bodies: Array[Node] = []
	var transfer_checks := 0

	func _init(registered: bool = true) -> void:
		terrain.allocate(Vector2i(12, 12))
		terrain.flags.fill(TerrainData.Flag.WALKABLE)
		terrain.site = {"id": "f07-original-actors", "minute": 0, "phase": 0.0, "paused": false,
			"controlled_person_id": 1, "combat_left": 0.0, "depot_cell": terrain.index(Vector2i(5, 4)),
			"capacity": 800, "inventory": {"wood": 80, "iron": 20, "fiber": 40, "cloth": 8, "tools": 1},
			"manual": {"target": "", "cargo": {}}, "worker": {"target": "", "cargo": {}}}
		assert(SiteRuntime.initialize_item_storage(terrain.site).ok)
		character.person_id = 1
		npc.person_id = 2
		character.data = terrain
		npc.data = terrain
		character.terrain_cell = Vector2i(4, 4)
		npc.terrain_cell = Vector2i(5, 5)
		character.item_state = SiteRuntime.new_item_state("person:1")
		npc.item_state = SiteRuntime.new_item_state("person:2")
		character.ammo_inventory = terrain.site.manual.cargo
		npc.ammo_inventory = terrain.site.worker.cargo
		site_controller.family_continuity.init(self)
		actions.init(self)
		if registered:
			var refs: Array = []
			for identity: int in [1, 2]:
				refs.append({"site_id": terrain.site.id, "person_id": identity,
					"path": "", "label": "原人物 #%d" % identity, "age_years": -1})
			assert(site_controller.family_continuity.register_members(refs, true, 1).ok)
			assert(site_controller.family_continuity.appoint_head(1, 1).ok)

	func controlled_person_id() -> int:
		return controlled_id

	func _combat_target(identity: int) -> Dictionary:
		for actor: TerrainTestCharacter in [character, npc]:
			if actor.person_id == identity:
				return {"owner": actor, "unit": -1, "cell": actor.terrain_cell, "hp": actor.hp}
		for team: TerrainArmy in combat_armies:
			var index := team.index_for_identity(identity)
			if index >= 0:
				return {"owner": team, "unit": index, "cell": team.cells[index],
					"hp": float(team.combat_hot_get(index, &"hp"))}
		return {}

	func _original_person_target(identity: int, _with_bodies: bool = false) -> Dictionary:
		return _combat_target(identity)

	func _fatigue_threat(_cell: Vector2i, _faction: int, owner: Variant, unit: int, _candidates: Dictionary) -> bool:
		var identity: int = int(owner.combat_identity(unit)) if unit >= 0 else int(owner.person_id)
		return threatened_ids.has(identity)

	func project() -> Dictionary:
		return Technology.active_project(terrain.site.family.get("technology", {}))

	func prepare(identity: int = 1, mode: String = "first", cap: Dictionary = {"wood": 12, "fiber": 6}) -> void:
		assert(actions.prepare_technology(controlled_id, identity, mode).ok)
		assert(actions.request_technology_consent(controlled_id, identity).ok)
		assert(actions.grant_technology_budget(controlled_id, cap).ok)

	func step(seconds: float) -> Dictionary:
		var requests := actions.work_requests(seconds)
		var planned := Fatigue.plan_work_interval(requests, seconds)
		assert(planned.ok, str(planned))
		# Test adapter applies each returned ORIGINAL pool exactly once, then PA
		# consumes only its allocation. No clone body or second fatigue owner.
		for group: Dictionary in planned.pools:
			if float(group.effort_seconds) <= 0.0: continue # A paused course must not mark a shared pool active.
			Fatigue.write(group.body, "fatigue", float(group.fatigue))
			Fatigue.write(group.body, "fatigue_rest", float(group.fatigue_rest))
		var handled := actions.advance(seconds, {"jobs": planned.jobs.get("person_actions", {})})
		return {"plan": planned, "handled": handled}

	func bow_count() -> int:
		var count := 0
		for record: Dictionary in terrain.site.item_records.values():
			if str(record.definition) == "weapon:bow_01": count += 1
		return count

	func commit_snapshot() -> PackedByteArray:
		return var_to_bytes([terrain.site, character.technology, npc.technology])

	func close() -> void:
		actions.cancel(1)
		actions.cancel(2)
		terrain.item_transfer_guard = Callable()
		for team: TerrainArmy in combat_armies:
			for index: int in team.combat_units.size(): actions.cancel(team.combat_identity(index))
			team.person_busy_query = Callable()
			team.controlled_person_query = Callable()
			team.free()
		combat_armies.clear()
		site_controller.family_continuity.lab = null
		actions.lab = null
		site_controller.free()
		character.free()
		npc.free()
		for actor: Node in old_bodies: actor.free()
		old_bodies.clear()

var checks := 0

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _trial(fixture: Fixture, identity: int = 1) -> Dictionary:
	var started := fixture.actions.begin_technology_trial(fixture.controlled_id, identity)
	_check(bool(started.ok), "Begin the genuine original trial: " + str(started))
	_check(is_equal_approx(float(started.seconds), 120.0), "Trials always use 120 effective seconds")
	fixture.step(120.0)
	var results := fixture.actions.settle_after_contacts()
	_check(results.size() == 1 and bool(results[0].ok), "One original paid bow commits: " + str(results))
	return results[0]

func _learn_teacher(fixture: Fixture) -> void:
	fixture.prepare()
	for index: int in 3: _trial(fixture)
	_check(Technology.learned(fixture.character.technology), "Teacher learned only through three real paid bows")
	_check(fixture.terrain.site.family.technology.known == ["F07"], "Real research granted this family's knowledge")

func run() -> void:
	_check_unregistered_and_three_trials()
	_check_original_sources_and_transaction_failures()
	_check_competing_real_stock_and_shared_version()
	_check_personal_effect_and_relearning()
	_check_cumulative_budget_and_personal_receipts()
	_check_teaching_occupancy_rest_threat_and_cancel()
	_check_contact_revalidation_and_relearn_closure()
	print("SITE_F07_RESEARCH_PASS: %d checks; real Actor/Family research A01/A04/A06/A12/A14/A15 and local teaching A03/A17; complete TerrainLab common clock, persistence, UI and A20 remain separate" % checks)
	quit(0)

func _check_unregistered_and_three_trials() -> void:
	var unregistered := Fixture.new(false)
	var untouched := unregistered.commit_snapshot()
	_check(str(unregistered.actions.technology_query().get("code", "")) == "UNREGISTERED", "Missing real family is explicit")
	_check(not unregistered.actions.prepare_technology(1, 1).ok, "No automatic registry or family")
	_check(unregistered.commit_snapshot() == untouched and not unregistered.terrain.site.has("family"), "Rejected command cannot invent relatives")
	unregistered.close()
	var f := Fixture.new()
	f.prepare()
	_check(f.actions.save_guard().ok and f.bow_count() == 0, "Prepare and grant occupy nobody and spend nothing")
	_check(f.project().budget.spent == {"wood": 0, "fiber": 0}, "An authorization is not a material reservation")
	var stock: Dictionary = f.terrain.site.inventory
	var original := stock.duplicate()
	for stage: int in range(1, 4):
		var start := f.actions.begin_technology_trial(1, 1)
		_check(start.ok and start.seconds == 120.0, "A01 original trial starts")
		var pending := f.commit_snapshot()
		f.step(119.0)
		_check(f.actions.settle_after_contacts().is_empty() and f.commit_snapshot() == pending, "119 effective seconds cannot commit")
		f.step(1.0)
		_check(f.commit_snapshot() == pending, "Finished work still waits for original contact settlement")
		var completed_job := f.actions.job_for(1)
		var result := f.actions.settle_after_contacts()
		_check(result.size() == 1 and result[0].ok and f.bow_count() == stage, "One tangible bow per successful trial")
		_check(Technology.learned(f.character.technology) == (stage == 3), "Only the original executor's third success teaches")
		_check(not Technology.learned(f.npc.technology), "Another registered person does not inherit the skill")
		_check(f.terrain.site.family.technology.known.has("F07") == (stage == 3), "Family knowledge shares the third real commit boundary")
		var committed := f.commit_snapshot()
		_check(not f.actions._commit_technology_trial(completed_job).ok, "A15 duplicate completion key is rejected")
		_check(f.commit_snapshot() == committed and f.actions.settle_after_contacts().is_empty(), "Duplicate creates no item, spend, receipt or knowledge")
	var history: Dictionary = f.terrain.site.family.technology.projects[0]
	_check(history.closed and history.receipts.size() == 3 and history.budget.spent == {"wood": 12, "fiber": 6}, "All three real receipts and cumulative costs survive closure")
	_check(stock.wood == original.wood - 12 and stock.fiber == original.fiber - 6 and stock.tools == 1, "Original finite stock pays 12/6 and retains tools")
	_check(f.actions.save_guard().ok, "Only settled work becomes saveable")
	for record: Dictionary in f.terrain.site.item_records.values():
		_check(record.holder == "depot" and int(record.original_owner) == 1, "Paid bow lives in original depot with actual maker")
	f.close()

func _check_original_sources_and_transaction_failures() -> void:
	for failure: String in ["holder", "cargo", "holder_version", "depot", "stock", "site", "materials", "tools", "capacity", "transaction", "body"]:
		var f := Fixture.new()
		f.prepare()
		_trial(f)
		_trial(f)
		_check(f.actions.begin_technology_trial(1, 1).ok, "A04 begin third trial")
		f.step(120.0)
		match failure:
			"holder": f.character.item_state = f.character.item_state.duplicate(true)
			"cargo":
				f.terrain.site.manual.cargo = f.terrain.site.manual.cargo.duplicate()
				f.character.ammo_inventory = f.terrain.site.manual.cargo
			"holder_version": f.character.item_state.version = int(f.character.item_state.version) + 1
			"depot": f.terrain.site.depot_items = f.terrain.site.depot_items.duplicate(true)
			"stock": f.terrain.site.inventory = f.terrain.site.inventory.duplicate()
			"site": f.terrain.site = f.terrain.site.duplicate(true)
			"materials": f.terrain.site.inventory.wood = 0
			"tools": f.terrain.site.inventory.tools = 0
			"capacity": f.terrain.site.capacity = 0
			"transaction":
				f.terrain.item_transfer_guard = func(_source: Dictionary, _destination: Dictionary, _resources: Dictionary, _items: Array) -> Dictionary:
					f.transfer_checks += 1
					return Runtime.fail("TEST_TRANSACTION_DENIED")
			"body":
				var old := f.character
				var replacement := TerrainTestCharacter.new()
				replacement.person_id = old.person_id
				replacement.data = f.terrain
				replacement.terrain_cell = old.terrain_cell
				replacement.item_state = old.item_state
				replacement.ammo_inventory = old.ammo_inventory
				replacement._received_effective_hit = old._received_effective_hit
				f.old_bodies.append(old)
				f.character = replacement
		var before := f.commit_snapshot()
		var result := f.actions.settle_after_contacts()
		_check(result.size() == 1 and not bool(result[0].ok), "A04 third completion rejects " + failure + ": " + str(result))
		_check(f.commit_snapshot() == before and f.bow_count() == 2, "Failure preserves both original committed bows and both knowledge states: " + failure)
		_check(f.project().receipts.size() == 2 and f.project().budget.spent == {"wood": 8, "fiber": 4}, "Failure cannot add a successful receipt or budget spend: " + failure)
		if failure == "transaction": _check(f.transfer_checks == 1, "Original real allocation guard, not only preview, caused the failure")
		f.close()
	# Explicit revocation after ready work also precedes both knowledge writes.
	var revoked := Fixture.new()
	revoked.prepare()
	_trial(revoked)
	_trial(revoked)
	_check(revoked.actions.begin_technology_trial(1, 1).ok, "A04 third ready for revocation")
	revoked.step(120.0)
	# Grantor cannot issue an operation while busy; stop first, then revoke.
	_check(not revoked.actions.grant_technology_budget(1, {}, "revoke").ok, "Busy original grantor cannot bypass camp admission")
	_check(revoked.actions.stop_technology(1, 1).ok, "Cancel only the specific trial")
	_check(revoked.actions.grant_technology_budget(1, {}, "revoke").ok, "Explicit source revocation")
	var saved := revoked.commit_snapshot()
	_check(not revoked.actions.begin_technology_trial(1, 1).ok and revoked.commit_snapshot() == saved, "Revoked source cannot start the third success")
	_check(revoked.project().receipts.size() == 2 and not Technology.learned(revoked.character.technology), "Revocation preserves 2/3 without skill")
	revoked.close()

func _check_competing_real_stock_and_shared_version() -> void:
	var shared := Fixture.new()
	shared.prepare()
	_check(shared.actions.begin_technology_trial(1, 1).ok, "Shared stock technology job")
	_check(shared.actions.begin_ranged_craft(2, "arrow").ok, "Another original person performs ordinary paid production")
	var depot: Dictionary = shared.terrain.site.depot_items
	var version := int(depot.version)
	shared.step(120.0)
	var results := shared.actions.settle_after_contacts()
	_check(results.size() == 2 and results[0].ok and results[1].ok and int(depot.version) > version, "A04 legitimate shared depot version changes allow both current-valid transactions")
	_check(shared.project().receipts.size() == 1 and shared.project().budget.spent == {"wood": 4, "fiber": 2}, "Ordinary production creates no research evidence")
	shared.close()
	var scarce := Fixture.new()
	scarce.prepare()
	scarce.terrain.site.inventory = {"wood": 4, "fiber": 2, "tools": 1}
	# Reauthorize the replacement source through the genuine camp entry.
	_check(scarce.actions.grant_technology_budget(1, {"wood": 12, "fiber": 6}).ok, "Replacement stock requires a new explicit binding")
	_check(scarce.actions.begin_technology_trial(1, 1).ok and scarce.actions.begin_ranged_craft(2, "bow").ok, "Both previews see one currently available batch")
	scarce.step(120.0)
	results = scarce.actions.settle_after_contacts()
	_check(results.size() == 2 and results[0].ok and not results[1].ok and scarce.bow_count() == 1, "Original stable-ID settlement spends scarce stock only once")
	_check(scarce.project().receipts.size() == 1 and not Technology.learned(scarce.npc.technology), "Only the successful real trial earns evidence")
	scarce.close()

func _check_personal_effect_and_relearning() -> void:
	var f := Fixture.new()
	_check(f.actions.ranged_craft_seconds(1, "bow") == 120.0, "A06 unlearned actual maker's normal bow is 120")
	_learn_teacher(f)
	var began := f.actions.begin_ranged_craft(1, "bow")
	_check(began.ok and began.seconds == 108.0, "A06 learned actual maker's ordinary bow is 108")
	_check(f.actions.cancel(1).ok, "Ordinary production canceled without a research receipt")
	_check(f.actions.begin_ranged_craft(2, "bow").seconds == 120.0, "Family knowledge cannot speed an unlearned maker")
	_check(f.actions.cancel(2).ok, "Return student to ready state")
	_check(not f.actions.prepare_technology(1, 2, "first").ok and not f.actions.prepare_technology(1, 1, "relearn").ok, "Known family needs relearn, and already learned people cannot retest")
	f.prepare(2, "relearn")
	f.character.action_time = 1.0 # Actual original action lock: teacher cannot be assigned now.
	_check(not f.actions.begin_technology_lesson(1, 1, 2).ok, "A12 unavailable original teacher is not forced free")
	for index: int in 3: _trial(f, 2)
	_check(Technology.learned(f.npc.technology) and f.terrain.site.family.technology.known == ["F07"], "A12 three explicit paid relearn trials teach only the student")
	_check(f.bow_count() == 6, "First research and relearn each cost three genuine bows")
	f.character.action_time = 0.0
	_check(f.actions.ranged_craft_seconds(2, "bow") == 108.0, "Relearn affects the actual student's future normal work")
	f.close()

func _check_cumulative_budget_and_personal_receipts() -> void:
	for finish_person: int in [1, 2]:
		var f := Fixture.new()
		f.prepare()
		_trial(f)
		_trial(f)
		var purpose := str(f.project().purpose)
		f.prepare(2)
		_trial(f, 2)
		_check(f.project().budget.spent == {"wood": 12, "fiber": 6}, "A14 one shared purpose accumulates both people's true spend")
		var before := f.commit_snapshot()
		_check(not f.actions.begin_technology_trial(1, 2).ok and f.commit_snapshot() == before, "A14 exhausted original cap cannot become another trial")
		_check(not f.actions.grant_technology_budget(2, {"wood": 20, "fiber": 10}, "increase").ok, "A14 noncontrolled person cannot impersonate material grantor")
		_check(f.actions.grant_technology_budget(1, {"wood": 20, "fiber": 10}, "increase").ok, "A14 genuine source person expressly raises the same finite cap")
		f.prepare(finish_person, "first", {"wood": 20, "fiber": 10})
		_check(str(f.project().purpose) == purpose and f.project().budget.spent == {"wood": 12, "fiber": 6}, "A15 changing maker and regranting preserve purpose and accumulated spend")
		if finish_person == 2: _trial(f, 2)
		_trial(f, finish_person)
		var closed: Dictionary = f.terrain.site.family.technology.projects[0]
		_check(f.bow_count() == (4 if finish_person == 1 else 5), "A15 personal evidence controls remaining true bows")
		_check(Technology.learned(f.character.technology) == (finish_person == 1) and Technology.learned(f.npc.technology) == (finish_person == 2), "Another maker's stages never transfer")
		_check(Technology.stages(closed, {"site_id": f.terrain.site.id, "person_id": finish_person}) == 3, "Only the finisher has three original receipts")
		_check(closed.budget.spent.wood == f.bow_count() * 4 and closed.budget.spent.fiber == f.bow_count() * 2, "Authorization spends exactly for paid products")
		f.close()

func _check_teaching_occupancy_rest_threat_and_cancel() -> void:
	var f := Fixture.new()
	_learn_teacher(f)
	var before := f.commit_snapshot()
	_check(f.actions.begin_technology_lesson(1, 1, 2).ok, "A03 free course needs no artificial material budget")
	_check(f.actions.is_busy(1) and f.actions.is_busy(2) and f.actions.job_for(1) == f.actions.job_for(2), "One genuine lesson occupies both original participants")
	_check(not f.actions.begin_ranged_craft(1, "bow").ok and not f.actions.begin_ranged_craft(2, "arrow").ok and not f.actions.save_guard().ok, "Both work maps and save guard see the joint occupancy")
	f.step(100.0)
	_check(f.actions.job_for(1).elapsed == 100.0 and f.actions.settle_after_contacts().is_empty(), "Joint course advances once")
	f.threatened_ids = [2]
	f.step(10.0)
	_check(f.actions.job_for(1).paused == "THREAT" and f.actions.job_for(1).elapsed == 0.0, "A17 only unheld student's local threat resets the whole course")
	_check(f.actions.is_busy(1) and f.actions.is_busy(2) and f.commit_snapshot() == before, "Threat does not create skill, item or material cost")
	f.threatened_ids.clear()
	f.step(10.0)
	f.npc.fatigue = 79.9
	f.npc.work_resting = false
	var advanced := f.step(100.0)
	var allocation: Dictionary = advanced.plan.jobs.person_actions["1"]
	_check(float(allocation.effective_seconds) > 0.0 and allocation.paused == "REST", "Actual fatigue planner reaches a partial interval then 80")
	var retained := float(f.actions.job_for(1).elapsed)
	_check(retained > 10.0 and f.actions.job_for(1).paused == "REST", "REST retains progress earned before its boundary")
	_check(f.actions.is_busy(1) and f.actions.is_busy(2) and not f.actions.save_guard().ok, "REST preserves both occupancies and save BUSY")
	f.step(50.0)
	_check(float(f.actions.job_for(1).elapsed) == retained, "REST adds no solo course progress or effort")
	f.npc.fatigue = 50.0 # This unit test observes original owner's recovered value, not full Lab recovery.
	_check(f.npc.work_resting, "Original recovery value alone does not clear the REST hysteresis latch")
	f.step(10.0)
	_check(float(f.actions.job_for(1).elapsed) > retained and not f.npc.work_resting, "Recovered original student resumes and original caller clears its REST latch")
	var resumed := float(f.actions.job_for(1).elapsed)
	f.step(10.0)
	_check(float(f.actions.job_for(1).elapsed) > resumed, "A second real work interval must not immediately rest again above 50")
	_check(f.actions.stop_technology(1, 2).ok and not f.actions.is_busy(1) and not f.actions.is_busy(2), "Cancel through student frees the single joint job")
	_check(f.commit_snapshot() == before and f.bow_count() == 3, "Canceled lesson changes no knowledge, bows or research spend")
	f.close()

func _check_contact_revalidation_and_relearn_closure() -> void:
	for identity: int in [1, 2]:
		for failure: String in ["move", "hit", "ko", "captive", "combat", "family_epoch"]:
			var f := Fixture.new()
			_learn_teacher(f)
			_check(f.actions.begin_technology_lesson(1, 1, 2).ok, "A17 real course starts")
			f.step(300.0)
			_check(not Technology.learned(f.npc.technology), "Time alone does not grant student skill")
			var actor: TerrainTestCharacter = f.character if identity == 1 else f.npc
			match failure:
				"move": actor.terrain_cell += Vector2i(1, 0)
				"hit": actor._received_effective_hit += 1
				"ko": actor.knockout_left = 1.0
				"captive": actor.captive = true
				"combat": f.terrain.site.combat_left = 1.0
				"family_epoch": f.terrain.site.family.technology.epoch += 1
			var before := f.commit_snapshot()
			var result := f.actions.settle_after_contacts()
			_check(result.size() == 1 and not result[0].ok and f.commit_snapshot() == before, "A17 contact-after-time invalidates either original participant: %d/%s" % [identity, failure])
			_check(not f.actions.is_busy(1) and not f.actions.is_busy(2), "Invalid course frees both participants together")
			f.close()
	for complete: bool in [false, true]:
		var f := Fixture.new()
		_learn_teacher(f)
		f.prepare(2, "relearn")
		_trial(f, 2)
		_trial(f, 2)
		var history_id := int(f.project().id)
		var old_bows := f.bow_count()
		_check(f.actions.begin_technology_lesson(1, 1, 2).ok, "A15 actual teacher can replace the student's 2/3 relearn route")
		var course := f.actions.job_for(1)
		f.step(300.0)
		if not complete: f.npc._received_effective_hit += 1
		var result := f.actions.settle_after_contacts()
		_check(result.size() == 1 and bool(result[0].ok) == complete, "A15 course completes only after valid original contact settlement")
		var relearn := {}
		for project: Dictionary in f.terrain.site.family.technology.projects:
			if int(project.id) == history_id: relearn = project
		_check(relearn.receipts.size() == 2 and relearn.budget.spent == {"wood": 8, "fiber": 4} and f.bow_count() == old_bows, "Course never refunds or manufactures a third relearn bow")
		_check(bool(relearn.closed) == complete and Technology.learned(f.npc.technology) == complete, "Skill and matching relearn closure share one commit")
		if complete:
			var settled := f.commit_snapshot()
			_check(not f.actions._commit_technology_lesson(course).ok and not f.actions.prepare_technology(1, 2, "relearn").ok, "Closed course and learned student's research cannot replay")
			_check(f.commit_snapshot() == settled, "No duplicate skill or reopened purpose")
		else:
			f.npc._received_effective_hit -= 1
			_trial(f, 2)
			_check(Technology.learned(f.npc.technology) and f.bow_count() == old_bows + 1, "Failed course preserves 2/3 for one final paid trial")
		f.close()

