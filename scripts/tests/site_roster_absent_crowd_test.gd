extends SceneTree
## G5 S2: a grid Site team with a detached row (member=false) and an off-map row (site_exited) enters the crowd.
## The D5 import makes the detached row native absent kind 1 and the off-map row kind 2, keeps the roster count, and
## the absent people neither draw nor move. A return rejoins the field; an off-map person cannot return. A save with
## absent members validates against the rows; a mismatched row is rejected. The formerly refused handover succeeds.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: SITE_ROSTER_ABSENT_CROWD_PASS on success; quit(1) on a failed check; quit(3) on the 300-second deadline.

const DT := 1.0 / 30.0
const Store = preload("res://scripts/terrain_lab/site_store.gd")

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _deadline())
	_run.call_deferred()

func _deadline() -> void:
	printerr("SITE_ROSTER_ABSENT_CROWD_FAIL: 300-second deadline")
	quit(3)

func _fail(message: String, detail: Variant = null) -> void:
	printerr("SITE_ROSTER_ABSENT_CROWD_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_ROSTER_ABSENT_CROWD OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

# One real frame of the formal scene, as in play. Returns false when the original step latched a fault.
func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		lab.site_controller.person_actions.settle_after_contacts()
		if not lab.site_controller._original_step_fault.is_empty():
			_fail("latched frame fault", lab.site_controller._original_step_fault)
			return false
	return true

# The native absence state of a soldier index as [absent, kind] integers.
func _absent(host: Node, index: int) -> Array:
	var state: Array = Array(host.crowd.site_person_absent_state(index))
	return [int(state[0]), int(state[1])] if state.size() >= 2 else [-1, -1]

func _position(host: Node, index: int) -> Array:
	var state: Dictionary = host.soldier_state(index)
	return [float(state.px), float(state.py)]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	# Setup as crowd_c2_actor_deploy_test.gd and site_g8a_crowd_test.gd: the NPC body is assigned before the scene enters the tree.
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for person: TerrainTestCharacter in lab.combat_actors: person.set_process(false)
	if not _check(lab.character != null and lab.npc != null and lab.site_controller != null, "formal scene has its player bodies and Controller"): return
	if not _check(lab.crowd_site != null and not lab.crowd_site.active, "formal scene has an inactive CrowdSite"): return
	var data: TerrainData = lab.terrain
	var centre: Vector2i = data.spawn_cell
	var cells: Array[Vector2i] = [centre + Vector2i(-1, 3), centre + Vector2i(0, 3), centre + Vector2i(1, 3)]

	# The grid team of three, not yet in the crowd: the second row is detached, the third is off-map.
	var source: TerrainArmy = lab.army
	source.roster_size = cells.size()
	source.faction_id = 0
	if not _check(source.deploy_at(data, lab.character, lab.npc, cells), "the grid team deploys"): return
	if not _check(source.enable_combat(false, 0), "the grid team enables combat"): return
	source.set_process(false)
	source.settle_combat_command()
	var detached: int = source.combat_identity(1)
	var exited: int = source.combat_identity(2)
	var kept: int = source.combat_identity(0)
	# The grid marks a detached row member=false, present=false (region_travel _detach_row) and an off-map row
	# site_exited=true, present=false (terrain_army _finish_site_exit). The writes go through the hot store.
	source.combat_hot_set(1, &"member", false)
	source.combat_hot_set(1, &"present", false)
	source.combat_hot_set(2, &"site_exited", true)
	source.combat_hot_set(2, &"present", false)

	# D5 import: the team that used to be refused (CS d5_prepare_existing UNSUPPORTED) now enters the crowd.
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false}])
	if not _check(imported.get("ok", false) == true, "the detached and off-map team enters the crowd through the D5 import", imported): return
	var host: Node = lab.crowd_site
	if not _check(host.active, "the crowd is active after the import"): return
	var detached_index: int = int(host.crowd.soldier_index(detached))
	var exited_index: int = int(host.crowd.soldier_index(exited))
	var kept_index: int = int(host.crowd.soldier_index(kept))
	if not _check(_absent(host, detached_index) == [1, 1], "the detached row is native absent kind 1", _absent(host, detached_index)): return
	if not _check(_absent(host, exited_index) == [1, 2], "the off-map row is native absent kind 2", _absent(host, exited_index)): return
	if not _check(_absent(host, kept_index)[0] == 0, "the remaining member stays on the roster"): return

	# The roster count is kept: all three rows, all three team people, and the absent flags in the owners.
	var formation: int = int(host.person_owner(kept).formation_index)
	var roster: Dictionary = host.team_record(formation)
	if not _check(roster.units.size() == cells.size(), "the roster keeps every row", roster.units.size()): return
	var team_people := 0
	for team: Dictionary in host.teams:
		if int(team.formation) == formation: team_people = team.person_ids.size()
	if not _check(team_people == cells.size(), "the team keeps every person id", team_people): return
	var detached_owner: Variant = host.person_owner(detached)
	var exited_owner: Variant = host.person_owner(exited)
	if not _check(not bool(detached_owner.combat_hot_get(detached_index, &"present")) and not bool(detached_owner.combat_hot_get(detached_index, &"member")), "the detached owner reads member false and present false"): return
	if not _check(bool(exited_owner.combat_hot_get(exited_index, &"member")) and bool(exited_owner.combat_hot_get(exited_index, &"site_exited")), "the off-map owner reads member true and site_exited true"): return

	# Absent people are not drawn and do not move; the remaining member keeps acting on the field.
	var frozen := {detached: _position(host, detached_index), exited: _position(host, exited_index)}
	if not _check(not bool(host.crowd.get_soldier_presence(detached_index)) and not bool(host.crowd.get_soldier_presence(exited_index)), "absent people are not present natively"): return
	if not _tick(90): return
	for identity: int in [detached, exited]:
		var index: int = int(host.crowd.soldier_index(identity))
		if not _check(_position(host, index) == frozen[identity], "an absent person does not move", identity): return
		if not _check(not bool(host.crowd.get_soldier_presence(index)), "an absent person is not drawn or present", identity): return
	if not _check(_absent(host, detached_index) == [1, 1] and _absent(host, exited_index) == [1, 2], "absence survives the ticks"): return

	# Save with absent members: the native blob and the GD rows agree and validate.
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.get("ok", false) == true, "a save with absent members captures", captured): return
	var detached_row: Dictionary = host.team_record(int(host.person_owner(detached).formation_index)).units[1]
	if not _check(detached_row.member == false and detached_row.present == false and not bool(detached_row.get("site_exited", false)), "the detached row is written as member false, present false"): return
	var exited_row: Dictionary = host.team_record(int(host.person_owner(exited).formation_index)).units[2]
	if not _check(exited_row.member == true and exited_row.site_exited == true and exited_row.present == false, "the off-map row is written as site_exited"): return
	var one: Dictionary = Store._validate_crowd(data, data.site, 1)
	if not _check(one.ok, "the absent save validates", one): return
	if not _check(one.native.save_state() == host.crowd.save_state(), "the reloaded native blob equals the live crowd"): return
	for identity: int in [detached, exited]:
		var index: int = int(host.crowd.soldier_index(identity))
		if not _check(Array(one.native.site_person_absent_state(index)) == Array(host.crowd.site_person_absent_state(index)), "the reloaded absent state equals the live state", identity): return
	# A row that disagrees with its native absence is refused.
	var broken: Dictionary = data.site.duplicate(true)
	for army: Dictionary in broken.armies:
		for row: Dictionary in army.get("units", []):
			if int(row.person_id) == detached: row.member = true
	if not _check(not Store._validate_crowd(data, broken).ok, "a detached native soldier with member=true is refused"): return

	# A return rejoins the field; the off-map person cannot return.
	# An off-map person stays absent (kind 2); a write that tries to return them is refused loudly (push_error), so the
	# verifier-clean test only checks the state and does not issue that write.
	if not _check(_absent(host, exited_index) == [1, 2], "an off-map person stays off the field", _absent(host, exited_index)): return
	detached_owner.combat_hot_set(detached_index, &"present", true)
	if not _check(_absent(host, detached_index) == [0, 0], "the returned person is on the roster again", _absent(host, detached_index)): return
	if not _check(bool(detached_owner.combat_hot_get(detached_index, &"present")) and bool(detached_owner.combat_hot_get(detached_index, &"member")), "the returned owner reads member and present"): return
	if not _check(bool(host.crowd.get_soldier_presence(detached_index)) or _absent(host, detached_index)[0] == 0, "the returned person is on the field"): return
	if not _tick(3): return
	if not _check(_absent(host, detached_index) == [0, 0] and host.crowd.soldier_index(detached) == detached_index, "the returned person stays rejoined after a tick"): return

	# The final save after the return validates and keeps the off-map person absent.
	var final_capture: Dictionary = lab.site_controller._capture_for_save()
	if not _check(final_capture.get("ok", false) == true, "the final save captures after the return", final_capture): return
	var final_validation: Dictionary = Store._validate_crowd(data, data.site, 1)
	if not _check(final_validation.ok, "the final save validates", final_validation): return

	for _warmup: int in range(3): await process_frame
	lab.free()
	print("SITE_ROSTER_ABSENT_CROWD_PASS: ", checks, " checks; the detached and off-map rows enter the crowd as native absent kinds 1 and 2, the roster count is kept, absent people neither draw nor move, the detached one returns and rejoins, the off-map one stays off the field, the absent save validates against the rows and rejects a mismatch")
	quit(0)
