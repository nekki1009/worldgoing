extends "res://scripts/tests/site_boarding_cross_link_test.gd"
## B5S1/S2 (plan line 93, Q7 A): a steady two-end link saves through Store.save and reloads through
## Store.load_site with the same two-end closure; an unsettled link (crosser in the channel) is refused
## on save with BUSY and writes nothing. Uses the B2/B3 link helper (inherited).

const StoreB5 = preload("res://scripts/terrain_lab/site_store.gd")
const ContractB5 = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B5_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b5(): return
	print("SITE_BOARDING_B5_PASS: " + get_script().resource_path)
	await _cleanup(0)

## Raw saved state (JSON form), the query on it without data, and each end's loaded fields.
func _raw_diag_b5(path: String) -> String:
	var wrapper: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var raw: Dictionary = JSON.parse_string(wrapper.payload).state
	var out: String = "raw_query=" + str(ContractB5.query(raw, boat_id))
	for identity: String in [boat_id, enemy_boat]:
		var v: Dictionary = raw.vehicles[identity]
		out += " [" + identity + " kind=" + str(v.get("kind")) + " id=" + str(v.get("id")) + " ship_type=" + str(v.get("ship_type")) + " facing=" + str(v.get("facing")) + " link=" + str(v.naval.get("boarding_link", {})) + "]"
	return out

func _cases_b5() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var path: String = "user://b5_steady_link.json"
	if not _must(_link_live_b3(), "B5_PREMISE_LINK"): return false
	# Steady link: admitted by the contract, saved, and reloaded with the same closure.
	if not _must(ContractB5.save_guard(lab.terrain.site, lab.terrain).ok, "B5_STEADY_CONTRACT_ADMITTED: " + str(ContractB5.save_guard(lab.terrain.site, lab.terrain))): return false
	var saved: Dictionary = StoreB5.save(lab.terrain, path)
	if not _must(bool(saved.get("ok", false)), "B5_STEADY_SAVE: " + str(saved)): return false
	var loaded: Dictionary = StoreB5.load_site(path)
	if not _must(bool(loaded.get("ok", false)), "B5_STEADY_LOAD: " + str(loaded) + " " + _raw_diag_b5(path)): return false
	var site: Dictionary = loaded.data.site
	for identity: String in [boat_id, enemy_boat]:
		var naval: Dictionary = site.vehicles[identity].naval
		var link: Dictionary = naval.get("boarding_link", {})
		if not _must(int(naval.version) == 2 and str(link.get("state", "")) == "linked" and int(link.get("crosser_id", -1)) == 0 and int(link.get("epoch", -1)) == 1, "B5_LOADED_LINK_CLOSURE " + identity + ": " + str(naval)): return false
	if not _must(str(site.vehicles[boat_id].naval.boarding_link.peer.vehicle_id) == enemy_boat and str(site.vehicles[enemy_boat].naval.boarding_link.peer.vehicle_id) == boat_id, "B5_LOADED_PEERS_CLOSED"): return false
	if not _must(ContractB5.query(site, boat_id, loaded.data).ok, "B5_LOADED_QUERY: " + str(ContractB5.query(site, boat_id, loaded.data))): return false
	# Unsettled link: a crosser in the channel refuses to save and writes nothing new.
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	for identity: String in [boat_id, enemy_boat]: vehicles.records()[identity].naval.boarding_link.crosser_id = people[0]
	var refused: Dictionary = StoreB5.save(lab.terrain, path)
	if not _must(str(refused.get("code", "")) == "BUSY", "B5_CROSSING_SAVE_BUSY: " + str(refused)): return false
	if not _must(FileAccess.get_file_as_bytes(path) == before, "B5_REFUSED_SAVE_WRITES_NOTHING"): return false
	return true
