extends SceneTree
## Automatic intent stays on the original Army and yields only to accepted manual orders.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE_ROOT := "res://.godot-temp/site_combat/tactical-ai-state/"

func _initialize() -> void:
	call_deferred("_run")
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("SITE TACTICAL AI STATE timed out")
		quit(1))

func _run() -> void:
	var data := Helper.build_flat_map(40, 40)
	var team := Helper.create_test_army(data, 1, 0, 4, Vector2i(5, 5))
	if team.get_parent() == null: root.add_child(team)
	assert(not team.tactical_ai_enabled)
	assert(not team.issue_tactical_ai_order(TerrainArmy.CombatOrder.ATTACK).ok)
	assert(not team.set_tactical_ai_enabled(-1, true).ok)
	assert(team.set_tactical_ai_enabled(team.current_commander, true).ok)
	team.tactical_ai_recovering = true
	team.tactical_ai_order_cooldown = 1.25
	team.tactical_ai_chase_cooldown = 7.5
	team.tactical_ai_status = "撤退"
	team.tactical_ai_reason = "測試原因"
	team.tactical_ai_target_id = 999
	team.tactical_ai_decisions = 7
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(snapshot, data), "AI state must survive the actual JSON numeric boundary")
	assert(snapshot.tactical_ai.enabled and snapshot.tactical_ai.recovering)
	assert(not snapshot.tactical_ai.has("status") and not snapshot.tactical_ai.has("target_id"), "Derived tactical presentation is not a second saved target")
	for field: String in ["order_cooldown", "chase_cooldown"]:
		for bad: Variant in [-0.1, 60.01, "1", null, true, INF, NAN]:
			var invalid: Dictionary = snapshot.duplicate(true)
			invalid.tactical_ai[field] = bad
			assert(not TerrainArmy.valid_combat_state(invalid, data), "Reject non-finite or invalid AI timer " + field)
	for field: String in ["enabled", "recovering"]:
		for bad: Variant in [0, 1, "false", null]:
			var invalid: Dictionary = snapshot.duplicate(true)
			invalid.tactical_ai[field] = bad
			assert(not TerrainArmy.valid_combat_state(invalid, data), "AI flags must be actual bools")
	for bad: Variant in [0, 2, 1.5, "1", null]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.tactical_ai.version = bad
		assert(not TerrainArmy.valid_combat_state(invalid, data))
	for bad: Variant in [[], null, true]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.tactical_ai = bad
		assert(not TerrainArmy.valid_combat_state(invalid, data))
	for field: String in ["version", "enabled", "recovering", "order_cooldown", "chase_cooldown"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.tactical_ai.erase(field)
		assert(not TerrainArmy.valid_combat_state(invalid, data), "An explicit incomplete AI packet is not a legacy save")
	var work_save := snapshot.duplicate(true)
	work_save.role = "work"
	assert(not TerrainArmy.valid_combat_state(work_save, data), "Worker teams cannot restore enabled combat AI")
	var restored := TerrainArmy.new()
	root.add_child(restored)
	restored.set_process(false)
	restored.restore_combat_state(snapshot.duplicate(true), data, null, null)
	assert(restored.tactical_ai_enabled and restored.tactical_ai_recovering)
	assert(restored.tactical_ai_order_cooldown == 1.25 and restored.tactical_ai_chase_cooldown == 7.5)
	assert(restored.tactical_ai_status == "待判斷" and restored.tactical_ai_reason.is_empty() and restored.tactical_ai_target_id == -1)
	assert(restored.tactical_ai_decisions == 0 and restored.tactical_ai_orders == 0)
	assert(restored.cells == team.cells and restored.role == team.role, "AI restoration must not change original cells or role")
	var legacy := snapshot.duplicate(true)
	legacy.erase("tactical_ai")
	assert(TerrainArmy.valid_combat_state(legacy, data))
	restored.restore_combat_state(legacy, data, null, null)
	assert(not restored.tactical_ai_enabled and not restored.tactical_ai_recovering)
	assert(restored.tactical_ai_order_cooldown == 0.0 and restored.tactical_ai_chase_cooldown == 0.0)
	var before := team._capture_tactical_ai_state()
	assert(not team.issue_combat_order(-1, TerrainArmy.CombatOrder.HOLD).ok)
	assert(not team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(-20, -20)).ok)
	assert(not team.issue_formation_change(team.current_commander, "not-a-formation").ok)
	assert(team._capture_tactical_ai_state() == before, "Rejected manual orders must preserve AI consent and recovery")
	assert(team.issue_tactical_ai_order(TerrainArmy.CombatOrder.ATTACK).ok)
	assert(team.tactical_ai_enabled and team.tactical_ai_recovering and team.tactical_ai_orders == 1)
	assert(not team.issue_tactical_ai_order(999).ok and team.tactical_ai_orders == 1)
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	assert(not team.tactical_ai_enabled and not team.tactical_ai_recovering)
	assert(team.tactical_ai_order_cooldown == 0.0 and team.tactical_ai_chase_cooldown == 0.0)
	assert(team.tactical_ai_decisions == 7 and team.tactical_ai_orders == 1, "Manual takeover preserves diagnostics")
	assert(team.set_tactical_ai_enabled(team.current_commander, true).ok)
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(20, 20)).ok)
	assert(not team.tactical_ai_enabled, "An accepted manual MOVE takes control")
	assert(team.set_tactical_ai_enabled(team.current_commander, true).ok)
	assert(team.issue_formation_change(team.current_commander, "square").ok)
	assert(not team.tactical_ai_enabled, "An accepted formation command takes control")
	var serial := team.get_order_serial()
	assert(team.set_tactical_ai_enabled(team.current_commander, true).ok)
	assert(team.issue_formation_change(team.current_commander, "square").ok)
	assert(not team.tactical_ai_enabled and team.get_order_serial() == serial, "An accepted identical formation takes control without rebuilding the route")
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	paused = true
	assert(not team.set_tactical_ai_enabled(team.current_commander, true).ok)
	paused = false
	data.site.paused = true
	assert(not team.set_tactical_ai_enabled(team.current_commander, true).ok)
	data.site.paused = false
	for noncombat: String in ["work", "logistics"]:
		team.role = noncombat
		assert(not team.set_tactical_ai_enabled(team.current_commander, true).ok)
		assert(not team.tactical_ai_enabled)
	team.role = "combat"
	assert(team.set_tactical_ai_enabled(team.current_commander, true).ok)
	team.tactical_ai_recovering = true
	team.tactical_ai_chase_cooldown = 3.5
	before = team._capture_tactical_ai_state()
	paused = true
	assert(not team.issue_tactical_ai_order(TerrainArmy.CombatOrder.ATTACK).ok)
	assert(not team.set_tactical_ai_enabled(team.current_commander, false).ok)
	paused = false
	assert(team._capture_tactical_ai_state() == before)
	var split := TerrainArmy.new()
	root.add_child(split)
	split.set_process(false)
	split.team_id = 2
	split.role = "logistics"
	var ids: Array[int] = [team.combat_identity(3)]
	# R1b: a split-off team is commanded only by an officer captain named at the split (otherwise it is
	# leaderless and nobody holds team.roster for the merge below: NO_AUTHORITY). Promote the moving
	# member through the original role transaction and name it, as site_army_roster_test does.
	var promoted: Dictionary = team.set_military_role(ids[0], "officer")
	assert(promoted.ok, "Moving member becomes an officer through the original role transaction: " + str(promoted))
	var split_result: Dictionary = team.split_members_to(split, ids, team.current_commander, ids[0])
	assert(split_result.ok, "Officer-captained split: " + str(split_result))
	assert(team._capture_tactical_ai_state() == before and team.role == "combat", "Rebuilding an existing roster preserves its own AI state")
	assert(not split.tactical_ai_enabled and split.role == "logistics", "A split does not copy AI consent or overwrite the recipient role")
	assert(split.merge_into(team, split.current_commander, team.current_commander).ok)
	assert(team._capture_tactical_ai_state() == before and team.role == "combat", "Merge must preserve the existing recipient AI state")
	assert(not split.has_army() and not split.tactical_ai_enabled)
	team.clear()
	assert(not team.tactical_ai_enabled and not team.tactical_ai_recovering and team.tactical_ai_order_cooldown == 0.0 and team.tactical_ai_chase_cooldown == 0.0)
	assert(team.tactical_ai_decisions == 0 and team.tactical_ai_orders == 0 and team.tactical_ai_target_id == -1)
	for original: TerrainArmy in [team, restored, split]:
		original.free()
	if not _store_roundtrip():
		TerrainArmy.release_contact_source()
		quit(1)
		return
	TerrainArmy.release_contact_source()
	print("SITE TACTICAL AI STATE PASS: real command authority, manual takeover, bounded saved timers, legacy restore, split/merge, clear and three-faction SiteStore save/load")
	quit(0)

func _store_check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("SITE TACTICAL AI STORE: " + message)
	return condition

func _store_roundtrip() -> bool:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "tactical-ai-store-fixture")
	# Persist terrain edits through the existing delta, so loading rebuilds the same map.
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var origin := TerrainArmy.INVALID_CELL
	for y in range(2, data.size.y - 2):
		for x in range(2, data.size.x - 12):
			var legal := true
			for offset in range(12):
				if not data.is_walkable(Vector2i(x + offset, y)):
					legal = false
					break
			if legal:
				origin = Vector2i(x, y)
				break
		if origin != TerrainArmy.INVALID_CELL:
			break
	if not _store_check(origin != TerrainArmy.INVALID_CELL, "Persisted fixture requires an unchanged legal deployment row"): return false
	var teams: Array[TerrainArmy] = []
	var expected: Array[Dictionary] = []
	for index in range(3):
		var team := Helper.create_test_army(data, index + 1, index, 2, origin + Vector2i(index * 4, 0))
		if team.get_parent() == null: root.add_child(team)
		if not _store_check(team.set_tactical_ai_enabled(team.current_commander, true).ok, "Cannot enable faction %d AI" % index): return false
		team.tactical_ai_recovering = index == 0
		team.tactical_ai_order_cooldown = 0.75 + float(index)
		team.tactical_ai_chase_cooldown = 7.25 + float(index) * 3.0
		if index == 1:
			if not _store_check(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok, "Initial manual takeover failed"): return false
		teams.append(team)
		expected.append(team._capture_tactical_ai_state())
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = 4
	data.site["actors"] = {}
	data.site["armies"] = []
	for team: TerrainArmy in teams:
		data.site.armies.append(team.capture_combat_state())
	if not _store_check(Store._validate_armies(data, data.site, true).ok, "All three original factions must pass cross-team validation"): return false
	data.site.combat_left = 1.0
	if not _store_check(not Store.save(data, SAVE_ROOT + "three-factions.json").ok, "AI cannot bypass the original in-combat save restriction"): return false
	data.site.combat_left = 0.0
	var saved := Store.save(data, SAVE_ROOT + "three-factions.json")
	if not _store_check(saved.ok, "Three-faction SiteStore save failed: " + str(saved)): return false
	var checksum := FileAccess.get_sha256(SAVE_ROOT + "three-factions.json")
	data.site.armies[2].tactical_ai.order_cooldown = 61.0
	if not _store_check(not Store.save(data, SAVE_ROOT + "three-factions.json").ok, "Store must reject invalid AI timers before replacing the file"): return false
	if not _store_check(FileAccess.get_sha256(SAVE_ROOT + "three-factions.json") == checksum, "Rejected AI save must retain the complete previous save"): return false
	data.site.armies[2] = teams[2].capture_combat_state()
	var loaded := Store.load_site(SAVE_ROOT + "three-factions.json")
	if not _store_check(loaded.ok, "Three-faction SiteStore load failed: " + str(loaded)): return false
	if not _store_check(loaded.data.site.armies.size() == 3, "Store must restore all three factions"): return false
	var copies: Array[TerrainArmy] = []
	for index in range(3):
		var copy := TerrainArmy.new()
		root.add_child(copy)
		copy.set_process(false)
		copy.restore_combat_state(loaded.data.site.armies[index], loaded.data, null, null)
		copies.append(copy)
		if not _store_check(copy._capture_tactical_ai_state() == expected[index], "Store roundtrip must preserve faction %d consent/recovery/timers" % index): return false
		if not _store_check(copy.team_id == teams[index].team_id and copy.faction_id == teams[index].faction_id and copy.role == teams[index].role, "Faction %d identity or role changed" % index): return false
		if not _store_check(copy.cells == teams[index].cells, "Faction %d positions changed: %s -> %s" % [index, teams[index].cells, copy.cells]): return false
		if not _store_check(copy.combat_units.size() == teams[index].combat_units.size(), "Faction %d lost original people" % index): return false
		# JSON stores numeric row fields as floats; the original identity reader
		# returns the validated integral identity for both live and restored rows.
		for member in range(copy.combat_units.size()):
			if not _store_check(copy.combat_identity(member) == teams[index].combat_identity(member), "Faction %d member %d identity changed" % [index, member]): return false
	# A real manual command after load must stay manual in the next saved session.
	if not _store_check(copies[0].issue_combat_order(copies[0].current_commander, TerrainArmy.CombatOrder.HOLD).ok, "Manual takeover after restore failed"): return false
	loaded.data.site.armies = []
	for copy: TerrainArmy in copies:
		loaded.data.site.armies.append(copy.capture_combat_state())
	saved = Store.save(loaded.data, SAVE_ROOT + "after-manual-takeover.json")
	if not _store_check(saved.ok, str(saved)): return false
	var manual := Store.load_site(SAVE_ROOT + "after-manual-takeover.json")
	if not _store_check(manual.ok, str(manual)): return false
	for index in range(3):
		copies[index].restore_combat_state(manual.data.site.armies[index], manual.data, null, null)
		if not _store_check(copies[index].tactical_ai_enabled == (index == 2), "A saved manual takeover cannot reactivate AI or disable another faction"): return false
	if not _store_check(not copies[0].tactical_ai_recovering and copies[0].tactical_ai_order_cooldown == 0.0 and copies[0].tactical_ai_chase_cooldown == 0.0, "Saved manual takeover retained an AI recovery clock"): return false
	if not _store_check(copies[2]._capture_tactical_ai_state() == expected[2], "Manual takeover changed the third faction's AI state"): return false
	# Exercise load-time validation with a correctly checksummed but invalid AI payload.
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_ROOT + "three-factions.json"))
	var payload: Dictionary = JSON.parse_string(envelope.payload)
	payload.state.armies[2].tactical_ai.enabled = "true"
	var body := JSON.stringify(payload, "", true, true)
	var invalid_file := FileAccess.open(SAVE_ROOT + "invalid-ai.json", FileAccess.WRITE)
	if not _store_check(invalid_file != null, "Cannot write the corrupt-save fixture"): return false
	invalid_file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	invalid_file.close()
	if not _store_check(not Store.load_site(SAVE_ROOT + "invalid-ai.json").ok, "Valid checksum cannot admit invalid AI state"): return false
	# Legacy saves contain no tactical packet. Loading them must not inherit live AI.
	for army_snapshot: Dictionary in manual.data.site.armies:
		army_snapshot.erase("tactical_ai")
	saved = Store.save(manual.data, SAVE_ROOT + "legacy-no-ai.json")
	if not _store_check(saved.ok, str(saved)): return false
	var legacy := Store.load_site(SAVE_ROOT + "legacy-no-ai.json")
	if not _store_check(legacy.ok, str(legacy)): return false
	for index in range(3):
		copies[index].restore_combat_state(legacy.data.site.armies[index], legacy.data, null, null)
		if not _store_check(not copies[index].tactical_ai_enabled and not copies[index].tactical_ai_recovering, "Legacy faction %d inherited live AI state" % index): return false
		if not _store_check(copies[index].tactical_ai_order_cooldown == 0.0 and copies[index].tactical_ai_chase_cooldown == 0.0, "Legacy faction %d inherited live AI timers" % index): return false
	for team: TerrainArmy in teams + copies:
		team.free()
	return true
