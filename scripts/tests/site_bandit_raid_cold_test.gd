extends SceneTree
## A band really raids a settlement on a Site nobody watches (O2, 2026-11-24). A small generated scenario world (6
## settlements, 3 bands, 1 town) opens on its empty start Site; the player's team and the five cadres stand with the band
## of the lowest id and the cadres are sent as a raid to the nearest settlement without a garrison (the band dispatch that
## a far raid uses, site_bandit_far_raid.gd). Checks:
## - the raid travels, enters the settlement's Site and that Site's owner binds;
## - it engages the residents, the battle closes, the band takes the stock into its hoard.
## Prints what stands there every two game hours; when nothing was plundered it prints SITE_BANDIT_RAID_COLD_OBSERVED and
## quit(1).
## Output: SITE_BANDIT_RAID_COLD_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(3300.0).timeout.connect(func() -> void: _fail("3300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("SITE_BANDIT_RAID_COLD_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_RAID_COLD OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

## What stands on the target Site: people by faction, orders, places and the battle.
func _field_report(field: Variant) -> Dictionary:
	var report := {"bound": field != null and is_instance_valid(field)}
	if not report.bound or field.crowd_site == null or not field.crowd_site.active: return report
	var rows: Array = []
	for team: Dictionary in field.crowd_site.teams:
		var alive := 0
		var at: Array = []
		for person: Variant in team.get("person_ids", []):
			var body: Dictionary = field.crowd_site.combat_target(int(person))
			if body.is_empty() or float(body.get("hp", 0.0)) <= 0.0: continue
			alive += 1
			if at.is_empty(): at = [body.cell.x, body.cell.y]
		rows.append({"faction": int(team.get("faction", -1)), "alive": alive, "people": team.get("person_ids", []).size(), "first_at": at, "order": field.crowd_site.formation_state(int(team.formation)).get("order"), "departed": bool(team.get("departed", false))})
	report["teams"] = rows
	report["battle_open"] = field.crowd_site.battle.open
	report["participants"] = field.crowd_site.battle.participants.size()
	report["combat_left"] = float(field.terrain.site.get("combat_left", 0.0))
	report["grain"] = int(Aftermath.stock_of(field.terrain.site, int(Settlement.record(field.terrain).get("owner_faction", -1))).get("grain", 0))
	report["owner"] = int(Settlement.record(field.terrain).get("owner_faction", -1))
	return report

func _run() -> void:
	var folder := "user://raid_cold_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "劫掠全程", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	var open_deadline := Time.get_ticks_msec() + 1200000 # by the clock: beside another run the birth takes more frames
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the world is born and opens"): return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var here := str(lab.terrain.site.id)
	var player := int(lab.controlled_person_id())
	var cadres: Array = []
	for person: Variant in _team_of(lab, player).get("person_ids", []):
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _ok(cadres.size() >= 5, "the player has five cadres", cadres): return
	# The band and the settlement it raids: the nearest settlement Site whose owner keeps no garrison there.
	var registry: Dictionary = slot.control.faction_registry
	var band := -1
	for key: Variant in registry.entries:
		var entry: Dictionary = registry.entries[key]
		if entry.get("status") == "active" and RegionFactionQuery.is_bandit(registry, int(entry.faction_id)) and (band < 0 or int(entry.faction_id) < band): band = int(entry.faction_id)
	var target := ""
	var stock_before := -1
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		if parts.size() != 2: continue
		var at := Vector2i(int(parts[0]), int(parts[1]))
		var id := "%s:%d:%d" % [str(slot.pin.atlas_id), at.x, at.y]
		if id == here: continue
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), at)
		if not loaded.ok: continue
		var found: Dictionary = Settlement.record(loaded.data)
		if found.is_empty() or not found.has("owner_faction") or int(found.owner_faction) == band: continue
		var soldiers := 0
		for army: Variant in loaded.data.site.get("armies", []):
			if not army is Dictionary or int(army.get("faction_id", -1)) != int(found.owner_faction): continue
			for unit: Variant in army.get("units", []):
				if unit is Dictionary and str(unit.get("military_role", "")) != "civilian": soldiers += 1
		if soldiers >= 10: continue # a market town's garrison
		if target.is_empty() or Bandit.site_distance(here, id) < Bandit.site_distance(here, target):
			target = id
			stock_before = int(Aftermath.stock_of(loaded.data.site, int(found.owner_faction)).get("grain", 0))
	if not _ok(band > 0 and not target.is_empty() and Bandit.site_distance(here, target) >= 1, "band %d will raid %s, %d Sites away; its stock holds %d grain" % [band, target, Bandit.site_distance(here, target), stock_before]): return
	var parts_at: PackedStringArray = target.split(":")
	var goal := Vector2i(int(parts_at[parts_at.size() - 2]), int(parts_at[parts_at.size() - 1]))
	# The player's team and the raid stand with the band (a band team beside another faction would fight).
	var relabeled: Dictionary = lab.relabel_team_faction(int(_team_of(lab, player).team_id), band)
	if not _ok(relabeled.ok and controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "").ok, "the player's team stands with the band", relabeled): return
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(int(cadres[0]), band)
	if not _ok(apart.ok, "#%d stands apart as the band's" % int(cadres[0]), apart): return
	var raid_team := int(apart.team_id)
	for person: Variant in cadres.slice(1, 5):
		if not _ok(lab.crowd_site.join_team(int(person), raid_team, true).ok, "#%d joins the raid" % int(person)): return
	if not _ok(lab.crowd_site.hand_over_captain(raid_team, int(cadres[0])).ok, "#%d leads the raid" % int(cadres[0])): return
	if not _ok(controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "").ok, "the raid is saved"): return
	for _frame: int in range(300): await process_frame
	var here_at: Dictionary = slot._coordinate(lab.terrain)
	var dispatched: Dictionary = {}
	var token := "band_raid_test"
	for attempt: int in range(31):
		var captain := int(controller.team_captain_of_team(raid_team))
		var body: Dictionary = lab.crowd_site.combat_target(captain) if captain > 0 else {}
		if not body.is_empty():
			var component: int = RegionTravelSite.start_component(slot, here_at.site, body.cell, lab.terrain)
			dispatched = slot.prepare_npc_region_dispatch(lab, "captain:band", raid_team, goal, component, [], token)
			if dispatched.get("ok", false): dispatched = slot.commit_npc_region_dispatch(dispatched)
			if dispatched.get("ok", false): break
		for _frame: int in range(60): await process_frame
	if not _ok(dispatched.get("ok", false), "the raid of five leaves for %s" % target, dispatched): return
	Attacked.note_raid(controller, band, target, int(float(slot.control.logical_game_seconds) / Bandit.DAY))
	var hoard_before := int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("hoard", {}).get("grain", 0))

	lab.simulation_speed = 4.0
	var started_clock := float(slot.control.logical_game_seconds)
	var entered := false
	for frame: int in range(120000):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			_fail("a frame fault on the way", controller._original_step_fault)
			return
		if str(slot.region_registry().parties.get(token, {}).get("phase", "")) == "entered":
			entered = true
			break
	if not _ok(entered, "the raid entered the settlement's Site after %.1f game hours" % ((float(slot.control.logical_game_seconds) - started_clock) / 3600.0)): return
	var field: Variant = null
	var arrived_clock := float(slot.control.logical_game_seconds)
	var next_report := 0.0
	var fought := false
	for frame: int in range(60000):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			_fail("a frame fault during the raid", controller._original_step_fault)
			return
		field = slot._region_original_labs.get(target)
		var hours := (float(slot.control.logical_game_seconds) - arrived_clock) / 3600.0
		if hours >= next_report:
			next_report += 2.0
			print("SITE_BANDIT_RAID_COLD RAID hours=%.1f %s" % [hours, JSON.stringify(_field_report(field)).left(1500)])
		var active: bool = field != null and is_instance_valid(field) and field.crowd_site != null and field.crowd_site.active
		if active and field.crowd_site.battle.open: fought = true
		if fought and active and not field.crowd_site.battle.open and field.site_controller.battle_effects_due.is_empty() and int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("hoard", {}).get("grain", 0)) != hoard_before: break
		if hours >= 12.0: break
	var final_report := _field_report(field)
	var hoard_after := int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("hoard", {}).get("grain", 0))
	print("SITE_BANDIT_RAID_COLD FINAL fought=%s hoard %d -> %d stock %d -> %d %s" % [str(fought), hoard_before, hoard_after, stock_before, int(final_report.get("grain", -1)), JSON.stringify(final_report).left(1500)])
	TerrainArmy.release_contact_source()
	await process_frame
	_finished = true
	if hoard_after <= hoard_before:
		print("SITE_BANDIT_RAID_COLD_OBSERVED: the raid did not plunder")
		quit(1)
		return
	print("SITE_BANDIT_RAID_COLD_PASS: ", checks, " checks")
	quit(0)
