extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

func _initialize() -> void:
	_run.call_deferred()

func _events_busy() -> Dictionary:
	return Runtime.fail("BUSY", "Released siege projectile still exists")

func _run() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(16, 16))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.feature_at.resize(data.size.x * data.size.y)
	var definition: Dictionary = Runtime.SIEGE_DEFINITIONS.ballista
	var vehicle := {"id": "1", "kind": "ballista", "team_id": 0, "cell": data.index(Vector2i(4, 4)),
		"facing": [1, 0], "operator_id": 0, "holder": Runtime.new_item_state("vehicle:1"),
		"cargo": {}, "move": {}, "stop_pending": false, "vehicle_version": 2, "definition_version": 1,
		"hp": 140.0, "ever_hp_damaged": false, "phase": "building", "crew_slots": {},
		"build": {"paid_cost": definition.cost.duplicate(), "total_work": definition.work_seconds, "progress": 0.0},
		"repair": {}, "command": {}, "action": {}, "next_attack_seq": 1, "rng_state": 1}
	data.site = {"vehicles": {"1": vehicle}, "next_vehicle": 2, "actors": {}, "armies": [], "features": {}}
	assert(Store._validate_vehicles(data, data.site).ok, "Original neutral construction record is stable")
	var baseline := data.site.duplicate(true)
	vehicle.hp = 1.0
	assert(not Store._validate_vehicles(data, data.site).ok, "Damage history cannot be omitted")
	assert(baseline.vehicles["1"].hp == 140.0, "Candidate validation does not change a separate baseline")
	vehicle.ever_hp_damaged = true
	assert(Store._validate_vehicles(data, data.site).ok)
	vehicle.build.paid_cost.wood = 0
	assert(not Store._validate_vehicles(data, data.site).ok, "Stored prepaid construction cannot manufacture materials")
	vehicle.build.paid_cost.wood = 24
	vehicle.hp = 0.0
	vehicle.phase = "wrecked"
	vehicle.build = {}
	vehicle.cargo = {"siege_bolt": 3}
	assert(Store._validate_vehicles(data, data.site).ok, "Wrecks preserve their original cargo")
	var station: int = int(Runtime.siege_work_slots(data, vehicle)[0].cell)
	data.feature_at[station] = 9
	assert(Store._validate_vehicles(data, data.site, true).ok, "Stable wrecks do not reserve abandoned construction stations")
	vehicle.hp = 140.0
	vehicle.phase = "building"
	vehicle.build = baseline.vehicles["1"].build.duplicate(true)
	assert(not Store._validate_vehicles(data, data.site, true).ok, "Active construction still requires its original stations")
	data.feature_at[station] = 0
	vehicle.hp = 0.0
	vehicle.phase = "wrecked"
	vehicle.build = {}
	vehicle.crew_slots = {"0": 42}
	assert(not Store._validate_vehicles(data, data.site).ok, "Stable wrecks cannot retain crew")
	vehicle.crew_slots = {}
	assert(not Store._validate_crowd(data, {"vehicles": {"1": vehicle}, "crowd": {}}).ok,
		"A candidate native load cannot bypass siege admission")
	assert(Store.siege_save_guard(data).ok)
	vehicle.phase = "loading"
	assert(not Store.siege_save_guard(data).ok)
	vehicle.phase = "wrecked"
	data.set_meta(&"siege_event_guard", Callable(self, "_events_busy"))
	data.site.vehicles.clear()
	assert(not Store.siege_save_guard(data).ok, "Deleting the final wreck cannot erase a released projectile guard")
	assert(not Store.siege_event_guard(data).ok)
	data.remove_meta(&"siege_event_guard")
	assert(Store.siege_save_guard(data).ok)
	print("SITE_SIEGE_STORE_GUARD_PASS")
	quit(0)
