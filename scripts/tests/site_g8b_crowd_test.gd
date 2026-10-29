extends SceneTree
## G8 slice B: crowd crew work pose at the station (pure presentation sampler, no lab).
## Standalone: needs no --crowd-test root because it never builds a Site controller.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const SiegeWorkPose = preload("res://scripts/terrain_lab/site_siege_work_pose.gd")
const CELL := 64.0
const INVALID := Vector2i(-1, -1)
var checks := 0

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		printerr("G8B CROWD FAIL: deadline")
		quit(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	checks += 1
	print("G8B CROWD ", "OK " if ok else "FAIL ", checks, ": ", label)
	if not ok:
		printerr("G8B CROWD FAIL: ", label)
		quit(2)
	return ok

func _person(cell: Vector2i, crowd: bool, at: Vector2 = Vector2.ZERO, moving_to: Vector2i = INVALID) -> Dictionary:
	var person := {"cell": cell, "moving_to": moving_to, "progress": 0.0, "pose": "idle", "hp": 10.0, "ko": 0.0,
		"reacting": false, "can_act": true}
	if crowd:
		person["crowd"] = true
		person["position"] = at * CELL
	return person

func _run() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(20, 20))
	var anchor := Vector2i(10, 10)
	var vehicle := {"id": "g8b_ram", "kind": "ram", "cell": data.index(anchor), "facing": [0, 1], "crew_slots": {"0": 7},
		"move": {}, "action": {"stage": "loading", "elapsed": 0.5}}
	var station: Vector2i = Runtime.siege_crew_cell(data, vehicle, "0")
	_check(data.contains(station), "crew station of slot 0 lies on the map")
	var centre := Vector2(station) + Vector2.ONE * 0.5
	var neighbour := station + Vector2i.RIGHT

	# Crowd crew member 0.6 cells from the station centre, floor cell is the neighbouring column.
	var off_centre := _person(neighbour, true, centre + Vector2(0.6, 0.0))
	var result: Dictionary = SiegeWorkPose.sample(data, vehicle, 7, off_centre)
	_check(str(result.get("clip", "")) == "siege_load", "crowd crew slightly off-centre in a neighbouring floor cell gets the loading work pose: %s" % str(result))
	_check(is_equal_approx(float(result.get("time", -1.0)), 0.5), "work pose time follows the original action elapsed")

	# Crowd crew member at the station cell centre still gets the pose.
	result = SiegeWorkPose.sample(data, vehicle, 7, _person(station, true, centre))
	_check(str(result.get("clip", "")) == "siege_load", "crowd crew at the exact station centre gets the work pose")

	# Crowd crew member too far from the station centre gets no pose.
	result = SiegeWorkPose.sample(data, vehicle, 7, _person(neighbour, true, centre + Vector2(0.95, 0.0)))
	_check(result.is_empty(), "crowd crew beyond the station radius gets no work pose")

	# A crowd crew member that is still walking gets no station pose.
	result = SiegeWorkPose.sample(data, vehicle, 7, _person(neighbour, true, centre + Vector2(0.6, 0.0), neighbour))
	_check(result.is_empty(), "moving crowd crew member gets no station work pose")

	# Grid people keep the exact cell test: an off-centre neighbouring cell is not the station.
	result = SiegeWorkPose.sample(data, vehicle, 7, _person(neighbour, false))
	_check(result.is_empty(), "grid person in a neighbouring cell still gets no work pose (grid behaviour unchanged)")
	result = SiegeWorkPose.sample(data, vehicle, 7, _person(station, false))
	_check(str(result.get("clip", "")) == "siege_load", "grid person on the station cell keeps the work pose")

	print("G8B CROWD PASS: ", checks, " checks")
	quit(0)
