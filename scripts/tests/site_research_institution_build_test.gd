extends SceneTree
## Research institutions (Nekki 11/07, option C) stage 1: the three building kinds exist, their
## build requirements refuse cleanly, and missing formal art refuses MISSING_ART with no change.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error("SITE_RESEARCH_INSTITUTION_BUILD_FAIL: " + message)
		quit(1)

func _fixture() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(72, 72))
	data.spawn_cell = Vector2i(3, 3)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "research-institution-build")
	data.resource_base.clear()
	data.site.changes.clear()
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.foundation.fill(80)
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.worker.cell = data.index(Vector2i(3, 4))
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.capacity = 100000
	var storage: Dictionary = Runtime.initialize_item_storage(data.site)
	check(storage.ok, "fixture item storage")
	SiteEnvironment.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _cells(data: TerrainData, kind: String, anchor: Vector2i) -> Array[int]:
	var geometry := Runtime.building_cells(data, kind, anchor, Vector2i(Runtime.FEATURES[kind].size), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	check(geometry.ok, kind + " has a legal fixed footprint: " + str(geometry))
	var cells: Array[int] = []
	cells.assign(geometry.get("cells", []))
	return cells

func _initialize() -> void:
	for kind: String in ["craft_room", "artisan_academy", "works_academy"]:
		check(Runtime.FEATURES.has(kind) and Runtime.RESEARCH_INSTITUTIONS.has(kind), kind + " is a formal building kind")
	check(Runtime.RESEARCH_INSTITUTIONS.craft_room.scope == "family" and int(Runtime.RESEARCH_INSTITUTIONS.craft_room.seats) == 1, "craft room serves one family researcher")
	check(Runtime.RESEARCH_INSTITUTIONS.artisan_academy.scope == "settlement" and int(Runtime.RESEARCH_INSTITUTIONS.artisan_academy.seats) == 2, "artisan academy serves two settlement researchers")
	check(Runtime.RESEARCH_INSTITUTIONS.works_academy.scope == "nation" and int(Runtime.RESEARCH_INSTITUTIONS.works_academy.seats) == 3, "works academy serves three nation researchers")
	var data := _fixture()
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	# No family, no settlement: each refuses on its requirement and changes nothing.
	for kind: String in ["craft_room", "artisan_academy", "works_academy"]:
		var before := var_to_bytes(data.site)
		var refused := Runtime.request_build(data, kind, _cells(data, kind, Vector2i(20, 20)), Callable(), options)
		check(not refused.ok and refused.code == "REQUIREMENTS" and var_to_bytes(data.site) == before, kind + " refuses its missing requirement: " + str(refused))
	# With a family the craft room meets its requirement; formal art is absent, so it refuses MISSING_ART.
	data.site["family"] = {"family_id": "fixture"}
	var before_art := var_to_bytes(data.site)
	var no_art := Runtime.request_build(data, "craft_room", _cells(data, "craft_room", Vector2i(20, 20)), Callable(), options)
	if Runtime.formal_building_art_available("craft_room", 0):
		check(no_art.ok, "craft room builds once its formal art is published: " + str(no_art))
		data.site.erase("family") # The fixture family is only the build requirement, not a valid saved family.
		var path := "user://research_institution_build_%d.json" % Time.get_ticks_usec()
		var saved: Dictionary = SiteStore.save(data, path)
		check(saved.ok, "a site with a craft room under construction saves: " + str(saved))
		# Load needs a generated map; this synthetic grid only proves the strict save validator admits the kind.
	else:
		check(not no_art.ok and no_art.code == "MISSING_ART" and var_to_bytes(data.site) == before_art, "missing formal art refuses with no change and no placeholder: " + str(no_art))
	print("SITE_RESEARCH_INSTITUTION_BUILD_PASS: checks=", checks, "; kinds, requirements, MISSING_ART refusal")
	quit(0)
