extends SceneTree
const Pose = preload("../terrain_lab/site_siege_work_pose.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var completed := 0

func _require(condition: bool, label: String) -> bool:
	if condition: return true
	push_error(label)
	quit(1)
	return false

func _initialize() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(48, 48))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "work-pose-projection")
	var anchor := Vector2i(20, 20)
	var vehicle := {"kind": "ram", "cell": data.index(anchor), "facing": [1, 0], "crew_slots": {"0": 11, "1": 12}, "move": {}, "action": {}}
	var source := Runtime.siege_crew_cell(data, vehicle, "0")
	var packet := {"cell": source, "moving_to": source + Vector2i.RIGHT, "progress": 0.5, "pose": "walk", "hp": 50.0, "ko": 0.0, "reacting": false, "can_act": true}
	vehicle.move = {"participants": [{"person_id": 11, "from": data.index(source), "to": data.index(source + Vector2i.RIGHT)}]}
	var before := JSON.stringify(vehicle)
	var work := Pose.sample(data, vehicle, 11, packet)
	if not _require(work.get("clip") == "siege_push" and is_equal_approx(float(work.time), 0.5), "Committed original half-step did not derive push phase"): return
	if not _require(Pose.sample(data, vehicle, 99, packet).is_empty() and JSON.stringify(vehicle) == before, "Work pose changed gameplay state or created another crew identity"): return
	completed += 1
	for override: Dictionary in [{"ko": 1.0}, {"hp": 0.0}, {"reacting": true}, {"can_act": false}, {"pose": "hit"}, {"pose": "unconscious"}, {"pose": "attack"}]:
		var stopped := packet.duplicate(true)
		stopped.merge(override, true)
		if not _require(Pose.sample(data, vehicle, 11, stopped).is_empty(), "Work animation replaced original reaction priority: " + str(override)): return
	completed += 1
	vehicle.move = {}
	vehicle.kind = "ballista"
	packet.cell = Runtime.siege_crew_cell(data, vehicle, "0")
	packet.moving_to = Vector2i(-1, -1)
	packet.pose = "idle"
	vehicle.action = {"stage": "loading", "elapsed": 0.7}
	work = Pose.sample(data, vehicle, 11, packet)
	if not _require(work.get("clip") == "siege_load" and is_equal_approx(float(work.time), 0.7), "Real loading elapsed did not derive work phase"): return
	vehicle.action.stage = "recovering"
	if not _require(Pose.sample(data, vehicle, 11, packet).is_empty(), "Recovery was relabeled as loading work"): return
	vehicle.action = {}
	if not _require(Pose.sample(data, vehicle, 11, packet).is_empty(), "Stopped idle crew was relabeled as active work"): return
	completed += 1
	vehicle.kind = "ram"
	var contacts := Runtime.siege_turn_contacts(data, vehicle)
	var rig: Dictionary = contacts[0]
	packet.cell = rig.station
	vehicle.action = {"stage": "rotate", "elapsed": 1.2}
	work = Pose.sample(data, vehicle, 11, packet)
	if not _require(work.get("clip") == "siege_pull" and is_equal_approx(float(work.time), 1.2) and work.facing != Vector2i.ZERO, "Original rig station did not derive pull toward real attachment"): return
	packet.cell += Vector2i.ONE
	if not _require(Pose.sample(data, vehicle, 11, packet).is_empty(), "Off-station person pulled an invisible rig"): return
	completed += 1
	if not _require(completed == 4, "Every work projection group must finish before PASS"): return
	print("SITE_SIEGE_WORK_POSE_PASS: pure original move/action projection, reaction/KO priority, loading versus idle/recovery, actual turn contact station; no GPU/body/native mechanics proof")
	quit(0)
