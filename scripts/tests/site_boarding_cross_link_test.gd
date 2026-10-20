extends "res://scripts/tests/site_boarding_contract_test.gd"
## B3S2 + B3S3: a linked pair crosses only through the link-gated path; unlinked pairs keep today's ship_cross.
## Reuses the B0 fixture (two real ferries, one person aboard the first).
const LINK_ONLY_MESSAGE := "接舷對只能經原接舷通道換船"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B3_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b3(): return
	print("SITE_BOARDING_B3_PASS: " + get_script().resource_path)
	await _cleanup(0)

func _live_b3() -> Dictionary:
	return lab.site_controller.vehicles.records()

## Writes a real two-end link on the original records through the B0/B2 contract builder.
func _link_live_b3() -> bool:
	var live: Dictionary = _live_b3()
	var site: Dictionary = lab.terrain.site
	var state: Dictionary = {"id": str(site.id), "vehicles": live.duplicate(true)}
	var a: Vector2i = lab.terrain.cell_from_index(int(live[boat_id].cell))
	var b: Vector2i = lab.terrain.cell_from_index(int(live[enemy_boat].cell))
	var made: Dictionary = LinkContract.make_pair(state, boat_id, enemy_boat, "b3-link", 1, a, b, [0.5, 0.5], [0.5, 0.5])
	if not _must(made.ok, "B3_PREMISE_LINK: " + str(made)): return false
	for identity: String in [boat_id, enemy_boat]:
		live[identity].naval = made.state.vehicles[identity].naval.duplicate(true)
	return true

func _cases_b3() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: Variant = lab.site_controller.person_actions
	var aboard: int = people[0]
	if not _must(str(vehicles.ship_person(aboard).row.get("embarked_vehicle_id", "")) == boat_id, "B3_PREMISE_EMBARKED"): return false

	# B3S2 regression, unlinked: the ordinary cross is not refused for the link reason.
	var plain: Dictionary = vehicles.ship_cross_query(aboard, enemy_boat, -1, aboard)
	if not _must(not str(plain.get("message", "")).contains(LINK_ONLY_MESSAGE), "B3S2_UNLINKED_NOT_LINK_REFUSED: " + str(plain)): return false

	# B3S2: once linked, the ordinary path refuses, and nothing is written.
	if not _must(_link_live_b3(), "B3_LINKED"): return false
	var before: PackedByteArray = var_to_bytes(_live_b3())
	var ordinary: Dictionary = actions.begin_ship_cross(aboard, enemy_boat, aboard, -1, false)
	if not _must(not ordinary.ok and str(ordinary.get("message", "")).contains(LINK_ONLY_MESSAGE), "B3S2_LINKED_ORDINARY_REFUSED: " + str(ordinary)): return false
	if not _must(var_to_bytes(_live_b3()) == before and actions._jobs.is_empty(), "B3S2_LINKED_ORDINARY_BYTES"): return false

	# B3S3: the link-gated path refuses the same hull and a non-linked target, writing nothing.
	var same: Dictionary = actions.begin_boarding_cross(aboard, boat_id, aboard)
	if not _must(not same.ok and same.code == "NO_TARGET", "B3S3_SAME_HULL: " + str(same)): return false
	if not _must(var_to_bytes(_live_b3()) == before and actions._jobs.is_empty(), "B3S3_SAME_HULL_BYTES"): return false

	# B3S3: the real begin writes the crosser on both ends and starts the existing ship path.
	var began: Dictionary = actions.begin_boarding_cross(aboard, enemy_boat, aboard)
	if not _must(began.ok, "B3S3_BEGIN: " + str(began)): return false
	var job: Dictionary = actions._jobs.get(str(aboard), {})
	if not _must(str(job.get("kind", "")) == "ship_cross" and bool(job.get("link_crossing", false)), "B3S3_JOB_SHAPE"): return false
	var live: Dictionary = _live_b3()
	for identity: String in [boat_id, enemy_boat]:
		var link: Dictionary = live[identity].naval.get("boarding_link", {})
		if not _must(int(link.get("crosser_id", 0)) == aboard and str(link.get("state", "")) == "linked", "B3S3_CROSSER_BOTH_ENDS: " + identity): return false

	# While the crossing is open: a second crosser is refused, and the save gate stays BUSY.
	var again: Dictionary = actions.begin_boarding_cross(aboard, enemy_boat, aboard)
	if not _must(not again.ok and again.code == "BUSY", "B3S3_SECOND_CROSSER_BUSY: " + str(again)): return false
	if not _must(vehicles.boarding_save_guard().code == "BUSY", "B3S3_SAVE_BUSY_WHILE_CROSSING"): return false
	return true
