extends "res://scripts/tests/site_market_t3_test.gd"
## 平民 C1c / C3a: the lookups behind sheltering at the settlement centre (site_resident_schedule.gd).
## Fixture as site_market_t3_test (building fixture; the player founds a settlement of faction 1 at (20, 20)). Checks:
## - centre_cell: no settlement -> null; a founded centre still building -> null; complete -> its entrance, walkable;
##   a person of another faction -> null;
## - house_lodges: a person with no registered house -> false.
## The crowd walk-and-enter path (home_enter at the entrance) is covered by site_resident_home_crowd_test's API checks.
## Output: SITE_RESIDENT_SHELTER_RULES_PASS on success; quit(1) on failure.
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")

var shelter_checks := 0

func _need(condition: bool, message: String, detail: Variant = null) -> bool:
	shelter_checks += 1
	if condition:
		print("SITE_RESIDENT_SHELTER_RULES OK ", shelter_checks, ": ", message)
		return true
	push_error("SITE_RESIDENT_SHELTER_RULES_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var player := int(lab.controlled_person_id())
	var me: Dictionary = lab.site_controller.person_actions._person(player, false)
	if not _need(Schedule.centre_cell(lab, me) == null, "no settlement: no centre to shelter in"): return
	if not _need(lab.character.place(Vector2i(20, 18), true), "the founder stands beside the center site"): return
	var layout := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), OPTIONS)
	var center_cells: Array[int] = []
	center_cells.assign(layout.get("cells", []))
	var founded := Settlement.found(lab, player, center_cells, {"layout_version": 1, "quarter": 0}, Callable(), "避難村")
	if not _need(founded.ok, "the player founds the settlement", founded): return
	var center_key := str(founded.feature)
	if not _need(Schedule.centre_cell(lab, me) == null, "a centre still being built shelters nobody", data.site.features[center_key].get("stage")): return
	_complete_key(data, center_key)
	var cell: Variant = Schedule.centre_cell(lab, me)
	var entrance: Vector2i = data.cell_from_index(int(data.site.features[center_key].entrance))
	if not _need(cell is Vector2i and cell == entrance and data.is_walkable(entrance), "a complete centre: shelter at its entrance", [cell, entrance]): return
	var stranger := me.duplicate()
	stranger["faction"] = int(me.faction) + 1
	if not _need(Schedule.centre_cell(lab, stranger) == null, "another faction's resident does not shelter in this centre"): return
	if not _need(not Schedule.house_lodges(lab, player, me), "nobody registered to a house: no house lodges him"): return
	print("SITE_RESIDENT_SHELTER_RULES_PASS checks=", shelter_checks, "; centre entrance only when complete and own faction; no house, no lodging")
	_finish_workflow_body()
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
