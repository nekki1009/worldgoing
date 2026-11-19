extends SceneTree
## Main-menu start choice 落草 (bandit spec §10, B2). A new world is requested through RegionEntry with
## start_faction {"mode": "bandit", "name": ...} and opened in the formal TerrainLab scene. Checks:
## - an empty name and an unknown mode are refused before any world is created;
## - the registry holds a new active band (kind bandit, grey-brown, display marked 匪) led by the player, with no title,
##   raid AI off and its lair at the player's cell in the start Site;
## - the player's start team is the band; the player's credit is -20;
## - the band is hostile to the neutral side and refuses diplomacy.
## Output: REGION_START_BANDIT_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const START := Vector2i(1170, 13252)
const NAME := "黑風寨"

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(280.0).timeout.connect(func() -> void: _fail("280-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_START_BANDIT_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_START_BANDIT OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _run() -> void:
	var refused: bool = RegionEntry.request_new_world(START, {}, "空名", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "  "})
	if not _check(not refused, "an empty lair name is refused before any world", RegionEntry.menu_message): return
	refused = RegionEntry.request_new_world(START, {}, "錯", "", RegionData.DEFAULT_MANIFEST, {"mode": "pirate", "name": "x"})
	if not _check(not refused, "an unknown start mode is refused", RegionEntry.menu_message): return
	var requested: bool = RegionEntry.request_new_world(START, {}, "落草世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": NAME})
	if not _check(requested and str(RegionEntry.pending.get("start_faction", {}).get("mode", "")) == "bandit", "the 落草 start is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens and settles its boot request", [current_scene.scene_file_path if current_scene != null else "", RegionEntry.menu_message, (current_scene as TerrainLab).site_controller.message.text if current_scene is TerrainLab else ""]): return
	for _frame: int in range(5): await process_frame
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var band := -1
	for key: String in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if str(entry.get("kind", "")) == "bandit" and str(entry.get("name", "")) == NAME and str(entry.get("status", "")) == "active": band = int(entry.faction_id)
	if not _check(band >= 0 and RegionFactionQuery.is_bandit(registry, band), "the registry holds the new active band", registry.get("entries", {}).keys()): return
	var entry: Dictionary = registry.entries[str(band)]
	var leader: Variant = entry.get("leader_ref")
	if not _check(RegionFactionQuery.ref_valid(leader, "person") and RegionPeerage.record_of(registry, leader).is_empty() and entry.nation_ref == null and entry.duty_ai == false, "the player leads the band, holds no title and no nation", entry): return
	var player := int(lab.controlled_person_id())
	var at: Dictionary = lab.site_controller.person_actions._person(player, false)
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
	if not _check(table.raid_ai == false and table.origin == "scenario" and table.lair is Dictionary and str(table.lair.site_id) == str(lab.terrain.site.id) and Vector2i(int(table.lair.cell[0]), int(table.lair.cell[1])) == Vector2i(at.cell), "raid AI off; the lair is the player's cell in the start Site", [table, at.get("cell")]): return
	var shown: Dictionary = slot.faction_display(band)
	if not _check(str(entry.color) == RegionFactionQuery.BANDIT_COLOR and str(shown.name).contains(RegionFactionQuery.BANDIT_MARK) and shown.bandit == true, "the band is grey-brown and shown marked 匪", shown): return
	var target: Dictionary = lab._original_person_target(player)
	if not _check(not target.is_empty() and int(target.owner.faction_id) == band, "the player's start team is the band", target.get("owner")): return
	if not _check(int(lab.site_controller.reputation_of(player).credit) == -20 * Reputation.SCALE, "落草 costs 20 credit", lab.site_controller.reputation_of(player)): return
	var now := float(slot.control.logical_game_seconds)
	if not _check(RegionDiplomacy.hostile(registry, band, RegionFactionQuery.NEUTRAL_FACTION_ID, now) and RegionDiplomacy.declare_war(registry, band, 0, leader, now).get("code") == "BANDIT_NO_DIPLOMACY", "the band is hostile to neutral and has no diplomacy"): return
	if not _check(lab.site_controller.diplomacy_head_faction() == -1, "a chief is not a diplomacy head"): return
	_finished = true
	print("REGION_START_BANDIT_PASS: ", checks, " checks; the 落草 start creates a band led by the player")
	quit(0)
