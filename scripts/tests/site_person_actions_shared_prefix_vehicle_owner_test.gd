extends SceneTree

# Actual original Actor/PA job/holder references. Native World has its independent
# 107-check receipt; this test only proves the PA consume-only prefix contract.
const Actions = preload("res://scripts/terrain_lab/site_person_actions.gd")
var checks := 0
var failures := 0

class Controller extends RefCounted:
	var _shared_work_plan: Dictionary = {}
	var lab: Variant
	var vehicles := SiteVehicleTransport.new()

class Fixture extends RefCounted:
	var terrain := TerrainData.new()
	var character := TerrainTestCharacter.new()
	var npc := TerrainTestNPC.new()
	var actions: Variant = Actions.new()
	var site_controller := Controller.new()
	var crowd_site: Variant = null
	var _shared_work_plan: Dictionary = {}
	func setup() -> void:
		terrain.allocate(Vector2i(12, 12))
		terrain.flags.fill(TerrainData.Flag.WALKABLE)
		SiteEnvironment.initialize(terrain, "pa-start-prefix-owner")
		terrain.site.manual.cargo = {}
		terrain.site.worker.cargo = {"wood": 1}
		assert(SiteRuntime.initialize_item_storage(terrain.site).ok)
		character.person_id = 1
		npc.person_id = 2
		character.data = terrain
		npc.data = terrain
		character.terrain_cell = Vector2i(4, 4)
		npc.terrain_cell = Vector2i(5, 4)
		character.item_state = SiteRuntime.new_item_state("person:1")
		npc.item_state = SiteRuntime.new_item_state("person:2")
		character.ammo_inventory = terrain.site.manual.cargo
		npc.ammo_inventory = terrain.site.worker.cargo
		npc.knockout_left = 30.0
		site_controller.lab = self
		site_controller.vehicles.init(site_controller)
		actions.init(self)
	func _original_person_target(identity: int) -> Dictionary:
		for actor: TerrainTestCharacter in [character, npc]:
			if actor.person_id == identity: return {"owner": actor, "unit": -1, "cell": actor.terrain_cell, "hp": actor.hp}
		return {}
	func controlled_person_id() -> int:
		return 1
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return false
	func close() -> void:
		if actions.has_method("end_shared_work_prefix_consumption"): actions.end_shared_work_prefix_consumption()
		actions.lab = null
		terrain.item_transfer_guard = Callable()
		terrain.ground_loot_removed = Callable()
		site_controller.vehicles.lab = null
		site_controller.vehicles.controller = null
		site_controller.lab = null
		character.free()
		npc.free()

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _run() -> void:
	var fixture := Fixture.new()
	fixture.setup()
	if not fixture.actions.has_method("prepare_shared_work_prefix"):
		_expect(false, "original PA prefix fragment not merged")
		fixture.close()
		quit(1)
		return
	var begun: Dictionary = fixture.actions.begin_loot(1, "person", "2", {"wood": 1}, [])
	_expect(bool(begun.ok), "true original loot command")
	if not begun.ok:
		fixture.close()
		quit(1)
		return
	var job: Dictionary = fixture.actions._jobs["1"]
	var seconds: float = float(job.duration)
	var requests: Array = fixture.actions.work_requests(seconds)
	var prepared: Dictionary = fixture.actions.prepare_shared_work_prefix(requests, seconds)
	var planned: Dictionary = PersonFatigue.plan_work_interval(requests, seconds)
	_expect(bool(prepared.ok) and bool(planned.ok), "original start pure capture and full-pool math")
	_expect(float(job.elapsed) == 0.0 and fixture.terrain.site.manual.cargo.is_empty() and int(fixture.terrain.site.worker.cargo.wood) == 1, "capture pays and advances nothing")
	fixture.character.hp = 0.0 # Actual original Actor endpoint state, never a proxy or fake alive row.
	fixture.character._received_effective_hit += 1
	_expect(not fixture.actions._job_context(job).ok, "original current endpoint guard truly rejects death/hit")
	var admitted: Dictionary = fixture.actions.validate_shared_work_prefix(prepared, planned, requests)
	_expect(bool(admitted.ok), "same true refs retain the qualified start prefix after endpoint death")
	_expect(fixture.actions.shared_job_work_prefix("1", job).is_empty(), "preparation cannot claim accepted consumption")
	if admitted.ok:
		fixture._shared_work_plan = planned
		fixture.site_controller._shared_work_plan = planned
		fixture.actions.begin_shared_work_prefix_consumption(admitted)
		_expect(not fixture.actions.shared_job_work_prefix("1", job).is_empty(), "positive accepted prefix only inside original consume interval")
		fixture.actions.advance(seconds, {"jobs": planned.jobs.person_actions})
		var elapsed: float = float(job.elapsed)
		_expect(elapsed > 0.0 and elapsed <= float(job.duration), "true prior work advances its original timer despite endpoint death")
		fixture.actions.advance(seconds, {"jobs": planned.jobs.person_actions})
		_expect(float(job.elapsed) == elapsed, "same interval cannot consume timer prefix twice")
		fixture.actions.end_shared_work_prefix_consumption()
		_expect(fixture.actions.shared_job_work_prefix("1", job).is_empty(), "reader expires at original consume end")
		fixture.actions.settle_after_contacts()
		_expect(fixture.terrain.site.manual.cargo.is_empty() and int(fixture.terrain.site.worker.cargo.wood) == 1, "current death guard rejects product transfer; accepted work is not receipt permission")
	fixture.close()
	print("SITE_PERSON_ACTIONS_SHARED_PREFIX_%s %d checks; true Actor/PA refs, current endpoint guards retained; Native/Runtime controlled integration separate" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
