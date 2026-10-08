extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/corps-authority.json"
const CORRUPT := "res://.godot-temp/site_combat/corps-authority-corrupt.json"

var _teams: Array[TerrainArmy] = []
var _actor: TerrainTestCharacter
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		push_error("CORPS AUTHORITY: " + message)
	return condition

func _person(identity: int) -> Dictionary:
	if _actor != null and _actor.combat_identity() == identity:
		return {"owner": _actor, "unit": -1}
	for team: TerrainArmy in _teams:
		var index := team.index_for_identity(identity)
		if index >= 0:
			return {"owner": team, "unit": index}
	return {}

func _room(data: TerrainData) -> Vector2i:
	for y in range(2, data.size.y - 7):
		for x in range(2, data.size.x - 22):
			var legal := true
			for dy in range(6):
				for dx in range(21):
					if not data.is_walkable(Vector2i(x + dx, y + dy)):
						legal = false
						break
				if not legal: break
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: push_error("CORPS AUTHORITY timed out"); quit(1))
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(80, 65)})
	SiteEnvironment.initialize(data, "corps-authority-fixture")
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var room := _room(data)
	if not _check(room != TerrainArmy.INVALID_CELL, "No persistent legal fixture room"):
		quit(1)
		return
	_teams.append(Helper.create_test_army(data, 1, 0, 3, room + Vector2i(1, 2)))
	_teams.append(Helper.create_test_army(data, 2, 0, 3, room + Vector2i(13, 2)))
	_actor = TerrainTestCharacter.new()
	_actor.person_id = 987654
	_actor.data = data
	var passed := _authority(data) and _persistence(data)
	_actor.free()
	for team: TerrainArmy in _teams:
		team.free()
	if passed:
		print("SITE CORPS AUTHORITY PASS: %d checks; explicit role, original live identity, denied-order immutability, legacy/roundtrip and corrupt-reference rejection" % _checks)
	quit(0 if passed else 1)

func _authority(data: TerrainData) -> bool:
	var source := _teams[0]
	var target := _teams[1]
	var commander := source.combat_identity(0)
	var target_before := target.capture_combat_state()
	if not _check(SiteRuntime.authorize_corps_reposition(data, commander, target, _person).code == "NO_AUTHORITY" and not data.site.has("corps"), "Missing relation must not grant or create an office"): return false
	data.site.corps = {"first": {"version": 1, "commander_person_id": commander, "team_ids": [1, 2]}}
	var authorized := SiteRuntime.authorize_corps_reposition(data, commander, target, _person)
	if not _check(authorized.ok and authorized.corps_id == "first", "Explicit commander must control the assigned original team"): return false
	if not _check(target.capture_combat_state() == target_before and target._retreat_resolution.is_empty(), "Authority lookup must not start MOVE, change AI, or enter retreat"): return false
	if not _check(SiteRuntime.authorize_corps_reposition(data, target.combat_identity(0), target, _person).code == "NO_AUTHORITY", "Same-faction captain is not a corps commander"): return false
	if not _check(SiteRuntime.authorize_corps_reposition(data, commander, target, Callable()).code == "NO_AUTHORITY", "Unbound lookup must not fabricate a live person"): return false
	var wrong_row := func(_identity: int) -> Dictionary: return {"owner": source, "unit": 1}
	if not _check(SiteRuntime.authorize_corps_reposition(data, commander, target, wrong_row).code == "NO_AUTHORITY", "Lookup row must match the original stable identity"): return false
	data.site.corps.first.team_ids = [1]
	if not _check(SiteRuntime.authorize_corps_reposition(data, commander, target, _person).code == "NO_AUTHORITY", "A real commander cannot order an unassigned team"): return false
	data.site.corps.first.team_ids = [1, 2]
	for field: String in ["ko", "hp", "captive", "site_exited", "surrender_pending", "departed"]:
		var original: Variant = source.combat_hot_get(0, StringName(field))
		source.combat_hot_set(0, StringName(field), 4.0 if field == "ko" else (0.0 if field == "hp" else true))
		var denied := SiteRuntime.authorize_corps_reposition(data, commander, target, _person)
		source.combat_hot_set(0, StringName(field), original)
		if not _check(denied.code == "NO_AUTHORITY" and target.capture_combat_state() == target_before, "Ineligible commander or side effects: " + field): return false
	source.faction_id = 1
	var foreign := SiteRuntime.authorize_corps_reposition(data, commander, target, _person)
	source.faction_id = 0
	if not _check(foreign.code == "NO_AUTHORITY", "Faction changes must be rechecked on the original owner"): return false
	data.site.corps.first.commander_person_id = _actor.person_id
	if not _check(SiteRuntime.authorize_corps_reposition(data, _actor.person_id, target, _person).ok, "A real explicitly appointed Actor retains its original owner"): return false
	_actor.site_exited = true
	if not _check(SiteRuntime.authorize_corps_reposition(data, _actor.person_id, target, _person).code == "NO_AUTHORITY", "Exited Actor cannot command"): return false
	_actor.site_exited = false
	data.site.corps.first.commander_person_id = commander
	return _check(target.capture_combat_state() == target_before and not target.is_sustain_routed(), "All authority checks leave the original high-morale team unchanged")

func _write_payload(payload: Dictionary) -> void:
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(CORRUPT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()

func _persistence(data: TerrainData) -> bool:
	data.site.armies = [_teams[0].capture_combat_state(), _teams[1].capture_combat_state()]
	data.site.actors = {}
	var corps: Dictionary = data.site.corps.duplicate(true)
	data.site.erase("corps")
	var saved := Store.save(data, SAVE)
	if not _check(saved.ok, "Legacy save failed: " + str(saved)): return false
	var loaded := Store.load_site(SAVE)
	if not _check(loaded.ok and loaded.data.site.get("corps", {}).is_empty(), "Legacy load invented military authority: " + str(loaded)): return false
	data.site.corps = corps
	saved = Store.save(data, SAVE)
	if not _check(saved.ok, "Explicit original role save failed: " + str(saved)): return false
	loaded = Store.load_site(SAVE)
	if not _check(loaded.ok and loaded.data.site.corps == corps, "Actual SiteStore roundtrip changed the relation: " + str(loaded)): return false
	if not _check(loaded.data.site.corps.first.commander_person_id is int and loaded.data.site.corps.first.team_ids[0] is int, "JSON identities must normalize after validation"): return false
	var payload: Dictionary = Store._read(SAVE).payload
	var digest := FileAccess.get_sha256(SAVE)
	var people := {}
	var teams := {1: 0, 2: 0}
	for team: TerrainArmy in _teams:
		for index in range(team.combat_units.size()):
			people[team.combat_identity(index)] = team.faction_id
	if not _check(SiteRuntime.valid_corps(corps, people, teams), "Original references must pass the shared validator"): return false
	var variants: Array = [null, [], {"": corps.first}, {"bad/key": corps.first}]
	for field: String in ["version", "commander_person_id", "team_ids"]:
		var missing := corps.duplicate(true)
		missing.first.erase(field)
		variants.append(missing)
	for value: Variant in [0, -1, 1.5, "1", true, 987654]:
		var bad := corps.duplicate(true)
		bad.first.commander_person_id = value
		variants.append(bad)
	for value: Variant in [[], [1, 1], [99], [1.5], ["1"], [true], null]:
		var bad := corps.duplicate(true)
		bad.first.team_ids = value
		variants.append(bad)
	var duplicate := corps.duplicate(true)
	duplicate["second"] = corps.first.duplicate(true)
	variants.append(duplicate)
	var extra := corps.duplicate(true)
	extra.first["authorized"] = true
	variants.append(extra)
	var version := corps.duplicate(true)
	version.first.version = 2
	variants.append(version)
	for index in range(variants.size()):
		data.site.corps = variants[index]
		var refused := Store.save(data, SAVE)
		if not _check(refused.code == "CORRUPT_SAVE" and FileAccess.get_sha256(SAVE) == digest, "Invalid role save changed the valid original file: %d %s" % [index, refused]): return false
		var invalid := payload.duplicate(true)
		invalid.state.corps = variants[index]
		_write_payload(invalid)
		var incoming_digest := FileAccess.get_sha256(CORRUPT)
		refused = Store.load_site(CORRUPT)
		if not _check(refused.code == "CORRUPT_SAVE" and FileAccess.get_sha256(CORRUPT) == incoming_digest, "Invalid role load must reject without rewriting: %d %s" % [index, refused]): return false
	data.site.corps = corps
	var foreign := payload.duplicate(true)
	foreign.state.armies[1].faction_id = 1
	_write_payload(foreign)
	if not _check(Store.load_site(CORRUPT).code == "CORRUPT_SAVE", "Cross-faction assigned team must reject"): return false
	return _check(data.site.corps == corps and _teams[1]._retreat_resolution.is_empty(), "Persistence cannot invent retreat or alter original role data")
