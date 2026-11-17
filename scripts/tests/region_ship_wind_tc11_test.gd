extends SceneTree
## 時間與氣候 TC11 (day-weather-season plan §4.7, D8 A): ships feel the wind. Pure checks on Ship.weather_factor and
## RegionRoute.sea_action_steps over an open-water fixture (no world). Checks:
## - a sailing ship gains 25% running before a full wind, loses 40% beating into it, nothing across it;
## - an oared ship feels half (+12.5% / -20%); still air changes nothing; a storm halves on top;
## - a sea step's duration is divided by the factor of its heading; a turn is not; no weather is the old timeline.
## Output: REGION_SHIP_WIND_TC11_PASS on success; quit(1) on any failure.

const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const Route = preload("res://scripts/region_lab/region_route.gd")
const Travel = preload("res://scripts/region_lab/region_travel.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

var checks := 0

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_SHIP_WIND_TC11 OK ", checks, ": ", message)
		return true
	printerr("REGION_SHIP_WIND_TC11_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _close(a: float, b: float) -> bool:
	return absf(a - b) <= 0.000001 * maxf(1.0, absf(b))

func _terrain() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.height_levels.fill(2)
	data.flags.fill(0)
	data.surface_types.fill(TerrainData.Surface.WATER)
	data.water_kind.resize(10000)
	data.water_kind.fill(2)
	data.water_body.resize(10000)
	data.water_body.fill(1)
	data.parameters = {"navigable_water_version": 1, "navigable_water_bodies": [1]}
	return data

func _passenger(ship: Dictionary) -> Dictionary:
	var row := {"person_id": 1, "hp": 100.0, "ko": 0.0, "fatigue": 0.0, "embarked_vehicle_id": "1", "berth_id": 0, "cargo": {},
		"item_state": Travel.Runtime.new_item_state("person:1")}
	var sustain := Sustain.create()
	Sustain.add_members(sustain, {1: {"hp": 100.0, "ko": 0.0, "captive": false, "present": true}}, [1])
	return {"controlled_person_id": 1, "actors": {}, "armies": [{"team_id": 1, "units": [row]}], "vehicles": {"1": ship},
		"item_records": {}, "person_supply": {}, "team_supply": {"1": {"version": 1, "revision": 0, "inventory": {}, "sustain": sustain}}}

func _run() -> void:
	var east := Vector2.RIGHT
	if not _check(_close(Ship.weather_factor("coastal", east, east), 1.25) and _close(Ship.weather_factor("coastal", east, -east), 0.6)
		and _close(Ship.weather_factor("coastal", east, Vector2.DOWN), 1.0), "a sailing ship: +25% before the wind, -40% into it, nothing across"): return
	if not _check(_close(Ship.weather_factor("ferry", east, east), 1.125) and _close(Ship.weather_factor("ferry", east, -east), 0.8), "an oared ship feels half"): return
	if not _check(_close(Ship.weather_factor("coastal", east, Vector2.ZERO), 1.0) and _close(Ship.weather_factor("coastal", east, east, true), 0.625)
		and _close(Ship.weather_factor("ferry", east, Vector2.ZERO, true), 0.5), "still air changes nothing; a storm halves on top"): return
	if not _check(_close(Ship.weather_factor("tower", east, east * 0.5), 1.125), "a half-strength wind gives half the gain"): return

	var sea := _terrain()
	var ship := {"id": "1", "kind": "ship", "ship_type": "ferry", "team_id": 1, "operator_id": 1,
		"cell": 5050, "facing": [1, 0], "cargo": {}, "holder": {"version": 1, "equipped": {}, "item_ids": []}}
	var content := _passenger(ship)
	var poses := {"1": {"anchor": [50, 50], "operator": [50, 50], "facing": [1, 0]}}
	var paths := {"1": [[50, 50, 1, 0], [51, 50, 1, 0], [51, 50, 0, 1]]}
	var still := Route.sea_action_steps(sea, sea, [ship], poses, paths, 1, content)
	var tail := Route.sea_action_steps(sea, sea, [ship], poses, paths, 1, content, null, {"wind": east, "storm": false})
	var head := Route.sea_action_steps(sea, sea, [ship], poses, paths, 1, content, null, {"wind": -east, "storm": true})
	if not _check(still.ok and tail.ok and head.ok and still.actions.size() == 2, "the three timelines are built", [still.get("code"), tail.get("code"), head.get("code")]): return
	var step := float(still.actions[0].duration)
	if not _check(_close(float(tail.actions[0].duration), step / 1.125) and _close(float(head.actions[0].duration), step / (0.8 * 0.5)), "the east step takes 1/1.125 with the wind, 1/0.4 into it in a storm"): return
	if not _check(_close(float(tail.actions[1].duration), float(still.actions[1].duration)) and _close(float(head.actions[1].duration), float(still.actions[1].duration)), "a turn takes as long in any weather"): return
	var none := Route.sea_action_steps(sea, sea, [ship], poses, paths, 1, content, null, {})
	if not _check(none.ok and _close(float(none.action_seconds), float(still.action_seconds)), "no weather is the old timeline"): return
	print("REGION_SHIP_WIND_TC11_PASS: ", checks, " checks; ships feel the wind")
	quit(0)
