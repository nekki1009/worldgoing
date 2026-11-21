extends "res://scripts/tests/site_building_ui_test.gd"
## 平民行為 C1b (reports/civilian-site-behavior-plan.md §4.4; Nekki 11/15 Q4 A). A completed house of faction 1 and a
## two-person team of faction 1; the first person is registered to the house and stands on its door rest cell. Checks:
## - open_pantries turns the team's ledger into food locations, one "house:<id>" per household, and is idempotent;
## - stock_pantry moves real camp food into the house and refuses more than the camp holds or a non-food item;
## - the registered member at his door eats from the house's pantry under the normal meal rules;
## - the ledger with house locations saves and validates.
## Output: SITE_RESIDENT_PANTRY_PASS on success; quit(1) on failure.

const Households = preload("res://scripts/terrain_lab/site_households.gd")
const ResidentLife = preload("res://scripts/terrain_lab/site_resident_life.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RESIDENT_PANTRY OK ", checks, ": ", message)
		return true
	push_error("SITE_RESIDENT_PANTRY_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func Sustain_valid(entry: Dictionary) -> bool:
	return SiteSustain._valid_locations(entry.locations) and int(entry.sustain.version) == 2

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var house := _formal_feature(data, "house", Vector2i(28, 20), Vector2i.ONE, {"variant": "small"})
	var layout: Dictionary = Runtime.house_layout(data, house)
	if not _ok(layout.ok and not layout.slots.is_empty(), "the house has a door rest cell", layout): return
	var door: Vector2i = data.cell_from_index(int(layout.slots[0]))
	var team: TerrainArmy = lab.army
	team.roster_size = 2
	team.faction_id = 1
	var away := Vector2i(door.x + 6, door.y + 4)
	var deployed := team.deploy_at(data, null, null, [door, away]) and team.enable_combat(false)
	if not _ok(deployed, "a two-person team deploys at the door and away"): return
	team.set_process(false)
	team.settle_combat_command()
	var resident := team.combat_identity(0)
	if not data.site.has("housing"): data.site["housing"] = {}
	data.site.housing[str(resident)] = {"version": 1, "house_id": house, "cell": int(layout.slots[0])}
	Households.reconcile(data.site)
	var opened := ResidentLife.open_pantries(controller, team)
	var entry: Dictionary = controller._supply_entry(team)
	if not _ok(opened.ok and int(entry.get("version", 0)) == 3 and entry.locations.has(Households.food_key(house)), "the ledger gets the house's pantry", [opened, entry.keys()]): return
	if not _ok(ResidentLife.open_pantries(controller, team).get("added", -1) == 0, "opening again adds nothing"): return
	if not data.site.has("inventory"): data.site["inventory"] = {}
	data.site.inventory["grain"] = 3
	if not _ok(ResidentLife.stock_pantry(controller, team, house, "grain", 4).code == "INSUFFICIENT" and ResidentLife.stock_pantry(controller, team, house, "wood", 1).code == "INVALID", "only real camp food moves"): return
	var stocked := ResidentLife.stock_pantry(controller, team, house, "grain", 3)
	if not _ok(stocked.ok and int(data.site.inventory.grain) == 0 and int(ResidentLife.pantry(controller, team, house).inventory.grain) == 3, "three grain move from the camp into the house", stocked): return
	var locations: Dictionary = controller.ship_food_locations(team, controller._team_members(team))
	if not _ok(str(locations.get(resident, "")) == Households.food_key(house) and str(locations.get(team.combat_identity(1), "x")) == "", "the resident at his door eats at home; the other person has no food place", locations): return
	controller.advance_team_sustain(team, 7.0 * 3600.0)
	var left := int(ResidentLife.pantry(controller, team, house).inventory.get("grain", 0))
	if not _ok(left < 3, "a meal came out of the house's pantry", ResidentLife.pantry(controller, team, house)): return
	if not _ok(controller._supply_locations_valid(team, entry.locations) and Sustain_valid(entry), "the ledger with house locations validates"): return
	print("SITE_RESIDENT_PANTRY_PASS checks=", checks)
	lab.free()
	quit(0)
