extends SceneTree
## 官方剿匪 end to end (Nekki 2026-11-22 B; stages 1 and 3 with the band rule BQ7), a real journey. A small generated
## scenario world (6 settlements, 3 bands, 1 town) opens on its start Site. The player's team stands with NPC faction 1;
## the five cadres form an expedition of faction 1 and are sent against the nearest band, whose heat is set to 75. Then
## game time runs (speed 4x) and nothing else is touched:
## - the expedition leaves, travels and enters the lair Site (its journey's phase becomes entered);
## - at the lair, which nobody watches, the expedition is ordered to attack and fights the band; when that battle closes
##   the band is recorded as attacked by an official faction: its heat rises by 20 and the day is kept;
## - on the band's next day it moves its lair (hot and attacked), heat 30.
## On a timeout the test prints what the lair Site's owner holds (bound, crowd, teams, the day passes) before failing.
## Output: SITE_BANDIT_SUPPRESSION_E2E_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Suppression = preload("res://scripts/terrain_lab/site_bandit_suppression.gd")
const BanditDay = preload("res://scripts/terrain_lab/site_bandit_day.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(3300.0).timeout.connect(func() -> void: _fail("3300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("SITE_BANDIT_SUPPRESSION_E2E_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_SUPPRESSION_E2E OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

## What the lair Site's owner holds now, for the log.
func _lair_report(slot: RegionSaveSlot, lair: String, token: String, band: int) -> String:
	var band_entry: Dictionary = slot.control.faction_registry.entries.get(str(band), {})
	var report := {"party_phase": str(slot.region_registry().parties.get(token, {}).get("phase", "")), "bound": slot._region_original_labs.has(lair), "band_status": str(band_entry.get("status", "")),
		"clock": float(slot.control.logical_game_seconds), "heat": int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("heat", -1)),
		"attacked_day": int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("attacked_day", -1)), "pending_events": slot.pending_region_events().size()}
	var original: Variant = slot._region_original_labs.get(lair)
	if original != null and is_instance_valid(original):
		report["crowd_active"] = original.crowd_site != null and original.crowd_site.active
		report["suppress_day"] = int(original.site_controller.get_meta(&"suppress_day", -1))
		report["suppress_refused"] = str(original.site_controller.get_meta(&"suppress_refused", ""))
		if original.crowd_site != null and original.crowd_site.get("battle") != null:
			report["battle"] = {"open": bool(original.crowd_site.battle.open), "participants": original.crowd_site.battle.participants.size(), "deaths": original.crowd_site.battle.deaths}
		report["attacked_due"] = slot.get_meta(&"bandit_attacked_due", {})
		report["notices"] = original.terrain.site.get("notices", []).slice(-4)
		report["combat_left"] = float(original.terrain.site.get("combat_left", 0.0))
		var teams: Array = []
		if original.crowd_site != null:
			for team: Dictionary in original.crowd_site.teams:
				var alive := 0
				for person: Variant in team.get("person_ids", []):
					var body: Dictionary = original.crowd_site.combat_target(int(person))
					if not body.is_empty() and float(body.get("hp", 0.0)) > 0.0: alive += 1
				teams.append({"team": int(team.team_id), "faction": int(team.get("faction", -1)), "people": team.get("person_ids", []).size(), "alive": alive, "departed": bool(team.get("departed", false))})
		report["teams"] = teams
		report["armies"] = original.terrain.site.get("armies", []).size()
	# The live Lab's retained cold replay (a destination catching up) and its open Region point.
	var live := current_scene as TerrainLab
	if live != null:
		report["replay_id"] = str(live._cold_replay_id)
		report["replay_target"] = float(live._cold_replay_target)
		if is_instance_valid(live._cold_replay_lab):
			report["replay_at"] = float(live._cold_replay_lab.region_cold_actual_progress().get("game_seconds", -1.0))
			report["replay_crowd"] = live._cold_replay_lab.crowd_site != null and live._cold_replay_lab.crowd_site.active
		report["point_pending"] = live._region_point_pending.keys()
		report["point_dispatching"] = live._region_point_dispatching
	var due: Array = slot.pending_region_events()
	if not due.is_empty(): report["first_event"] = {"kind": str(due[0].get("kind", "")), "at": float(due[0].get("at", -1.0)), "id": str(due[0].get("id", "")).left(80)}
	return JSON.stringify(report)

func _run() -> void:
	var folder := "user://suppression_e2e_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "剿匪全程", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
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
	# The nearest band.
	var registry: Dictionary = slot.control.faction_registry
	var band := -1
	var lair := ""
	for key: Variant in registry.entries:
		var entry: Dictionary = registry.entries[key]
		if entry.get("status") != "active" or not RegionFactionQuery.is_bandit(registry, int(entry.faction_id)): continue
		var at := str(RegionFactionQuery.bandit_of(registry, int(entry.faction_id)).lair.site_id)
		if band < 0 or Bandit.site_distance(here, at) < Bandit.site_distance(here, lair) or Bandit.site_distance(here, at) == Bandit.site_distance(here, lair) and int(entry.faction_id) < band:
			band = int(entry.faction_id)
			lair = at
	if not _ok(band > 0 and Bandit.site_distance(here, lair) >= 1, "the nearest band is %d, lair %s, %d Sites away" % [band, lair, Bandit.site_distance(here, lair)]): return
	var heated: Dictionary = Bandit.set_heat(slot.control.faction_registry, band, 75, float(slot.control.logical_game_seconds))
	if not _ok(heated.ok and controller._commit_diplomacy(heated, "").ok, "the band is hot (heat 75)", heated): return
	# The player's team stands with faction 1 (a faction 1 team beside a neutral one would fight); the cadres form the expedition.
	var relabeled: Dictionary = lab.relabel_team_faction(int(_team_of(lab, player).team_id), 1)
	if not _ok(relabeled.ok and controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "").ok, "the player's team stands with faction 1", relabeled): return
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(int(cadres[0]), 1)
	if not _ok(apart.ok, "#%d stands apart as faction 1" % int(cadres[0]), apart): return
	var expedition := int(apart.team_id)
	for person: Variant in cadres.slice(1, 5):
		var joined: Dictionary = lab.crowd_site.join_team(int(person), expedition, true)
		if not _ok(joined.ok, "#%d joins the expedition" % int(person), joined): return
	var led: Dictionary = lab.crowd_site.hand_over_captain(expedition, int(cadres[0]))
	if not _ok(led.ok, "#%d leads the expedition" % int(cadres[0]), led): return
	if not _ok(controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "").ok, "the expedition is saved"): return
	for _frame: int in range(300): await process_frame # the native seats the new captain on its next step; the team regroups and stands still
	var today := int(float(slot.control.logical_game_seconds) / Bandit.DAY)
	var sent: Dictionary = {}
	for attempt: int in range(31):
		sent = Suppression.send(controller, 1, {"band": band, "team_id": expedition, "lair_site": lair}, today)
		if sent.ok or str(sent.get("code", "")) not in ["NOT_READY", "NO_COMMANDER"]: break
		for _frame: int in range(60): await process_frame
	if not _ok(sent.ok, "the expedition of five is sent against band %d" % band, sent): return
	var token := str(sent.sent.token)

	# Game time runs.
	lab.simulation_speed = 4.0
	var started_clock := float(slot.control.logical_game_seconds)
	var entered := false
	var travel_prints := 0
	var arrival_probes := 0
	for frame: int in range(120000):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			# Why the lair Site's owner did not bind: the same request, asked again for its own refusal.
			var probe: Dictionary = lab._region_gameplay_owner_lab(lair, "cold_exact")
			probe.erase("lab")
			print("SITE_BANDIT_SUPPRESSION_E2E BIND_PROBE ", JSON.stringify(probe).left(1500), " | ", _lair_report(slot, lair, token, band))
			_fail("a frame fault on the way", controller._original_step_fault)
			return
		var phase := str(slot.region_registry().parties.get(token, {}).get("phase", ""))
		if phase == "entered":
			entered = true
			break
		# Often while the arrival is being worked on (a frame may take a quarter second there), rarely otherwise.
		var waiting := not slot.pending_region_events().is_empty() or is_instance_valid(lab._cold_replay_lab)
		if frame % 6000 == 0 or waiting and frame % 40 == 0 and travel_prints < 60:
			travel_prints += 1
			print("SITE_BANDIT_SUPPRESSION_E2E TRAVEL frame=%d msec=%d %s" % [frame, Time.get_ticks_msec(), _lair_report(slot, lair, token, band)])
		# The arrival waits: bind the lair Site's owner here, slice by slice, and print what it answers when its cold replay
		# is done; then ask the arrival itself (once).
		var due_now: Array = slot.pending_region_events()
		if OS.get_cmdline_user_args().has("--cold-bind-diag") and arrival_probes < 1 and not due_now.is_empty() and str(due_now[0].get("kind", "")) == "arrival" and frame > 60:
			arrival_probes += 1
			var began := Time.get_ticks_msec()
			var bound: Dictionary = {}
			var slices := 0
			for attempt: int in range(2000):
				bound = lab._region_gameplay_owner_lab(lair, "cold_exact")
				slices += 1
				if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
			var shown := {}
			for key: Variant in bound:
				if not bound[key] is Object and not bound[key] is Callable: shown[key] = bound[key] if not (bound[key] is Dictionary or bound[key] is Array) else str(bound[key]).left(400)
			print("SITE_BANDIT_SUPPRESSION_E2E BIND_RESULT slices=%d took_ms=%d %s | %s" % [slices, Time.get_ticks_msec() - began, JSON.stringify(shown).left(1800), _lair_report(slot, lair, token, band)])
			began = Time.get_ticks_msec()
			var asked: Dictionary = lab.consume_region_point() # the dispatcher's own entry, as the step calls it
			var told := {}
			for key: Variant in asked:
				if not asked[key] is Object and not asked[key] is Callable: told[key] = asked[key] if not (asked[key] is Dictionary or asked[key] is Array) else str(asked[key]).left(300)
			print("SITE_BANDIT_SUPPRESSION_E2E ARRIVAL_RESULT took_ms=%d %s | %s" % [Time.get_ticks_msec() - began, JSON.stringify(told).left(1800), _lair_report(slot, lair, token, band)])
			if OS.get_cmdline_user_args().has("--cold-bind-diag") and (not bound.get("ok", false) or not asked.get("ok", false) or not bool(asked.get("complete", false))):
				_fail("diagnostic run: the lair Site's owner did not bind or the arrival was refused", [shown, told])
				return
	print("SITE_BANDIT_SUPPRESSION_E2E ARRIVAL ", _lair_report(slot, lair, token, band))
	if not _ok(entered, "the expedition entered the lair Site after %.1f game hours" % ((float(slot.control.logical_game_seconds) - started_clock) / 3600.0)): return
	var attacked := false
	var destroyed := false
	for frame: int in range(120000):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			_fail("a frame fault during the fight", controller._original_step_fault)
			return
		if int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("attacked_day", -1)) >= 0:
			attacked = true
			break
		if str(slot.control.faction_registry.entries.get(str(band), {}).get("status", "")) != "active":
			destroyed = true
			break
		if frame % 6000 == 0: print("SITE_BANDIT_SUPPRESSION_E2E FIGHT frame=%d %s" % [frame, _lair_report(slot, lair, token, band)])
	print("SITE_BANDIT_SUPPRESSION_E2E AFTER ", _lair_report(slot, lair, token, band))
	if not attacked:
		var original: Variant = slot._region_original_labs.get(lair)
		if original != null and is_instance_valid(original) and original.crowd_site != null and original.crowd_site.active:
			print("SITE_BANDIT_SUPPRESSION_E2E PROBE attack=", JSON.stringify(Suppression.attack(original.site_controller, int(float(slot.control.logical_game_seconds) / Bandit.DAY))))
	if not destroyed and not _ok(attacked, "the band is recorded as attacked by an official faction after %.1f game hours" % ((float(slot.control.logical_game_seconds) - started_clock) / 3600.0)): return
	var table: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, band)
	if not destroyed and not _ok(int(table.heat) == 95 and str(table.lair.site_id) == lair, "its heat rose from 75 to 95; it still holds its lair", table): return
	# The fight on the unwatched Site runs to its end: its battle closes after a quiet minute and is in the battle log.
	var log_entry: Dictionary = {}
	for frame: int in range(120000):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			_fail("a frame fault after the fight", controller._original_step_fault)
			return
		for battle: Dictionary in slot.pending_battles + RegionBattleLog.table(slot.control.faction_registry).records:
			if str(battle.site_id) == lair and battle.sides.has(str(band)) and battle.sides.has("1"): log_entry = battle
		if not log_entry.is_empty(): break
		if frame % 6000 == 0: print("SITE_BANDIT_SUPPRESSION_E2E CLOSING frame=%d %s" % [frame, _lair_report(slot, lair, token, band)])
	if not _ok(not log_entry.is_empty(), "the battle on the unwatched lair is in the battle log"): return
	if not _ok(int(log_entry.winner) in [-1, 1, band] and int(log_entry.sides["1"].people) > 0 and int(log_entry.sides[str(band)].people) > 0, "it names both sides and their people", log_entry): return
	for _frame: int in range(120):
		await process_frame
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
	var field: Variant = slot._region_original_labs.get(lair)
	if not _ok(field != null and is_instance_valid(field) and field.site_controller.battle_effects_due.is_empty(), "what the battle saves was flushed between two steps"): return
	var fought := 0
	for team: Dictionary in field.crowd_site.teams:
		if int(team.get("faction", -1)) != 1: continue
		for person: Variant in team.get("person_ids", []):
			var found: Dictionary = field.site_controller.person_actions._person(int(person), false)
			if not found.is_empty() and int(preload("res://scripts/terrain_lab/person_social.gd").combat_record(found.body).get("battles", 0)) >= 1: fought += 1
	if not _ok(fought >= 1, "%d official people carry the battle in their records" % fought): return
	var ended: Dictionary = slot.control.faction_registry.entries.get(str(band), {})
	if not preload("res://scripts/terrain_lab/site_bandit_ended.gd").members_left(field, band):
		# Nobody of the band is left: it ended (extinct, no lair) with the battle.
		if not _ok(str(ended.get("status", "")) == "extinct" and RegionFactionQuery.canonical_bandit(ended.get("bandit", {})).get("lair") == null, "the wiped-out band ended (status %s)" % str(ended.get("status", "")), ended): return
		_finished = true
		TerrainArmy.release_contact_source()
		await process_frame
		print("SITE_BANDIT_SUPPRESSION_E2E_PASS: ", checks, " checks (band wiped out)")
		quit(0)
		return
	if not _ok(str(ended.get("status", "")) == "active", "a band with members left goes on", ended): return
	# O2: what a band that won a raid takes on a Site nobody watches. That Site may not save the registry itself; the active
	# Site's controller saves the hoard and the Site's lower stock in one publication. (The stand-in settlement is read when
	# the winner is judged and gone before anything saves: no raid won a real settlement in this test.)
	var field_site: Dictionary = field.terrain.site
	if not field_site.get("inventory") is Dictionary: field_site["inventory"] = {}
	var stock_before := int(field_site.inventory.get("grain", 0))
	field_site.inventory["grain"] = stock_before + 200
	var real_settlement: Variant = field_site.get("settlement")
	field_site["settlement"] = {"version": 1, "settlement_id": "o2_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": 1, "offices": SiteOffices.default_offices("settlement", 0, false), "fall_record": SiteSettlement.empty_fall_record()}
	var verdict: Dictionary = Aftermath.judge(field.site_controller, {band: 3, 1: 0})
	if real_settlement == null: field_site.erase("settlement")
	else: field_site["settlement"] = real_settlement
	if not _ok(int(verdict.get("band", -1)) == band and int(verdict.get("taken", {}).get("grain", 0)) == 60, "the winning band would take 60 grain", verdict): return
	var hoard_before := int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("hoard", {}).get("grain", 0))
	var refused: Dictionary = Aftermath.apply(field.site_controller, verdict)
	if not _ok(not refused.get("ok", false) and int(field_site.inventory.grain) == stock_before + 200, "the unwatched Site cannot save it alone; its stock is unchanged", refused): return
	var saved: Dictionary = {}
	for _frame: int in range(600):
		saved = Aftermath.apply(field.site_controller, verdict, controller)
		if saved.get("ok", false): break
		await process_frame
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
	if not _ok(saved.get("ok", false), "the active Site's controller saves the plunder", saved): return
	if not _ok(int(field_site.inventory.get("grain", 0)) == stock_before + 140, "the unwatched Site's stock lost 60", field_site.inventory.get("grain")): return
	if not _ok(int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).hoard.get("grain", 0)) == hoard_before + 60, "the band's hoard gained 60"): return
	var lair_at: Vector2i = slot._coordinate(field.terrain).site
	var on_disk: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[slot._site_key(lair_at)].path)), lair_at)
	if not _ok(on_disk.ok and int(on_disk.data.site.get("inventory", {}).get("grain", -1)) == stock_before + 140, "the published file of the unwatched Site has the lower stock", on_disk.get("code")): return
	table = RegionFactionQuery.bandit_of(slot.control.faction_registry, band)
	# The band's next day: hot and attacked, it moves its lair.
	var next_day := int(table.attacked_day) + 1
	var ran: Dictionary = {}
	var moved := false
	for attempt: int in range(61):
		ran = BanditDay.run(controller, next_day)
		for row: Dictionary in ran.get("actions", []):
			if int(row.band) == band and str(row.action) == "move_lair" and bool(row.ok): moved = true
		if moved: break
		for _frame: int in range(60):
			await process_frame
			lab._process(1.0 / 30.0)
			controller.person_actions.settle_after_contacts()
	var after: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, band)
	if not _ok(moved and str(after.lair.site_id) != lair and int(after.heat) == Bandit.HEAT_AFTER_MOVE, "on its next day the attacked hot band moves its lair (heat 30)", [ran, after]): return
	# Stage 2 (2026-11-26): once no band person stands at the old lair, the expedition goes home and arrives there.
	var home := Suppression.home_of(slot.control.faction_registry, 1, next_day)
	if not _ok(not home.is_empty() and home != lair, "the expedition's home is recorded: %s" % home): return
	var homeward: Dictionary = {}
	var seen: Array = [] # each change of the refusal, in order, with the attempt and the game hours since the move
	var last := {}
	var same := 0
	var moved_at := float(slot.control.logical_game_seconds)
	for attempt: int in range(400):
		var at_lair: Variant = slot._region_original_labs.get(lair)
		if at_lair != null and is_instance_valid(at_lair):
			homeward = Suppression.go_home(at_lair.site_controller, next_day)
			if homeward.has("sent"): break
			if last != homeward:
				last = homeward
				seen.append([attempt, snappedf((float(slot.control.logical_game_seconds) - moved_at) / 3600.0, 0.01), homeward])
				same = 0
			same += 1
			# Fail fast: a refusal that is not waiting for the band or for the hold to settle does not change by itself.
			if same >= 20 and str(homeward.get("reason", "")) not in ["BAND_HERE", "HOLDING"]: break
		for _frame: int in range(30):
			await process_frame
			if _finished: return
			lab._process(1.0 / 30.0)
			controller.person_actions.settle_after_contacts()
	if not _ok(homeward.has("sent") and str(homeward.sent.home) == home, "with the band gone it goes home", seen): return
	var home_token := str(homeward.sent.token)
	var home_phase := ""
	var went_from := float(slot.control.logical_game_seconds)
	for frame: int in range(120000):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			_fail("a frame fault on the way home", controller._original_step_fault)
			return
		home_phase = str(slot.region_registry().parties.get(home_token, {}).get("phase", ""))
		if home_phase in ["entered", ""]: break
	var hours_home := (float(slot.control.logical_game_seconds) - went_from) / 3600.0
	if not _ok(home_phase in ["entered", ""] and hours_home < 48.0, "it arrived home after %.1f game hours (phase '%s')" % [hours_home, home_phase]): return
	print("SITE_BANDIT_SUPPRESSION_E2E HOME %s after %.1f game hours; on the way out: %s" % [home, hours_home, JSON.stringify(seen)])
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	print("SITE_BANDIT_SUPPRESSION_E2E_PASS: ", checks, " checks")
	quit(0)
