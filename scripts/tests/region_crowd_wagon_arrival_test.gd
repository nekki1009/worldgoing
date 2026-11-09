extends SceneTree
## 2026-11-09: a whole land team with one wagon leaves a live crowd Site and arrives at a second live crowd Site.
## Setup as region_crowd_arrival_test (two formal TerrainLab scenes; deploy_trial_armies for the wagon, as site_crowd_convoy_test).
## The real whole-team land departure: departure_plan, departure_release, then the Site capture and RegionTravel.extract.
## Checks:
## - the wagon's operator is ready on a settled convoy and the team passes departure_plan; release takes every member out;
## - the origin holds no native convoy for the departed wagon (convoy_state of the old id is empty), its vehicles no longer hold
##   the wagon, and the origin saves, validates through SiteStore and reloads still without that convoy;
## - a ship vehicle arriving by land is refused UNSUPPORTED and leaves the destination file and blob hash unchanged;
## - RegionTravel.insert keeps the arriving team's own id; the wagon is parked on a walkable in-Site cell clear of every arriving
##   soldier, operator_id 0, no convoy_id; the arriving team number is covered by the destination's army_next_team;
## - the destination saves, validates through SiteStore and reloads with the new formation, soldiers and the parked wagon.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_WAGON_ARRIVAL_PASS on success; quit(1) on any failure.

const DT := 1.0 / 30.0
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
## The origin's team numbering starts here, above the destination's own team numbers (1..3), so the arriving id is new there.
const ORIGIN_TEAM_COUNTER := 10

var checks := 0
var lab: TerrainLab
var lab2: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_WAGON_ARRIVAL_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_WAGON_ARRIVAL OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _new_lab() -> TerrainLab:
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	var instance := packed.instantiate() as TerrainLab
	instance.pause_when_unfocused = false
	instance.movement_input_enabled = false
	root.add_child(instance)
	instance.set_process(false)
	instance.character.set_process(false)
	# The worker presenter stays in the tree so it is freed with the scene (a detached TerrainTestNPC leaked at exit).
	var worker := TerrainTestNPC.new()
	instance.add_child(worker)
	worker.set_process(false)
	instance.npc = worker
	for person: TerrainTestCharacter in instance.combat_actors: person.set_process(false)
	return instance

func _spec(identity: int, team_id: int) -> Dictionary:
	return {"person_id": identity, "actor_key": "", "team_id": team_id, "controller": "npc", "mode": "land",
		"crowd_departure": true, "game_seconds": 0.0}

## The first vehicle record of a kind (in-memory records keep int fields).
func _vehicle_key(vehicles: Dictionary, kind: String) -> String:
	for key: Variant in vehicles.keys():
		if vehicles[key] is Dictionary and str(vehicles[key].get("kind", "")) == kind: return str(key)
	return ""

func _vehicle_count(vehicles: Dictionary, kind: String) -> int:
	var count := 0
	for key: Variant in vehicles.keys():
		if vehicles[key] is Dictionary and str(vehicles[key].get("kind", "")) == kind: count += 1
	return count

func _army(state: Dictionary, team_id: int) -> Dictionary:
	for army: Variant in state.get("armies", []):
		if army is Dictionary and int(army.get("team_id", -1)) == team_id: return army
	return {}

func _army_ids(state: Dictionary) -> Array:
	var ids: Array = []
	for army: Variant in state.get("armies", []):
		if army is Dictionary: ids.append(int(army.get("team_id", -1)))
	return ids

func _crowd_team_ids(state: Dictionary) -> Array:
	var ids: Array = []
	for team: Variant in state.get("crowd", {}).get("teams", []):
		if team is Dictionary: ids.append(int(team.get("team_id", -1)))
	return ids

func _sha(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return

	# Origin: a friendly team of seven with one wagon, against two enemies. Its team numbers start at ORIGIN_TEAM_COUNTER.
	lab = _new_lab()
	lab.terrain.site["army_next_team"] = ORIGIN_TEAM_COUNTER
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 7, "role": "logistics", "cart_count": 0, "wagon_count": 1, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(deployed.ok, "origin: deploy trial armies with one friendly wagon", deployed): return
	var crowd: Variant = lab.crowd_site
	if not _check(crowd.active and crowd.convoy_native_supported(), "origin: a live crowd Site with native convoy support"): return
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var wagon_key := _vehicle_key(vehicles.records(), "wagon")
	if not _check(wagon_key != "", "origin: the friendly team has a wagon"): return
	# Two steps let the wagon's operator sync to its native convoy, as in the wagon convoy test.
	for _step in range(2): crowd.step(DT, DT, 0.0)
	var wagon: Dictionary = vehicles.records()[wagon_key]
	var team_id := int(wagon.get("team_id", 0))
	var old_convoy := int(wagon.get("convoy_id", 0))
	if not _check(old_convoy > 0 and int(wagon.get("operator_id", 0)) > 0 and team_id > 0, "origin: the wagon owns a native convoy and a crowd operator", wagon): return
	if not _check(team_id == ORIGIN_TEAM_COUNTER, "origin: the friendly team takes the origin's first team number", team_id): return
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0: roster = candidate
	if not _check(not roster.is_empty() and int(roster.team_id) == team_id, "origin: the friendly roster is the wagon's team"): return
	var soldiers := int(roster.units.size())
	var captain := int(roster.units[int(roster.formal_commander)].person_id)
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.get("ok", false) == true, "origin: the Site captures before departure", captured): return

	# An idle deployed convoy is never complete until it has a goal, so it is first ordered to settle on its own cell
	# (zero-length convoy goal), then ticked until complete. The operator stays aboard the wagon.
	var wagon_facing := Vector2i(int(wagon.facing[0]), int(wagon.facing[1]))
	var wagon_anchor: Vector2i = lab.terrain.cell_from_index(int(wagon.cell))
	var settle: Dictionary = vehicles.order_convoy_goal(wagon_key, wagon_anchor - wagon_facing, wagon_facing, int(wagon.get("operator_id", 0)), true)
	if not _check(settle.get("ok", false) == true, "the wagon is ordered to settle at its own cell", settle): return
	for _tick in range(90):
		crowd.step(DT, DT, 0.0)
		if bool(vehicles.convoy_state(wagon).get("complete", false)): break
	if not _check(bool(vehicles.convoy_state(wagon).get("complete", false)), "the settled wagon convoy completes", vehicles.convoy_state(wagon)): return
	captured = lab.site_controller._capture_for_save()
	if not _check(captured.get("ok", false) == true, "the Site captures the settled wagon before departure", captured): return

	# The real whole-team land departure: plan, release, capture, extract.
	var plan: Dictionary = crowd.departure_plan(captain)
	if not _check(plan.get("ok", false) == true and plan.people.size() == soldiers, "the wagon team passes the whole-team departure plan", plan): return
	var released: Dictionary = crowd.departure_release(plan)
	if not _check(released.get("ok", false) == true and int(released.released) == soldiers, "every team member is released", released): return
	var travelling: Dictionary = released.roster.duplicate(true)
	var saved: Dictionary = crowd.capture_save()
	if not _check(saved.get("ok", false) == true, "the origin crowd captures after the release", saved): return
	saved.rosters.append(travelling)
	lab.site_controller._apply_region_crowd_capture(saved)
	# The origin holds no native convoy for the departed wagon.
	if not _check(crowd.crowd.convoy_state(old_convoy).is_empty(), "the origin crowd holds no native convoy for the departed wagon", crowd.crowd.convoy_state(old_convoy)): return
	var extracted: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), _spec(captain, team_id), "crowd_wagon_arrival_test")
	if not _check(extracted.get("ok", false) == true, "the whole team extracts with its wagon", extracted): return
	var party: Dictionary = extracted.party
	var party_armies: Array = party.content.armies
	if not _check(party_armies.size() == 1 and party_armies[0].units.size() == soldiers, "the party carries the whole team", party_armies.size()): return
	if not _check(_vehicle_count(party.content.get("vehicles", {}), "wagon") == 1, "the party carries exactly one wagon"): return
	var party_wagon: Dictionary = party.content.vehicles[_vehicle_key(party.content.vehicles, "wagon")]
	if not _check(int(party_wagon.get("operator_id", 0)) > 0, "the travelling wagon keeps its operator", party_wagon.get("operator_id")): return

	# The origin: the Site the team left, saved, validated and reloaded with no wagon and no convoy for it.
	var origin: Dictionary = extracted.origin
	if not _check(_vehicle_key(origin.get("vehicles", {}), "wagon") == "", "the origin's vehicles no longer hold the wagon", origin.get("vehicles", {}).keys()): return
	lab.terrain.site = origin
	DirAccess.make_dir_recursive_absolute("user://sites")
	var origin_path := "user://sites/crowd_wagon_origin.json"
	var origin_written: Dictionary = Store.save(lab.terrain, origin_path, crowd.crowd)
	if not _check(origin_written.get("ok", false) == true, "the origin Site saves after the wagon departure", origin_written): return
	var origin_loaded: Dictionary = Store.load_site(origin_path, Callable(), 1, false)
	if not _check(origin_loaded.get("ok", false) == true, "the origin Site validates and loads after the wagon departure", origin_loaded): return
	var origin_native: Variant = origin_loaded.get("crowd_native")
	if not _check(origin_native is Object and origin_native.convoy_state(old_convoy).is_empty(), "the reloaded origin holds no native convoy for the departed wagon"): return

	# Destination: a second live crowd Site with its own team of seven and two enemies (team numbers 1..3), no wagon.
	lab2 = _new_lab()
	lab2.terrain.site["id"] = "crowd_wagon_destination"
	lab2.terrain.site.erase("travel_identity")
	var dest_deployed: Dictionary = lab2.deploy_trial_armies([
		{"faction": 0, "count": 7, "role": "logistics", "cart_count": 0, "wagon_count": 0, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(dest_deployed.ok and lab2.crowd_site.active, "destination: its own two-side live crowd deploys", dest_deployed): return
	var dest_captured: Dictionary = lab2.site_controller._capture_for_save()
	if not _check(dest_captured.get("ok", false) == true, "destination: the Site captures", dest_captured): return
	var dest_path := "user://sites/crowd_wagon_destination.json"
	var dest_written: Dictionary = Store.save(lab2.terrain, dest_path, lab2.crowd_site.crowd)
	if not _check(dest_written.get("ok", false) == true, "destination: the Site saves", dest_written): return
	var dest_loaded: Dictionary = Store.load_site(dest_path, Callable(), 1, false)
	if not _check(dest_loaded.get("ok", false) == true, "destination: the Site loads", dest_loaded): return
	var dest_native: Variant = dest_loaded.get("crowd_native")
	if not _check(dest_native is Object and dest_native.get_class() == &"ArmyCrowd", "destination: the loaded native crowd exists"): return
	var dest_state: Dictionary = dest_loaded.data.site
	var file_before := FileAccess.get_sha256(dest_path)
	var blob_before := str(dest_state.crowd.blob_sha256)
	var formations_before := int(dest_native.formation_count())
	var soldiers_before := int(dest_native.soldier_count())
	var entry: Vector2i = dest_loaded.data.spawn_cell
	var nav: TerrainData = Env.navigation_for_state(dest_loaded.data, dest_state)
	if not _check(not _crowd_team_ids(dest_state).has(team_id), "the arriving team id is free in the destination", [_crowd_team_ids(dest_state), team_id]): return

	# Refusal: the same party with its wagon re-typed as a ship is refused UNSUPPORTED (a ship by land is not admitted).
	var wagon_party_key := _vehicle_key(party.content.vehicles, "wagon")
	var ship_party: Dictionary = party.duplicate(true)
	ship_party.content.vehicles[wagon_party_key]["kind"] = "ship"
	var refused: Dictionary = RegionTravel.insert(dest_state, ship_party, nav, entry, dest_path, 0.0, 0.0, {})
	if not _check(refused.get("ok", true) == false and refused.get("code", "") == "UNSUPPORTED", "a ship vehicle arriving by land is refused UNSUPPORTED", refused): return
	if not _check(FileAccess.get_sha256(dest_path) == file_before and str(dest_state.crowd.blob_sha256) == blob_before, "the ship refusal leaves the destination file and blob hash unchanged"): return

	# The arrival: the land team with its wagon keeps its own team id.
	var inserted: Dictionary = RegionTravel.insert(dest_state, party, nav, entry, dest_path, 0.0, 0.0, {})
	if not _check(inserted.get("ok", false) == true, "the land team with its wagon arrives at the crowd Site", inserted): return
	var after_state: Dictionary = inserted.state
	print("WAGON_DIAG team ids: army=", _army_ids(after_state), " crowd=", _crowd_team_ids(after_state), " army_next_team=", after_state.get("army_next_team"))
	var arrived: Dictionary = _army(after_state, team_id)
	if not _check(not arrived.is_empty() and bool(arrived.get("crowd", false)), "the arriving roster keeps its team id and is crowd=true", _army_ids(after_state)): return
	if not _check(int(after_state.crowd.teams.size()) == int(dest_state.crowd.teams.size()) + 1, "the destination gains one crowd team"): return
	if not _check(int(after_state.get("army_next_team", 0)) > team_id, "the destination team counter covers the arriving team id", after_state.get("army_next_team")): return
	var wagon_key_after := _vehicle_key(after_state.get("vehicles", {}), "wagon")
	if not _check(wagon_key_after != "" and _vehicle_count(after_state.get("vehicles", {}), "wagon") == 1, "the destination holds exactly one arrived wagon", after_state.get("vehicles", {}).keys()): return
	var vehicle: Dictionary = after_state.vehicles[wagon_key_after]
	if not _check(int(vehicle.get("operator_id", -1)) == 0, "the arrived wagon has no operator", vehicle.get("operator_id")): return
	if not _check(not vehicle.has("convoy_id"), "the arrived wagon carries no origin convoy_id", vehicle.get("convoy_id")): return
	var anchor: Vector2i = nav.cell_from_index(int(vehicle.cell))
	if not _check(nav.contains(anchor) and nav.is_walkable(anchor), "the wagon anchor is a walkable cell inside the Site", anchor): return
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var length := int(SiteVehicleTransport.LENGTH.get("wagon", 1))
	var footprint: Array[Vector2i] = []
	for step in range(length): footprint.append(anchor + facing * step)
	for cell: Vector2i in footprint:
		if not _check(nav.contains(cell) and nav.is_walkable(cell), "every wagon footprint cell is walkable inside the Site", cell): return
	for unit: Dictionary in arrived.units:
		var soldier_cell := Vector2i(int(unit.cell[0]), int(unit.cell[1]))
		if not _check(not footprint.has(soldier_cell), "no arriving soldier stands in the wagon footprint", soldier_cell): return

	# Save -> load: the destination validates and reloads with the new formation, the soldiers and the parked wagon.
	var arrival_path := "user://sites/crowd_wagon_after.json"
	dest_loaded.data.site = after_state
	var arrival_saved: Dictionary = Store.save(dest_loaded.data, arrival_path)
	if not _check(arrival_saved.get("ok", false) == true, "the arrived Site saves", arrival_saved): return
	var reloaded: Dictionary = Store.load_site(arrival_path, Callable(), 1, false)
	if not _check(reloaded.get("ok", false) == true, "the arrived Site validates and reloads", reloaded): return
	var restored: Variant = reloaded.get("crowd_native")
	if not _check(int(restored.formation_count()) == formations_before + 1, "the reloaded native crowd has the new formation", [int(restored.formation_count()), formations_before]): return
	if not _check(int(restored.soldier_count()) == soldiers_before + soldiers, "the reloaded native crowd has the arriving soldiers", [int(restored.soldier_count()), soldiers_before, soldiers]): return
	var reloaded_key := _vehicle_key(reloaded.data.site.get("vehicles", {}), "wagon")
	if not _check(reloaded_key != "" and _vehicle_count(reloaded.data.site.get("vehicles", {}), "wagon") == 1, "the reloaded Site holds the one wagon"): return
	var reloaded_vehicle: Dictionary = reloaded.data.site.vehicles[reloaded_key]
	if not _check(int(reloaded_vehicle.get("operator_id", -1)) == 0 and not reloaded_vehicle.has("convoy_id"), "the reloaded wagon has no operator and no convoy_id", reloaded_vehicle): return
	if not _check(int(reloaded_vehicle.get("cell", -1)) == int(vehicle.cell), "the reloaded wagon keeps its parked cell", [reloaded_vehicle.get("cell"), vehicle.cell]): return

	# Free both formal scenes before quitting, so no node or resource is still in use at exit.
	lab2.queue_free()
	lab.queue_free()
	await process_frame
	await process_frame
	print("REGION_CROWD_WAGON_ARRIVAL_PASS: ", checks, " checks; a whole land team with one wagon departs the crowd Site through the real plan and release (origin saves, validates and holds no convoy for the wagon), a ship by land is refused UNSUPPORTED with unchanged files, and the land wagon arrives under its own team id, parked clear of the soldiers with no operator and no convoy; the destination saves, validates and reloads")
	quit(0)

