extends "res://scripts/tests/site_family_first_earned_base.gd"
## Research institutions end to end (Nekki 11/07, option C):
## - the real F03 family fixture builds a real 工法室 through the formal build owner;
## - the family head seats the controlled person as its researcher through the public command;
## - one researcher-day of preparation marks the project halved;
## - the original earned F03 flow then completes with 1 kiln trial instead of 3.
## Preparation time is fed to the institution owner directly (one game day of points would take
## too long here); the trials themselves run through the full original shared-point caller.

const Institutions = preload("res://scripts/terrain_lab/site_research_institutions.gd")

func _earned_id() -> String:
	return "F03"

func _earned_fixture() -> Dictionary:
	var f: Dictionary = super._earned_fixture()
	if f.is_empty(): return f
	var data: TerrainData = f.data
	var room := _earned_host(data, "craft_room", data.cell_from_index(int(data.site.depot_cell)) + Vector2i(6, 0), Vector2i(3, 3))
	if not _earned_check(not room.is_empty(), "A real craft room is built by the formal owner"): return {}
	var seated: Dictionary = f.actions.set_institution_researcher(int(f.control), room, int(f.control))
	if not _earned_check(seated.ok, "The family head seats the controlled person as the craft room researcher: " + str(seated)): return {}
	var door: Vector2i = data.cell_from_index(int(data.site.features[room].entrance))
	var beside := Vector2i(-1, -1)
	for side: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
		var cell: Vector2i = door + side
		if beside.x < 0 and data.contains(cell) and data.is_walkable(cell) and int(data.feature_at[data.index(cell)]) == 0: beside = cell
	if not _earned_check(beside.x >= 0 and f.lab.character.place(beside, true), "The researcher stands beside the craft room door"): return {}
	data.site.inventory["grain"] = int(data.site.inventory.get("grain", 0)) + 2
	Institutions.advance(data, f.actions, Institutions.PREPARED_SECONDS)
	var project: Dictionary = _earned_project(f)
	if not _earned_check(project.get("institution_halved") == true, "One researcher-day prepares and halves the active F03 project"): return {}
	var phase := Technology.scope_next_phase(project, project.executor, data.site.family.technology.get("person_links", []))
	if not _earned_check(int(phase.repeat) == 1, "The 3 kiln trials now need 1 real trial"): return {}
	var unseated: Dictionary = f.actions.set_institution_researcher(int(f.control), room, int(f.control), false)
	if not _earned_check(unseated.ok, "The researcher leaves the seat to run the trial"): return {}
	f["expected_receipts"] = 1
	# The base's final balance check compares what was spent: halved trials spend half the
	# granted cap (rounded down per phase), and the rest of the grant simply stays unspent.
	var spent := {}
	for phase_spec: Dictionary in EarnedCatalog.get_node("F03").research.routes[0].phases:
		for material: String in phase_spec.materials:
			spent[material] = int(spent.get(material, 0)) + int(phase_spec.materials[material]) * Technology.phase_repeat(project, phase_spec)
	f["cap"] = spent
	return f
