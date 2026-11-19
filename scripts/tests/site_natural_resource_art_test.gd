extends SceneTree
## Run through the canonical verifier: headless, or visual with user arg --visual.
## Formal captures use the configured main scene and normally generated resources.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const RegionViewer = preload("res://scripts/region_lab/region_lab.gd")
const OUT := "res://output/wildlife_formal_20261002"
const ART_NAMES: Array[String] = ["stag", "boar", "doe", "horse", "sheep"]
const ART_VARIANTS: Array[int] = [0, 1, 2, 0, 2]
const CELL := 64.0
var lab: TerrainLab
var view: SiteResourceView
var visual := false
var deadline := 0
var failed := false
var finished := false
var report := {"status": "INCOMPLETE", "captures": [], "assets": [], "owner_checks": []}

func _initialize() -> void:
	visual = OS.get_cmdline_user_args().has("--visual")
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline:
		_check(false, "SITE_NATURAL_RESOURCE_ART_TIMEOUT")
		_stop_failed("deadline")
	return false

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	failed = true
	report.status = "FAIL"
	if not report.has("failure"):
		report["failure"] = message
	push_error("SITE_NATURAL_RESOURCE_ART_FAIL: " + message)
	return false

func _stop_failed(stage: String) -> void:
	if not failed:
		_check(false, "Stage did not finish successfully: " + stage)
	finished = true
	_write_report()
	quit(1)

func _run() -> void:
	if not _check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/captures")) == OK, "Contract failed: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + \"/captures\")) == OK"):
		_stop_failed("startup or owner check")
		return
	report["mode"] = "visual" if visual else "headless"
	report["scope"] = "Formal main scene, normally generated sources, frozen simulation; no performance claim."
	report["user_data_dir"] = OS.get_user_data_dir()
	if not _write_report():
		_stop_failed("report write")
		return
	# The main scene can load/save user data during startup and map replacement.
	if not _check(OS.get_environment("APPDATA").replace("\\", "/").contains("/godot_verify/"), "Use verify_godot.ps1 with its isolated APPDATA directory"):
		_stop_failed("startup or owner check")
		return
	if not _check(not FileAccess.file_exists(Store.DEFAULT_PATH), "The verification profile already has a current Site"):
		_stop_failed("startup or owner check")
		return
	if not _check(not visual or DisplayServer.get_name() != "headless", "--visual requires a GPU-backed window"):
		_stop_failed("startup or owner check")
		return
	if visual:
		DisplayServer.window_set_size(Vector2i(1600, 1000))
	root.gui_embed_subwindows = true
	var main_path := str(ProjectSettings.get_setting("application/run/main_scene"))
	var scene := load(main_path) as PackedScene
	if not _check(scene != null, "Contract failed: scene != null"):
		_stop_failed("startup or owner check")
		return
	lab = scene.instantiate() as TerrainLab
	if not _check(lab != null, "Contract failed: lab != null"):
		_stop_failed("startup or owner check")
		return
	report["main_scene"] = main_path
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	paused = true
	lab.site_controller._auto_save_blocked = true
	view = lab.site_controller.view as SiteResourceView
	if not _check(view != null and view.data == lab.terrain, "Contract failed: view != null and view.data == lab.terrain"):
		_stop_failed("startup or owner check")
		return
	await process_frame
	if not _check_assets():
		_stop_failed("assets")
		return
	if not _check_generated_contract():
		_stop_failed("generated contract")
		return
	var original := _owner_signature()
	var original_mapping: Dictionary = _wildlife_art_mapping(lab.terrain)
	var original_nodes: Dictionary = _resource_node_account(view)
	if not _check(original_nodes.actual == original_nodes.expected, "Resource presenter gained nodes beyond its original rows/runs"):
		_stop_failed("presenter nodes")
		return
	for mode in range(SiteResourceView.VIEW_NAMES.size()):
		view.view_mode = mode
		view.refresh()
		view.animate(0.25)
		if not _check(_owner_signature() == original, "Presenter altered authoritative state in view mode " + str(mode)):
			_stop_failed("startup or owner check")
			return
		if not _check(_wildlife_art_mapping(lab.terrain) == original_mapping and _resource_node_account(view).actual == original_nodes.actual, "Refresh changed wildlife appearance or presenter node boundary"):
			_stop_failed("mapping or node refresh")
			return
	view.view_mode = 0
	view.refresh()
	report.owner_checks.append({"phase": "all_view_modes", "same_owners": true})
	var original_pause: bool = bool(lab.terrain.site.paused)
	lab.terrain.site.paused = true
	var pause_owners: PackedByteArray = _owner_signature()
	var pause_time: float = view.animation_time
	view.animate(0.625)
	var pause_ok: bool = view.animation_time == pause_time and _owner_signature() == pause_owners and _resource_node_account(view).actual == original_nodes.actual
	lab.terrain.site.paused = original_pause
	if not _check(pause_ok and _owner_signature() == original, "Paused presentation advanced animation or changed original owners/nodes"):
		_stop_failed("pause")
		return
	report.owner_checks.append({"phase": "wildlife_pause_refresh_nodes", "same_owners": true, "mapping_stable": true, "pause_freezes_animation": true, "presenter_nodes": original_nodes})
	if visual:
		if not await _formal_captures():
			_stop_failed("formal captures")
			return
	else:
		report["visual_checked"] = false
		report["visual_note"] = "Headless proves data/assets contracts only; no rendered-image evidence."
	if failed:
		_stop_failed("final failure guard")
		return
	finished = true
	report.status = "PASS"
	report["elapsed_ms"] = Time.get_ticks_msec() - (deadline - 90000)
	if not _write_report():
		_stop_failed("report write")
		return
	print("SITE_NATURAL_RESOURCE_ART_PASS mode=", report.mode, " captures=", report.captures.size(),
		" actual main scene; atlas schema; variants; cleared/exhausted round trip; unchanged owners")
	lab.queue_free()
	await process_frame
	quit(0)

func _write_report() -> bool:
	var file := FileAccess.open(OUT + "/result_" + ("visual" if visual else "headless") + ".json", FileAccess.WRITE)
	if not _check(file != null, "Contract failed: file != null"):
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return true

func _alpha_bounds(picture: Image, rectangle: Rect2i, threshold: int) -> Dictionary:
	var tile := picture.get_region(rectangle)
	tile.convert(Image.FORMAT_RGBA8)
	var bytes := tile.get_data()
	var low := Vector2i(tile.get_width(), tile.get_height())
	var high := Vector2i(-1, -1)
	var raw_low := low
	var raw_high := high
	var faint_pixels := 0
	for y in range(tile.get_height()):
		for x in range(tile.get_width()):
			var alpha: int = bytes[(y * tile.get_width() + x) * 4 + 3]
			if alpha == 0:
				continue
			raw_low = raw_low.min(Vector2i(x, y))
			raw_high = raw_high.max(Vector2i(x, y))
			if alpha < threshold:
				faint_pixels += 1
				continue
			low = low.min(Vector2i(x, y))
			high = high.max(Vector2i(x, y))
	if not _check(high.x >= low.x and high.y >= low.y, "Empty visible atlas frame"):
		return {}
	var size := high - low + Vector2i.ONE
	var raw_size := raw_high - raw_low + Vector2i.ONE
	return {"visible": [low.x, low.y, size.x, size.y],
		"raw": [raw_low.x, raw_low.y, raw_size.x, raw_size.y], "faint_pixels": faint_pixels,
		"edge_margin": mini(mini(low.x, low.y), mini(tile.get_width() - high.x - 1, tile.get_height() - high.y - 1))}

func _load_png(path: String) -> Image:
	var picture := Image.new()
	if not _check(picture.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK, "Could not decode original PNG: " + path):
		return null
	return picture

func _check_anchor(anchor: Array) -> bool:
	if not _check(anchor.size() == 2 and float(anchor[0]) >= 0.0 and float(anchor[0]) <= 1.0, "Contract failed: anchor.size() == 2 and float(anchor[0]) >= 0.0 and float(anchor[0]) <= 1.0"):
		return false
	if not _check(float(anchor[1]) >= 0.0 and float(anchor[1]) <= 1.0, "Contract failed: float(anchor[1]) >= 0.0 and float(anchor[1]) <= 1.0"):
		return false
	return true

func _check_assets() -> bool:
	var manifest_path := "res://assets/map/site/natural_resources/manifest.json"
	var constants: Dictionary = view.get_script().get_script_constant_map()
	if not _check(str(constants.get("RESOURCE_ART_MANIFEST", "")) == manifest_path, "Formal presenter must use the verified manifest"):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not _check(parsed is Dictionary, "Contract failed: parsed is Dictionary"):
		return false
	var manifest: Dictionary = parsed
	if not _check(int(manifest.schema_version) == 1 and int(manifest.alpha_visible_threshold) == 16, "Contract failed: int(manifest.schema_version) == 1 and int(manifest.alpha_visible_threshold) == 16"):
		return false
	var picture := _load_png(str(manifest.texture))
	if not _check(picture != null and picture.get_size() == Vector2i(int(manifest.atlas_size[0]), int(manifest.atlas_size[1])), "Contract failed: picture != null and picture.get_size() == Vector2i(int(manifest.atlas_size[0]), int(manifest.atlas_size[1]))"):
		return false
	var atlas_rect := Rect2i(Vector2i.ZERO, picture.get_size())
	var sprite_rows := {}
	var names := ["conifer", "broadleaf", "olive", "stone", "clay", "iron", "salt", "food", "herb", "fish"]
	if not _check(manifest.sprites.size() == names.size(), "Contract failed: manifest.sprites.size() == names.size()"):
		return false
	for key: String in names:
		if not _check(manifest.sprites.has(key), "Contract failed: manifest.sprites.has(key)"):
			return false
		var sprite: Dictionary = manifest.sprites[key]
		if not _check(sprite.region.size() == 4 and sprite["size"].size() == 2, "Contract failed: sprite.region.size() == 4 and sprite[\"size\"].size() == 2"):
			return false
		var region := Rect2i(int(sprite.region[0]), int(sprite.region[1]), int(sprite.region[2]), int(sprite.region[3]))
		if not _check(region.has_area() and atlas_rect.encloses(region), "Invalid source region " + key):
			return false
		if not _check(float(sprite["size"][0]) > 0.0 and float(sprite["size"][1]) > 0.0, "Contract failed: float(sprite[\"size\"][0]) > 0.0 and float(sprite[\"size\"][1]) > 0.0"):
			return false
		if not _check_anchor(sprite.anchor):
			return false
		var measured := _alpha_bounds(picture, region, 16)
		if measured.is_empty():
			return false
		if not _check(int(measured.edge_margin) >= 2, "Static body clipped by region: " + key):
			return false
		measured["source_region"] = sprite.region
		sprite_rows[key] = measured
	report.assets.append({"path": manifest.texture, "sha256": FileAccess.get_sha256(str(manifest.texture)),
		"atlas_size": manifest.atlas_size, "alpha_visible_threshold": 16, "sprites": sprite_rows})
	if not _check(manifest.wildlife.size() == ART_NAMES.size(), "Formal wildlife manifest must cover five appearances"):
		return false
	for art_index: int in range(ART_NAMES.size()):
		var animal: Dictionary = manifest.wildlife[art_index]
		if not _check(str(animal.name) == ART_NAMES[art_index] and int(animal.variant) == ART_VARIANTS[art_index] and animal.grid.size() == 2 and int(animal.grid[0]) == 4 and int(animal.grid[1]) == 2, "Wildlife name, source variant or numeric grid dimensions are invalid"):
			return false
		if not _check(animal.anchors.size() == 2 and animal.visible_bounds.size() == 8, "Contract failed: animal.anchors.size() == 2 and animal.visible_bounds.size() == 8"):
			return false
		if not _check(float(animal.width) > 0.0 and int(animal.alpha_visible_threshold) == 16, "Contract failed: float(animal.width) > 0.0 and int(animal.alpha_visible_threshold) == 16"):
			return false
		for anchor: Array in animal.anchors:
			if not _check_anchor(anchor):
				return false
		picture = _load_png(str(animal.texture))
		if not _check(picture != null and picture.get_size() == Vector2i(int(animal.atlas_size[0]), int(animal.atlas_size[1])), "Contract failed: picture != null and picture.get_size() == Vector2i(int(animal.atlas_size[0]), int(animal.atlas_size[1]))"):
			return false
		var frames: Array = []
		for frame in range(8):
			var column := frame % 4
			var row := floori(float(frame) / 4.0)
			# Runtime uses fractional source cells. Integer QA crops may differ by
			# one pixel from Python's ties-to-even rounding in the authoring record.
			var left := roundi(float(column) * picture.get_width() / 4.0)
			var top := roundi(float(row) * picture.get_height() / 2.0)
			var right := roundi(float(column + 1) * picture.get_width() / 4.0)
			var bottom := roundi(float(row + 1) * picture.get_height() / 2.0)
			var measured := _alpha_bounds(picture, Rect2i(left, top, right - left, bottom - top), 16)
			if measured.is_empty():
				return false
			if not _check(int(measured.edge_margin) >= 4, "Wildlife body touches frame boundary"):
				return false
			for coordinate in range(4):
				if not _check(absi(int(measured.visible[coordinate]) - int(animal.visible_bounds[frame][coordinate])) <= 1, "Wildlife bounds disagree with manifest: " + str(animal.texture) + " frame " + str(frame)):
					return false
			frames.append(measured)
		report.assets.append({"path": animal.texture, "sha256": FileAccess.get_sha256(str(animal.texture)),
			"art_index": art_index, "name": animal.name, "variant": animal.variant, "atlas_size": animal.atlas_size, "grid": animal.grid,
			"alpha_visible_threshold": 16, "bounds_rounding_tolerance_px": 1, "frames": frames})
	report["manifest_sha256"] = FileAccess.get_sha256(manifest_path)
	report["alpha_note"] = "Visible body uses alpha >= 16. Original alpha 1-15 pixels are retained and counted separately."
	if not _write_report():
		return false
	return true

func _check_generated_contract() -> bool:
	var kinds := {}
	var wildlife_variants := {}
	var wildlife_appearances: Dictionary = {}
	# Independent expectations catch a reversed parity or changed variant contract.
	for sample: Array in [[0, 10, 0], [0, 11, 3], [1, 10, 1], [1, 11, 1], [2, 10, 2], [2, 11, 4]]:
		if not _check(SiteResourceView.wildlife_art_index(int(sample[0]), int(sample[1])) == int(sample[2]), "Known wildlife source mapping changed: " + str(sample)):
			return false
	var fixture: TerrainData
	for preset in range(TerrainPreset.NAMES.size()):
		var data := TerrainGenerator.generate(preset, 71)
		Env.initialize(data, "natural-art-contract-" + str(preset))
		if preset == TerrainPreset.Kind.PLAINS:
			fixture = data
		for key: String in data.resource_base:
			var base: Dictionary = data.resource_base[key]
			var resource := Env.resource(data, key)
			if not _check(int(base.kind) >= 0 and int(base.kind) < 9, "Contract failed: int(base.kind) >= 0 and int(base.kind) < 9"):
				return false
			if not _check(int(base.variant) in [0, 1, 2], "Resource variant schema changed"):
				return false
			if not _check(not base.has("species"), "Art introduced a second species field into the source"):
				return false
			if not _check(resource.variant == base.variant and int(resource.remaining) <= int(base.capacity), "Contract failed: resource.variant == base.variant and int(resource.remaining) <= int(base.capacity)"):
				return false
			kinds[int(base.kind)] = true
			if int(base.kind) == Env.Kind.WILDLIFE:
				wildlife_variants[int(base.variant)] = true
				var art_index: int = SiteResourceView.wildlife_art_index(int(base.variant), int(base.cell))
				if not _check(art_index >= 0 and art_index < ART_NAMES.size(), "Generated source has no formal wildlife appearance"):
					return false
				wildlife_appearances[art_index] = true
	if not _check(kinds.size() == 9 and wildlife_variants.size() == 3, "Contract failed: kinds.size() == 9 and wildlife_variants.size() == 3"):
		return false
	if not _check(wildlife_appearances.size() == ART_NAMES.size(), "Generated source matrix does not cover five wildlife appearances"):
		return false
	if not _check(fixture != null, "Contract failed: fixture != null"):
		return false
	var timber := _first_kind(fixture, Env.Kind.TIMBER)
	var stone := _first_kind(fixture, Env.Kind.STONE)
	if not _check(not timber.is_empty() and not stone.is_empty(), "Contract failed: not timber.is_empty() and not stone.is_empty()"):
		return false
	# A detached contract fixture uses existing generated sources. It is never captured.
	var fixture_mapping: Dictionary = _wildlife_art_mapping(fixture)
	if not _check(not fixture_mapping.is_empty(), "Detached generated fixture has no wildlife for stock/save mapping checks"):
		return false
	var original_changes: Dictionary = fixture.site.changes.duplicate(true)
	for key: String in fixture_mapping:
		var stock: int = int(fixture.resource_base[key].capacity)
		for change: Dictionary in [{"remaining": stock - 1}, {"cleared": true, "remaining": 0}, {"cleared": false, "remaining": stock}]:
			Env.change(fixture, key, change)
			if not _check(_wildlife_art_mapping(fixture) == fixture_mapping, "Stock/clearing/restoration changed source appearance"):
				return false
	fixture.site.changes = original_changes
	var wildlife_key: String = str(fixture_mapping.keys()[0])
	var wildlife_remaining: int = int(fixture.resource_base[wildlife_key].capacity) - 1
	Env.change(fixture, wildlife_key, {"remaining": wildlife_remaining})
	Env.change(fixture, timber, {"cleared": true, "remaining": 0})
	Env.change(fixture, stone, {"remaining": 0})
	var saved := Store.save(fixture, "user://natural_art_contract/site.json")
	if not _check(saved.ok, str(saved)):
		return false
	var loaded := Store.load_site("user://natural_art_contract/site.json")
	if not _check(loaded.ok, str(loaded)):
		return false
	var restored: TerrainData = loaded.data
	if not _check(restored.fingerprint() == fixture.fingerprint(), "Contract failed: restored.fingerprint() == fixture.fingerprint()"):
		return false
	if not _check(var_to_bytes(restored.resource_base) == var_to_bytes(fixture.resource_base), "Save/load changed source variants"):
		return false
	if not _check(_wildlife_art_mapping(restored) == fixture_mapping, "Save/load changed stable wildlife appearances"):
		return false
	if not _check(int(Env.resource(restored, wildlife_key).remaining) == wildlife_remaining, "Save/load refilled the existing wildlife stock delta"):
		return false
	if not _check(JSON.stringify(restored.site.changes, "", true) == JSON.stringify(fixture.site.changes, "", true), "Contract failed: JSON.stringify(restored.site.changes, \"\", true) == JSON.stringify(fixture.site.changes, \"\", true)"):
		return false
	if not _check(bool(Env.resource(restored, timber).cleared) and int(Env.resource(restored, timber).remaining) == 0, "Contract failed: bool(Env.resource(restored, timber).cleared) and int(Env.resource(restored, timber).remaining) == 0"):
		return false
	if not _check(not bool(Env.resource(restored, stone).cleared) and int(Env.resource(restored, stone).remaining) == 0, "Contract failed: not bool(Env.resource(restored, stone).cleared) and int(Env.resource(restored, stone).remaining) == 0"):
		return false
	# RegionLab uses this same presenter without advancing its animation clock.
	if not _check(RegionViewer.ResourceViewScript == view.get_script(), "RegionLab stopped using the original resource presenter"):
		return false
	var regional_owners: PackedByteArray = var_to_bytes([restored.resource_base, restored.site, restored.static_blocked, restored.feature_at])
	var regional_view: SiteResourceView = RegionViewer.ResourceViewScript.new()
	regional_view.display(restored)
	regional_view.refresh()
	var regional_nodes: Dictionary = _resource_node_account(regional_view)
	var regional_ok: bool = regional_view.data == restored and regional_view.animation_time == 0.0 and _wildlife_art_mapping(regional_view.data) == fixture_mapping and regional_nodes.actual == regional_nodes.expected and var_to_bytes([restored.resource_base, restored.site, restored.static_blocked, restored.feature_at]) == regional_owners
	regional_view.free()
	if not _check(regional_ok, "RegionLab shared-presenter static mapping or node contract changed"):
		return false
	report["generated_contract"] = {"kinds": kinds.size(), "wildlife_variants": wildlife_variants.keys(),
		"wildlife_art_indices": wildlife_appearances.keys(), "known_mapping_cases": 6,
		"stock_clear_restore_mapping_stable": true, "save_reload_mapping_stable": true,
		"cleared_and_exhausted_roundtrip": true, "fixture_never_captured": true,
		"regionlab_shared_presenter_static": true, "regionlab_scope": "Detached existing presenter call only; no geographic GPU/lifecycle claim"}
	return true

func _wildlife_art_mapping(data: TerrainData) -> Dictionary:
	var result: Dictionary = {}
	for key: String in data.resource_base:
		var resource: Dictionary = Env.resource(data, key)
		if int(resource.kind) == Env.Kind.WILDLIFE:
			result[key] = SiteResourceView.wildlife_art_index(int(resource.variant), int(resource.cell))
	return result

func _resource_node_account(presenter: SiteResourceView) -> Dictionary:
	var expected: int = 1 + presenter.data.size.y
	var actual: int = 1 + presenter.get_child_count()
	for row: Node2D in presenter.rows:
		actual += row.get_child_count()
	for row_index: int in range(presenter.data.size.y):
		var previous: int = -1
		for key: String in presenter.resources_by_row.get(row_index, []):
			var animated: int = int(int(presenter.data.resource_base[key].kind) in [Env.Kind.WILDLIFE, Env.Kind.FISH])
			if animated != previous:
				expected += 1
				previous = animated
		if presenter.features_by_row.has(row_index) or presenter.data.cell_from_index(int(presenter.data.site.depot_cell)).y == row_index:
			expected += 1
	return {"actual": actual, "expected": expected, "rows": presenter.rows.size()}

func _first_kind(data: TerrainData, kind: int) -> String:
	for key: String in data.resource_base:
		if int(data.resource_base[key].kind) == kind:
			return key
	return ""

func _owner_signature() -> PackedByteArray:
	var resources := {}
	for key: String in lab.terrain.resource_base:
		resources[key] = Env.resource(lab.terrain, key)
	var actors: Array = []
	for actor: TerrainTestCharacter in lab.combat_actors:
		actors.append(actor.capture_state())
	var armies: Array = []
	for team: TerrainArmy in lab.combat_armies:
		armies.append(team.capture_combat_state())
	return var_to_bytes([lab.terrain.fingerprint(), lab.terrain.resource_base, lab.terrain.site,
		resources, actors, armies, lab.terrain.static_blocked, lab.terrain.feature_at])

func _safe_rect() -> Rect2:
	var area := lab.camera_usable_rect()
	var controller: Node = lab.site_controller
	var launcher: Window = controller.launcher_window
	if launcher != null and launcher.visible and launcher.position.x > lab.get_viewport_rect().size.x / 2.0:
		area.size.x = minf(area.size.x, float(launcher.position.x) - 16.0 - area.position.x)
	var panel: Control = controller.panel
	if panel != null and panel.is_visible_in_tree():
		var panel_rect := panel.get_global_rect()
		if panel_rect.position.x > lab.get_viewport_rect().size.x / 2.0:
			area.size.x = minf(area.size.x, panel_rect.position.x - 16.0 - area.position.x)
	if not _check(area.size.x > 400 and area.size.y > 300, "Formal UI leaves insufficient capture area"):
		return Rect2()
	return area

func _source_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data := lab.terrain
	for key: String in data.resource_base:
		var resource := Env.resource(data, key)
		if bool(resource.cleared) or int(resource.remaining) <= 0:
			continue
		if data.feature_at[int(resource.cell)] != 0:
			continue
		var cells: Array[int] = [int(resource.cell)]
		if int(resource.kind) == Env.Kind.WILDLIFE:
			cells.clear()
			for n in range(mini(int(resource.remaining), resource.cells.size())):
				var cell: int = resource.cells[n]
				if data.is_walkable(data.cell_from_index(cell)) and data.feature_at[cell] == 0:
					cells.append(cell)
		for cell in cells:
			var art_index: int = SiteResourceView.wildlife_art_index(int(resource.variant), int(resource.cell)) if int(resource.kind) == Env.Kind.WILDLIFE else -1
			result.append({"key": key, "kind": int(resource.kind), "variant": int(resource.variant),
				"remaining": int(resource.remaining), "cell": cell, "source_cell": int(resource.cell),
				"art_index": art_index, "appearance": ART_NAMES[art_index] if art_index >= 0 else "",
				"point": (Vector2(data.cell_from_index(cell)) + Vector2.ONE * 0.5) * CELL})
	return result

func _pick_focus(kinds: Array[int], zoom: float) -> Vector2:
	var points := _source_points()
	var safe := _safe_rect()
	if not safe.has_area():
		return Vector2.INF
	var half_extent := (safe.size - Vector2(160, 240)) / (2.0 * zoom)
	var best := Vector2.ZERO
	var best_score := -1
	for candidate: Dictionary in points:
		if int(candidate.kind) not in kinds:
			continue
		var found := {}
		var count := 0
		var area := Rect2(candidate.point - half_extent, half_extent * 2.0)
		for source: Dictionary in points:
			if int(source.kind) in kinds and area.has_point(source.point):
				found[int(source.kind)] = true
				count += 1
		var score := found.size() * 1000 + count
		if score > best_score:
			best_score = score
			best = candidate.point
	if not _check(best_score >= 0, "Generated Site has no visible source for " + str(kinds)):
		return Vector2.INF
	return best

func _aim(point: Vector2, zoom: float) -> bool:
	if not _check(point.is_finite() and zoom > 0.0, "No usable generated capture focus"):
		return false
	var area := _safe_rect()
	if not area.has_area():
		return false
	lab.camera.zoom = Vector2.ONE * zoom
	lab.camera.position = point + (lab.get_viewport_rect().size * 0.5 - area.get_center()) / zoom
	lab.camera.force_update_scroll()
	return true

func _settle() -> bool:
	# Only the renderer may resume when a regenerated progressive display needs to drain.
	if lab.renderer.display_pending:
		lab.renderer.set_process(true)
	while lab.renderer.display_pending:
		await process_frame
		await RenderingServer.frame_post_draw
		if not _check(not failed and Time.get_ticks_msec() <= deadline, "Rendering did not settle before the deadline"):
			return false
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
		if not _check(not failed and Time.get_ticks_msec() <= deadline, "Rendering did not settle before the deadline"):
			return false
	return true

func _capture(label: String, point: Vector2, zoom: float, required: Array[int]) -> bool:
	var before := _owner_signature()
	if not _aim(point, zoom):
		return false
	view.refresh()
	if not await _settle():
		return false
	var safe := _safe_rect()
	if not safe.has_area():
		return false
	safe = safe.grow(-28)
	var visible: Array = []
	var seen := {}
	for source: Dictionary in _source_points():
		var screen: Vector2 = view.get_global_transform_with_canvas() * source.point
		if not safe.has_point(screen):
			continue
		var item: Dictionary = source.duplicate()
		item.erase("point")
		item["screen"] = [screen.x, screen.y]
		visible.append(item)
		seen[int(source.kind)] = true
	for kind in required:
		if not _check(seen.has(kind), "Requested source is covered/outside capture: " + label + " kind " + str(kind)):
			return false
	var picture := root.get_texture().get_image()
	if not _check(picture != null and not picture.is_empty(), "Contract failed: picture != null and not picture.is_empty()"):
		return false
	var path := OUT + "/captures/" + label + ".png"
	if not _check(picture.save_png(path) == OK, "Contract failed: picture.save_png(path) == OK"):
		return false
	if not _check(_owner_signature() == before, "Formal capture changed source, save, terrain, or actor owners"):
		return false
	report.captures.append({"label": label, "path": path, "sha256": FileAccess.get_sha256(path),
		"preset": lab.terrain.preset, "seed": lab.terrain.seed_value, "view_mode": view.view_mode,
		"zoom": zoom, "focus_world": [point.x, point.y], "animation_time": view.animation_time,
		"safe_rect": [safe.position.x, safe.position.y, safe.size.x, safe.size.y],
		"natural_sources_visible": visible, "same_owners": true, "planted_resources": false})
	if not _write_report():
		return false
	return true

func _freeze_callbacks(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze_callbacks(child)

func _compare_retention(label: String, point: Vector2, zoom: float) -> bool:
	var owners := _owner_signature()
	if not _aim(point, zoom):
		return false
	if not await _settle():
		return false
	_freeze_callbacks(lab)
	var animation := view.animation_time
	view.retain_static_rows = false
	view.display(lab.terrain)
	view.animation_time = animation
	if not await _settle():
		return false
	var reference := root.get_texture().get_image()
	view.retain_static_rows = true
	view.display(lab.terrain)
	view.animation_time = animation
	if not await _settle():
		return false
	var retained := root.get_texture().get_image()
	if not _check(reference != null and not reference.is_empty() and retained != null and not retained.is_empty(), "Missing retained comparison image"):
		return false
	var equal := reference.get_data() == retained.get_data()
	var evidence := {"label": label, "zoom": zoom, "view_mode": view.view_mode,
		"animation_time": animation, "rgba_equal": equal, "same_owners": _owner_signature() == owners}
	if not report.has("retained_pairs"):
		report["retained_pairs"] = []
	report.retained_pairs.append(evidence)
	if not _write_report():
		return false
	if not equal:
		if not _check(reference.save_png(OUT + "/captures/" + label + "_reference_failure.png") == OK, "Contract failed: reference.save_png(OUT + \"/captures/\" + label + \"_reference_failure.png\") == OK"):
			return false
		if not _check(retained.save_png(OUT + "/captures/" + label + "_retained_failure.png") == OK, "Contract failed: retained.save_png(OUT + \"/captures/\" + label + \"_retained_failure.png\") == OK"):
			return false
	if not _check(equal, "Same-owner retained/nonretained full-main RGBA differs: " + label):
		return false
	if not _check(bool(evidence.same_owners), "Retention switch changed source/save/actor owners"):
		return false
	return true

func _formal_captures() -> bool:
	var before := _owner_signature()
	var mixed: Array[int] = [Env.Kind.TIMBER, Env.Kind.STONE, Env.Kind.FOOD, Env.Kind.HERB]
	var center := _pick_focus(mixed, 1.0)
	if not await _capture("01_natural_overview_zoom05", center, 0.5, []):
		return false
	if not await _capture("02_natural_zoom1", center, 1.0, []):
		return false
	if not await _capture("03_natural_zoom2", center, 2.0, []):
		return false
	if not await _capture("04_forest", _pick_focus([Env.Kind.TIMBER], 1.4), 1.4, [Env.Kind.TIMBER]):
		return false
	if not await _capture("05_minerals", _pick_focus([Env.Kind.STONE, Env.Kind.CLAY, Env.Kind.IRON], 1.6), 1.6, []):
		return false
	if not await _capture("06_plants", _pick_focus([Env.Kind.FOOD, Env.Kind.HERB], 2.0), 2.0, []):
		return false
	if not await _compare_retention("overview", center, 0.5):
		return false
	if not await _compare_retention("plants", _pick_focus([Env.Kind.FOOD, Env.Kind.HERB], 2.0), 2.0):
		return false
	var wildlife := _pick_focus([Env.Kind.WILDLIFE], 2.0)
	if not await _capture("07_wildlife_a", wildlife, 2.0, [Env.Kind.WILDLIFE]):
		return false
	view.animate(0.625)
	if not await _capture("08_wildlife_b", wildlife, 2.0, [Env.Kind.WILDLIFE]):
		return false
	# Close-ups select existing walkable wildlife cells; no sources are planted.
	var variant_owners := _owner_signature()
	var animal_sources := {}
	for source: Dictionary in _source_points():
		if int(source.kind) == Env.Kind.WILDLIFE and not animal_sources.has(int(source.art_index)):
			animal_sources[int(source.art_index)] = source
	for art_index: int in range(ART_NAMES.size()):
		if not _check(animal_sources.has(art_index), "Default generated Site has no visible wildlife appearance " + ART_NAMES[art_index]):
			return false
		var source: Dictionary = animal_sources[art_index]
		if not await _capture("%02d_%s" % [12 + art_index, ART_NAMES[art_index]], source.point, 3.0, [Env.Kind.WILDLIFE]):
			return false
		var focus_visible: bool = false
		for visible_source: Dictionary in report.captures.back().natural_sources_visible:
			if visible_source.key == source.key and int(visible_source.cell) == int(source.cell) and int(visible_source.art_index) == art_index:
				focus_visible = true
		if not _check(focus_visible, "Requested natural wildlife appearance was outside/covered: " + ART_NAMES[art_index]):
			return false
		report.captures.back()["focus_variant"] = source.variant
		report.captures.back()["focus_art_index"] = art_index
		report.captures.back()["focus_appearance"] = ART_NAMES[art_index]
		report.captures.back()["focus_resource_key"] = source.key
		report.captures.back()["focus_cell"] = source.cell
		report.captures.back()["focus_source_cell"] = source.source_cell
	if not _check(_owner_signature() == variant_owners, "Wildlife variant close-ups changed original owners"):
		return false
	report.owner_checks.append({"phase": "five_wildlife_appearances_original_variants_0_1_2", "same_owners": true, "planted_resources": false})
	if not _write_report():
		return false

	if not _check(_owner_signature() == before, "Contract failed: _owner_signature() == before"):
		return false
	report.owner_checks.append({"phase": "highland_captures", "same_owners": true})
	# Use the formal generate command. It archives only inside the isolated verifier profile.
	lab.generate_terrain(TerrainPreset.Kind.COASTAL_CLIFF, 71)
	if not _check(lab.terrain.preset == TerrainPreset.Kind.COASTAL_CLIFF and lab.terrain.seed_value == 71, "Contract failed: lab.terrain.preset == TerrainPreset.Kind.COASTAL_CLIFF and lab.terrain.seed_value == 71"):
		return false
	lab.site_controller._auto_save_blocked = true
	view = lab.site_controller.view as SiteResourceView
	await process_frame
	before = _owner_signature()
	var coast := _pick_focus([Env.Kind.SALT, Env.Kind.FISH], 1.0)
	if not await _capture("09_coastal_water", coast, 1.0, []):
		return false
	if not await _capture("10_salt", _pick_focus([Env.Kind.SALT], 2.0), 2.0, [Env.Kind.SALT]):
		return false
	if not await _capture("11_fish", _pick_focus([Env.Kind.FISH], 2.0), 2.0, [Env.Kind.FISH]):
		return false
	if not _check(_owner_signature() == before, "Contract failed: _owner_signature() == before"):
		return false
	report.owner_checks.append({"phase": "coastal_captures", "same_owners": true})
	report["visual_checked"] = true
	report["visual_note"] = "PNG capture and provenance checked automatically; final visual acceptance requires image inspection."
	return true



