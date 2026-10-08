extends SceneTree
## Runnable with the canonical Godot helper; exercises the production D5 mapping methods.
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
class NativeStub extends RefCounted:
	func set_soldier_equip(_index: int, _packed: int) -> bool:
		return true
class HostStub extends RefCounted:
	var lab: Variant
	var crowd := NativeStub.new()
	var _index_by_id := {10: 0, 11: 1}
	var states := {0: {}, 1: {"hp": 100.0}}
	var formation: Dictionary = {}
	func _packed_equip(_appearance: Dictionary) -> int:
		return 7
	func set_soldier_fields(index: int, fields: Dictionary) -> bool:
		states[index] = fields.duplicate()
		return true
	func soldier_state(index: int) -> Dictionary:
		return states[index]
	func set_formation_fields(_index: int, fields: Dictionary) -> bool:
		formation = fields.duplicate(true)
		return true
class LabStub extends RefCounted:
	var terrain := TerrainData.new()

func _initialize() -> void:

	var host := HostStub.new()
	host.lab = LabStub.new()
	host.lab.terrain.site = {"captivity": {"10": {"captor_id": 900, "guard_id": 11}}}
	var holder := {"marker": "original"}
	var body := {"person_id": 10, "cargo": {"arrow": 17}, "item_state": holder}
	var row := {"hp": 62.0, "stun": 8.0, "grace": 0.8, "ko": 12.0, "pose": "get_up", "age": 0.4,
		"captive": true, "bandaged": true, "escape_t": 7.0, "exchange_stagger": 0.2,
		"exchange_cooldown": 0.7, "ranged_cooldown": 1.3, "exchange_skill_cooldown": 5.0}
	var entry := {"index": 0, "person_id": 10, "body": body, "saved": row,
		"actor": null, "appearance": {"parts": {"weapon": "bow_01"}},
		"abilities": {"tactics": 37, "leadership": 21, "coach": 9},
		"position": Vector2(4.25, 5.75), "face": 0.8}
	var snapshot := {"units": [{"person_id": 10}, {"person_id": 11}], "player_member": {},
		"formal_commander": 1, "acting_commander": 0, "current_commander": 0,
		"officers": [0], "officer_service": [0], "combat_order": TerrainArmy.CombatOrder.MOVE,
		"training": 43.0, "team_fatigue": {"fatigue": 27.0, "fatigue_rest": 19.0},
		"goal": [20, 7], "origin": [4.5, 5.5], "reference": [4.5, 5.5],
		"command_reference_valid": true, "pursuit_left": 8.0, "pursuit_target": 11,
		"_order_delay": 0.3, "combat_attacking": false, "tactical_ai": {"enabled": true}}
	var plan := {"snapshot": snapshot, "units": [entry], "centre": Vector2(4.5, 5.5),
		"facing": 0.8, "goal_facing": 1.2, "formation": 0,
		"supply": {"morale": 51.0, "regroup_seconds": 73.0, "routed": false, "commander_present": true}}
	var result: Dictionary = CrowdSite.d5_import_existing_hot(host, [plan])
	assert(result.ok)
	var hot: Dictionary = host.states[0]
	assert(hot.hp == 62.0 and hot.ko == 12.0 and hot.stun == 8.0 and hot.grace == 0.8)
	assert(hot.captor_person == 11 and hot.captor_person != 900)
	assert(hot.ammo == 17 and hot.bandaged and hot.escape_t == 7.0)
	assert(hot.exch_cd == 0.7 and hot.ranged_cd == 1.3 and hot.skill_cd == 5.0)
	assert(hot.px == 4.25 and hot.py == 5.75 and hot.role == 2)
	assert(hot.tactics == 37 and hot.leadership == 21 and hot.coach == 9)
	assert(host.formation.order == 1 and host.formation.goal_x == 20.5 and host.formation.goal_y == 7.5)
	assert(not host.formation.host_center and host.formation.ai_enabled)
	assert(host.formation.fatigue == 27.0 and host.formation.morale == 51.0 and host.formation.rally_rest == 73.0)
	assert(host.formation.formal_person == 11 and host.formation.acting_person == 10 and host.formation.current_person == 10)
	assert(host.formation.officer_persons == [10])
	assert(is_same(body.item_state, holder) and body.cargo.arrow == 17 and row.hp == 62.0)
	host.lab.terrain.site.captivity["10"].guard_id = 12
	result = CrowdSite.d5_import_existing_hot(host, [plan])
	assert(result.ok and host.states[0].captor_person == -1)
	assert(host.lab.terrain.site.captivity["10"].guard_id == 12)
	print("CROWD_C2_D5_MAPPING_PASS")
	quit(0)

