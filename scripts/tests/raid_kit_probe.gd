extends SceneTree
## Probe (2026-11-25): what a lair's band and a village's people fight with in the native crowd. A small generated world,
## the lair and the nearest village bound; prints each person's native weapon family, material, armour, shield, role,
## ability and hit points. Output: RAID_KIT lines and RAID_KIT_DONE.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const FAMILIES := ["none", "longsword", "spear", "axe", "wood_axe", "hammer", "dagger", "bow", "crossbow", "pickaxe", "tool_hammer", "shovel"]

var lab: TerrainLab
var slot: RegionSaveSlot
var finished := false

func _initialize() -> void:
	create_timer(1500.0).timeout.connect(func() -> void: _end("deadline"))
	_run.call_deferred()

func _end(reason: String) -> void:
	if finished: return
	finished = true
	print("RAID_KIT END %s" % reason)
	print("RAID_KIT_DONE")
	TerrainArmy.release_contact_source()
	quit(0)

func _bind(id: String) -> Dictionary:
	var bound: Dictionary = {}
	for attempt: int in range(6000):
		bound = lab._region_gameplay_owner_lab(id, "cold_exact")
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	return bound

func _print_people(name: String, field: TerrainLab) -> void:
	for team: Dictionary in field.crowd_site.teams:
		var kits := {}
		for person: Variant in team.person_ids:
			var id := int(person)
			var appearance: Dictionary = field.crowd_site._appearance(id)
			var packed: int = field.crowd_site._packed_equip(appearance)
			var state: Dictionary = field.crowd_site.soldier_state(int(field.crowd_site._index_by_id[id]))
			var body: Variant = field.site_controller.person_actions._person(id, false).get("body")
			var ability: Variant = body.get("combat_ability") if body != null else null
			var key := "role %d %s/m%d armour%d shield%d hp%d ability %s" % [int(state.military_role), FAMILIES[packed & 255], (packed >> 8) & 255, (packed >> 16) & 255, (packed >> 24) & 255, int(state.hp), str(ability)]
			kits[key] = int(kits.get(key, 0)) + 1
		print("RAID_KIT %s team %d faction %d people %d: %s" % [name, int(team.team_id), int(team.faction), team.person_ids.size(), JSON.stringify(kits)])

func _run() -> void:
	var folder := "user://raid_kit_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a"))
	var natural := RegionData.new()
	natural.load_manifest(RegionData.DEFAULT_MANIFEST)
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 4, 1, 0, 20261122)
	if not built.get("ok", false) or not RegionEntry.request_new_world(built.start, {}, "裝備追查", "", str(built.path)):
		_end("no world")
		return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 1200000
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		_end("the world did not open")
		return
	for _warm: int in range(5): await process_frame
	slot = lab.site_controller.region_slot
	lab.set_process(false)
	_print_people("PLAYER", lab)
	var registry: Dictionary = slot.control.faction_registry
	var lair := ""
	for key: Variant in registry.entries:
		if registry.entries[key].get("status") == "active" and RegionFactionQuery.is_bandit(registry, int(registry.entries[key].faction_id)): lair = str(RegionFactionQuery.bandit_of(registry, int(registry.entries[key].faction_id)).lair.site_id)
	var target := ""
	for site: Variant in slot._marker.sites:
		var id := "%s:%s" % [str(slot.pin.atlas_id), str(site)]
		if id == lair or id == str(lab.terrain.site.id): continue
		if target.is_empty() or Bandit.site_distance(lair, id) < Bandit.site_distance(lair, target): target = id
	for id: String in [lair, target]:
		var bound: Dictionary = await _bind(id)
		if not bound.get("ok", false):
			_end("bind %s" % str(bound).left(200))
			return
		_print_people("LAIR" if id == lair else "VILLAGE", bound.lab)
	_end("complete")
