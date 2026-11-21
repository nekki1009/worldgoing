extends SceneTree
## G6.4: remote membership and Region travel accept an active native crowd.
## Activates a two-faction native crowd on the formal TerrainLab scene, then checks:
## - the travel combat check reads native crowd positions: an enemy crowd soldier near blocks, none near allows;
## - remote team membership accepts a CrowdPersonOwner of this crowd and refuses a stale TerrainArmy with its own code;
## - Region travel start stays refused under a crowd with a named refusal (no Region slot in the formal scene).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_TRAVEL_MEMBERSHIP_PASS on success; quit(1) on any failure.

const AI = preload("res://scripts/region_lab/region_gameplay_ai.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_TRAVEL_MEMBERSHIP_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_TRAVEL_MEMBERSHIP OK ", checks, ": ", message)
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

	var teams: Array = AI.command_team_owners(lab)
	if not _check(teams.size() >= 2, "crowd exposes at least two command teams", teams.size()): return
	var friendly_owner: Variant = null
	var enemy_owner: Variant = null
	for owner_ref: Variant in teams:
		if int(owner_ref.faction_id) == 0 and friendly_owner == null: friendly_owner = owner_ref
		if int(owner_ref.faction_id) == 1 and enemy_owner == null: enemy_owner = owner_ref
	if not _check(friendly_owner != null and enemy_owner != null, "crowd has a friendly and an enemy team"): return

	# Travel combat check (native positions): an enemy crowd soldier three cells away blocks departure from the centre.
	var near_cells: Array[Vector2i] = [centre]
	if not _check(RegionTravelSite._hostile_near(lab, 0, near_cells) == true,
		"an enemy crowd soldier near the departing cell blocks travel", near_cells): return
	# A cell far from both crowd teams is not "near" an enemy, so travel from it is not blocked by the crowd.
	var far_cells: Array[Vector2i] = [centre + Vector2i(200, 0)]
	if not _check(RegionTravelSite._hostile_near(lab, 0, far_cells) == false,
		"no enemy crowd soldier within the enemy radius allows travel", far_cells): return

	# Remote membership: a crowd team reaches its own membership checks (not the crowd-mismatch refusal);
	# the empty nation source and the empty site refs end it at a named membership code.
	var slot := RegionSaveSlot.new()
	var authority := {"lab": lab, "nation": {"members": []}}
	var crowd_membership: Dictionary = slot._region_remote_team_membership(authority, lab, friendly_owner, {})
	if not _check(crowd_membership.get("ok", false) == true or crowd_membership.get("code", "") in ["NO_COMMANDER", "PLAYER_PARTY", "REMOTE_MEMBERSHIP_CHANGED"],
		"remote membership for a crowd team ends at a named membership code", crowd_membership): return
	var missing: Dictionary = slot._region_remote_team_membership(authority, lab, null, {})
	if not _check(missing.get("code", "") == "INVALID_REMOTE_MEMBERSHIP", "remote membership refuses a missing team", missing): return
	if lab.combat_armies.size() > 0:
		var stale: Dictionary = slot._region_remote_team_membership(authority, lab, lab.combat_armies[0], {})
		if not _check(stale.get("code", "") == "INVALID_REMOTE_MEMBERSHIP", "a TerrainArmy never stands in for an active crowd team", stale): return

	# Region travel start: the formal scene has no Region slot, so depart and selected_departure refuse by name before any crowd state changes.
	var departed: Dictionary = RegionTravelSite.depart(lab.site_controller)
	if not _check(departed.get("ok", true) == false and departed.get("code", "") in ["NO_REGION_SLOT", "UNSUPPORTED"],
		"Region travel start refuses under an active crowd", departed): return
	var selected: Dictionary = RegionTravelSite.selected_departure(lab.site_controller)
	if not _check(selected.get("ok", true) == false and selected.get("code", "") in ["NO_REGION_SLOT", "REGION_BACKEND_UNADMITTED"],
		"selected Region departure refuses under an active crowd", selected): return
	if not _check(lab.crowd_site.active, "crowd stays active after the refused travel checks"): return

	print("REGION_CROWD_TRAVEL_MEMBERSHIP_PASS: ", checks, " checks; travel combat check reads native positions, crowd membership reaches its own checks, travel start refuses by name under a crowd; site ", site_id)
	quit(0)
