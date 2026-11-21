extends SceneTree
## G6.3: Region battle and Region AI accept an active native crowd.
## Activates a two-faction native crowd on the formal TerrainLab scene, then checks:
## - region_gameplay_ai command team enumeration returns the crowd teams;
## - dispatch_context and dispatch_candidates pass the former crowd gate;
## - region_gameplay_battle.resolve_people accepts crowd people on both sides;
## - melee contact and exchange fatigue still refuse with their named codes;
## - prepare_original_siege fails at its owner gate without a Region slot (not a crowd refusal).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_BATTLE_AI_PASS on success; quit(1) on any failure.

const Battle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
const AI = preload("res://scripts/region_lab/region_gameplay_ai.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_BATTLE_AI_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_BATTLE_AI OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side.faction = faction
	return side

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null and lab.site_controller != null, "formal scene has its player body and Controller"): return
	lab.character.set_process(false)
	if not _check(lab.crowd_site != null and not lab.crowd_site.active, "formal scene has an inactive CrowdSite"): return
	if not _check(lab.terrain != null and lab.terrain.spawn_cell != Vector2i(-1, -1), "scene has a legal spawn cell"): return
	var site_id := str(lab.terrain.site.get("id", ""))
	var centre: Vector2i = lab.terrain.spawn_cell
	var friendly_cells: Array[Vector2i] = [centre + Vector2i(-1, 3), centre + Vector2i(0, 3)]
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -3), centre + Vector2i(0, -3)]
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var formations: Array = [friendly_cells, enemy_cells]
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "two-faction native crowd activates", entered): return

	# Team enumeration: one command owner per crowd formation with an army record.
	var teams: Array = AI.command_team_owners(lab)
	if not _check(teams.size() >= 2, "crowd exposes at least two command teams", teams.size()): return
	for owner_ref: Variant in teams:
		if not _check(is_same(AI.command_team_by_id(lab, int(owner_ref.team_id)), owner_ref),
			"command_team_by_id returns the crowd owner for its team", owner_ref.team_id): return
	if not _check(AI.command_team_list(lab) == teams, "command_team_list uses crowd teams while the crowd is active"): return

	# Region AI: the former UNSUPPORTED_BACKEND gate is gone; a nation with no authority still refuses by its own code.
	var context: Dictionary = AI.dispatch_context(lab, "no_such_nation", int(teams[0].team_id), "destination", "token", Callable())
	if not _check(context.get("code", "") == "NO_AUTHORITY", "dispatch_context reaches its own authority check under a crowd", context): return
	var candidates: Dictionary = AI.dispatch_candidates(lab, {}, 60.0)
	if not _check(candidates.get("ok", false) == true and candidates.get("intents", [1]).is_empty(),
		"dispatch_candidates passes its crowd gate and yields no intents without nations", candidates): return

	# Region battle: crowd people on both sides resolve as people, not UNSUPPORTED_BACKEND.
	var friendly_owner: Variant = null
	var enemy_owner: Variant = null
	for owner_ref: Variant in teams:
		if int(owner_ref.faction_id) == 0 and friendly_owner == null: friendly_owner = owner_ref
		if int(owner_ref.faction_id) == 1 and enemy_owner == null: enemy_owner = owner_ref
	if not _check(friendly_owner != null and enemy_owner != null, "crowd has a friendly and an enemy team"): return
	var friendly_keys: Array = friendly_owner.combat_units.keys()
	var enemy_keys: Array = enemy_owner.combat_units.keys()
	if not _check(not friendly_keys.is_empty() and not enemy_keys.is_empty(), "both crowd teams have member records"): return
	var source_id: int = friendly_owner.combat_identity(int(friendly_keys[0]))
	var target_id: int = enemy_owner.combat_identity(int(enemy_keys[0]))
	var battle := {"site_id": site_id, "attackers": [source_id], "defenders": [target_id]}
	var resolved: Dictionary = Battle.resolve_people(lab, battle, Callable(), {"ok": true, "person_id": 0})
	if not _check(resolved.get("ok", false) == true, "resolve_people accepts crowd people", resolved): return
	var people: Dictionary = resolved.get("people", {})
	if not _check(people.has(source_id) and people.has(target_id), "resolve_people returns both crowd people", people.keys()): return
	var source_cell: Array = people[source_id].get("contact_cell", [])
	var target_cell: Array = people[target_id].get("contact_cell", [])
	if not _check(source_cell.size() == 2 and target_cell.size() == 2, "resolved crowd people carry contact cells", people): return

	# Admitted melee contact and exchange fatigue now write the native crowd person (G63 gaps A and B).
	var target_index: int = enemy_owner.index_for_identity(target_id)
	var hp_before: float = float(enemy_owner.combat_hot_get(target_index, &"hp"))
	var fatigue_before: float = float(enemy_owner.combat_hot_get(target_index, &"fatigue"))
	var witness := {"verified": true, "site_id": site_id, "source": source_id, "target": target_id,
		"game_time": 5.0, "source_cell": source_cell, "target_cell": target_cell}
	# A NaN effect is refused by name before any native write.
	var refused: Dictionary = Battle._owned_damage(lab, battle, {"id": "probe_nan", "kind": "damage", "person_id": target_id,
		"source_person_id": source_id, "attack_id": "probe", "hp": NAN, "stun": 0.0, "game_time": 10.0, "contact": witness})
	if not _check(refused.get("code", "") == "INVALID_EFFECT", "NaN melee HP on a crowd person is refused before any write", refused): return
	var damage: Dictionary = Battle._owned_damage(lab, battle, {"id": "probe_damage", "kind": "damage", "person_id": target_id,
		"source_person_id": source_id, "attack_id": "probe", "hp": 1.0, "stun": 0.0, "game_time": 10.0, "contact": witness})
	if not _check(damage.get("ok", false) == true, "melee contact on a crowd person is applied natively", damage): return
	var hp_after: float = float(enemy_owner.combat_hot_get(target_index, &"hp"))
	if not _check(hp_after < hp_before, "native HP falls after melee contact", [hp_before, hp_after]): return
	var fatigue: Dictionary = Battle._owned_fatigue(lab, battle, {"id": "probe_fatigue", "kind": "fatigue", "person_id": target_id, "amount": 1.0})
	if not _check(fatigue.get("ok", false) == true, "exchange fatigue on a crowd person is charged natively", fatigue): return
	var fatigue_after: float = float(enemy_owner.combat_hot_get(target_index, &"fatigue"))
	if not _check(fatigue_after > fatigue_before, "native formation fatigue rises after the exchange charge", [fatigue_before, fatigue_after]): return

	# Original siege: without a Region slot the owner gate refuses first (crowd is not the cause).
	var siege: Dictionary = Battle.prepare_original_siege(lab, {})
	if not _check(siege.get("code", "") == "MISSING_ORIGINAL_SIEGE_OWNER", "prepare_original_siege reaches its owner gate under a crowd", siege): return

	print("REGION_CROWD_BATTLE_AI_PASS: ", checks, " checks; crowd teams enumerated, AI gates passed, battle resolves crowd people, contact and fatigue apply natively")
	quit(0)
