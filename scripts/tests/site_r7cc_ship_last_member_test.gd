extends "res://scripts/tests/site_workflow_test.gd"
## R7 CC (test only): the team last-member refusal on a REAL ship build. The fixture steps are copied from
## scripts/tests/site_ship_build_test.gd: _ship_fixture (lines 17-38), _yard (lines 40-57) and the start call
## Runtime.begin_ship_build(data, key, "ferry", 1, 0) (line 87). The start writes the real site build state; the check reads it.
## No job is written by hand. Side-effecting calls are assigned before any assert (no side effects inside assert).

const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")

class StubTeam extends RefCounted:
	var team_id := 1
	var members := 1
	func living_member_count() -> int:
		return members

func _ship_fixture() -> TerrainData:
	var data := _fixture()
	data.site.capacity = 100000
	for resource: String in ["wood", "fiber", "iron", "stone", "tools"]: data.site.inventory[resource] = 10000
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_bodies = [900]
	for y: int in range(15, 35):
		for x: int in range(15, 55):
			var index := data.index(Vector2i(x, y))
			data.surface_types[index] = TerrainData.Surface.WATER
			data.flags[index] = TerrainData.Flag.BLOCKED | TerrainData.Flag.WET
			data.water_kind[index] = 1
			data.water_body[index] = 900
	data.site.depot_cell = data.index(Vector2i(20, 45))
	data.site.worker.cell = data.index(Vector2i(19, 45))
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	var storage: Dictionary = Runtime.initialize_item_storage(data.site)
	assert(storage.ok)
	data.site.vehicles = {}
	data.site.next_vehicle = 1
	return data

func _yard(data: TerrainData, x: int, launch_x: int = -1) -> String:
	var options := {"owner_faction": 0, "quarter": 0, "waterfront_version": 1,
		"launch_cell": data.index(Vector2i(x if launch_x < 0 else launch_x, 34))}
	var layout: Dictionary = Runtime.building_cells(data, "shipyard", Vector2i(x, 35), Vector2i(4, 3), options)
	assert(layout.ok)
	var build: Dictionary = Runtime.request_build(data, "shipyard", layout.cells, Callable(), options)
	assert(build.ok)
	var key := str(build.feature)
	var feature: Dictionary = data.site.features[key]
	var worker: Dictionary = data.site.worker
	worker.cell = int(feature.entrance)
	worker.target = "feature:" + key
	worker.action = "construct"
	worker.mode = "work"
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), null, null, Runtime.CARRY_CAPACITY, 0)
	assert(feature.stage == "complete")
	return key

func _run() -> void:
	var data := _ship_fixture()
	var key := _yard(data, 25)
	var started: Dictionary = Runtime.begin_ship_build(data, key, "ferry", 1, 0)
	assert(started.ok)
	assert(Runtime.ship_build_uses_team(data, 1))
	var before := var_to_bytes(data.site)

	# The last member of the team that the real build uses: refused, and the site is unchanged.
	var refused: Dictionary = Runtime.team_last_member_refusal(data, StubTeam.new(), false)
	assert(not bool(refused.get("ok", true)) and str(refused.code) == "BUSY")
	assert(var_to_bytes(data.site) == before)

	# Joining is never refused by this check; a team with another member, or another team, is not refused.
	assert(Runtime.team_last_member_refusal(data, StubTeam.new(), true).ok)
	var two_members := StubTeam.new()
	two_members.members = 2
	assert(Runtime.team_last_member_refusal(data, two_members, false).ok)
	var other_team := StubTeam.new()
	other_team.team_id = 2
	assert(Runtime.team_last_member_refusal(data, other_team, false).ok)
	assert(var_to_bytes(data.site) == before)

	print("SITE R7 CC SHIP LAST MEMBER PASS: a real ferry build (Runtime.begin_ship_build) makes the last voluntary departure of its team refused with BUSY and the site unchanged; joining, a team with another member, and another team are not refused.")
	quit(0)
