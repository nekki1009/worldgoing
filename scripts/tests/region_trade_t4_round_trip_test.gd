extends SceneTree
## Trade T4 TR-40: a team carries salt in its wagon's hold to another Site and trades it there from the hold. The real
## owners: the origin's whole-team departure (plan, release, capture, RegionTravel.extract) and the destination's arrival
## (RegionTravel.insert), the destination saved and loaded into a live Site through SiteController.load_from, then
## SiteTradeSession from the wagon's hold (TR-40's player side, the team's commander beside it) against a person of the
## destination's own team trading from his cargo. Checks:
## - the wagon leaves with its 10 salt and arrives with exactly 10 (nothing lost or doubled on the way);
## - at the destination the commander trades salt from the wagon's hold for iron; the delivery commits once;
## - salt and iron are conserved across both holders; each holder's version rises once.
## The way home is the same departure/arrival pair (a tax team's cart drives home in region_tax_team_test --tax-case=cart);
## food eaten on the road is RegionTravel's (R1-U), not repeated here.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_TRADE_T4_ROUND_TRIP_PASS on success; quit(1) on any failure.

const TradeSession = preload("res://scripts/terrain_lab/site_trade_session.gd")
const DT := 1.0 / 30.0
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const SiteFinance = preload("res://scripts/terrain_lab/site_finance.gd")
## The origin's team numbering starts here, above the destination's own team numbers (1..3), so the arriving id is new there.
const ORIGIN_TEAM_COUNTER := 10

var checks := 0
var lab: TerrainLab
var lab2: TerrainLab

func _initialize() -> void:
	create_timer(420.0).timeout.connect(func() -> void: _fail("420-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_TRADE_T4_ROUND_TRIP_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_TRADE_T4_ROUND_TRIP OK ", checks, ": ", message)
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

	# The player's team pays from its own wagon (a team may bind a vehicle as its pay source); the binding must not keep
	# the origin from saving once the wagon has left with the team.
	var finance_ref := {"kind": "team", "site_id": str(lab.terrain.site.get("id", "")), "org_id": str(team_id)}
	var finance_made: Dictionary = SiteFinance.ensure(lab.terrain, finance_ref, 0)
	if not _check(finance_made.get("ok", false) == true, "origin: the team has a finance record", finance_made): return
	finance_made.record["pay_source"] = {"kind": "vehicle", "site_id": str(lab.terrain.site.get("id", "")), "vehicle_id": wagon_key}
	if not _check(SiteFinance.validate(lab.terrain.site).get("ok", false) == true, "origin: the wagon is a valid pay source before departure"): return
	# The wagon carries 10 salt (trade goods, in its own hold).
	wagon["cargo"]["salt"] = 10
	wagon.holder["version"] = int(wagon.holder.version) + 1
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
	if not _check(int(party_wagon.cargo.get("salt", 0)) == 10, "the travelling wagon carries its 10 salt", party_wagon.cargo): return

	# The origin: the Site the team left, saved, validated and reloaded with no wagon and no convoy for it.
	var origin: Dictionary = extracted.origin
	if not _check(_vehicle_key(origin.get("vehicles", {}), "wagon") == "", "the origin's vehicles no longer hold the wagon", origin.get("vehicles", {}).keys()): return
	var origin_record: Dictionary = origin.get("finance", {}).get(SiteFinance.org_key(finance_ref), {})
	if not _check(not origin_record.is_empty() and origin_record.pay_source.is_empty(), "the origin keeps the team's finance record but no longer binds the departed wagon", origin_record.get("pay_source")): return
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

	# The arrival: the land team with its wagon keeps its own team id.
	var inserted: Dictionary = RegionTravel.insert(dest_state, party, nav, entry, dest_path, 0.0, 0.0, {})
	if not _check(inserted.get("ok", false) == true, "the land team with its wagon arrives at the crowd Site", inserted): return
	var after_state: Dictionary = inserted.state
	var wagon_key_after := _vehicle_key(after_state.get("vehicles", {}), "wagon")
	if not _check(wagon_key_after != "" and int(after_state.vehicles[wagon_key_after].cargo.get("salt", 0)) == 10, "the wagon arrives with exactly its 10 salt", after_state.get("vehicles", {})): return
	# The destination with the arrived team, saved and loaded into the live destination Site.
	var arrival_path: String = lab2.site_controller.save_root.path_join("t4_round_trip_arrived.json") # the crowd_test run directory
	dest_loaded.data.site = after_state
	var arrival_saved: Dictionary = Store.save(dest_loaded.data, arrival_path)
	if not _check(arrival_saved.get("ok", false) == true, "the arrived Site saves", arrival_saved): return
	var opened: Dictionary = lab2.site_controller.load_from(arrival_path)
	if not _check(opened.get("ok", false) == true and lab2.crowd_site.active, "the arrived Site opens live", opened): return
	for _step in range(4): lab2.crowd_site.step(DT, DT, 0.0) # commanders take their seats
	var live: Dictionary = lab2.terrain.site
	var wagon_live: Dictionary = live.vehicles[wagon_key_after]
	var anchor_cell: Vector2i = lab2.terrain.cell_from_index(int(wagon_live.cell))
	var arrived_team: Dictionary = lab2.crowd_site._team_by_id(team_id)
	if not _check(not arrived_team.is_empty(), "the arrived team is live", team_id): return
	var trader := int(lab2.crowd_site.formation_state(int(arrived_team.formation)).current_person)
	# The counterparty: a person of the destination's own faction-0 team (not the arrived team), trading from his own cargo.
	var local := -1
	for team: Dictionary in lab2.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != 0 or int(team.team_id) == team_id: continue
		for person: Variant in team.get("person_ids", []):
			if local < 0 and lab2.crowd_site.contains_person(int(person)): local = int(person)
	if not _check(trader > 0 and local > 0, "the arrived team has a commander; the destination has a person of its own", [trader, local]): return
	var actions: SitePersonActions = lab2.site_controller.person_actions
	var local_body: Dictionary = actions._person(local)
	local_body.cargo.clear()
	local_body.cargo["iron"] = 2
	# Stands: the trader beside the wagon, the local person face to face with him.
	var facing := Vector2i(int(wagon_live.facing[0]), int(wagon_live.facing[1]))
	var side := Vector2i(-facing.y, facing.x)
	var trader_cell := anchor_cell - facing
	var local_cell := anchor_cell - facing + side
	for cell: Vector2i in [trader_cell, local_cell]:
		if not _check(lab2.terrain.contains(cell) and lab2.terrain.is_walkable(cell), "a walkable stand beside the wagon", cell): return
	var moved_a: bool = lab2.crowd_site.set_soldier_fields(int(lab2.crowd_site._index_by_id[trader]), {"px": float(trader_cell.x) + 0.5, "py": float(trader_cell.y) + 0.5})
	var moved_b: bool = lab2.crowd_site.set_soldier_fields(int(lab2.crowd_site._index_by_id[local]), {"px": float(local_cell.x) + 0.5, "py": float(local_cell.y) + 0.5})
	if not _check(moved_a and moved_b, "the trader stands beside his wagon, the local person before him"): return
	var session: TradeSession = lab2.site_controller._trade()
	var own := session.player_side(trader, "vehicle:" + wagon_key_after)
	if not _check(own.ok, "the arrived commander may trade from his wagon's hold", own): return
	local_body = actions._person(local)
	var salt_total := int(wagon_live.cargo.get("salt", 0)) + int(local_body.cargo.get("salt", 0))
	var iron_total := int(wagon_live.cargo.get("iron", 0)) + int(local_body.cargo.get("iron", 0))
	var versions := [int(wagon_live.holder.version), int(local_body.holder.version)]
	var offer: Dictionary = session.propose(trader, local, TradeSession.goods({"salt": 9}), TradeSession.goods({"iron": 1}), "vehicle:" + wagon_key_after)
	if not _check(offer.get("ok", false) == true and str(offer.get("decision", "")) in ["ACCEPT", "COUNTER"], "the local person takes salt from the wagon for iron", offer): return
	var gave: Dictionary = offer.player_gives.resources
	var got: Dictionary = offer.npc_gives.resources
	var started: Dictionary = session.accept(str(offer.offer_id))
	if not _check(started.get("ok", false) == true, "the delivery starts", started): return
	lab2.fire_action_cursor += 31.0
	var results: Array[Dictionary] = session.advance()
	if not _check(results.size() == 1 and results[0].ok, "the delivery commits once", results): return
	local_body = actions._person(local)
	if not _check(int(wagon_live.cargo.get("salt", 0)) == 10 - int(gave.get("salt", 0)) and int(wagon_live.cargo.get("iron", 0)) == int(got.get("iron", 0)) and int(got.get("iron", 0)) >= 1,
		"the wagon's hold paid the salt and received the iron", [wagon_live.cargo, gave, got]): return
	if not _check(int(wagon_live.cargo.get("salt", 0)) + int(local_body.cargo.get("salt", 0)) == salt_total 		and int(wagon_live.cargo.get("iron", 0)) + int(local_body.cargo.get("iron", 0)) == iron_total, "salt and iron are conserved across both holders", [wagon_live.cargo, local_body.cargo]): return
	if not _check(int(wagon_live.holder.version) == versions[0] + 1 and int(local_body.holder.version) == versions[1] + 1, "each holder's version rose once"): return
	lab2.queue_free()
	lab.queue_free()
	await process_frame
	await process_frame
	print("REGION_TRADE_T4_ROUND_TRIP_PASS: ", checks, " checks; the wagon carried its salt across Sites intact and traded it from its hold for iron, conserved")
	quit(0)
