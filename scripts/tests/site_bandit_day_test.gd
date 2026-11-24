extends SceneTree
## 土匪 B4d-1 in a live world (reports/bandit-faction-spec.md §5.2, §11, §12): the daily band decision.
## A neutral world opens; an NPC band (chief not present here, lair at this Site) is registered. Checks:
## - heat cools by 5 on every 10th day only, once for the whole world however many Sites run the day's pass;
## - at heat >= 70 a band nobody attacked lies low (no move); an official attack (queued, saved at rest: heat +20 and the
##   day kept) makes the hot band move its lair to a land neighbour Site (same cell) and its heat drop to 30, saved
##   (Nekki 2026-11-22 B);
## - the daily entry point runs once a day;
## - a band the player chiefs (落草 mid-game) is never moved by the AI.
## Output: SITE_BANDIT_DAY_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const BanditDay = preload("res://scripts/terrain_lab/site_bandit_day.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_BANDIT_DAY_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_DAY OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _commit(controller: SiteController, candidate: Dictionary) -> bool:
	return candidate.get("ok", false) and controller._commit_diplomacy(candidate, "").ok

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "土匪每日世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"}), "a neutral world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var site_id := str(lab.terrain.site.id)
	var now := float(slot.control.logical_game_seconds)
	# An NPC chief who is not in this Site (an allocator person id far beyond this world's people).
	var chief_ref: Dictionary = RegionPeerage.world_person_ref(str(slot.pin.world_instance_id), 900000)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "黑風寨", "kind": "bandit", "leader_ref": chief_ref, "founded_at": now, "bandit": {"origin": "scenario", "lair": {"site_id": site_id, "cell": [12, 34]}}})
	if not _check(prepared.ok, "an NPC band is prepared", prepared): return
	var band := int(prepared.faction_id)
	if not _check(_commit(controller, prepared), "the band is saved"): return

	# Heat cools on the 10th day only.
	if not _check(_commit(controller, Bandit.set_heat(slot.control.faction_registry, band, 40, now)), "heat is set to 40"): return
	var ran: Dictionary = BanditDay.run(controller, 9)
	if not _check(int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).heat) == 40 and ran.actions.is_empty(), "day 9: no cooling, no action", ran): return
	ran = BanditDay.run(controller, 10)
	if not _check(int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).heat) == 35 and ran.actions.is_empty(), "day 10: heat cools to 35, the band rests", ran): return
	# Another Site's owner runs the same day's pass (every bound Site does): the world cools once a day.
	ran = BanditDay.run(controller, 10)
	if not _check(int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).heat) == 35, "day 10 again (another Site's pass): no second cooling", ran): return

	# A hot band nobody attacked lies low; after an official attack it moves its lair to a land neighbour.
	if not _check(_commit(controller, Bandit.set_heat(slot.control.faction_registry, band, 75, now)), "heat is set to 75"): return
	ran = BanditDay.run(controller, 11)
	if not _check(ran.actions.size() == 1 and ran.actions[0].action == "lie_low" and str(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).lair.site_id) == site_id
		and int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).heat) == 75, "day 11: the hot band nobody attacked lies low and stays", ran): return
	Attacked.queue(controller, band, 11)
	var flushed: Dictionary = Attacked.flush(controller)
	var attacked_table: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, band)
	if not _check(flushed.ok and int(attacked_table.heat) == 95 and int(attacked_table.get("attacked_day", -1)) == 11 and not slot.has_meta(&"bandit_attacked_due"), "an official attack on day 11 is saved: heat 75 -> 95, attacked_day 11", [flushed, attacked_table]): return
	var generation := int(slot._marker.generation)
	ran = BanditDay.run(controller, 12)
	var table: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, band)
	var moved_to := str(table.lair.site_id)
	if not _check(ran.actions.size() == 1 and ran.actions[0].action == "move_lair" and ran.actions[0].ok, "day 12: the attacked hot band moves its lair", ran): return
	if not _check(moved_to != site_id and Bandit.site_distance(moved_to, site_id) == 1 and table.lair.cell == [12, 34] and int(table.heat) == Bandit.HEAT_AFTER_MOVE, "the new lair is next door, same cell, heat 30", table): return
	var parts := moved_to.split(":")
	var summary: Dictionary = slot.source.get_site_summary(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))
	if not _check(summary.ok and str(summary.status) in ["land", "mixed"], "the new lair Site is land", summary): return
	if not _check(int(slot._marker.generation) > generation and RegionFactionQuery.bandit_of(slot.control.faction_registry, band).lair.site_id == moved_to, "the move is published", slot._marker.generation): return

	# The daily entry point runs once per game day (the controller's own daily pass has already run it today).
	if not _check(controller.has_meta(&"bandit_day") and BanditDay.day(controller).is_empty(), "the controller's daily pass already ran the band day today"): return
	controller.remove_meta(&"bandit_day")
	var first: Dictionary = BanditDay.day(controller)
	if not _check(first.has("day") and BanditDay.day(controller).is_empty(), "the daily entry runs once a day", first): return

	# A band the player chiefs is never moved by the AI.
	var fell: Dictionary = controller.go_outlaw("")
	if not _check(fell.ok, "the neutral player founds a band of his own", fell): return
	var player := int(lab.controlled_person_id())
	var own := int(lab._original_person_target(player).owner.faction_id)
	if not _check(own != band and RegionFactionQuery.is_bandit(slot.control.faction_registry, own), "the player's team is a band", own): return
	if not _check(_commit(controller, Bandit.set_heat(slot.control.faction_registry, own, 90, now)), "the player's band is hot"): return
	var own_lair: Variant = RegionFactionQuery.bandit_of(slot.control.faction_registry, own).lair
	ran = BanditDay.run(controller, 13)
	if not _check(RegionFactionQuery.bandit_of(slot.control.faction_registry, own).lair == own_lair and int(RegionFactionQuery.bandit_of(slot.control.faction_registry, own).heat) == 90
		and not ran.actions.any(func(a: Dictionary) -> bool: return int(a.band) == own), "the AI never moves the player's band", ran): return
	_finished = true
	print("SITE_BANDIT_DAY_PASS: ", checks, " checks; heat cools, a hot band lies low until attacked, then moves its lair, the player's band is left alone")
	quit(0)
