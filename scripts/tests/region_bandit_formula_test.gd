extends SceneTree
## 公式遠征 (Nekki 2026-11-25 B and A; region_bandit_formula.gd). A small generated scenario world (6 settlements, 3 bands,
## 1 town) opens on its empty start Site. Checks:
## - pure: the outcome of a raid (square law, at least one on their feet, a lost raid takes nothing), the rest days, the
##   same settlement not again within 30 days, the table rows (merged while in the same file, dropped when void);
## - the saved files, read raw, tell the owner, the people and the stock that are in them;
## - no raid before day 1; on day 1 every band whose lair is closed raids the settlement it picks: heat +10, the loot joins
##   the hoard and is owed by the Site, never more than its file holds; the day runs once; the registry is valid;
## - the same roll on the same day; the owed loot leaves an opened body exactly, with a notice;
## - a settlement that is open musters the lair instead: it is bound at the next hour and its band really leaves for it;
## - a raided settlement really opened (bound) carries the notice; once it is published nothing is owed any more.
## Output: REGION_BANDIT_FORMULA_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Formula = preload("res://scripts/region_lab/region_bandit_formula.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

var checks := 0
var _finished := false
var lab: TerrainLab
var slot: RegionSaveSlot
var hold := "" # a Site kept bound: the idle release would let it go after six quiet hours

func _initialize() -> void:
	create_timer(3000.0).timeout.connect(func() -> void: _fail("3000-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("REGION_BANDIT_FORMULA_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BANDIT_FORMULA OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _frame() -> bool:
	await process_frame
	if _finished: return false
	if not hold.is_empty(): slot._idle_since[hold] = float(slot.control.logical_game_seconds)
	lab._process(1.0 / 30.0)
	lab.site_controller.person_actions.settle_after_contacts()
	if not lab.site_controller._original_step_fault.is_empty(): return _fail("a step fault", lab.site_controller._original_step_fault)
	return true

func _bind(id: String) -> Dictionary:
	lab.set_process(false)
	var bound: Dictionary = {}
	for attempt: int in range(6000):
		bound = lab._region_gameplay_owner_lab(id, "cold_exact")
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	lab.set_process(true)
	return bound

func _pure() -> bool:
	var strong: Dictionary = Formula.outcome(8, 2.0, 0.5)
	if not _ok(strong.won and int(strong.standing) == 8, "8 against 2: won, eight on their feet (sqrt 61)", strong): return false
	var close: Dictionary = Formula.outcome(6, 5.0, 0.5)
	if not _ok(close.won and int(close.standing) == 4, "6 against 5: won by a roll of 0.5, four on their feet (sqrt 17)", close): return false
	var lost: Dictionary = Formula.outcome(6, 5.0, 0.82)
	if not _ok(not lost.won and int(lost.standing) == 0, "6 against 5: lost by a roll of 0.82 (odds 1.2 to the eighth, 81 in 100)", lost): return false
	if not _ok(not Formula.outcome(7, 7.0, 0.51).won and Formula.outcome(7, 7.0, 0.49).won and Formula.outcome(9, 7.0, 0.88).won and not Formula.outcome(9, 7.0, 0.89).won, "an even fight is a coin, 9 against 7 is won 88 times in 100"): return false
	var people := {"3": {"armed": 2, "civil": 10}, "101": {"armed": 9, "civil": 0}, "255": {"armed": 6, "civil": 0}}
	if not _ok(Formula.defence(people, 101) == 7.0 and Formula.estimate(people, 101) == 7.0 and Formula.attack(people, 101) == 9, "a village of 2 soldiers and 10 residents is 7 strong; the band and the neutral side do not count"): return false
	var lucky: Dictionary = Formula.outcome(3, 3.0, 0.4)
	if not _ok(lucky.won and int(lucky.standing) == 2, "an even win of three leaves two on their feet", lucky): return false
	if not _ok(not Formula.outcome(0, 1.0, 0.0).won, "nobody wins nothing"): return false
	var table := {"raided": {}}
	Bandit.note_raided(table, "a:1:1", 5, {"grain": 10}, "generations/f1.json")
	if not _ok(not Bandit.raid_rested(table, 14) and Bandit.raid_rested(table, 15), "the band rests ten days after a raid"): return false
	if not _ok(Bandit.raided_lately(table, "a:1:1", 34) and not Bandit.raided_lately(table, "a:1:1", 35) and not Bandit.raided_lately(table, "a:1:2", 6), "and not the same settlement again within 30"): return false
	Bandit.note_raided(table, "a:1:1", 40, {"grain": 5, "wood": 2}, "generations/f1.json")
	if not _ok(table.raided["a:1:1"] == {"day": 40, "taken": {"grain": 15, "wood": 2}, "source": "generations/f1.json"}, "two loots out of the same file add up", table): return false
	Bandit.note_raided(table, "a:1:1", 41, {}, "")
	if not _ok(table.raided["a:1:1"] == {"day": 41, "taken": {"grain": 15, "wood": 2}, "source": "generations/f1.json"}, "a really fought raid keeps what is owed", table): return false
	Bandit.note_raided(table, "a:1:1", 80, {"grain": 7}, "generations/f2.json")
	if not _ok(table.raided["a:1:1"].taken == {"grain": 7}, "a newer file starts anew", table): return false
	Bandit.note_raided(table, "a:2:2", 90, {}, "")
	Bandit.note_raided(table, "a:3:3", 130, {"iron": 1}, "generations/f9.json")
	return _ok(not table.raided.has("a:2:2") and table.raided.has("a:1:1"), "an old row nothing depends on is dropped, an owed one stays", table)

func _run() -> void:
	if not _pure(): return
	var folder := "user://bandit_formula_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "公式遠征", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 1200000
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the world is born and opens"): return
	for _warm: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	slot = controller.region_slot
	var registry: Dictionary = slot.control.faction_registry
	var lairs := {}
	for key: Variant in registry.entries:
		var band := int(registry.entries[key].faction_id)
		if registry.entries[key].get("status") != "active" or not RegionFactionQuery.is_bandit(registry, band): continue
		var lair: Variant = RegionFactionQuery.bandit_of(registry, band).get("lair")
		if lair is Dictionary: lairs[band] = str(lair.site_id)
	if not _ok(lairs.size() == 3, "three bands have lairs", lairs): return

	# The files: read raw, against the loaded Site.
	var read_from := Time.get_ticks_usec()
	for key: Variant in slot._marker.sites: Formula.summary(slot, str(key))
	print("REGION_BANDIT_FORMULA READ %d files in %d us" % [slot._marker.sites.size(), Time.get_ticks_usec() - read_from])
	var checked := 0
	for key: Variant in slot._marker.sites:
		var read: Dictionary = Formula.summary(slot, str(key))
		if not _ok(read.get("ok", false), "%s is read" % str(key), read): return
		var parts: PackedStringArray = str(key).split(":")
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[key].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not _ok(loaded.ok, "%s loads" % str(key)): return
		var same: Dictionary = Formula.summary_of(loaded.data.site)
		var plain: Dictionary = read.summary.duplicate()
		var lived: Array = [plain, same.duplicate()].map(func(value: Dictionary) -> Dictionary:
			value.erase("living")
			value.erase("run")
			return value)
		if not _ok(lived[0] == lived[1], "%s reads raw as the loaded Site: owner %d people %s stock %s" % [str(key), int(read.summary.owner), JSON.stringify(read.summary.people), JSON.stringify(read.summary.stock)], same): return
		# 居民吃飯 L2: ten days of its harvests and meals, read raw or loaded, come to the same.
		if not _ok(read.summary.living.is_empty() == same.living.is_empty(), "%s feeds its people or not, either way" % str(key)): return
		var later := {"control": {"logical_game_seconds": float(slot.control.logical_game_seconds) + 10.0 * 86400.0, "faction_registry": slot.control.faction_registry}}
		var raw_copy: Dictionary = read.summary.duplicate(true)
		raw_copy.erase("run")
		var raw_stock: Dictionary = Formula.stock_now(later, raw_copy)
		var loaded_stock: Dictionary = Formula.stock_now(later, same)
		if not _ok(JSON.stringify(raw_stock, "", true) == JSON.stringify(loaded_stock, "", true), "%s in ten days: %s" % [str(key), JSON.stringify(raw_stock)], loaded_stock): return
		if not same.living.is_empty() and not _ok(int(raw_stock.get("grain", 0)) != int(read.summary.stock.get("grain", 0)), "its grain moves from %d" % int(read.summary.stock.get("grain", 0))): return
		checked += 1
	if not _ok(checked == slot._marker.sites.size(), "every saved Site was compared"): return

	# The band whose pick is bound (open) first, and what the others pick.
	var picks := {}
	for band: int in lairs:
		var known: Array = Formula.known_settlements(slot, band, lairs[band])
		if not _ok(not known.is_empty(), "the chief of %d knows the settlements around %s" % [band, lairs[band]], known): return
		for target: Dictionary in known:
			if not _ok(Bandit.site_distance(lairs[band], str(target.site_id)) <= Bandit.REACH_SITES and not bool(target.open) and int(target.faction) != band, "%s is within reach: strength %.2f stock %s" % [str(target.site_id), float(target.strength), JSON.stringify(target.stock)]): return
			if not _ok(float(target.defence) >= float(target.strength), "its defence is %.2f" % float(target.defence)): return
		var attackers := Formula.attack(Formula.summary(slot, Formula.site_key(lairs[band])).summary.people, band)
		var pick: Dictionary = Bandit.pick_raid(registry, band, known, float(attackers), 1)
		print("REGION_BANDIT_FORMULA PICK band=%d attackers=%d -> %s" % [band, attackers, JSON.stringify(pick)])
		if not pick.is_empty(): picks[band] = {"target": str(pick.site_id), "attackers": attackers}
	if not _ok(picks.size() >= 2, "at least two bands have a settlement to raid", picks): return
	var bands: Array = picks.keys()
	bands.sort()
	var mustering := int(bands[0])
	var open_target := str(picks[mustering].target)
	var bound: Dictionary = await _bind(open_target)
	if not _ok(bound.get("ok", false), "%s, the pick of band %d, is open" % [open_target, mustering], bound): return
	hold = open_target
	if not _ok(Formula.is_open(slot, open_target) and not Formula.is_open(slot, lairs[mustering]), "open and closed are told apart"): return
	var seen: Dictionary = Formula.open_settlement(slot, open_target, mustering)
	if not _ok(not seen.is_empty() and bool(seen.open) and float(seen.strength) > 0.0, "an open settlement is counted from its people: %.2f" % float(seen.get("strength", 0.0)), seen): return

	# Day 0: nothing. Day 1: the raids.
	if not _ok(Formula.day(controller).is_empty(), "nothing is raided on the first day"): return
	var heat_before := {}
	var hoard_before := {}
	for band: int in lairs:
		heat_before[band] = int(RegionFactionQuery.bandit_of(registry, band).heat)
		hoard_before[band] = RegionFactionQuery.bandit_of(registry, band).get("hoard", {}).duplicate()
	lab.simulation_speed = 16.0
	var result: Dictionary = {}
	for frame: int in range(12000):
		if not await _frame(): return
		if int(slot.get_meta(&"bandit_formula_day", -1)) >= 1:
			result = slot.get_meta(&"bandit_formula_last", {})
			break
	if not _ok(int(result.get("day", -1)) == 1, "the first day's raids were settled", [slot.get_meta(&"bandit_formula_last", {}), slot.get_meta(&"bandit_formula_refused", {}), float(slot.control.logical_game_seconds)]): return
	print("REGION_BANDIT_FORMULA DAY %s" % JSON.stringify(result))
	registry = slot.control.faction_registry
	if not _ok(RegionFactionQuery.validate(registry, float(slot.control.logical_game_seconds)).ok, "the registry is valid"): return
	if not _ok(not result.raids.is_empty() and result.raids.all(func(row: Dictionary) -> bool: return bool(row.ok)), "bands raided", result): return
	for row: Dictionary in result.raids:
		var table: Dictionary = RegionFactionQuery.bandit_of(registry, int(row.band))
		if not _ok(int(table.heat) == mini(100, int(heat_before[int(row.band)]) + 10), "band %d is hotter by 10" % int(row.band), [heat_before, table.heat]): return
		var owed: Dictionary = table.raided[str(row.target)]
		if not _ok(int(owed.day) == 1 and owed.taken == row.taken and (row.taken.is_empty() or bool(row.won)), "%s owes what was taken: %s" % [str(row.target), JSON.stringify(row.taken)], owed): return
		for item: String in row.taken:
			if not _ok(int(table.hoard[item]) == int(hoard_before[int(row.band)].get(item, 0)) + int(row.taken[item]), "the hoard of %d holds it: %s" % [int(row.band), item]): return
		var stock: Dictionary = Formula.stock_now(slot, Formula.summary(slot, Formula.site_key(str(row.target))).summary)
		var all_owed: Dictionary = Formula.debts(slot, str(row.target)).taken
		for item: String in all_owed:
			if not _ok(int(all_owed[item]) <= int(stock.get(item, 0)), "%s owes no more %s than it has" % [str(row.target), item], [all_owed, stock]): return
		if not _ok(Formula.roll(slot, int(row.band), str(row.target), 1) == Formula.roll(slot, int(row.band), str(row.target), 1), "the same day rolls the same"): return
	for row: Dictionary in result.raids:
		var gone := int(RegionFactionQuery.bandit_of(registry, int(row.band)).get("fallen", 0))
		if not _ok(gone == int(row.lost) and (gone == 0) == bool(row.won) and int(row.lost) == (0 if bool(row.won) else int(row.attackers) - floori(float(row.attackers) * 0.5)), "a lost raid costs half: %d of %d" % [gone, int(row.attackers)], row): return
	slot.remove_meta(&"bandit_formula_day")
	var again: Dictionary = Formula.day(controller)
	if not _ok(again.get("raids", []).is_empty() and slot.control.faction_registry == registry, "a reload the same day raids nobody twice (the bands rest)", again): return
	if not _ok(result.mustered.any(func(row: Dictionary) -> bool: return int(row.band) == mustering and str(row.target) == open_target), "band %d musters for the open settlement" % mustering, result): return

	# The owed loot leaves an opened body exactly (a loot written for the third band: the day's rolls may all have lost).
	var third := 103
	var third_target := ""
	for target: Dictionary in Formula.known_settlements(slot, third, lairs[third]):
		if not bool(target.open) and not result.raids.any(func(row: Dictionary) -> bool: return str(row.target) == str(target.site_id)): third_target = str(target.site_id)
	if not _ok(not third_target.is_empty(), "a third settlement is closed and unraided"): return
	var written: Dictionary = Bandit.raided(slot.control.faction_registry, third, third_target, 1, {"grain": 30, "wood": 5}, str(slot._marker.sites[Formula.site_key(third_target)].path), float(slot.control.logical_game_seconds))
	if not _ok(written.ok and controller._commit_diplomacy(written, "").ok, "a loot of 30 grain and 5 wood is owed by %s" % third_target, written): return
	var raid := {"band": third, "target": third_target}
	var raided_key := Formula.site_key(str(raid.target))
	var raided_at: PackedStringArray = raided_key.split(":")
	var body: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[raided_key].path)), Vector2i(int(raided_at[0]), int(raided_at[1])))
	var owner := int(Settlement.record(body.data).owner_faction)
	var stock_before: Dictionary = Aftermath.stock_of(body.data.site, owner)
	var debts: Dictionary = Formula.debts(slot, str(raid.target)).taken
	var applied: Array = Formula.apply_to(slot, body.data)
	var stock_after: Dictionary = Aftermath.stock_of(body.data.site, owner)
	var exact := not applied.is_empty()
	for item: String in stock_before: exact = exact and int(stock_after.get(item, 0)) == int(stock_before[item]) - int(debts.get(item, 0))
	if not _ok(exact and SiteStockpiles.validate(body.data.site).ok, "the opened body lost exactly the loot: %s - %s = %s" % [JSON.stringify(stock_before), JSON.stringify(debts), JSON.stringify(stock_after)]): return
	if not _ok(str(slot.get_meta(&"bandit_loot_news", {}).get(str(raid.target), [])).contains("劫掠"), "the news of it waits", slot.get_meta(&"bandit_loot_news", {})): return
	slot.remove_meta(&"bandit_loot_news")

	# The mustered lair: bound at the next hour, its band leaves for the open settlement with the next day's move.
	var lair: String = lairs[mustering]
	var mustered_at := -1.0
	var went := ""
	var from := float(slot.control.logical_game_seconds)
	for frame: int in range(30000):
		if not await _frame(): return
		var hours := (float(slot.control.logical_game_seconds) - from) / 3600.0
		if mustered_at < 0.0 and slot._region_original_labs.has(lair):
			mustered_at = hours
			print("REGION_BANDIT_FORMULA MUSTERED %s at %.2f hours, block %s" % [lair, hours, slot.idle_release_block(lair)])
		for token: Variant in slot.region_registry().parties:
			if str(token).begins_with("band_raid_"): went = str(token)
		if not went.is_empty() or hours > 30.0: break
	if not _ok(mustered_at >= 0.0 and mustered_at <= 1.2, "the lair was bound within the hour (%.2f)" % mustered_at): return
	if not _ok(not went.is_empty(), "its band really left", {"hours": (float(slot.control.logical_game_seconds) - from) / 3600.0, "bound": slot._region_original_labs.keys()}): return
	var plan: Dictionary = slot._region_npc_plan(went)
	var goal: Array = plan.plan.steps.back().site if plan.ok else []
	if not _ok(goal.size() == 2 and "%s:%d:%d" % [str(slot.pin.atlas_id), int(goal[0]), int(goal[1])] == open_target, "for the open settlement", goal): return

	# The people a band lost stand in its lair's file: once the lair is open they die there, the chief last, and the
	# registry forgets them.
	var loser := 103
	if not slot._region_original_labs.has(lairs[loser]):
		var opened_lair: Dictionary = await _bind(lairs[loser])
		if not _ok(opened_lair.get("ok", false), "the lair of %d is opened" % loser, opened_lair): return
	hold = lairs[loser]
	var den: TerrainLab = slot._region_original_labs[lairs[loser]]
	var alive_before := 0
	for person: Variant in den.crowd_site._index_by_id: alive_before += 1 if float(den.site_controller.person_actions._person(int(person), false).get("hp", 0.0)) > 0.0 else 0
	var chief: int = slot.person_id_of_ref(slot.control.faction_registry.entries[str(loser)].leader_ref)
	var owed_dead := int(RegionFactionQuery.bandit_of(slot.control.faction_registry, loser).get("fallen", 0))
	var lose: Dictionary = Bandit.raided(slot.control.faction_registry, loser, third_target, 1, {}, "", float(slot.control.logical_game_seconds), 4)
	if not _ok(lose.ok and controller._commit_diplomacy(lose, "").ok, "band %d lost four people" % loser, lose): return
	var cleared := false
	for frame: int in range(6000):
		if not await _frame(): return
		if not RegionFactionQuery.bandit_of(slot.control.faction_registry, loser).has("fallen"):
			cleared = true
			break
	var alive_after := 0
	for person: Variant in den.crowd_site._index_by_id: alive_after += 1 if float(den.site_controller.person_actions._person(int(person), false).get("hp", 0.0)) > 0.0 else 0
	if not _ok(cleared and alive_before - alive_after == owed_dead + 4, "four died in the lair (%d -> %d) and the registry forgot them" % [alive_before, alive_after], [cleared, owed_dead, RegionFactionQuery.bandit_of(slot.control.faction_registry, loser)]): return
	if not _ok(float(den.site_controller.person_actions._person(chief, false).get("hp", 0.0)) > 0.0, "the chief is alive"): return

	# The raided settlement is really opened: the notice is there, and published nothing is owed any more.
	if str(raid.target) != open_target:
		var opened: Dictionary = await _bind(str(raid.target))
		if not _ok(opened.get("ok", false), "%s is opened" % str(raid.target), opened): return
		var site_now: Dictionary = opened.lab.terrain.site
		if not _ok(str(slot.get_meta(&"bandit_loot_news", {}).get(str(raid.target), [])).contains("劫掠"), "the news waits for whoever stands there", slot.get_meta(&"bandit_loot_news", {})): return
		var wood_now := int(Aftermath.stock_of(site_now, owner).get("wood", 0))
		if not _ok(wood_now <= int(stock_before.get("wood", 0)) - int(debts.get("wood", 0)), "the loot left the opened settlement: wood %d of %d" % [wood_now, int(stock_before.get("wood", 0))]): return
		print("REGION_BANDIT_FORMULA OPENED stock %s, file stock %s, owed %s" % [JSON.stringify(Aftermath.stock_of(site_now, owner)), JSON.stringify(stock_before), JSON.stringify(debts)])
		var saved: Dictionary = controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
		if not _ok(saved.ok and Formula.debts(slot, str(raid.target)).rows.is_empty(), "once it is published nothing is owed any more", [saved, Formula.debts(slot, str(raid.target))]): return
	TerrainArmy.release_contact_source()
	await process_frame
	_finished = true
	print("REGION_BANDIT_FORMULA_PASS: ", checks, " checks")
	quit(0)
