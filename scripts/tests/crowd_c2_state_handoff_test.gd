extends SceneTree
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")

class LabFixture extends Node2D:
	var terrain := TerrainData.new()
	var character := TerrainTestCharacter.new()
	var npc: TerrainTestCharacter
	func controlled_person_id() -> int:
		return character.person_id

class OwnerFixture extends RefCounted:
	var team_id := 7
	var formation_index := 0

class SiteProbe extends "res://scripts/terrain_lab/crowd_site.gd":
	var states := {}
	var formation := {}
	var writes := 0
	func soldier_state(index: int) -> Dictionary:
		var result: Dictionary = states[index].duplicate(true)
		result.military_role = 0 # Getter shape only: this SiteProbe is not a Native World.
		return result
	func formation_state(_index: int) -> Dictionary:
		return formation.duplicate(true)
	func set_soldier_fields(index: int, fields: Dictionary) -> bool:
		writes += 1
		states[index].merge(fields, true)
		return true
	func set_formation_fields(_index: int, fields: Dictionary) -> bool:
		writes += 1
		formation.merge(fields, true)
		return true
	func _appearance(_identity: int) -> Dictionary:
		return {"parts": {"weapon": "bow_01"}}

func _initialize() -> void:
	var fixture := LabFixture.new()
	var actor := fixture.character
	actor.person_id = 1
	fixture.terrain.site = {"manual": {"cargo": {"arrow": 17}}, "worker": {"cargo": {}},
		"captivity": {"1": {"captor_id": 900, "guard_id": 999}}}
	var probe := SiteProbe.new()
	probe.lab = fixture
	probe._actors[1] = actor
	probe._index_by_id[1] = 0
	probe._owner_by_id[1] = OwnerFixture.new()
	probe.teams.append({"team_id": 7, "formation": 0, "solo": true})
	var hot := {"hp": 63.0, "hit_revision": 9, "stun": 20.0, "grace": 0.8, "ko": 0.0, "getup": 1.2,
		"stagger": 2.0, "captive": true, "captor_person": -1, "prison_id": 0, "bandaged": true, "ammo": 17,
		"tactics": 37, "leadership": 21, "coach": 9, "escape_t": 7.0, "role": 2,
		"px": 4.25, "py": 5.75, "face": 0.8, "exch_cd": 0.7, "ranged_cd": 1.3,
		"skill_cd": 5.0, "knock_t": 0.1, "act_t": 0.3}
	var formation := {}
	for key: String in CrowdSite.FORMATION_FIELDS:
		formation[key] = 0.0
	formation.merge({"morale": 51.0, "rally_rest": 73.0, "fatigue": 27.0, "fatigue_rest": 19.0,
		"training": 43.0, "fatigue_count": 1, "order": 1, "goal_x": 20.375, "goal_y": 7.625,
		"goal_facing": 1.2, "pursuit_left": 8.0, "origin_x": 4.5, "origin_y": 5.5,
		"cx": 4.5, "cy": 5.5, "facing": 0.8, "order_delay": 0.3, "ref_x": 4.5, "ref_y": 5.5,
		"commander_present": true, "ref_valid": true, "no_orders": true, "host_center": true,
		"formal_person": 1, "acting_person": -1, "current_person": 1, "target_person": -1, "officer_persons": []}, true)
	formation = CrowdSite._formation_handoff_snapshot(formation)
	probe.states[0] = hot.duplicate(true)
	probe.formation = formation.duplicate(true)
	probe._sync_actor(1)
	assert(actor._received_effective_hit == 9) # Supplied getter counter, not old Actor zero.
	assert(actor.action_time == 1.2 and actor._getting_up) # Stagger cannot extend the get-up timer.
	assert(actor.terrain_cell == Vector2i(4, 5))
	var extra: Dictionary = actor.get_meta(&"crowd_handoff")
	assert(SiteStore._valid_crowd_actor_handoff(extra, actor.person_id))
	assert(extra.bandaged and extra.escape_t == 7.0 and extra.role == 2)
	assert(extra.solo_formation.goal_x == 20.375 and extra.solo_formation.goal_facing == 1.2)
	probe.states[0] = hot.duplicate(true)
	probe.states[0].hp = 1.0
	probe.formation.goal_x = 0.5
	assert(probe._import_actor(1).ok)
	for key: String in hot:
		assert(probe.states[0][key] == hot[key], key)
	for key: String in formation:
		assert(probe.formation[key] == formation[key], key)
	assert(fixture.terrain.site.captivity["1"].guard_id == 999)

	# Current references are rejected before any setter writes.
	extra.solo_formation.target_person = 999
	actor.set_meta(&"crowd_handoff", extra)
	var before := probe.writes
	assert(not probe._actor_handoff_guard(actor).ok)
	assert(not probe._import_actor(1).ok and probe.writes == before)
	extra.solo_formation.target_person = -1
	extra.solo_formation.formal_person = 2
	assert(not probe._actor_handoff_guard(actor).ok and probe.writes == before)
	extra.solo_formation.formal_person = 1
	actor.set_meta(&"crowd_handoff", extra)
	var metadata_before := var_to_str(extra)
	probe.states[0].escape_t = 8.0
	probe._sync_actor(1, false)
	assert(var_to_str(actor.get_meta(&"crowd_handoff")) == metadata_before)
	probe.states[0].px = 1.99999999
	probe._sync_actor(1, false)
	assert(actor.terrain_cell.x == 1)

	var holder := {"original": true}
	var cargo := {"arrow": 17}
	var appearance := {"parts": {"weapon": "bow_01"}}
	var row := {"person_id": 10, "hit_revision": 7, "item_state": holder, "cargo": cargo, "appearance": appearance,
		"site_only_marker": {"untouched": true}, "pose": "get_up", "age": 0.4}
	CrowdSite._write_row_handoff(row, hot.merged({"military_role": 0}), formation)
	assert(row.hit_revision == 9) # Original row seven takes the authoritative supplied hot nine.
	var roster := {"units": [row, {"person_id": 11}], "player_member": {}, "team_fatigue": {"active": true},
		"formation_preset_id": "long_snake", "officer_service": [1], "tactical_ai": {"site_only_marker": 13}}
	var roster_state := formation.duplicate(true)
	roster_state.merge({"formal_person": 11, "acting_person": 10, "current_person": 10, "officer_persons": [10]}, true)
	assert(CrowdSite._write_roster_handoff(roster, roster_state).ok)
	assert(roster.formal_commander == 1 and roster.acting_commander == 0 and roster.current_commander == 0)
	assert(roster.officers == [0] and roster.officer_service == [1])
	assert(roster.combat_order == TerrainArmy.CombatOrder.MOVE and roster.goal == [20, 7])
	assert(roster.team_fatigue.fatigue == 27.0 and roster.team_fatigue.count == 1 and roster.team_fatigue.active)
	assert(roster.tactical_ai.site_only_marker == 13 and roster.formation_preset_id == "long_snake")
	assert(is_same(row.item_state, holder) and is_same(row.cargo, cargo) and is_same(row.appearance, appearance))
	assert(row.site_only_marker.untouched and row.exchange_cooldown == 0.7)
	var restored := CrowdSite.d5_row_hot({"actor": null, "saved": row, "body": row, "appearance": appearance,
		"abilities": row.command_abilities, "index": 0, "person_id": 10,
		"position": Vector2(hot.px, hot.py), "face": hot.face}, roster, {"10": {"guard_id": -1}})
	assert(typeof(restored.hit_revision) == TYPE_INT and restored.hit_revision == 9)
	for key: String in hot:
		assert(restored[key] == hot[key], key)
	var restored_formation := CrowdSite._formation_handoff_fields(roster, formation.duplicate(true))
	assert(restored_formation.goal_x == 20.375 and restored_formation.goal_y == 7.625)
	assert(restored_formation.formal_person == 11 and restored_formation.current_person == 10)
	assert(restored_formation.host_center == formation.host_center)
	probe.free()
	actor.free()
	fixture.free()
	print("CROWD_C2_STATE_HANDOFF_PASS")
	quit(0)
