extends "res://scripts/tests/site_technology_artisan_g06_siege_gates_base.gd"
## Siege gate cases whose helper starts outside the commander's radius (F11/F12). Only these
## cases need the presence refresh and helper walk; the point-order/contact family keeps the base.
# Fixture placement does not refresh command presence; the original presence owner does (CC-124).
func _place(f: Dictionary, identity: int, cell: Vector2i) -> void:
	super._place(f, identity, cell)
	if _crowd(f): return # Crowd: presence follows the formation HOLD centre the fixture moves with the commander.
	var commander: int = f.team.current_commander
	f.team._refresh_command_presence()
	_require(f.team.current_commander == commander, "Fixture geometry refresh uses the original presence owner without reselecting command")

# An absent idle helper walks to the commander's reference on real movement edges before assignment.
func _siege_assign(f: Dictionary, key: String, identities: Array) -> void:
	for identity: Variant in identities:
		if _crowd(f): break # Crowd: the base assignment lands and stands the team itself.
		_land_committed_step(f, int(identity))
		var member: int = f.team.index_for_identity(int(identity))
		if not bool(f.team.combat_hot_get(member, &"present", false)):
			_walk_siege_helper_to_reference(f, int(identity))
	super._siege_assign(f, key, identities)

func _walk_siege_helper_to_reference(f: Dictionary, identity: int) -> void:
	var team: TerrainArmy = f.team
	var member: int = team.index_for_identity(identity)
	_require(member >= 0 and team.command_reference_valid and team.combat_units[member].get("work_task", {}).is_empty(), "Only an actual idle absent helper walks to the original command reference")
	var anchor: Vector2i = Vector2i(team.command_reference)
	var path: Array[Vector2i] = []
	for direction: Vector2i in TerrainData.DIRECTIONS:
		path = team._find_local_route(team.cells[member], anchor + direction * 2, 256, false, member)
		if not path.is_empty(): break
	_require(not path.is_empty() and path.size() <= 128, "Original helper route reaches a legal nearby reference cell within a finite bound")
	_require(not path.is_empty() and path[0] == team.cells[member], "Original member route retains its source vertex before genuine movement edges")
	for edge: int in range(1, path.size()):
		var destination: Vector2i = path[edge]
		_require(Time.get_ticks_msec() < deadline, "Helper movement stays inside the original test deadline")
		var reserved: bool = team._reserve_combat_step(member, destination)
		_require(reserved, "Original Army admits each genuine helper movement edge")
		if not reserved: return
		_land_committed_step(f, identity)
	team._refresh_command_presence()
	_require(bool(team.combat_hot_get(member, &"present", false)), "Genuinely arrived original helper is present under the unchanged ordinary-member rule")

# The named operator (master) must also stand within the commander's radius before the original
# siege preview names it; walk an absent idle master the same real way.
func _siege_anchor(f: Dictionary, kind: String, near: Vector2i) -> Vector2i:
	if _crowd(f):
		# Crowd: the commander walks the team's HOLD centre to the job, so the named master stands in command presence.
		_park(f, int(f.commander), near + Vector2i(0, 8))
		return super._siege_anchor(f, kind, near)
	var master: int = f.team.index_for_identity(int(f.master))
	if master >= 0 and not bool(f.team.combat_hot_get(master, &"present", false)) and f.team.combat_units[master].get("work_task", {}).is_empty():
		_walk_siege_helper_to_reference(f, int(f.master))
	return super._siege_anchor(f, kind, near)
