extends "res://scripts/tests/region_ship_finite_food_physical_test.gd"
## B5F (plan line 99): the Region checkpoint admits a steady two-end link and refuses a crosser in the
## channel. Fixture: region_ship_finite_food_physical_test.gd `_setup_action_world` (a bound Region world,
## two original ferries from deploy_ship at its line ~134, ship_ids and ship_people filled).
## deploy_ship creates no naval record. The game's own path that creates one is the hull damage entry
## SiteRuntime.damage_ship_vehicle (site_runtime.gd): it sets naval v1, afloat, and applies the hit. One point
## of damage is used here, through that entry; no ship record is written by the test.
## Reopen through the Region path is NOT covered here.

const LinkB5F = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world(): _finish(); return
	if not _b5f_region_link(): _finish(); return
	_finish()

func _b5f_region_link() -> bool:
	if not _check(ship_ids.size() == 2 and ship_people.size() >= 1, "two original ships and a crew member from the Region ship fixture"): return false
	for identity: String in ship_ids:
		var hit: Dictionary = SiteRuntime.damage_ship_vehicle(lab.terrain, identity, 1.0)
		if not _check(hit.ok, "the game's own hull damage entry gives the original ship a naval record (v1, afloat)", hit): return false
	var records: Dictionary = controller.vehicles.records()
	for identity: String in ship_ids:
		var ship: Dictionary = records[identity]
		if not _check(ship.get("naval", {}).get("version") == 1 and ship.naval.state == "afloat" and ship.move.is_empty() and ship.command.is_empty(), "ship is calm before the pair: naval v1 afloat, no move, no command", ship): return false
	var first: Dictionary = records[ship_ids[0]]
	var second: Dictionary = records[ship_ids[1]]
	var made: Dictionary = LinkB5F.make_pair({"id": str(lab.terrain.site.id), "vehicles": records.duplicate(true)},
		ship_ids[0], ship_ids[1], "b5f-region-link", 1,
		lab.terrain.cell_from_index(int(first.cell)), lab.terrain.cell_from_index(int(second.cell)), [0.5, 0.5], [0.5, 0.5])
	if not _check(made.ok, "make_pair accepts the two original Region ships", made): return false
	for identity: String in ship_ids: records[identity].naval = made.state.vehicles[identity].naval.duplicate(true)
	# Steady linked pair: admitted by the same Region checkpoint the physical fixture uses.
	var steady: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(steady.ok, "steady linked pair is admitted by checkpoint_region_internal", steady): return false
	# A crosser in the channel: refused BUSY through the same checkpoint.
	for identity: String in ship_ids: records[identity].naval.boarding_link.crosser_id = ship_people[0]
	var crossing: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(not crossing.ok and str(crossing.get("code", "")) == "BUSY", "crosser in the channel is refused BUSY through the Region checkpoint", crossing): return false
	return true
