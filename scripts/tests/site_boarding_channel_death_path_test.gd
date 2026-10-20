extends "res://scripts/tests/site_boarding_cross_link_test.gd"
## B4S2 path test: a person dies in a link-gated channel through the real damage entry
## (apply_unit_contact, the same entry that site_ship_naval_lifecycle_test uses for its ship death cases),
## the body settles at the real channel point, the loot validates, and saving stays refused while the
## link is still active (B5 gate).

const StoreChannelPath = preload("res://scripts/terrain_lab/site_store.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B4S2P_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b4s2_path(): return
	print("SITE_BOARDING_B4S2P_PASS: " + get_script().resource_path)
	await _cleanup(0)

## Diagnostics for the channel reach rule: nearest footprint cell distance per hull, against CHANNEL_REACH.
func _reach_b4s3(container: Dictionary) -> String:
	var records: Dictionary = lab.site_controller.vehicles.records()
	var point: Vector2 = Vector2(float(container.channel_point[0]), float(container.channel_point[1]))
	var out: String = ""
	for identity: Variant in [container.get("vehicle_id", ""), container.get("peer_vehicle_id", "")]:
		var hull: Dictionary = records.get(str(identity), {})
		if hull.is_empty():
			out += " missing=" + str(identity)
			continue
		var anchor: Vector2i = lab.terrain.cell_from_index(int(hull.cell))
		var facing := Vector2i(int(hull.facing[0]), int(hull.facing[1]))
		var nearest: float = INF
		for cell: Vector2i in Ship.footprint(str(hull.ship_type), anchor, facing):
			nearest = minf(nearest, point.distance_to(Vector2(cell)))
		out += " " + str(identity) + " nearest=" + str(nearest) + " reach=" + str(Ship.CHANNEL_REACH)
	return out

func _cases_b4s2_path() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: Variant = lab.site_controller.person_actions
	var controller: Variant = lab.site_controller
	var aboard: int = people[0]
	if not _must(_link_live_b3(), "B4S2P_PREMISE_LINK"): return false
	var began: Dictionary = actions.begin_boarding_cross(aboard, enemy_boat, aboard)
	if not _must(began.ok, "B4S2P_BEGIN: " + str(began)): return false
	actions.advance_ship_jobs(0.5)
	if not _must(not actions._jobs.is_empty(), "B4S2P_MID_CHANNEL_JOB_OPEN"): return false
	var person: Dictionary = vehicles.ship_person(aboard)
	vehicles._kill_ship_person(person)
	var hp_after: float = float(vehicles.ship_person(aboard).get("hp", 1.0))
	if not _must(hp_after <= 0.0, "B4S2P_REAL_DAMAGE_KILLS hp=" + str(hp_after)): return false
	actions.advance_ship_jobs(0.1)
	actions.settle_after_contacts()
	if not _must(actions._jobs.is_empty(), "B4S2P_DEATH_CLOSES_CROSS"): return false
	var row: Dictionary = vehicles.ship_person(aboard).get("row", {})
	if not _must(row.has("ship_death_channel") and str(row.ship_death_channel.get("peer_vehicle_id", "")) == enemy_boat, "B4S2P_DEATH_CHANNEL_RECORDED row_keys=" + str(row.keys())): return false
	# Settle the pending death through the controller's own settlement (the down timer is advanced).
	controller.settle_person_deaths(100.0)
	var ground: Dictionary = lab.terrain.site.get("ground_loot", {})
	var found: String = ""
	for key: Variant in ground:
		var holder: Dictionary = ground[key]
		if holder.has("channel_point") and str(holder.get("vehicle_id", "")) == boat_id: found = str(key)
	if not _must(found != "", "B4S2P_LOOT_CHANNEL_HOLDER ground_keys=" + str(ground.keys())): return false
	var container: Dictionary = ground[found]
	var location: Dictionary = {"vehicle_id": str(container.get("vehicle_id", "")), "peer_vehicle_id": str(container.get("peer_vehicle_id", "")), "channel_point": container.get("channel_point", [])}
	if not _must(Runtime.valid_ship_loot_location(lab.terrain, location), "B4S3_RUNTIME_VALID location=" + str(location) + " reach:" + _reach_b4s3(container)): return false
	var checked: Dictionary = StoreChannelPath._validate_ship_loot_location(lab.terrain, lab.terrain.site, found, container)
	if not _must(checked.ok, "B4S2P_STORE_VALID: " + str(checked)): return false
	# Saving stays refused while the link is still active (B5 gate); the body is no longer pending.
	var stored: Dictionary = StoreChannelPath.save(lab.terrain, "user://b4s2_channel_death.json", null, false, {}, true)
	return _must(str(stored.get("code", "")) == "BUSY", "B4S2P_SAVE_BUSY_WHILE_LINKED: " + str(stored))
