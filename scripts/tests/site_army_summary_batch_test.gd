extends "res://scripts/tests/site_single_troop_contract_test.gd"
## Original owner fixtures only; no scene startup, rendering, save or clock work.

class AssetCallback extends RefCounted:
	var calls := 0
	var victim: TerrainArmy
	var thread_ids: Array[int] = []
	func _to_string() -> String:
		assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "Coercion must never enter a worker")
		calls += 1
		thread_ids.append(OS.get_thread_caller_id())
		victim.combat_hot_set(3, &"hp", 0.0)
		victim.command_notice = "Changed by earlier equipment coercion"
		return "longsword_01"

class OrderedArmy extends TerrainArmy:
	var events: Array[String] = []
	var victim: TerrainArmy
	func has_army() -> bool:
		events.append("prefix")
		return super.has_army()
	func combat_summary() -> String:
		events.append("summary")
		victim.combat_hot_set(3, &"hp", 0.0)
		victim.command_notice = "Changed by earlier custom Army"
		return super.combat_summary()

class OrderedActor extends TerrainTestCharacter:
	var calls := 0
	var victim: TerrainArmy
	func combat_identity() -> int:
		calls += 1
		victim.combat_hot_set(3, &"hp", 0.0)
		victim.command_notice = "Changed by earlier Actor identity"
		return person_id

class OtherHot extends RefCounted:
	var calls := 0
	func row_count() -> int:
		calls += 1
		return 128
	func read_summary(_a: Variant, _b: Variant, _c: Variant, _d: Variant, _e: Variant, _f: Variant) -> Array:
		calls += 1
		return []

class OrderedController extends SiteController:
	var calls := 0
	var victim: TerrainArmy
	func _trial_team_choice_text(team: TerrainArmy) -> String:
		calls += 1
		if team.team_id == 4:
			victim.combat_hot_set(3, &"hp", 0.0)
			victim.command_notice = "Changed by earlier custom prefix"
		return super._trial_team_choice_text(team)

var batch_map := TerrainData.new()
var batch_teams: Array[TerrainArmy] = []
var batch_lab := TerrainLab.new()
var batch_ui := SiteController.new()
var batch_window := Window.new()
var batch_label := Label.new()
var batch_checks := 0

func _make_batch_team(ordinal: int) -> TerrainArmy:
	var team := TerrainArmy.new()
	team.data = batch_map
	team.team_id = ordinal + 1
	team.roster_size = 128
	team.combat_enabled = true
	team.formal_commander = 0
	team.current_commander = 1
	team.officer_order.assign([2])
	team.command_abilities = {0: {"tactics": 65, "leadership": 72.75, "coach": 39}}
	team.command_status = "Team %d original status" % ordinal
	team.command_notice = "Original notice"
	team.team_fatigue = {"fatigue": 17.25 + ordinal, "fatigue_rest": 0.0, "count": 128, "active": true}
	var definition := "definition:%d:arbitrary" % ordinal
	batch_map.site.item_definitions[definition] = {"asset": ["longsword_01", "bow_01", "crossbow_01"][ordinal % 3]}
	for index in range(128):
		var item := "item:%d:%d:original" % [ordinal, index]
		batch_map.site.item_records[item] = {"definition": definition}
		var row := {"person_id": 9007199254740993 + ordinal * 1000 + index,
			"hp": 0.0 if index == 5 else 100.0, "ko": 4.0 if index == 6 else 0.0,
			"age": 0.0, "think": 0.5, "stun": 0.0, "grace": 0.0, "pose": "idle",
			"attack": false, "member": index != 7, "captive": false, "departed": index == 8, "present": true,
			"fatigue": 3.0, "_fatigue_pool": team.team_fatigue,
			"item_state": {"equipped": {"weapon": item}}, "appearance": {"parts": {"weapon": "longsword_01"}}}
		if ordinal == 0:
			row._fatigue_pool = {}
			row.fatigue = [1.0e16, 1.0, -1.0e16, 1.0][index % 4]
		if ordinal == 1:
			var identity: Variant = row.person_id
			row.erase("person_id")
			row[&"person_id"] = identity
		team.combat_units.append(row)
		team.cells.append(Vector2i(index % 16, floori(float(index) / 16.0)))
	if ordinal == 0: team.team_fatigue = {}
	team.native_hot_enabled = true
	assert(team._try_install_combat_hot_store())
	return team

func _batch_state() -> PackedByteArray:
	var values: Array = [batch_map.site]
	for team: TerrainArmy in batch_teams:
		values.append([team.combat_units, team._combat_hot_store.capture_rows(), team.team_fatigue,
			team.cells, team.formal_commander, team.current_commander, team.officer_order,
			team.command_abilities, team.command_status, team.command_notice])
		if is_instance_valid(team.player_member):
			var actor := team.player_member
			values.append([actor.person_id, actor.hp, actor.fatigue, actor._fatigue_pool,
				actor.item_state, actor._saved_appearance])
	return var_to_bytes(values)

func _batch_reference_packet(team: TerrainArmy) -> Array:
	var alive := 0
	var knocked := 0
	var dead := 0
	var total_fatigue := 0.0
	var living := 0
	var tired := 0
	var kind := &""
	var exempt := team._troop_exempt_ids()
	for index in range(team.combat_units.size()):
		var row: Dictionary = team.combat_units[index]
		var hp := float(team.combat_hot_get(index, &"hp"))
		var departed := bool(team.combat_hot_get(index, &"departed"))
		if hp > 0.0 and not departed:
			living += 1
			var fatigue := PersonFatigue.read(row)
			total_fatigue += fatigue
			tired += int(fatigue > PersonFatigue.THRESHOLD)
		if kind != &"mixed" and hp > 0.0 and not departed and team.is_member(index) and not exempt.has(team.combat_identity(index)):
			var current := _legacy_row_class(row, team.data.site)
			if current != &"": kind = current if kind == &"" or kind == current else &"mixed"
		if hp <= 0.0: dead += 1
		elif float(team.combat_hot_get(index, &"ko")) > 0.0: knocked += 1
		else: alive += 1
	return [alive, knocked, dead, total_fatigue, living, tired, kind]

func _check_batch() -> void:
	var expected := PackedStringArray()
	var packets: Array = []
	var job := TerrainArmy._CombatSummaryBatch.new()
	for team: TerrainArmy in batch_teams:
		expected.append(_legacy_summary(team))
		packets.append(_batch_reference_packet(team))
		var request := team._combat_summary_batch_request()
		assert(request.size() == 7)
		job.requests.append(request)
		team.combat_hot_diagnostics_enabled = true
		team.combat_hot_reset_stats()
	job.requests.make_read_only()
	var before := _batch_state()
	assert(var_to_bytes(job.collect()) == var_to_bytes(packets), "Joined native packets must preserve all seven values/types and serial summation")
	assert(not job.thread_ids.has(0) and not job.thread_ids.has(OS.get_main_thread_id()), "All four pure-query chunks must actually execute off-main")
	assert(TerrainArmy.combat_summaries(batch_teams) == expected, "Batch text must equal the independent original full-summary oracle")
	assert(_batch_state() == before, "Batch must leave original cold/hot/ledger/command state byte-identical")
	for index in range(batch_teams.size()):
		var team := batch_teams[index]
		assert(is_same(job.requests[index][1], team.combat_units) and is_same(job.requests[index][2], batch_map.site.item_records)
			and is_same(job.requests[index][3], batch_map.site.item_definitions) and job.requests[index][0] == team._combat_hot_store)
		var stats := team.combat_hot_stats()
		assert(int(stats.native_calls) == 1 and int(stats.native_rows) == 128 and int(stats.materialized_rows) == 0)
	batch_checks += 1

func _ordered_ui(ui: SiteController) -> String:
	# Frozen original prefix -> summary order, including the non-combat branch.
	var texts := PackedStringArray()
	for team: TerrainArmy in batch_teams:
		if not team.has_army(): continue
		if team.combat_enabled:
			texts.append(ui._trial_team_choice_text(team) + "\n" + team.combat_summary())
		else:
			texts.append("隊伍 #%d · 陣營 %d · %d 人\n%s\n陣型：%s · 站位 %d · 移動 %d" % [team.team_id, team.faction_id + 1, team.roster_size, team.command_status, team.formation_mode_name(), team.occupied_count(), team.moving_count()])
	return "\n\n".join(texts)

func _check_ui() -> void:
	var expected := _ordered_ui(batch_ui)
	var before := _batch_state()
	batch_ui._update_team_info()
	assert(batch_label.text == expected and _batch_state() == before)
	batch_checks += 1

func _restore_victim(team: TerrainArmy, hp: Variant, notice: String) -> void:
	team.combat_hot_set(3, &"hp", hp)
	team.command_notice = notice

func _callback_contracts() -> void:
	var victim := batch_teams[6]
	var hp: Variant = victim.combat_hot_get(3, &"hp")
	var notice := victim.command_notice
	var definition: Dictionary = batch_map.site.item_definitions["definition:3:arbitrary"]
	var asset: Variant = definition.asset
	var callback := AssetCallback.new()
	callback.victim = victim
	definition.asset = callback
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty())
	assert(callback.calls == 0 and victim.combat_hot_get(3, &"hp") == hp and victim.command_notice == notice,
		"Worker rejection must not coerce an Object or format/fallback any team early")
	var expected := _ordered_ui(batch_ui)
	var expected_calls := callback.calls
	var expected_state := _batch_state()
	assert(expected_calls > 0)
	_restore_victim(victim, hp, notice)
	callback.calls = 0
	callback.thread_ids.clear()
	batch_ui._update_team_info()
	assert(batch_label.text == expected and _batch_state() == expected_state and callback.calls == expected_calls)
	for thread: int in callback.thread_ids: assert(thread == OS.get_main_thread_id())
	definition.asset = asset
	_restore_victim(victim, hp, notice)
	var original := batch_teams[3]
	var custom := OrderedArmy.new()
	for field: String in ["data", "team_id", "roster_size", "combat_enabled", "formal_commander", "current_commander",
		"command_abilities", "command_status", "command_notice", "team_fatigue", "_combat_hot_store"]:
		custom.set(field, original.get(field))
	custom.combat_units.assign(original.combat_units)
	custom.cells.assign(original.cells)
	custom.officer_order.assign(original.officer_order)
	custom.victim = victim
	batch_teams[3] = custom
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty() and custom.events.is_empty(), "Custom methods must not run during admission")
	expected = _ordered_ui(batch_ui)
	var events := custom.events.duplicate()
	expected_state = _batch_state()
	assert(events == ["prefix", "prefix", "summary"])
	_restore_victim(victim, hp, notice)
	custom.events.clear()
	batch_ui._update_team_info()
	assert(batch_label.text == expected and custom.events == events and _batch_state() == expected_state)
	batch_teams[3] = original
	custom._combat_hot_store = null
	custom.free()
	_restore_victim(victim, hp, notice)
	var actor := OrderedActor.new()
	actor.person_id = 41
	actor.hp = 91.0
	actor.fatigue = 79.0
	actor.victim = victim
	var commander := original.formal_commander
	original.player_member = actor
	original.formal_commander = TerrainArmy.PLAYER_MEMBER
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty() and actor.calls == 0, "Actor identity/fatigue/classification remains at its original serial position")
	expected = _ordered_ui(batch_ui)
	expected_calls = actor.calls
	expected_state = _batch_state()
	_restore_victim(victim, hp, notice)
	actor.calls = 0
	batch_ui._update_team_info()
	assert(batch_label.text == expected and actor.calls == expected_calls and expected_calls > 0 and _batch_state() == expected_state)
	original.player_member = null
	original.formal_commander = commander
	actor.free()
	_restore_victim(victim, hp, notice)
	var custom_ui := OrderedController.new()
	custom_ui.lab = batch_lab
	custom_ui.formal_windows = batch_ui.formal_windows
	custom_ui.team_info_label = batch_label
	custom_ui.victim = victim
	expected = _ordered_ui(custom_ui)
	expected_state = _batch_state()
	_restore_victim(victim, hp, notice)
	custom_ui.calls = 0
	custom_ui._update_team_info()
	assert(batch_label.text == expected and custom_ui.calls == 8 and _batch_state() == expected_state, "Custom prefix must precede its own and later-team summaries")
	custom_ui.free()
	_restore_victim(victim, hp, notice)
	batch_checks += 4

func _fallback_contracts() -> void:
	var team := batch_teams[3]
	team.native_summary_enabled = false
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty())
	_check_ui()
	team.native_summary_enabled = true
	team._borrow_combat_hot_row(4)
	var ko: Variant = team.combat_hot_get(4, &"ko")
	team.combat_hot_set(4, &"ko", 13.0)
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty())
	_check_ui()
	team.combat_hot_set(4, &"ko", ko)
	team._return_combat_hot_row()
	var store: RefCounted = team._combat_hot_store
	var other := OtherHot.new()
	team._combat_hot_store = other
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty() and other.calls == 0, "Unknown/older owner must reject before calling its methods")
	team._combat_hot_store = store
	var row: Dictionary = team.combat_units[3]
	var typed: Dictionary[String, Variant] = {}
	for key: Variant in row: typed[str(key)] = row[key]
	team.combat_units[3] = typed
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty(), "One typed/native-rejected middle team invalidates the entire batch")
	_check_ui()
	team.combat_units[3] = row
	var ability: Variant = team.command_abilities[0].tactics
	team.command_abilities[0].tactics = "61"
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty(), "Formatter coercions retain the original serial path")
	_check_ui()
	team.command_abilities[0].tactics = ability
	var unexpected := AssetCallback.new()
	unexpected.victim = batch_teams[6]
	team.command_abilities[0].tactics = unexpected
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty() and unexpected.calls == 0)
	team.command_abilities[0].tactics = ability
	var fatigue: Variant = team.team_fatigue.fatigue
	team.team_fatigue.fatigue = "22.5"
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty())
	_check_ui()
	team.team_fatigue.fatigue = fatigue
	team.team_fatigue.fatigue = unexpected
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty() and unexpected.calls == 0)
	team.team_fatigue.fatigue = fatigue
	var identity: Variant = team.combat_units[0].person_id
	team.combat_units[0].person_id = str(identity)
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty(), "Commander coercion must not be hoisted into admission")
	_check_ui()
	team.combat_units[0].person_id = identity
	team.combat_units[0].person_id = unexpected
	assert(TerrainArmy.combat_summaries(batch_teams).is_empty() and unexpected.calls == 0)
	team.combat_units[0].person_id = identity
	var small: Array[TerrainArmy] = [batch_teams[0], batch_teams[1]]
	assert(TerrainArmy.combat_summaries(small).is_empty())
	small.assign([batch_teams[0], batch_teams[1], batch_teams[2], batch_teams[3]])
	assert(TerrainArmy.combat_summaries(small).is_empty(), "Small batches retain the existing serial loop")
	team.combat_enabled = false
	_check_ui()
	team.combat_enabled = true
	batch_checks += 4

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("Summary batch contract deadline"); quit(1))
	assert(TerrainArmy._get_idle_kernel() != null)
	batch_map.site = {"item_records": {}, "item_definitions": {}}
	for index in range(8): batch_teams.append(_make_batch_team(index))
	batch_lab.combat_armies = batch_teams
	batch_ui.lab = batch_lab
	batch_ui.formal_windows = {"team_info": batch_window}
	batch_ui.team_info_label = batch_label
	batch_window.visible = true
	_check_batch()
	_check_ui()
	var row: Dictionary = batch_teams[1].combat_units[64]
	batch_teams[1].combat_units[64] = batch_teams[0].combat_units[64]
	_check_batch() # Shared cold dictionaries are read-only across workers.
	batch_teams[1].combat_units[64] = row
	var readonly := row.duplicate(true)
	readonly.item_state.equipped.make_read_only()
	readonly.item_state.make_read_only()
	readonly.make_read_only()
	batch_teams[1].combat_units[64] = readonly
	_check_batch()
	assert(readonly.is_read_only() and readonly.item_state.is_read_only() and readonly.item_state.equipped.is_read_only())
	batch_teams[1].combat_units[64] = row
	var definition: Dictionary = batch_map.site.item_definitions["definition:4:arbitrary"]
	var asset: Variant = definition.asset
	definition.asset = "crossbow_01"
	_check_batch() # The same dictionary identity changes between calls.
	definition.asset = asset
	_fallback_contracts()
	_callback_contracts()
	_check_batch()
	batch_window.visible = false
	batch_label.text = "Hidden sentinel"
	for team: TerrainArmy in batch_teams: team.combat_hot_reset_stats()
	batch_ui._update_team_info()
	assert(batch_label.text == "Hidden sentinel")
	for team: TerrainArmy in batch_teams:
		assert(int(team.combat_hot_stats().native_calls) == 0 and int(team.combat_hot_stats().materialized_rows) == 0)
		team.free()
	batch_label.free()
	batch_window.free()
	batch_ui.free()
	batch_lab.free()
	print("SUMMARY_BATCH_PARITY_OK checks=", batch_checks, " seven_field_bytes=true full_text=true main_thread_callbacks=true")
	quit()
