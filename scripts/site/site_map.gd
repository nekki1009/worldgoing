class_name SiteMap
extends Node2D

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const SiteTransitionDataType = preload("res://scripts/data/site_transition_data.gd")
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")
const MIN_ZOOM: float = 2.0
const MAX_ZOOM: float = 32.0
const COMPOSITE_TILE_SIZE_METERS: float = float(SiteLayoutDataType.SIZE_METERS.x)
const COMPOSITE_ART_SIZE_PIXELS: int = 1254
const COMPOSITE_ART_TILE_PIXELS: int = 418
# Terrain joins are authored as a shared, hard edge. This is deliberately a
# narrow pixel band rather than a blurred colour feather: both adjacent Sites
# use the same deterministic boundary profile, so the edge can be drawn once
# and still meets exactly at the Region seam. Roads, rivers and height faces
# remain separate overlays and are never modified by this pass.
const COMPOSITE_EDGE_BAND_PIXELS: int = 2

signal debug_state_changed(state: Dictionary)
signal move_requested(direction: Vector2i)

var runtime_snapshot: SiteRuntimeSnapshot
var site_texture: Texture2D
var scene_texture: Texture2D
var height_texture: Texture2D
var show_debug_overlay: bool = false
var show_scale_guide: bool = false
var camera_initialized: bool = false
var composite_mode: bool = false
var composite_center_region_cell: Vector2i = SiteLayoutDataType.INVALID_CELL
var composite_center_global_region_cell: Vector2i = SiteLayoutDataType.INVALID_CELL
var composite_tiles: Array[SiteMap] = []
var suppress_site_frame: bool = false
var composite_scene_river_axis: int = -1
var composite_river_enabled: bool = true
var composite_river_cells: Dictionary = {}
var composite_background_texture: Texture2D
var composite_background_kind: String = ""
var composite_background_only: bool = false
var composite_suppress_poi: bool = false
var forest_clear_edge_mask: int = 0

@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup(p_runtime_snapshot: SiteRuntimeSnapshot, defer_art: bool = false) -> void:
	_clear_composite_tiles()
	composite_mode = false
	composite_center_region_cell = SiteLayoutDataType.INVALID_CELL
	composite_center_global_region_cell = SiteLayoutDataType.INVALID_CELL
	composite_scene_river_axis = -1
	composite_river_enabled = true
	composite_river_cells.clear()
	composite_background_texture = null
	composite_background_kind = ""
	composite_background_only = false
	composite_suppress_poi = false
	forest_clear_edge_mask = 0
	var previous_site_id: String = runtime_snapshot.site_id if runtime_snapshot != null else ""
	var next_site_id: String = p_runtime_snapshot.site_id if p_runtime_snapshot != null else ""
	var reset_camera: bool = not camera_initialized or previous_site_id != next_site_id
	runtime_snapshot = p_runtime_snapshot
	var setup_layout: SiteLayoutDataType = runtime_snapshot.layout if runtime_snapshot != null else null
	if defer_art:
		# Composite tiles only contribute a downsampled raster to the parent
		# background. Do not build each tile's 800px texture before that raster is
		# requested; doing so made a 3x3 entry needlessly expensive.
		scene_texture = null
		site_texture = null
		height_texture = null
	else:
		scene_texture = MapArtCatalogType.site_scene_texture(setup_layout)
		# Authored strategic scenes already provide their complete surface.  Avoid
		# generating an additional fallback raster for every child in a 3x3 view;
		# ordinary Sites still receive the generated texture below.
		site_texture = _build_layout_texture(setup_layout) if scene_texture == null else null
	# Only scenes with an authored height composition get the expensive shifted
	# surface.  A normal terrain Site must keep its continuous painted floor;
	# applying a 50x50 shifted tile cache to every mountain cell turns the image
	# into a grid of translucent rectangles instead of a readable ledge.
	var scene_template: String = str(setup_layout.details.get("scene_template", "")) \
		if setup_layout != null else ""
	var has_authored_height: bool = _layout_needs_height_texture(setup_layout, scene_template)
	if not defer_art:
		height_texture = _build_height_texture(setup_layout) if has_authored_height and scene_texture == null else null
	if camera != null and reset_camera and runtime_snapshot != null and runtime_snapshot.layout != null:
		camera.position = Vector2(runtime_snapshot.layout.bounds_meters.position) \
			+ Vector2(runtime_snapshot.layout.bounds_meters.size) * 0.5
	# Site cells represent 2m x 2m; start close enough to read authored
	# terrain edges and height transitions while retaining wheel zoom-out.
	if camera != null:
		camera.zoom = Vector2(10.0, 10.0)
	camera_initialized = true
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func _layout_needs_height_texture(
		layout: SiteLayoutDataType,
		scene_template: String = ""
	) -> bool:
	if layout == null or not layout.has_height_base():
		return false
	var template: String = scene_template
	if template.is_empty():
		template = str(layout.details.get("scene_template", ""))
	return layout.site_landform == SiteLayoutDataType.Landform.MOUNTAIN_PASS \
		or layout.transitions.size() > 0 \
		or template in ["MOUNTAIN_TERRACE", "CASTLE_COURTYARD", "RUINS_TERRACE", "CAVE_ENTRANCE", "RIVER_DOCK"]

func _apply_composite_surface_policy(layout: SiteLayoutDataType) -> void:
	# POI art is the final presentation layer and is intentionally not part of a
	# Region's initial 3x3 preview. Keep the POI layout/data, but rebuild this
	# child from its native terrain and generated height base so a settlement
	# painting cannot cover neighboring Site edges.
	composite_suppress_poi = layout != null \
		and layout.layout_kind == SiteLayoutDataType.LayoutKind.POI
	if not composite_suppress_poi:
		return
	scene_texture = null
	# The composite raster is built at its final 418px tile resolution. Keep POI
	# art suppressed without rebuilding an unused 800px surface here.
	site_texture = null
	height_texture = null

func setup_composite(
		p_snapshots: Array[SiteRuntimeSnapshot],
		p_center_region_cell: Vector2i
	) -> void:
	_clear_composite_tiles()
	composite_mode = false
	composite_center_region_cell = p_center_region_cell
	composite_center_global_region_cell = SiteLayoutDataType.INVALID_CELL
	var center_snapshot: SiteRuntimeSnapshot
	for snapshot: SiteRuntimeSnapshot in p_snapshots:
		if snapshot != null and snapshot.parent_region_cell == p_center_region_cell:
			center_snapshot = snapshot
			break
	if center_snapshot == null:
		for snapshot: SiteRuntimeSnapshot in p_snapshots:
			if snapshot != null:
				center_snapshot = snapshot
				break
	if center_snapshot == null:
		return
	composite_center_global_region_cell = _snapshot_grid_cell(center_snapshot)
	runtime_snapshot = center_snapshot
	composite_mode = true
	composite_river_cells = _select_composite_river_cells(
		p_snapshots,
		p_center_region_cell
	)
	var stitched_river_axis: int = _composite_river_axis_for_cells(
		p_snapshots,
		composite_river_cells
	)
	composite_scene_river_axis = stitched_river_axis
	composite_background_kind = _composite_background_kind_for(p_snapshots)
	composite_background_texture = MapArtCatalogType.site_scene_texture_kind(
		composite_background_kind
	) if not composite_background_kind.is_empty() else null
	# The parent draws the stitched 3x3 image; a full-size center Site texture is
	# not needed here and would duplicate the most expensive raster build.
	site_texture = null
	scene_texture = null
	height_texture = null
	if camera != null:
		camera.enabled = true
		camera.position = Vector2.ZERO
		camera.zoom = Vector2.ONE * 3.4
		camera_initialized = true
	for snapshot: SiteRuntimeSnapshot in p_snapshots:
		if snapshot == null or snapshot.layout == null:
			continue
		# Do not load SiteMap.tscn from inside SiteMap: reloading the scene while
		# its global script is active makes Godot re-register global classes. A
		# lightweight child with the same presentation script keeps each tile's
		# local draw transforms isolated without recursive scene loading.
		var tile: SiteMap = SiteMap.new()
		var tile_camera: Camera2D = Camera2D.new()
		tile_camera.name = "Camera2D"
		tile.add_child(tile_camera)
		add_child(tile)
		tile.position = Vector2(
			(_snapshot_grid_cell(snapshot) - composite_center_global_region_cell)
			* int(COMPOSITE_TILE_SIZE_METERS)
		)
		tile.setup(snapshot, true)
		tile._apply_composite_surface_policy(snapshot.layout)
		tile.suppress_site_frame = true
		tile.composite_scene_river_axis = stitched_river_axis
		tile.composite_river_enabled = composite_river_cells.has(_snapshot_grid_cell(snapshot))
		tile.composite_background_only = not composite_background_kind.is_empty()
		tile.forest_clear_edge_mask = _forest_clear_edge_mask_for(snapshot, p_snapshots)
		tile.show_debug_overlay = false
		tile.show_scale_guide = false
		if tile.camera != null:
			tile.camera.enabled = false
		tile.process_mode = Node.PROCESS_MODE_DISABLED
		tile.set_meta("composite_center", _snapshot_grid_cell(snapshot) == composite_center_global_region_cell)
		composite_tiles.append(tile)
	# A mixed footprint still needs one parent-owned surface.  Painting nine
	# complete Site scenes as independent children makes a Sand 2x2 block look
	# like a pasted rectangle and makes every shared edge a visible seam.  Build
	# one bounded raster from the already resolved native Site scenes, then leave
	# the children responsible only for mutable runtime overlays.
	if composite_background_kind.is_empty():
		_build_mixed_composite_background()
		for tile: SiteMap in composite_tiles:
			tile.composite_background_only = composite_background_texture != null
			tile.queue_redraw()
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func is_composite_view() -> bool:
	return composite_mode

func refresh_composite_center(p_runtime_snapshot: SiteRuntimeSnapshot) -> void:
	if not composite_mode or p_runtime_snapshot == null:
		return
	runtime_snapshot = p_runtime_snapshot
	site_texture = null
	for tile: SiteMap in composite_tiles:
		if bool(tile.get_meta("composite_center", false)):
			var saved_forest_clear_edge_mask: int = tile.forest_clear_edge_mask
			var saved_composite_river_enabled: bool = tile.composite_river_enabled
			tile.setup(p_runtime_snapshot, true)
			tile._apply_composite_surface_policy(p_runtime_snapshot.layout)
			tile.suppress_site_frame = true
			tile.composite_scene_river_axis = _composite_river_axis([p_runtime_snapshot])
			tile.composite_river_enabled = saved_composite_river_enabled
			tile.composite_background_only = not composite_background_kind.is_empty()
			tile.forest_clear_edge_mask = saved_forest_clear_edge_mask
			tile.queue_redraw()
			tile.show_debug_overlay = false
			tile.show_scale_guide = false
			if tile.camera != null:
				tile.camera.enabled = false
			tile.process_mode = Node.PROCESS_MODE_DISABLED
			break
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func _forest_clear_edge_mask_for(
		snapshot: SiteRuntimeSnapshot,
		p_snapshots: Array[SiteRuntimeSnapshot]
	) -> int:
	if snapshot == null or snapshot.layout == null \
		or snapshot.layout.terrain_type != TerrainType.FOREST:
		return 0
	var mask: int = 0
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for index: int in range(directions.size()):
		var neighbor_cell: Vector2i = _snapshot_grid_cell(snapshot) + directions[index]
		for neighbor: SiteRuntimeSnapshot in p_snapshots:
			if neighbor == null or _snapshot_grid_cell(neighbor) != neighbor_cell:
				continue
			if neighbor.layout == null or neighbor.layout.terrain_type != TerrainType.FOREST:
				mask |= 1 << index
			break
		# An absent neighbour is not evidence of a terrain change. Leave that edge
		# populated; only an explicitly resolved non-Forest neighbour clears it.
	return mask

func _composite_river_axis(p_snapshots: Array[SiteRuntimeSnapshot]) -> int:
	# A river crossing a shared Site edge must keep one cardinal axis across the
	# visible footprint.  Generated cell bases may have different fallback
	# orientations, so the composite chooses the first river's axis and applies
	# it to all river artwork without changing the underlying runtime layouts.
	for snapshot: SiteRuntimeSnapshot in p_snapshots:
		if snapshot == null or snapshot.layout == null:
			continue
		var layout: SiteLayoutDataType = snapshot.layout
		if not layout.river_connection_offsets.is_empty():
			return _river_axis(layout)
	return -1

func _composite_river_axis_for_cells(
		p_snapshots: Array[SiteRuntimeSnapshot],
		selected_cells: Dictionary
	) -> int:
	for snapshot: SiteRuntimeSnapshot in p_snapshots:
		if snapshot == null or snapshot.layout == null \
			or not selected_cells.has(_snapshot_grid_cell(snapshot)):
			continue
		if not snapshot.layout.river_connection_offsets.is_empty():
			return _river_axis(snapshot.layout)
	return -1

func _select_composite_river_cells(
		p_snapshots: Array[SiteRuntimeSnapshot],
		_p_center_region_cell: Vector2i
	) -> Dictionary:
	# A composite footprint can contain several independent macro-river hints.
	# Build cardinal connected components from the resolved Site edge contracts
	# and keep the center component when it has a river; otherwise keep the
	# largest component. Child Sites then render one channel instead of every
	# local hint, which is what previously produced parallel rivers in 3x3 art.
	var river_layouts: Dictionary = {}
	for snapshot: SiteRuntimeSnapshot in p_snapshots:
		if snapshot == null or snapshot.layout == null \
			or snapshot.layout.river_connection_offsets.is_empty():
			continue
		river_layouts[_snapshot_grid_cell(snapshot)] = snapshot.layout
	if river_layouts.is_empty():
		return {}
	var visited: Dictionary = {}
	var components: Array[Array] = []
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for cell_value: Variant in river_layouts.keys():
		var start_cell: Vector2i = cell_value as Vector2i
		if visited.has(start_cell):
			continue
		var queue: Array[Vector2i] = [start_cell]
		var component: Array[Vector2i] = []
		visited[start_cell] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			component.append(cell)
			var layout: SiteLayoutDataType = river_layouts[cell] as SiteLayoutDataType
			for direction: Vector2i in directions:
				var neighbor_cell: Vector2i = cell + direction
				if not river_layouts.has(neighbor_cell) or visited.has(neighbor_cell):
					continue
				var neighbor_layout: SiteLayoutDataType = river_layouts[neighbor_cell] as SiteLayoutDataType
				if not _river_has_offset(layout, direction) \
					or not _river_has_offset(neighbor_layout, -direction):
					continue
				visited[neighbor_cell] = true
				queue.append(neighbor_cell)
		components.append(component)
	var center_component: Array[Vector2i] = []
	for component: Array[Vector2i] in components:
		if component.has(composite_center_global_region_cell):
			center_component = component
			break
	if not center_component.is_empty():
		return _cells_to_dictionary(center_component)
	var best_component: Array[Vector2i] = []
	for component: Array[Vector2i] in components:
		if component.size() > best_component.size():
			best_component = component
			continue
		if component.size() != best_component.size():
			continue
		if _component_distance_to_center(component, composite_center_global_region_cell) \
			< _component_distance_to_center(best_component, composite_center_global_region_cell):
			best_component = component
	return _cells_to_dictionary(best_component)

func _cells_to_dictionary(cells: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for cell: Vector2i in cells:
		result[cell] = true
	return result

func _component_distance_to_center(
		component: Array[Vector2i],
		center: Vector2i
	) -> int:
	var result: int = 1_000_000
	for cell: Vector2i in component:
		result = mini(result, absi(cell.x - center.x) + absi(cell.y - center.y))
	return result

func _river_has_offset(layout: SiteLayoutDataType, offset: Vector2i) -> bool:
	if layout == null:
		return false
	return offset in layout.river_connection_offsets

func _clear_composite_tiles() -> void:
	for tile: SiteMap in composite_tiles:
		if is_instance_valid(tile):
			remove_child(tile)
			tile.free()
	composite_tiles.clear()
	composite_river_cells.clear()
	composite_background_texture = null
	composite_background_kind = ""
	composite_center_global_region_cell = SiteLayoutDataType.INVALID_CELL

func _snapshot_grid_cell(snapshot: SiteRuntimeSnapshot) -> Vector2i:
	if snapshot == null:
		return SiteLayoutDataType.INVALID_CELL
	if snapshot.global_region_cell != SiteLayoutDataType.INVALID_CELL:
		return snapshot.global_region_cell
	return WorldCoordinates.world_region_to_global_region_cell(
		snapshot.parent_world_cell,
		snapshot.parent_region_cell
	)

func _build_mixed_composite_background() -> void:
	if composite_tiles.size() != 9 or OS.has_feature("headless"):
		return
	var composite: Image = Image.create(
		COMPOSITE_ART_SIZE_PIXELS,
		COMPOSITE_ART_SIZE_PIXELS,
		false,
		Image.FORMAT_RGBA8
	)
	composite.fill(Color("211d2b"))
	var tile_images: Dictionary = {}
	var tile_terrains: Dictionary = {}
	for tile: SiteMap in composite_tiles:
		if tile == null or tile.runtime_snapshot == null:
			continue
		var tile_image: Image = _composite_tile_image(tile)
		if tile_image == null or tile_image.is_empty():
			continue
		var tile_key: Vector2i = _snapshot_grid_cell(tile.runtime_snapshot) - composite_center_global_region_cell
		tile_images[tile_key] = tile_image
		tile_terrains[tile_key] = tile.runtime_snapshot.layout.terrain_type
		var offset: Vector2i = tile_key + Vector2i.ONE
		composite.blit_rect(
			tile_image,
			Rect2i(Vector2i.ZERO, Vector2i(COMPOSITE_ART_TILE_PIXELS, COMPOSITE_ART_TILE_PIXELS)),
			offset * COMPOSITE_ART_TILE_PIXELS
		)
	if tile_images.size() != 9:
		return
	_draw_mixed_vertical_edges(composite, tile_terrains)
	_draw_mixed_horizontal_edges(composite, tile_terrains)
	composite_background_texture = ImageTexture.create_from_image(composite)
	composite_background_kind = "generated_mixed_v1"

func _composite_tile_image(tile: SiteMap) -> Image:
	# Composite ground is always the native Site surface.  A generated height
	# layer is alpha-blended over that surface so mountain ledges remain visible
	# without replacing the whole tile with a scene painting.  Explicit POI art
	# is deliberately excluded from a 3x3 footprint by the surface policy.
	var layout: SiteLayoutDataType = tile.runtime_snapshot.layout
	if not tile.composite_river_enabled:
		# The generated native surface already contains the local river hint. In a
		# stitched footprint that hint may belong to a parallel channel rejected by
		# the composite connection resolver; remove it from the raster as well as
		# suppressing the child overlay, otherwise the hidden river remains visible
		# as a blue strip in the parent-owned background.
		layout = _layout_without_composite_river(layout)
	var source: Image = MapArtCatalogType.build_layout_composite_image(
		layout,
		COMPOSITE_ART_TILE_PIXELS
	)
	var scene_kind: String = MapArtCatalogType.site_scene_kind(tile.runtime_snapshot.layout)
	# River artwork must use the single axis selected for the whole footprint;
	# otherwise two adjacent River Sites can each be internally correct while
	# their water turns a false corner at the shared edge.
	if source == null and scene_kind.begins_with("strategic_river") and composite_scene_river_axis >= 0:
		var river_kind: String = "strategic_river_meadow_v1" \
			if composite_scene_river_axis == 1 \
			else "strategic_river_meadow_vertical_v1"
		var river_texture: Texture2D = MapArtCatalogType.site_scene_texture_kind(river_kind)
		source = river_texture.get_image() if river_texture != null else null
	if source == null or source.is_empty():
		return null
	source = source.duplicate()
	source.convert(Image.FORMAT_RGBA8)
	if _layout_needs_height_texture(layout):
		var height_image: Image = _build_height_image(
			layout,
			COMPOSITE_ART_TILE_PIXELS,
			source
		)
		if height_image != null and not height_image.is_empty():
			source.blend_rect(
				height_image,
				Rect2i(Vector2i.ZERO, height_image.get_size()),
				Vector2i.ZERO
			)
	_apply_composite_scene_variant(
		source,
		scene_kind,
		posmod(int(tile.runtime_snapshot.layout.details.get("site_visual_variant", 0)), 3)
	)
	return source

func _layout_without_composite_river(layout: SiteLayoutDataType) -> SiteLayoutDataType:
	var result: SiteLayoutDataType = layout.copy()
	# Use a cache-distinct identity because MapArtCatalog caches deterministic
	# rasters by site_id; this presentation override must not reuse the original
	# river-bearing image.
	result.site_id = "%s|composite_no_river" % layout.site_id
	result.river_connection_offsets.clear()
	var replacement_surface: int = SiteContentTypes.NativeSurface.ROCK \
		if result.terrain_type == TerrainType.MOUNTAIN \
		else SiteContentTypes.NativeSurface.DIRT
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell := Vector2i(x, y)
			if result.native_surface_at(cell) != SiteContentTypes.NativeSurface.RIVER_WATER:
				continue
			result.native_surface_cells[y * SiteLayoutDataType.GRID_SIZE.x + x] = replacement_surface
	return result

func _apply_composite_scene_variant(source: Image, scene_kind: String, variant: int) -> void:
	if scene_kind.is_empty():
		# Native terrain samples already use the global Region texture phase. A
		# per-tile mirror or palette lift would break that shared edge again, so
		# variation comes from deterministic resources/decorations instead.
		return
	# A mixed composite cannot show the same Sand/Mountain/Snow painting nine
	# times. Keep river scenes on the shared axis, while preserving one authored
	# orientation for all trees, rocks and stairs. Variant 2 may still apply a
	# small palette lift; no horizontal or vertical flip is allowed.
	if scene_kind.begins_with("strategic_river"):
		return
	if variant != 2:
		return
	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			var color: Color = source.get_pixel(x, y)
			color.r = clampf(color.r * 1.045, 0.0, 1.0)
			color.g = clampf(color.g * 1.035, 0.0, 1.0)
			color.b = clampf(color.b * 1.015, 0.0, 1.0)
			source.set_pixel(x, y, color)

func _draw_mixed_vertical_edges(composite: Image, tile_terrains: Dictionary) -> void:
	for row: int in range(3):
		for column: int in range(2):
			var left_key: Vector2i = Vector2i(column - 1, row - 1)
			var right_key: Vector2i = Vector2i(column, row - 1)
			if tile_terrains.get(left_key, -1) == tile_terrains.get(right_key, -2):
				continue
			var seam_x: int = (column + 1) * COMPOSITE_ART_TILE_PIXELS
			var left_type: int = int(tile_terrains.get(left_key, TerrainType.PLAINS))
			var right_type: int = int(tile_terrains.get(right_key, TerrainType.PLAINS))
			for local_y: int in range(COMPOSITE_ART_TILE_PIXELS):
				var boundary_offset: int = _mixed_edge_offset(local_y, row, column, false)
				var boundary_x: int = seam_x + boundary_offset
				for step: int in range(-COMPOSITE_EDGE_BAND_PIXELS, COMPOSITE_EDGE_BAND_PIXELS + 1):
					var x: int = boundary_x + step
					if x < 0 or x >= composite.get_width():
						continue
					composite.set_pixel(
						x,
						(row * COMPOSITE_ART_TILE_PIXELS) + local_y,
						_mixed_edge_color(left_type, right_type, step)
					)

func _draw_mixed_horizontal_edges(composite: Image, tile_terrains: Dictionary) -> void:
	for row: int in range(2):
		for column: int in range(3):
			var top_key: Vector2i = Vector2i(column - 1, row - 1)
			var bottom_key: Vector2i = Vector2i(column - 1, row)
			if tile_terrains.get(top_key, -1) == tile_terrains.get(bottom_key, -2):
				continue
			var seam_y: int = (row + 1) * COMPOSITE_ART_TILE_PIXELS
			var top_type: int = int(tile_terrains.get(top_key, TerrainType.PLAINS))
			var bottom_type: int = int(tile_terrains.get(bottom_key, TerrainType.PLAINS))
			for local_x: int in range(COMPOSITE_ART_TILE_PIXELS):
				var boundary_offset: int = _mixed_edge_offset(local_x, row, column, true)
				var boundary_y: int = seam_y + boundary_offset
				for step: int in range(-COMPOSITE_EDGE_BAND_PIXELS, COMPOSITE_EDGE_BAND_PIXELS + 1):
					var y: int = boundary_y + step
					if y < 0 or y >= composite.get_height():
						continue
					composite.set_pixel(
						(column * COMPOSITE_ART_TILE_PIXELS) + local_x,
						y,
						_mixed_edge_color(top_type, bottom_type, step)
					)

func _mixed_edge_offset(along: int, row: int, column: int, horizontal: bool) -> int:
	# One shared profile is used by both sides of each join. This produces a
	# deliberate, drawable boundary instead of two independent blurred edges.
	var phase: float = float(
		composite_center_region_cell.x * (17 if horizontal else 13)
		+ composite_center_region_cell.y * (5 if horizontal else 7)
		+ row * (23 if horizontal else 19)
		+ column * (13 if horizontal else 11)
	)
	var primary: float = sin(float(along) * (0.041 if horizontal else 0.045) + phase) * 8.0
	var secondary: float = sin(float(along) * (0.087 if horizontal else 0.091) + phase * (0.59 if horizontal else 0.63)) * 4.0
	return roundi(primary + secondary)

func _mixed_edge_color(first_type: int, second_type: int, step: int) -> Color:
	var first: Color = MapArtCatalogType.terrain_color(first_type)
	var second: Color = MapArtCatalogType.terrain_color(second_type)
	var join: Color = first.lerp(second, 0.5).darkened(0.10)
	# A thin dark soil/stone line makes the join legible without smearing either
	# terrain. The outer pixels are keyed to their own terrain palette, so the
	# boundary remains stable if one side is sand, snow or mountain.
	if step < 0:
		return first.darkened(0.16 if step == -1 else 0.08)
	if step > 0:
		return second.darkened(0.16 if step == 1 else 0.08)
	return join

func _composite_background_kind_for(_p_snapshots: Array[SiteRuntimeSnapshot]) -> String:
	# Region cells are assembled from native surfaces plus data-backed overlays.
	# No single authored painting may own a footprint: it would reintroduce
	# baked roads/highlands and would hide the actual terrain boundary contract.
	# Returning an empty kind deliberately routes every 3x3 view through the
	# shared-edge stitcher below.  The method remains for callers that inspect the
	# old presentation policy.
	return ""

func _can_use_coherent_composite_background(p_snapshots: Array[SiteRuntimeSnapshot]) -> bool:
	# Retain the boolean helper for older presentation checks while keeping the
	# selected art profile in one canonical resolver.
	return not _composite_background_kind_for(p_snapshots).is_empty()

func get_debug_state() -> Dictionary:
	if runtime_snapshot == null:
		return {"layer": "SITE MAP", "instruction": "Site snapshot unavailable"}
	var region_label: String = "World %s" % _format_cell(runtime_snapshot.parent_world_cell)
	if not runtime_snapshot.parent_region_name.is_empty():
		region_label = "%s (%s)" % [
			runtime_snapshot.parent_region_name,
			runtime_snapshot.parent_region_id,
		]
	return {
		"layer": "SITE MAP",
		"site_view": "3x3 SITE COMPOSITE" if composite_mode else "SINGLE SITE",
		"site_composite_tiles": composite_tiles.size() if composite_mode else 1,
		"site_composite_background": composite_background_kind if composite_mode else "",
		"current_region": region_label,
		"world_seed": runtime_snapshot.world_seed,
		"world_time": _format_world_time(runtime_snapshot.world_time_seconds),
		"party_id": runtime_snapshot.party_id,
		"party_position": "Site %s / Global %s" % [
			_format_cell(runtime_snapshot.party_site_local_cell),
			_format_cell(runtime_snapshot.party_global_region_cell),
		] if SiteLayoutDataType.is_valid_cell(runtime_snapshot.party_site_local_cell) \
			else "Global %s" % _format_cell(runtime_snapshot.party_global_region_cell),
		"party_state": "At Site" if runtime_snapshot.party_at_site else "Not required",
		"world_cell": _format_cell(runtime_snapshot.parent_world_cell),
		"hovered_region_cell": "??",
		"selected_region_cell": _format_cell(runtime_snapshot.parent_region_cell),
		"global_region_cell": _format_cell(runtime_snapshot.global_region_cell),
		"global_meter_position": _format_meters(runtime_snapshot.entrance_global_meters),
		"terrain_type": TerrainType.to_display_name(runtime_snapshot.source_terrain_type),
		"site_landform": SiteLayoutDataType.landform_name(runtime_snapshot.site_landform),
		"travel_exit_mask": runtime_snapshot.travel_exit_mask,
		"elevation": "%.2f" % runtime_snapshot.source_elevation,
		"moisture": "%.2f" % runtime_snapshot.source_moisture,
		"river_mask": "Yes" if runtime_snapshot.source_river_nearby else "No",
		"river_strength": "nearby" if runtime_snapshot.source_river_nearby else "0.00",
		"poi_id": runtime_snapshot.source_poi_id if not runtime_snapshot.source_poi_id.is_empty() else "No POI (strategic tile)",
		"site_id": runtime_snapshot.site_id,
		"site_seed": runtime_snapshot.site_seed,
		"site_base_version": runtime_snapshot.base_generation_version,
		"site_entrance_local_meters": _format_meters(runtime_snapshot.entrance_local_meters),
		"site_entrance_global_meters": _format_meters(runtime_snapshot.entrance_global_meters),
		"site_layout_version": runtime_snapshot.layout.generation_version if runtime_snapshot.layout != null else 0,
		"site_layout_bounds": str(runtime_snapshot.layout.bounds_meters) if runtime_snapshot.layout != null else "unavailable",
		"site_layout_path_points": runtime_snapshot.layout.primary_path_meters.size() if runtime_snapshot.layout != null else 0,
		"site_layout_landmarks": runtime_snapshot.layout.landmark_points_meters.size() if runtime_snapshot.layout != null else 0,
		"site_revision": runtime_snapshot.revision,
		"site_runtime_allocated": runtime_snapshot.runtime_allocated,
		"site_test_flag": runtime_snapshot.architecture_test_flag,
		"site_feature_ids": _feature_ids(),
		"poi_type": WorldPOIType.to_display_name(runtime_snapshot.site_type) if not runtime_snapshot.source_poi_id.is_empty() else "STRATEGIC TILE",
		"poi_name": runtime_snapshot.site_name,
		"poi_candidate_cell": _format_cell(runtime_snapshot.source_candidate_cell),
		"poi_priority": "%.3f" % runtime_snapshot.source_priority,
		"poi_river_nearby": "Yes" if runtime_snapshot.source_river_nearby else "No",
		"site": "%s (%s)" % [
			runtime_snapshot.site_name,
			WorldPOIType.to_display_name(runtime_snapshot.site_type) if not runtime_snapshot.source_poi_id.is_empty() else "STRATEGIC TILE",
		],
		"debug_view": "DATA + SCALE GUIDE" if show_debug_overlay and show_scale_guide \
			else "DATA OVERLAY" if show_debug_overlay \
			else "SCALE GUIDE" if show_scale_guide else "FORMAL ART",
		"site_visual_scale": "%dm tile / %dcm / %.2fm Site / %.2f px per metre" % [
			int(MapArtCatalogType.SITE_TILE_SIZE_METERS),
			MapArtCatalogType.SITE_TILE_SIZE_CENTIMETERS,
			MapArtCatalogType.SITE_SIZE_METERS,
			MapArtCatalogType.SITE_PIXELS_PER_METER,
		],
		"site_detail_tile_pixels": MapArtCatalogType.SITE_DETAIL_TILE_PIXELS,
		"site_height_levels": _height_level_range(),
		"site_transitions": runtime_snapshot.layout.transitions.size() if runtime_snapshot.layout != null else 0,
		"site_scene_template": str(runtime_snapshot.layout.details.get("scene_template", "TERRAIN")) if runtime_snapshot.layout != null else "unavailable",
		"site_visual_archetype": str(runtime_snapshot.layout.details.get("site_visual_archetype", "curated")) if runtime_snapshot.layout != null else "unavailable",
		"site_visual_variant": int(runtime_snapshot.layout.details.get("site_visual_variant", 0)) if runtime_snapshot.layout != null else 0,
		"site_person_reference": "%.2fm x %.2fm display guide" % [
			MapArtCatalogType.PERSON_REFERENCE_SIZE_METERS.x,
			MapArtCatalogType.PERSON_REFERENCE_SIZE_METERS.y,
		],
		"site_large_poi_policy": "DEFERRED: compose POI from multiple 2m tiles",
		"site_zoom": "%.2fx" % camera.zoom.x if camera != null else "unavailable",
		"instruction": "WASD / Arrows: Move   Wheel: Zoom   F1: Toggle Data Overlay   F2: Toggle 2m Scale Guide   ESC / T: Return to Region Map"
	}

func _feature_ids() -> Array[String]:
	var ids: Array[String] = []
	for feature: SiteFeatureState in runtime_snapshot.added_features:
		if feature.enabled:
			ids.append(feature.feature_id)
	return ids

func _draw() -> void:
	if composite_mode:
		var footprint_size: float = COMPOSITE_TILE_SIZE_METERS * 3.0
		draw_rect(
			Rect2(Vector2.ONE * -footprint_size * 0.5, Vector2.ONE * footprint_size).grow(10.0),
			Color("211d2b")
		)
		# Fill the shared-edge underlay before child Site paintings draw.  This
		# prevents a dark gutter if an authored scene intentionally leaves a thin
		# edge margin; the adjacent native terrain still reads continuously.
		for tile: SiteMap in composite_tiles:
			if tile == null or tile.runtime_snapshot == null:
				continue
			var tile_origin: Vector2 = tile.position - Vector2.ONE * COMPOSITE_TILE_SIZE_METERS * 0.5
			var tile_color: Color = TerrainType.to_color(tile.runtime_snapshot.source_terrain_type).darkened(0.18)
			draw_rect(
				Rect2(tile_origin, Vector2.ONE * COMPOSITE_TILE_SIZE_METERS),
				tile_color,
				true
			)
		if composite_background_texture != null:
			draw_texture_rect(
				composite_background_texture,
				Rect2(Vector2.ONE * -footprint_size * 0.5, Vector2.ONE * footprint_size),
				false
			)
		return
	if runtime_snapshot == null or runtime_snapshot.layout == null \
		or not runtime_snapshot.layout.is_valid():
		return
	var layout: SiteLayoutDataType = runtime_snapshot.layout
	var bounds: Rect2 = Rect2(Vector2(layout.bounds_meters.position), Vector2(layout.bounds_meters.size))
	if not suppress_site_frame:
		draw_rect(bounds.grow(8.0), Color("211d2b"))
	if composite_background_only:
		_draw_composite_runtime_overlays(layout)
		return
	if scene_texture != null:
		_draw_scene_background(layout, bounds)
	elif site_texture != null:
		draw_texture_rect(site_texture, bounds, false)
	else:
		draw_rect(bounds, TerrainType.to_color(runtime_snapshot.source_terrain_type).darkened(0.18))
	_draw_height_surfaces(layout)
	_draw_site_art(layout)
	if show_debug_overlay:
		_draw_debug_overlay(layout)
	if show_scale_guide:
		_draw_scale_guide(layout)

func _draw_composite_runtime_overlays(layout: SiteLayoutDataType) -> void:
	# The stitched native surface owns the continuous ground and generated height
	# layer. Roads and rivers are not part of that floor: they are artificial or
	# connection facilities and are drawn only when the layout contains the
	# corresponding data.
	if not layout.road_connection_offsets.is_empty():
		_draw_cell_base_corridors(layout)
	var has_river: bool = composite_river_enabled \
		and not layout.river_connection_offsets.is_empty()
	if has_river and layout.terrain_type not in [TerrainType.WATER, TerrainType.OCEAN]:
		var river_axis: int = _river_axis(layout)
		var river_kind: String = "site_river_horizontal" if river_axis == 1 else "site_river_vertical"
		_draw_river_band(layout, MapArtCatalogType.site_texture(river_kind), river_kind)
	_draw_generated_resources(layout)
	_draw_generated_facilities(layout)
	_draw_tile_landmarks(layout)
	if SiteLayoutDataType.is_valid_cell(runtime_snapshot.party_site_local_cell):
		var party_cell: Vector2i = runtime_snapshot.party_site_local_cell
		_draw_party_flag(_height_adjusted_point(layout, layout.cell_center_meters(party_cell), layout.elevation_level_at(party_cell)))

func _draw_scene_background(layout: SiteLayoutDataType, bounds: Rect2) -> void:
	var scene_kind: String = MapArtCatalogType.site_scene_kind(layout)
	if not MapArtCatalogType.is_strategic_scene_kind(scene_kind):
		draw_texture_rect(scene_texture, bounds, false)
		return
	var background_texture: Texture2D = scene_texture
	if composite_scene_river_axis >= 0 and scene_kind.begins_with("strategic_river"):
		var stitched_kind: String = "strategic_river_meadow_v1" \
			if composite_scene_river_axis == 1 \
			else "strategic_river_meadow_vertical_v1"
		background_texture = MapArtCatalogType.site_scene_texture_kind(stitched_kind)
	if background_texture == null:
		return
	# Keep every authored composition in its canonical orientation.  Mirroring a
	# whole Site made trees and stairs face the opposite way from their neighbours
	# even though the underlying terrain was continuous.
	draw_set_transform(bounds.get_center(), 0.0, Vector2.ONE)
	draw_texture_rect(background_texture, Rect2(-bounds.size * 0.5, bounds.size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_site_art(layout: SiteLayoutDataType) -> void:
	if scene_texture != null:
		var scene_kind: String = MapArtCatalogType.site_scene_kind(layout)
		if MapArtCatalogType.is_strategic_scene_kind(scene_kind):
			_draw_strategic_scene_overlays(layout)
		else:
			_draw_curated_scene_overlays(layout)
		return
	if layout.site_landform == SiteLayoutDataType.Landform.MOUNTAIN_PASS:
		_draw_mountain_pass_landform(layout)
		_draw_mountain_pass_corridors(layout)
	else:
		_draw_terrain_composition(layout)
		# Use the authored shoreline sprite for every non-curated river Site. It
		# keeps water organic and readable without turning a nearby river into a
		# bridge; bridge decks still come only from the crossing scene/transition.
		if layout.terrain_type == TerrainType.WATER \
			or not layout.river_connection_offsets.is_empty():
			var river_kind: String = "site_river_horizontal" if _river_axis(layout) == 1 else "river_straight"
			_draw_river_band(layout, MapArtCatalogType.site_texture(river_kind), river_kind)
	if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI \
		and layout.site_landform != SiteLayoutDataType.Landform.MOUNTAIN_PASS:
		var elevated_path: Array = []
		for path_point: Vector2i in layout.primary_path_meters:
			elevated_path.append(
			Vector2(path_point) if layout.site_landform == SiteLayoutDataType.Landform.MOUNTAIN_PASS \
			else _height_adjusted_meters(layout, Vector2(path_point))
		)
		_draw_polyline_texture(
			elevated_path,
		null,
			MapArtCatalogType.site_art_width_meters("path_straight", 3.0)
		)
	elif layout.layout_kind != SiteLayoutDataType.LayoutKind.POI:
		_draw_cell_base_corridors(layout)
	if layout.site_landform != SiteLayoutDataType.Landform.MOUNTAIN_PASS:
		_draw_height_transitions(layout)
	else:
		_draw_ai_stair_overlays(layout)
	if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI:
		# Large POI art is deliberately deferred. Keep only a 2m hub anchor until
		# a multi-tile footprint and connection contract are available.
		_draw_deferred_poi_anchor(
			Vector2(layout.hub_local_meters) if layout.site_landform == SiteLayoutDataType.Landform.MOUNTAIN_PASS \
			else _height_adjusted_meters(layout, Vector2(layout.hub_local_meters))
		)
		if layout.site_landform != SiteLayoutDataType.Landform.MOUNTAIN_PASS:
			var entrance: Texture2D = MapArtCatalogType.site_texture("entrance_gate")
			_draw_centered_texture(
				entrance,
				_height_adjusted_meters(layout, Vector2(layout.entrance_local_meters)),
				MapArtCatalogType.site_art_size_meters("entrance_gate")
			)
		if layout.site_landform != SiteLayoutDataType.Landform.MOUNTAIN_PASS:
			for index: int in range(layout.landmark_points_meters.size()):
				var landmark: Texture2D = MapArtCatalogType.site_texture("stone_marker")
				_draw_centered_texture(
					landmark,
					_height_adjusted_meters(layout, Vector2(layout.landmark_points_meters[index])),
					MapArtCatalogType.site_art_size_meters("stone_marker")
				)
	_draw_generated_resources(layout)
	_draw_generated_facilities(layout)
	_draw_tile_landmarks(layout)
	if SiteLayoutDataType.is_valid_cell(runtime_snapshot.party_site_local_cell):
		var party_cell: Vector2i = runtime_snapshot.party_site_local_cell
		_draw_party_flag(_height_adjusted_point(layout, layout.cell_center_meters(party_cell), layout.elevation_level_at(party_cell)))

func _draw_curated_scene_overlays(layout: SiteLayoutDataType) -> void:
	# The painted scene already contains its path, stairs, cliffs and large
	# structures. Keep runtime resource truth visible as small, anchored markers
	# instead of re-stamping the old oversized sprites over the painting.
	var grouped: Dictionary = {}
	for placement: Dictionary in layout.resource_placements:
		var type_key: int = int(placement.get("type", -1))
		if not grouped.has(type_key):
			grouped[type_key] = placement
	for type_key: int in grouped.keys():
		var placement: Dictionary = grouped[type_key] as Dictionary
		var origin_value: Variant = placement.get("origin", SiteLayoutDataType.INVALID_CELL)
		var kind: String = MapArtCatalogType.resource_art_kind(type_key)
		var texture: Texture2D = MapArtCatalogType.site_texture(kind)
		if not origin_value is Vector2i or kind.is_empty() or texture == null:
			continue
		var origin: Vector2i = origin_value as Vector2i
		var point: Vector2 = _height_adjusted_point(
			layout,
			layout.cell_center_meters(origin),
			layout.elevation_level_at(origin)
		)
		# The authored scene already contains the landform and resource groups;
		# keep the runtime marker tiny and sprite-shaped. Coloured circles read as
		# debug pins and destroy the scene composition at full-map zoom.
		_draw_centered_texture(texture, point + Vector2(0.0, -0.8), MapArtCatalogType.site_art_size_meters(kind) * 0.22)

func _draw_strategic_scene_overlays(layout: SiteLayoutDataType) -> void:
	# The generated background supplies the painted ground, foliage and the
	# cardinal trail composition. Keep canonical runtime data visible without
	# stamping the old flat texture back over the scene.
	var scene_kind: String = MapArtCatalogType.site_scene_kind(layout)
	var has_river: bool = not layout.river_connection_offsets.is_empty()
	# A mixed-terrain composite cannot use the green river painting for a sand or
	# snow Site. Keep the native terrain scene and draw the connection as the
	# shared cardinal overlay instead; bridge facilities are drawn below from the
	# generated Site layout.
	if has_river and not scene_kind.begins_with("strategic_river"):
		var river_axis: int = _river_axis(layout)
		var river_kind: String = "site_river_horizontal" if river_axis == 1 else "site_river_vertical"
		_draw_river_band(layout, MapArtCatalogType.site_texture(river_kind), river_kind)
	if not layout.road_connection_offsets.is_empty():
		_draw_cell_base_corridors(layout)
	_draw_curated_scene_overlays(layout)
	_draw_generated_facilities(layout)
	_draw_tile_landmarks(layout)

func _draw_terrain_composition(layout: SiteLayoutDataType) -> void:
	# Composition is made from recognisable landform/resource silhouettes, not
	# translucent geometric masks.  The anchors are deterministic and stay near
	# the scene edge so the central path, stairs and POI remain playable/readable.
	var anchors: Array[Vector2] = []
	var kinds: Array[String] = []
	var terrain_scale: float = 1.0
	match layout.terrain_type:
		TerrainType.PLAINS:
			anchors = [Vector2(-34.0, -28.0), Vector2(35.0, -24.0), Vector2(-36.0, 28.0), Vector2(35.0, 30.0), Vector2(-22.0, 37.0)]
			# Trees are a wood-resource overlay, not part of the native floor.
			# Keep the meadow silhouette varied with low vegetation and outcrops.
			kinds = ["dry_bush", "dry_bush", "rock_cluster", "dry_bush", "dry_bush"]
			terrain_scale = 1.18
		TerrainType.FOREST:
			anchors = [Vector2(-34.0, -30.0), Vector2(34.0, -28.0), Vector2(-36.0, 30.0)]
			# A Forest terrain is still only native ground.  Harvestable trees are
			# drawn below by _draw_generated_resources from RESOURCE_FOREST data.
			kinds = ["dry_bush", "dry_bush", "rock_cluster"]
			terrain_scale = 0.90
		TerrainType.MOUNTAIN:
			anchors = [Vector2(-32.0, -28.0), Vector2(32.0, -26.0), Vector2(-34.0, 29.0), Vector2(31.0, 31.0), Vector2(0.0, 34.0)]
			kinds = ["rock_cluster", "rock_cluster", "rock_cluster", "rock_cluster", "rock_cluster"]
			terrain_scale = 1.12
		TerrainType.SAND:
			anchors = [Vector2(-33.0, -28.0), Vector2(31.0, -23.0), Vector2(-30.0, 30.0), Vector2(30.0, 31.0)]
			kinds = ["sand_dune", "sand_dune", "dry_bush", "sand_dune"]
			terrain_scale = 1.25
		TerrainType.SNOW:
			anchors = [Vector2(-32.0, -28.0), Vector2(33.0, -25.0), Vector2(-34.0, 29.0), Vector2(31.0, 30.0)]
			kinds = ["snowdrift", "snowdrift", "rock_cluster", "snowdrift"]
			terrain_scale = 1.20
		TerrainType.SWAMP:
			anchors = [Vector2(-32.0, -27.0), Vector2(31.0, -24.0), Vector2(-34.0, 29.0), Vector2(30.0, 31.0)]
			kinds = ["swamp_reeds", "swamp_reeds", "deadwood", "swamp_reeds"]
			terrain_scale = 1.15
		_:
			return
	var visual_variant: int = posmod(int(layout.details.get("site_visual_variant", layout.site_seed)), 3)
	var bounds: Rect2 = Rect2(Vector2(layout.bounds_meters.position), Vector2(layout.bounds_meters.size))
	for index: int in range(anchors.size()):
		var kind: String = kinds[index] if index < kinds.size() else ""
		var texture: Texture2D = MapArtCatalogType.site_texture(kind)
		if kind.is_empty() or texture == null:
			continue
		var jitter: Vector2 = Vector2(
			float(DeterministicHash.int_range(layout.site_seed, layout.global_region_cell, 49_200 + index * 2, -3, 3)),
			float(DeterministicHash.int_range(layout.site_seed, layout.global_region_cell, 49_201 + index * 2, -3, 3))
		)
		var anchor: Vector2 = anchors[index]
		# Keep the same terrain language while changing the deterministic clearing
		# layout per Site.  This prevents every forest/plains tile from reading as
		# one copied screenshot, without introducing a second map or random state.
		match visual_variant:
			1:
				anchor = Vector2(-anchor.y, anchor.x)
			2:
				anchor = Vector2(anchor.y, -anchor.x)
		var point: Vector2 = Vector2(bounds.get_center()) + anchor + jitter
		var size: Vector2 = MapArtCatalogType.site_art_size_meters(kind) * terrain_scale
		point.x = clampf(point.x, bounds.position.x + size.x * 0.55, bounds.end.x - size.x * 0.55)
		point.y = clampf(point.y, bounds.position.y + size.y * 0.55, bounds.end.y - size.y * 0.55)
		_draw_centered_texture(texture, _height_adjusted_meters(layout, point), size)

func _draw_mountain_pass_landform(layout: SiteLayoutDataType) -> void:
	var center: Vector2 = Vector2(layout.bounds_meters.get_center())
	var exits: Array[Vector2i] = SiteLayoutDataType.exit_offsets(layout.travel_exit_mask)
	var horizontal: bool = exits.size() >= 2 and exits[0].x != 0
	# The authored cliff sprite is a complete gate scene (two faces, floor and
	# vegetation).  Keep it at a readable scale and let the continuous trail pass
	# through it; broad procedural rectangles made the previous result look like
	# a UI panel laid over the mountain texture.
	var cliff: Texture2D = MapArtCatalogType.site_texture("mountain_pass_cliff")
	if cliff != null:
		var art_size: Vector2 = Vector2(38.0, 38.0)
		draw_set_transform(center, PI * 0.5 if horizontal else 0.0, Vector2.ONE)
		_draw_centered_texture(cliff, Vector2.ZERO, art_size)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _height_level_range() -> String:
	if runtime_snapshot == null or runtime_snapshot.layout == null or not runtime_snapshot.layout.has_height_base():
		return "0"
	var minimum: int = 999
	var maximum: int = -999
	for level: int in runtime_snapshot.layout.elevation_levels:
		minimum = mini(minimum, level)
		maximum = maxi(maximum, level)
	return "%d..%d" % [minimum, maximum]

func _height_adjusted_point(_layout: SiteLayoutDataType, point: Vector2, level: int) -> Vector2:
	return point + Vector2(0.0, -float(level) * MapArtCatalogType.SITE_HEIGHT_OFFSET_METERS)

func _height_adjusted_meters(layout: SiteLayoutDataType, point: Vector2) -> Vector2:
	if not layout.has_height_base():
		return point
	var local: Vector2 = (point - Vector2(layout.bounds_meters.position)) \
		/ float(SiteLayoutDataType.CELL_SIZE_METERS)
	var cell: Vector2i = Vector2i(
		clampi(floori(local.x), 0, SiteLayoutDataType.GRID_SIZE.x - 1),
		clampi(floori(local.y), 0, SiteLayoutDataType.GRID_SIZE.y - 1)
	)
	return _height_adjusted_point(layout, point, layout.elevation_level_at(cell))

func _draw_height_surfaces(layout: SiteLayoutDataType) -> void:
	if height_texture == null or not layout.has_height_base():
		return
	var bounds: Rect2 = Rect2(Vector2(layout.bounds_meters.position), Vector2(layout.bounds_meters.size))
	draw_texture_rect(height_texture, bounds, false)

func _build_height_texture(layout: SiteLayoutDataType) -> Texture2D:
	var image: Image = _build_height_image(layout)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _build_height_image(
		layout: SiteLayoutDataType,
		output_pixel_size: int = -1,
		base_image_override: Image = null
	) -> Image:
	# Headless contract tests do not have a GPU-backed CanvasItem. Keep their
	# data/path assertions valid without creating a dummy ImageTexture; the
	# non-headless preview gate is the authoritative visual check for this layer.
	if OS.has_feature("headless") or layout == null or not layout.has_height_base():
		return null
	var pixel_size: int = output_pixel_size if output_pixel_size > 0 \
		else MapArtCatalogType.SITE_DETAIL_SURFACE_PIXELS
	var pixels_per_meter: float = float(pixel_size) / MapArtCatalogType.SITE_SIZE_METERS
	var tile_pixels: int = maxi(1, roundi(float(SiteLayoutDataType.CELL_SIZE_METERS) * pixels_per_meter))
	var level_pixels: int = maxi(1, roundi(MapArtCatalogType.SITE_HEIGHT_OFFSET_METERS * pixels_per_meter))
	var base_image: Image = base_image_override
	if base_image == null and site_texture != null:
		base_image = site_texture.get_image()
	if base_image == null and output_pixel_size > 0:
		base_image = MapArtCatalogType.build_layout_composite_image(layout, pixel_size)
	var image: Image = Image.create(pixel_size, pixel_size, false, Image.FORMAT_RGBA8)
	# Draw vertical faces first, so the opaque top surfaces sit on top of them.
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var level: int = layout.elevation_level_at(cell)
			if level <= 0:
				continue
			var top_y: int = y * tile_pixels - level * level_pixels
			var neighbor_levels: Array[int] = [
				layout.elevation_level_at(cell + Vector2i.UP),
				layout.elevation_level_at(cell + Vector2i.RIGHT),
				layout.elevation_level_at(cell + Vector2i.DOWN),
				layout.elevation_level_at(cell + Vector2i.LEFT),
			]
			# Fill only the exposed drop between the raised top and its neighbour.
			var face_color: Color = _height_face_color(layout, cell, level)
			if neighbor_levels[0] < level:
				_image_fill_safe(image, Rect2i(x * tile_pixels, top_y, tile_pixels, (level - neighbor_levels[0]) * level_pixels), face_color)
				_image_draw_segment(image, Vector2(x * tile_pixels, top_y), Vector2((x + 1) * tile_pixels, top_y), 1.4, Color("a69b83", 0.62))
				_image_draw_segment(image, Vector2(x * tile_pixels, top_y + (level - neighbor_levels[0]) * level_pixels - 1.0), Vector2((x + 1) * tile_pixels, top_y + (level - neighbor_levels[0]) * level_pixels - 1.0), 1.8, Color("30383e", 0.78))
			if neighbor_levels[1] < level:
				_image_fill_safe(
					image,
					Rect2i((x + 1) * tile_pixels - 2, top_y, 2, (level - neighbor_levels[1]) * level_pixels),
					face_color
				)
				_image_draw_segment(image, Vector2((x + 1) * tile_pixels - 1.0, top_y), Vector2((x + 1) * tile_pixels - 1.0, top_y + tile_pixels), 1.4, Color("a69b83", 0.58))
			if neighbor_levels[2] < level:
				_image_fill_safe(
					image,
					Rect2i(x * tile_pixels, top_y + tile_pixels, tile_pixels, (level - neighbor_levels[2]) * level_pixels),
					face_color
				)
				_image_draw_segment(image, Vector2(x * tile_pixels, top_y + tile_pixels - 1.0), Vector2((x + 1) * tile_pixels, top_y + tile_pixels - 1.0), 1.8, Color("30383e", 0.78))
			if neighbor_levels[3] < level:
				_image_fill_safe(
					image,
					Rect2i(x * tile_pixels, top_y, 2, (level - neighbor_levels[3]) * level_pixels),
					face_color
				)
				_image_draw_segment(image, Vector2(x * tile_pixels + 1.0, top_y), Vector2(x * tile_pixels + 1.0, top_y + tile_pixels), 1.4, Color("a69b83", 0.58))
	# Then draw the raised tile tops.
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var level: int = layout.elevation_level_at(cell)
			var surface: int = layout.surface_flags_at(cell)
			if level == 0 and surface == 0:
				continue
			var top_y: int = y * tile_pixels - level * level_pixels
			var use_flat_top: bool = (surface & SiteLayoutDataType.SURFACE_WALL) != 0
			var top_color: Color = _height_surface_color(surface, level, layout.terrain_type)
			if base_image != null:
				_image_copy_tile_safe(
					image,
					base_image,
					Vector2i(x * tile_pixels, y * tile_pixels),
					Vector2i(x * tile_pixels, top_y),
					tile_pixels
				)
				if level > 0 and (surface & SiteLayoutDataType.SURFACE_PLATFORM) != 0:
					var platform_tint: Color = Color("d2bf8f", 0.14) \
						if layout.terrain_type == TerrainType.MOUNTAIN \
						else Color("d2bf8f", 0.07)
					_image_tint_tile_safe(image, Vector2i(x * tile_pixels, top_y), tile_pixels, platform_tint)
			if use_flat_top:
				_image_fill_safe(
					image,
					Rect2i(x * tile_pixels, top_y, tile_pixels, tile_pixels),
					top_color
				)
	# Re-assert one shared contour after the shifted top tiles are copied.  The
	# old per-face lines were drawn underneath those copies, so east/west and
	# south edges disappeared and the raised rock read as broken fragments.  A
	# single post-pass makes every exposed edge continuous while keeping the
	# contour muted enough to belong to the natural rock palette.
	_draw_height_edge_contours(image, layout, tile_pixels, level_pixels)
	# Stairs and bridges are rendered into the same cached layer; this avoids
	# thousands of CanvasItem draw calls while keeping each transition legible.
	for transition: SiteTransitionDataType in layout.transitions:
		if transition == null:
			continue
		if transition.from_level == transition.to_level:
			continue
		# The formal renderer draws the regenerated pixel-art stair sprite on top
		# of this cached floor. Keep the procedural fallback below for headless or
		# older layouts that do not have a GPU-backed overlay.
		if transition.kind in [
			SiteTransitionDataType.Kind.STAIR,
			SiteTransitionDataType.Kind.BRIDGE,
			SiteTransitionDataType.Kind.DOCK,
		]:
			continue
		var from_point: Vector2 = _height_image_point(layout, transition.from_cell, transition.from_level, tile_pixels, level_pixels)
		var to_point: Vector2 = _height_image_point(layout, transition.to_cell, transition.to_level, tile_pixels, level_pixels)
		var width: float = 2.8 * pixels_per_meter if transition.kind == SiteTransitionDataType.Kind.BRIDGE else 2.2 * pixels_per_meter
		var color: Color = Color("9a673b", 0.98) if transition.kind == SiteTransitionDataType.Kind.BRIDGE else Color("d2a15c", 0.98)
		_image_draw_segment(image, from_point, to_point, width + 2.0, Color("3d3027", 0.94))
		_image_draw_segment(image, from_point, to_point, width, color)
		if transition.kind == SiteTransitionDataType.Kind.STAIR:
			var direction: Vector2 = (to_point - from_point).normalized()
			var perpendicular: Vector2 = Vector2(-direction.y, direction.x) * width * 0.46
			var tread_shadow: Color = Color("4b4b50", 0.96) if layout.terrain_type == TerrainType.MOUNTAIN else Color("68482f", 0.96)
			var tread_highlight: Color = Color("c4c2b0", 0.98) if layout.terrain_type == TerrainType.MOUNTAIN else Color("e6bd79", 0.98)
			for step: int in range(1, 7):
				var point: Vector2 = from_point.lerp(to_point, float(step) / 7.0)
				_image_draw_segment(image, point - perpendicular, point + perpendicular, 0.82 * pixels_per_meter, tread_shadow)
				_image_draw_segment(image, point - perpendicular, point + perpendicular, 0.48 * pixels_per_meter, tread_highlight)
	return image

func _draw_height_edge_contours(
		image: Image,
		layout: SiteLayoutDataType,
		tile_pixels: int,
		level_pixels: int
	) -> void:
	if layout == null or not layout.has_height_base():
		return
	var rim: Color = Color("a69b83", 0.74) if layout.terrain_type == TerrainType.MOUNTAIN \
		else Color("b7aa8d", 0.58)
	var shadow: Color = Color("30383e", 0.88) if layout.terrain_type == TerrainType.MOUNTAIN \
		else Color("3d3027", 0.72)
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell := Vector2i(x, y)
			var level: int = layout.elevation_level_at(cell)
			if level <= 0:
				continue
			var top_y: float = float(y * tile_pixels - level * level_pixels)
			var depth: float = float(level * level_pixels)
			var neighbors: Array[Array] = [
				[Vector2i.UP, SiteLayoutDataType.EDGE_NORTH],
				[Vector2i.RIGHT, SiteLayoutDataType.EDGE_EAST],
				[Vector2i.DOWN, SiteLayoutDataType.EDGE_SOUTH],
				[Vector2i.LEFT, SiteLayoutDataType.EDGE_WEST],
			]
			for item: Array in neighbors:
				var neighbor := cell + (item[0] as Vector2i)
				if not SiteLayoutDataType.is_valid_cell(neighbor) \
					or layout.elevation_level_at(neighbor) >= level:
					continue
				var edge: int = int(item[1])
				var top_start: Vector2
				var top_end: Vector2
				var outer_start: Vector2
				var outer_end: Vector2
				match edge:
					SiteLayoutDataType.EDGE_NORTH:
						top_start = Vector2(x * tile_pixels, top_y)
						top_end = Vector2((x + 1) * tile_pixels, top_y)
						outer_start = top_start + Vector2(0.0, depth)
						outer_end = top_end + Vector2(0.0, depth)
					SiteLayoutDataType.EDGE_EAST:
						top_start = Vector2((x + 1) * tile_pixels, top_y)
						top_end = Vector2((x + 1) * tile_pixels, top_y + tile_pixels)
						outer_start = top_start + Vector2(0.0, depth)
						outer_end = top_end + Vector2(0.0, depth)
					SiteLayoutDataType.EDGE_SOUTH:
						top_start = Vector2((x + 1) * tile_pixels, top_y + tile_pixels)
						top_end = Vector2(x * tile_pixels, top_y + tile_pixels)
						outer_start = top_start + Vector2(0.0, depth)
						outer_end = top_end + Vector2(0.0, depth)
					_:
						top_start = Vector2(x * tile_pixels, top_y + tile_pixels)
						top_end = Vector2(x * tile_pixels, top_y)
						outer_start = top_start + Vector2(0.0, depth)
						outer_end = top_end + Vector2(0.0, depth)
				_image_draw_segment(image, outer_start, outer_end, 2.2, shadow)
				_image_draw_segment(image, top_start, top_end, 1.1, rim)

func _height_image_point(
		_layout: SiteLayoutDataType,
		cell: Vector2i,
		level: int,
		tile_pixels: int,
		level_pixels: int
	) -> Vector2:
	return Vector2(
		float(cell.x * tile_pixels) + float(tile_pixels) * 0.5,
		float(cell.y * tile_pixels) + float(tile_pixels) * 0.5 - float(level * level_pixels)
	)

func _image_fill_safe(image: Image, rect: Rect2i, color: Color) -> void:
	var clipped: Rect2i = rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if clipped.size.x > 0 and clipped.size.y > 0:
		image.fill_rect(clipped, color)

func _image_copy_tile_safe(
		destination: Image,
		source: Image,
		source_origin: Vector2i,
		destination_origin: Vector2i,
		tile_pixels: int
	) -> void:
	for local_y: int in range(tile_pixels):
		var destination_y: int = destination_origin.y + local_y
		if destination_y < 0 or destination_y >= destination.get_height():
			continue
		for local_x: int in range(tile_pixels):
			var destination_x: int = destination_origin.x + local_x
			if destination_x < 0 or destination_x >= destination.get_width():
				continue
			var source_x: int = clampi(source_origin.x + local_x, 0, source.get_width() - 1)
			var source_y: int = clampi(source_origin.y + local_y, 0, source.get_height() - 1)
			destination.set_pixel(destination_x, destination_y, source.get_pixel(source_x, source_y))

func _image_tint_tile_safe(image: Image, origin: Vector2i, tile_pixels: int, tint: Color) -> void:
	for local_y: int in range(tile_pixels):
		for local_x: int in range(tile_pixels):
			var pixel_x: int = origin.x + local_x
			var pixel_y: int = origin.y + local_y
			if pixel_x < 0 or pixel_x >= image.get_width() or pixel_y < 0 or pixel_y >= image.get_height():
				continue
			var current: Color = image.get_pixel(pixel_x, pixel_y)
			image.set_pixel(pixel_x, pixel_y, current.lerp(tint, tint.a))

func _image_draw_segment(image: Image, start: Vector2, end: Vector2, width: float, color: Color) -> void:
	var radius: float = maxf(width * 0.5, 0.5)
	var min_x: int = maxi(0, floori(minf(start.x, end.x) - radius))
	var max_x: int = mini(image.get_width() - 1, ceili(maxf(start.x, end.x) + radius))
	var min_y: int = maxi(0, floori(minf(start.y, end.y) - radius))
	var max_y: int = mini(image.get_height() - 1, ceili(maxf(start.y, end.y) + radius))
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			if _distance_to_segment(Vector2(x, y), start, end) <= radius:
				image.set_pixel(x, y, color)

func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var delta: Vector2 = end - start
	var length_squared: float = delta.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var factor: float = clampf((point - start).dot(delta) / length_squared, 0.0, 1.0)
	return point.distance_to(start + delta * factor)

func _height_surface_color(surface: int, level: int, terrain_type: int = TerrainType.PLAINS) -> Color:
	if (surface & SiteLayoutDataType.SURFACE_WATER) != 0 \
		and (surface & (SiteLayoutDataType.SURFACE_BRIDGE | SiteLayoutDataType.SURFACE_DOCK)) == 0:
		return Color("347f9b", 0.72)
	if (surface & SiteLayoutDataType.SURFACE_WALL) != 0:
		return Color("72635a", 0.96)
	if (surface & SiteLayoutDataType.SURFACE_STAIR) != 0:
		return Color("c18c52", 0.96)
	if (surface & SiteLayoutDataType.SURFACE_BRIDGE) != 0:
		return Color("9a673b", 0.98)
	if (surface & SiteLayoutDataType.SURFACE_DOCK) != 0:
		return Color("80613e", 0.98)
	if (surface & SiteLayoutDataType.SURFACE_CLIFF) != 0:
		return Color("737b80", 0.98).lerp(_terrain_height_color(terrain_type), 0.28)
	if (surface & SiteLayoutDataType.SURFACE_PLATFORM) != 0:
		return _terrain_height_color(terrain_type).lightened(0.18 if level > 0 else 0.05)
	return Color("b39a73", 0.92 if level > 0 else 0.72)

func _terrain_height_color(terrain_type: int) -> Color:
	match terrain_type:
		TerrainType.FOREST:
			return Color("507745")
		TerrainType.SAND:
			return Color("b78a4c")
		TerrainType.SNOW:
			return Color("b9ced1")
		TerrainType.SWAMP:
			return Color("535d48")
		TerrainType.MOUNTAIN:
			return Color("6d747b")
		_:
			return Color("789052")

func _height_face_color(layout: SiteLayoutDataType, cell: Vector2i, level: int) -> Color:
	var terrain_color: Color = _terrain_height_color(layout.terrain_type)
	var native_surface: int = layout.native_surface_at(cell)
	if native_surface == SiteContentTypes.NativeSurface.ROCK \
		or (layout.surface_flags_at(cell) & SiteLayoutDataType.SURFACE_CLIFF) != 0:
		terrain_color = Color("3d454d").lerp(terrain_color, 0.22)
	else:
		terrain_color = terrain_color.darkened(0.34)
	var result: Color = terrain_color.darkened(clampf(float(level - 1) * 0.08, 0.0, 0.20))
	result.a = 1.0
	return result

func _draw_height_faces(
		layout: SiteLayoutDataType,
		cell: Vector2i,
		origin: Vector2,
		level: int
	) -> void:
	if level <= 0:
		return
	var neighbors: Array[Array] = [
		[Vector2i.UP, SiteLayoutDataType.EDGE_NORTH],
		[Vector2i.RIGHT, SiteLayoutDataType.EDGE_EAST],
		[Vector2i.DOWN, SiteLayoutDataType.EDGE_SOUTH],
		[Vector2i.LEFT, SiteLayoutDataType.EDGE_WEST],
	]
	var edge_flags: int = layout.height_edge_flags_at(cell)
	for item: Array in neighbors:
		var neighbor: Vector2i = cell + (item[0] as Vector2i)
		var edge: int = int(item[1])
		if (edge_flags & edge) == 0:
			continue
		var top_origin: Vector2 = origin \
			+ Vector2(0.0, -float(level) * MapArtCatalogType.SITE_HEIGHT_OFFSET_METERS)
		var segment: PackedVector2Array = _edge_segment(top_origin, edge)
		var drop: float = float(level - layout.elevation_level_at(neighbor)) \
			* MapArtCatalogType.SITE_HEIGHT_OFFSET_METERS
		var face: PackedVector2Array = PackedVector2Array([
			segment[0],
			segment[1],
			segment[1] + Vector2(0.0, drop),
			segment[0] + Vector2(0.0, drop),
		])
		draw_colored_polygon(face, Color("302f38", 0.96))
		draw_line(segment[0], segment[1], Color("d7c08f", 0.72), 0.38, true)

func _edge_segment(origin: Vector2, edge: int) -> PackedVector2Array:
	var size: float = float(SiteLayoutDataType.CELL_SIZE_METERS)
	match edge:
		SiteLayoutDataType.EDGE_NORTH:
			return PackedVector2Array([origin, origin + Vector2(size, 0.0)])
		SiteLayoutDataType.EDGE_EAST:
			return PackedVector2Array([origin + Vector2(size, 0.0), origin + Vector2(size, size)])
		SiteLayoutDataType.EDGE_SOUTH:
			return PackedVector2Array([origin + Vector2(size, size), origin + Vector2(0.0, size)])
		_:
			return PackedVector2Array([origin + Vector2(0.0, size), origin])

func _draw_height_transitions(layout: SiteLayoutDataType) -> void:
	if height_texture != null:
		_draw_ai_stair_overlays(layout)
		return
	if layout.transitions.is_empty():
		return
	for transition: SiteTransitionDataType in layout.transitions:
		if transition == null:
			continue
		if transition.from_level == transition.to_level:
			# Keep the fallback renderer consistent with the cached renderer: a flat
			# edge is not a height transition and must not receive stair art.
			continue
		if transition.kind in [SiteTransitionDataType.Kind.BRIDGE, SiteTransitionDataType.Kind.DOCK]:
			continue
		var from_point: Vector2 = _height_adjusted_point(
			layout,
			layout.cell_center_meters(transition.from_cell),
			transition.from_level
		)
		var to_point: Vector2 = _height_adjusted_point(
			layout,
			layout.cell_center_meters(transition.to_cell),
			transition.to_level
		)
		var color: Color = Color("d2a15c")
		var width: float = 2.15
		if transition.kind == SiteTransitionDataType.Kind.BRIDGE or transition.kind == SiteTransitionDataType.Kind.DOCK:
			color = Color("9a673b")
			width = 2.7
		var direction: Vector2 = (to_point - from_point).normalized()
		var perpendicular: Vector2 = Vector2(-direction.y, direction.x) * width * 0.5
		var band: PackedVector2Array = PackedVector2Array([
			from_point + perpendicular,
			from_point - perpendicular,
			to_point - perpendicular,
			to_point + perpendicular,
		])
		draw_colored_polygon(band, Color("3d3027", 0.92))
		draw_colored_polygon(PackedVector2Array([
			from_point + perpendicular * 0.78,
			from_point - perpendicular * 0.78,
			to_point - perpendicular * 0.78,
			to_point + perpendicular * 0.78,
		]), color)
		if transition.kind == SiteTransitionDataType.Kind.STAIR:
			for step: int in range(1, 7):
				var ratio: float = float(step) / 7.0
				var point: Vector2 = from_point.lerp(to_point, ratio)
				draw_line(
					point - perpendicular * 0.88,
					point + perpendicular * 0.88,
					Color("f6dca5", 0.9),
					0.42,
					true
				)

func _draw_ai_stair_overlays(layout: SiteLayoutDataType) -> void:
	var drawn: int = 0
	for transition: SiteTransitionDataType in layout.transitions:
		if transition == null or transition.kind != SiteTransitionDataType.Kind.STAIR:
			continue
		if transition.from_level == transition.to_level:
			# Defensive guard for older/session-authored layouts: a flat edge is
			# not a stair and must never receive stair art.
			continue
		if drawn >= 2:
			return
		var from_point: Vector2 = _height_adjusted_point(
			layout,
			layout.cell_center_meters(transition.from_cell),
			transition.from_level
		)
		var to_point: Vector2 = _height_adjusted_point(
			layout,
			layout.cell_center_meters(transition.to_cell),
			transition.to_level
		)
		var delta: Vector2 = to_point - from_point
		if delta.length_squared() <= 0.01:
			continue
		var stair_kind: String = _stair_art_kind(layout, transition)
		var stair: Texture2D = MapArtCatalogType.site_texture(stair_kind)
		if stair == null:
			continue
		var art_size: Vector2 = MapArtCatalogType.site_art_size_meters(stair_kind)
		var length: float = maxf(delta.length() + 1.0, art_size.y)
		var width: float = art_size.x
		var center: Vector2 = (from_point + to_point) * 0.5
		draw_set_transform(center, delta.angle() - PI * 0.5, Vector2.ONE)
		draw_texture_rect(stair, Rect2(Vector2(-width * 0.5, -length * 0.5), Vector2(width, length)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		drawn += 1

func _stair_art_kind(layout: SiteLayoutDataType, transition: SiteTransitionDataType) -> String:
	for facility: Dictionary in layout.facility_placements:
		var facility_type: int = int(facility.get("type", -1))
		if facility_type not in [SiteContentTypes.Facility.WOOD_STAIR, SiteContentTypes.Facility.STONE_STAIR]:
			continue
		var origin: Variant = facility.get("origin", SiteLayoutDataType.INVALID_CELL)
		var target: Variant = facility.get("target", SiteLayoutDataType.INVALID_CELL)
		if origin is Vector2i and target is Vector2i \
			and transition.connects(origin as Vector2i, target as Vector2i):
			return "wood_stair" if facility_type == SiteContentTypes.Facility.WOOD_STAIR else "stair"
	return "stair"

func _draw_bridge_surface_overlays(layout: SiteLayoutDataType) -> void:
	var bank_cells: Variant = layout.details.get("bridge_bank_cells", [])
	if bank_cells is Array:
		for value: Variant in bank_cells as Array:
			if not value is Vector2i:
				continue
			var cell: Vector2i = value as Vector2i
			var center: Vector2 = _height_adjusted_point(
				layout,
				layout.cell_center_meters(cell),
				layout.elevation_level_at(cell)
			)
			var dock_rect: Rect2 = Rect2(
				center - Vector2.ONE,
				Vector2.ONE * SiteLayoutDataType.CELL_SIZE_METERS
			)
			draw_rect(dock_rect, Color("b4864f", 0.94), true)
			draw_rect(dock_rect, Color("f1d08c", 0.92), false, 0.42)
	# The regenerated bridge sprite carries the deck, bank edges, and shadow;
	# avoid a second procedural rectangle over it.


func _draw_cell_base_corridors(layout: SiteLayoutDataType) -> void:
	var center: Vector2 = Vector2(layout.bounds_meters.get_center())
	_draw_connection_corridors(
		center,
		layout.road_connection_offsets,
		MapArtCatalogType.site_art_width_meters("path_straight", 3.0)
	)

func _draw_mountain_pass_corridors(layout: SiteLayoutDataType) -> void:
	var center: Vector2 = Vector2(layout.bounds_meters.get_center())
	var exits: Array[Vector2i] = SiteLayoutDataType.exit_offsets(layout.travel_exit_mask)
	if exits.is_empty():
		exits = [Vector2i.LEFT, Vector2i.RIGHT]
	var width: float = 5.0
	var horizontal_pass: bool = exits.size() >= 2 and exits[0].x != 0
	# Opposite exits are one continuous path. Splitting them at the center made a
	# visible seam and made the pass read like a wooden bridge/plank.
	if exits.size() >= 2 and ((exits[0] + exits[1]) == Vector2i.ZERO):
		var axis: Vector2 = Vector2.RIGHT if horizontal_pass else Vector2.DOWN
		_draw_clean_road_path([
			center - axis * (MapArtCatalogType.SITE_SIZE_METERS * 0.5),
			center + axis * (MapArtCatalogType.SITE_SIZE_METERS * 0.5)
		], width)
	else:
		for offset: Vector2i in exits:
			var edge: Vector2 = center + Vector2(offset) * (MapArtCatalogType.SITE_SIZE_METERS * 0.5)
			_draw_clean_road_path([center, edge], width)
	# A narrow dark lip is enough to separate the trail from the raised cliff
	# faces without drawing another opaque landform rectangle.
	if horizontal_pass:
		var top: float = center.y - width * 0.5
		var bottom: float = center.y + width * 0.5
		draw_line(Vector2(layout.bounds_meters.position.x, top), Vector2(layout.bounds_meters.end.x, top), Color("262d33", 0.76), 0.55, true)
		draw_line(Vector2(layout.bounds_meters.position.x, bottom), Vector2(layout.bounds_meters.end.x, bottom), Color("171a20", 0.82), 0.55, true)
	else:
		var left: float = center.x - width * 0.5
		var right: float = center.x + width * 0.5
		draw_line(Vector2(left, layout.bounds_meters.position.y), Vector2(left, layout.bounds_meters.end.y), Color("262d33", 0.76), 0.55, true)
		draw_line(Vector2(right, layout.bounds_meters.position.y), Vector2(right, layout.bounds_meters.end.y), Color("171a20", 0.82), 0.55, true)

func _draw_connection_corridors(
	center: Vector2,
	offsets: Array[Vector2i],
	width: float
) -> void:
	for offset: Vector2i in offsets:
		var edge: Vector2 = center + Vector2(offset) * (MapArtCatalogType.SITE_SIZE_METERS * 0.5)
		var delta: Vector2 = edge - center
		if delta.length() <= 0.1:
			continue
		_draw_clean_road_path([center, edge], width)

func _draw_polyline_texture(points: Array, _texture: Texture2D, width: float) -> void:
	# Road art is intentionally a single opaque, cleared surface. The former
	# straight/bend textures contain pebbles and grass fringes, which become
	# repeated visual litter when a road crosses many 2m tiles.
	_draw_clean_road_path(points, width)

func _draw_clean_road_path(points: Array, width: float) -> void:
	if points.size() < 2:
		return
	var path: PackedVector2Array = PackedVector2Array()
	for point: Variant in points:
		path.append(Vector2(point))
	var edge_width: float = maxf(width + 0.85, width)
	var edge_color: Color = Color("493727")
	var surface_color: Color = Color("9a7548")
	draw_polyline(path, edge_color, edge_width, true)
	draw_polyline(path, surface_color, width, true)

func _draw_river_band(layout: SiteLayoutDataType, texture: Texture2D, texture_kind: String = "river_straight") -> void:
	if texture == null:
		return
	var axis: int = _river_axis(layout)
	var center: float = _river_center(layout, axis)
	var river_width: float = MapArtCatalogType.site_art_width_meters(texture_kind, 8.0)
	var river_rect: Rect2 = Rect2(
		Vector2(center - river_width * 0.5, layout.bounds_meters.position.y),
		Vector2(river_width, layout.bounds_meters.size.y)
	) if axis == 0 else Rect2(
		Vector2(layout.bounds_meters.position.x, center - river_width * 0.5),
		Vector2(layout.bounds_meters.size.x, river_width)
	)
	# The v2 river sprite carries its own irregular transparent shoreline.  Do
	# not put a rectangular fill behind it or the bank would still read as a
	# canal. The destination rectangle already encodes the axis; rotating here
	# would turn a correctly horizontal river into a second vertical overlay.
	var river_center: Vector2 = river_rect.get_center()
	draw_set_transform(river_center, 0.0, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-river_rect.size * 0.5, river_rect.size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Only cap a one-sided stream. Opposite connections are a continuous river
	# segment and must meet neighboring Sites without artificial source/mouth
	# stamps at both boundaries.
	if axis == 0 and layout.river_connection_offsets.size() <= 1:
		var source_texture: Texture2D = MapArtCatalogType.site_texture("river_source")
		var mouth_texture: Texture2D = MapArtCatalogType.site_texture("river_mouth")
		var source_size: Vector2 = MapArtCatalogType.site_art_size_meters("river_source")
		var mouth_size: Vector2 = MapArtCatalogType.site_art_size_meters("river_mouth")
		var source_point: Vector2 = Vector2(center, layout.bounds_meters.position.y + source_size.y * 0.5) \
			if axis == 0 else Vector2(layout.bounds_meters.position.x + source_size.x * 0.5, center)
		var mouth_point: Vector2 = Vector2(center, layout.bounds_meters.end.y - mouth_size.y * 0.5) \
			if axis == 0 else Vector2(layout.bounds_meters.end.x - mouth_size.x * 0.5, center)
		_draw_centered_texture(source_texture, source_point, source_size)
		_draw_centered_texture(mouth_texture, mouth_point, mouth_size)

func _river_axis(layout: SiteLayoutDataType) -> int:
	for offset: Vector2i in layout.river_connection_offsets:
		if offset.x != 0:
			return 1
		if offset.y != 0:
			return 0
	return posmod(layout.site_seed, 2)

func _river_center(layout: SiteLayoutDataType, _axis: int) -> float:
	if not layout.river_connection_offsets.is_empty():
		return 0.0
	return float(DeterministicHash.int_range(
		layout.site_seed,
		layout.global_region_cell,
		41_502,
		-18,
		18
	))

func _draw_site_decorations(layout: SiteLayoutDataType) -> void:
	for index: int in range(layout.landmark_points_meters.size()):
		var decor: Texture2D = MapArtCatalogType.site_decor_texture(
			layout.terrain_type,
			index % 2
		)
		if decor == null:
			continue
		var point: Vector2 = _height_adjusted_meters(
			layout,
			Vector2(layout.landmark_points_meters[index]) + Vector2(7.0, 5.0)
		)
		if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI and _near_primary_path(layout, point, 4.0):
			continue
		_draw_centered_texture(
			decor,
			point,
			MapArtCatalogType.site_decor_size_meters(layout.terrain_type, index % 2)
		)

func _near_primary_path(layout: SiteLayoutDataType, point: Vector2, radius: float) -> bool:
	for path_point: Vector2i in layout.primary_path_meters:
		if point.distance_to(Vector2(path_point)) <= radius:
			return true
	return false

func _draw_generated_resources(layout: SiteLayoutDataType) -> void:
	var grouped: Dictionary = {}
	for placement: Dictionary in layout.resource_placements:
		var type_key: int = int(placement.get("type", -1))
		if not grouped.has(type_key):
			grouped[type_key] = []
		(grouped[type_key] as Array).append(placement)
	for type_key: int in grouped.keys():
		var placements: Array = grouped[type_key] as Array
		if placements.is_empty():
			continue
		if type_key == SiteContentTypes.RESOURCE_FOREST \
			and layout.terrain_type == TerrainType.FOREST:
			_draw_forest_resource_field(layout, placements)
			continue
		var anchor_placement: Dictionary = placements[0] as Dictionary
		var anchor_value: Variant = anchor_placement.get("origin", SiteLayoutDataType.INVALID_CELL)
		if not anchor_value is Vector2i:
			continue
		var anchor: Vector2i = anchor_value as Vector2i
		var anchor_center: Vector2 = _height_adjusted_point(layout, layout.cell_center_meters(anchor), layout.elevation_level_at(anchor))
		var safe_margin: float = 18.0
		anchor_center.x = clampf(anchor_center.x, float(layout.bounds_meters.position.x) + safe_margin, float(layout.bounds_meters.end.x) - safe_margin)
		anchor_center.y = clampf(anchor_center.y, float(layout.bounds_meters.position.y) + safe_margin, float(layout.bounds_meters.end.y) - safe_margin)
		var placement_slot: int = 0
		for placement: Dictionary in placements:
			var visual_limit: int = 12 if type_key == SiteContentTypes.RESOURCE_GRASS else 10 if type_key == SiteContentTypes.RESOURCE_FOREST else 8
			if placement_slot >= visual_limit:
				break
			var kind: String = MapArtCatalogType.resource_art_kind(int(placement.get("type", -1)))
			var texture: Texture2D = MapArtCatalogType.site_texture(kind)
			var origin_value: Variant = placement.get("origin", SiteLayoutDataType.INVALID_CELL)
			if kind.is_empty() or texture == null or not origin_value is Vector2i:
				continue
			var origin: Vector2i = origin_value as Vector2i
			var center: Vector2 = _height_adjusted_point(
				layout,
				layout.cell_center_meters(origin),
				layout.elevation_level_at(origin)
			)
			var center_offset: Vector2 = (center - anchor_center) * 0.12
			var cluster_slot: Vector2 = _resource_cluster_slot(layout, type_key, placement_slot)
			var draw_count: int = _resource_draw_count(kind, int(placement.get("quantity", 1)))
			var base_size: Vector2 = MapArtCatalogType.site_art_size_meters(kind)
			var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(-0.72, 0.16), Vector2(0.72, 0.16), Vector2(0.0, -0.62)]
			for index: int in range(draw_count):
				var size: Vector2 = base_size * (0.82 if draw_count > 1 else 1.0)
				_draw_centered_texture(texture, anchor_center + cluster_slot + center_offset + offsets[index] * 1.8, size)
			placement_slot += 1

func _draw_forest_resource_field(layout: SiteLayoutDataType, placements: Array) -> void:
	var total_quantity: int = 0
	for placement: Dictionary in placements:
		total_quantity += maxi(1, int(placement.get("quantity", 1)))
	if total_quantity <= 0:
		return
	# The resource amount controls density, while the minimum keeps a valid
	# Forest Site filled with wood resources instead of collapsing into one
	# lonely grove. This remains a visual projection of RESOURCE_FOREST;
	# harvesting and persistence still use the authoritative placements
	# generated by the authoritative Site layout data pipeline.
	var grove_count: int = clampi(ceili(float(total_quantity) / 0.55), 72, 96)
	var columns: int = 11
	var rows: int = 11
	var bounds: Rect2 = Rect2(Vector2(layout.bounds_meters.position), Vector2(layout.bounds_meters.size))
	var placed: int = 0
	var slot_count: int = columns * rows
	var slot_start: int = posmod(DeterministicHash.value(layout.site_seed, layout.global_region_cell, 48_219), slot_count)
	var slot_stride: int = 47 # coprime with 121, so every row is visited before reuse
	for placement_slot: int in range(slot_count):
		if placed >= grove_count:
			break
		var slot: int = posmod(slot_start + placement_slot * slot_stride, slot_count)
		var column: int = slot % columns
		var row: int = floori(float(slot) / float(columns))
		var point: Vector2 = Vector2(
			-42.5 + float(column) * 8.5,
			-42.5 + float(row) * 8.5
		)
		var slot_cell := Vector2i(column, row)
		point.x += float(DeterministicHash.int_range(layout.site_seed, slot_cell, 48_220, -3, 3))
		point.y += float(DeterministicHash.int_range(layout.site_seed, slot_cell, 48_221, -3, 3))
		if not _forest_point_allowed(layout, point, bounds):
			continue
		var placement_hash: int = DeterministicHash.value(
			layout.site_seed,
			layout.global_region_cell + slot_cell,
			48_222
		)
		var kind: String = "tree_cluster" if posmod(placement_hash, 7) <= 2 else "forest_resource"
		var texture: Texture2D = MapArtCatalogType.site_texture(kind)
		if texture == null:
			continue
		var size_factor: float = 0.58 + DeterministicHash.normalized(
			layout.site_seed,
			layout.global_region_cell + slot_cell,
			48_223
		) * 0.64
		var size: Vector2 = MapArtCatalogType.site_art_size_meters(kind) * size_factor
		var draw_point: Vector2 = _height_adjusted_meters(layout, point)
		var flip_x: float = -1.0 if posmod(placement_hash, 2) == 0 else 1.0
		draw_set_transform(draw_point, 0.0, Vector2(flip_x, 1.0))
		draw_texture_rect(texture, Rect2(-size * 0.5, size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		placed += 1

func _forest_point_allowed(layout: SiteLayoutDataType, point: Vector2, bounds: Rect2) -> bool:
	var clearance: float = 9.0
	if (forest_clear_edge_mask & 1) != 0 and point.y < bounds.position.y + clearance:
		return false
	if (forest_clear_edge_mask & 2) != 0 and point.x > bounds.end.x - clearance:
		return false
	if (forest_clear_edge_mask & 4) != 0 and point.y > bounds.end.y - clearance:
		return false
	if (forest_clear_edge_mask & 8) != 0 and point.x < bounds.position.x + clearance:
		return false
	var local: Vector2 = (point - Vector2(bounds.position)) / float(SiteLayoutDataType.CELL_SIZE_METERS)
	var cell: Vector2i = Vector2i(
		clampi(floori(local.x), 0, SiteLayoutDataType.GRID_SIZE.x - 1),
		clampi(floori(local.y), 0, SiteLayoutDataType.GRID_SIZE.y - 1)
	)
	var flags: int = layout.navigation_flags_at(cell)
	if (flags & (SiteLayoutDataType.NAV_BLOCKED | SiteLayoutDataType.NAV_ROAD | SiteLayoutDataType.NAV_RIVER)) != 0:
		return false
	if SiteContentTypes.is_water_surface(layout.native_surface_at(cell)):
		return false
	if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI and _near_primary_path(layout, point, 4.0):
		return false
	return true

func _resource_cluster_slot(layout: SiteLayoutDataType, resource_type: int, index: int) -> Vector2:
	# Golden-angle placement keeps a deterministic grove/vein organic while
	# avoiding the row-and-column stamp that made the previous preview look like
	# a farm spreadsheet.
	var phase: float = DeterministicHash.normalized(
		layout.site_seed,
		layout.global_region_cell + Vector2i(resource_type, index),
		48_100
	) * TAU
	var angle: float = phase + float(index) * 2.399963
	var radius: float = 2.0 + float(posmod(index, 4)) * 1.35
	return Vector2(cos(angle), sin(angle)) * radius

func _resource_draw_count(kind: String, quantity: int) -> int:
	if kind == "fruit_tree_resource":
		return 1
	if kind == "forest_resource":
		return mini(3, maxi(1, ceili(float(quantity) / 8.0)))
	if kind == "grass_resource":
		return mini(3, maxi(1, ceili(float(quantity) / 8.0)))
	if kind.ends_with("_ore_resource"):
		return mini(3, maxi(1, ceili(float(quantity) / 3.0)))
	return 1

func _draw_tile_landmarks(layout: SiteLayoutDataType) -> void:
	var default_kind: String = _tile_landmark_kind(layout.terrain_type)
	if default_kind.is_empty():
		return
	var step: int = 18 if layout.terrain_type in [TerrainType.SAND, TerrainType.SNOW] else 17
	var drawn: int = 0
	var rock_drawn: int = 0
	for y: int in range(5, SiteLayoutDataType.GRID_SIZE.y - 5, step):
		for x: int in range(5, SiteLayoutDataType.GRID_SIZE.x - 5, step):
			var cell: Vector2i = Vector2i(x, y)
			var native_surface: int = layout.native_surface_at(cell)
			var is_rock_outcrop: bool = native_surface == SiteContentTypes.NativeSurface.ROCK \
				and layout.terrain_type != TerrainType.MOUNTAIN
			if is_rock_outcrop:
				if rock_drawn >= 2:
					continue
			elif drawn >= 2 or native_surface != SiteContentTypes.NativeSurface.DIRT:
				continue
			var kind: String = "rock_cluster" if is_rock_outcrop else default_kind
			var texture: Texture2D = MapArtCatalogType.site_texture(kind)
			if texture == null:
				continue
			var size: Vector2 = MapArtCatalogType.site_art_size_meters(kind)
			var flags: int = layout.navigation_flags_at(cell)
			if (flags & (SiteLayoutDataType.NAV_BLOCKED | SiteLayoutDataType.NAV_ROAD | SiteLayoutDataType.NAV_RIVER)) != 0:
				continue
			var placement_hash: int = DeterministicHash.value(layout.site_seed, layout.global_region_cell + cell, 47_100)
			if posmod(placement_hash, 19) != 0:
				continue
			var jitter: Vector2 = Vector2(
				float(DeterministicHash.int_range(layout.site_seed, cell, 47_101, -3, 3)),
				float(DeterministicHash.int_range(layout.site_seed, cell, 47_102, -3, 3))
			)
			_draw_centered_texture(
				texture,
				_height_adjusted_point(layout, layout.cell_center_meters(cell) + jitter, layout.elevation_level_at(cell)),
				size * 1.15
			)
			if is_rock_outcrop:
				rock_drawn += 1
			else:
				drawn += 1
			if drawn >= 2 and rock_drawn >= 2:
				return

func _tile_landmark_kind(terrain_type: int) -> String:
	match terrain_type:
		TerrainType.FOREST:
			# Do not bake wood-bearing trees into the native terrain.  The forest
			# resource placement owns every tree silhouette on a Forest Site.
			return "dry_bush"
		TerrainType.MOUNTAIN:
			return "rock_cluster"
		TerrainType.SAND:
			return "sand_dune"
		TerrainType.SNOW:
			return "snowdrift"
		TerrainType.SWAMP:
			return "swamp_reeds"
		TerrainType.PLAINS:
			return "dry_bush"
		_:
			return ""

func _draw_generated_facilities(layout: SiteLayoutDataType) -> void:
	for placement: Dictionary in layout.facility_placements:
		var facility_type: int = int(placement.get("type", -1))
		# A bridge is a river-crossing facility, not an independent decoration.
		# Composite tiles may keep the authoritative crossing in their layout while
		# suppressing that tile's rejected river component; drawing the bridge in
		# that case leaves a bridge floating on ordinary ground.  Keep the data and
		# navigation transition intact, but hide only this presentation layer.
		if facility_type == SiteContentTypes.Facility.BRIDGE \
			and composite_background_only and not composite_river_enabled:
			continue
		if facility_type in [SiteContentTypes.Facility.WOOD_STAIR, SiteContentTypes.Facility.STONE_STAIR]:
			continue
		var kind: String = MapArtCatalogType.facility_art_kind(
			facility_type,
			str(placement.get("definition_id", ""))
		)
		var texture: Texture2D = MapArtCatalogType.site_texture(kind)
		var origin_value: Variant = placement.get("origin", SiteLayoutDataType.INVALID_CELL)
		var size_value: Variant = placement.get("size", Vector2i.ONE)
		if kind.is_empty() or texture == null or not origin_value is Vector2i or not size_value is Vector2i:
			continue
		var origin: Vector2i = origin_value as Vector2i
		var size: Vector2i = size_value as Vector2i
		var center_cell: Vector2 = Vector2(origin) + Vector2(size) * 0.5 - Vector2.ONE * 0.5
		var center: Vector2 = Vector2(layout.bounds_meters.position) \
			+ (center_cell + Vector2.ONE * 0.5) * float(SiteLayoutDataType.CELL_SIZE_METERS)
		center = _height_adjusted_point(layout, center, layout.elevation_level_at(origin))
		var draw_size: Vector2 = MapArtCatalogType.site_art_size_meters(kind)
		if facility_type == SiteContentTypes.Facility.BUILDING:
			draw_size = Vector2(size * SiteLayoutDataType.CELL_SIZE_METERS)
		var draw_rotation: float = PI * 0.5 if int(placement.get("orientation", SiteContentTypes.Orientation.HORIZONTAL)) \
			== SiteContentTypes.Orientation.VERTICAL else 0.0
		draw_set_transform(center, draw_rotation, Vector2.ONE)
		_draw_centered_texture(texture, Vector2.ZERO, draw_size)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for wall: Dictionary in layout.wall_edges:
		_draw_wall_edge(layout, wall)

func _draw_wall_edge(layout: SiteLayoutDataType, wall: Dictionary) -> void:
	var from_value: Variant = wall.get("from", SiteLayoutDataType.INVALID_CELL)
	var to_value: Variant = wall.get("to", SiteLayoutDataType.INVALID_CELL)
	if not from_value is Vector2i or not to_value is Vector2i:
		return
	var from_cell: Vector2i = from_value as Vector2i
	var to_cell: Vector2i = to_value as Vector2i
	if _cell_inside_building(layout, from_cell) or _cell_inside_building(layout, to_cell):
		return
	var kind: String = MapArtCatalogType.facility_art_kind(int(wall.get("type", -1)))
	var texture: Texture2D = MapArtCatalogType.site_texture(kind)
	if texture == null:
		return
	var center: Vector2 = (layout.cell_center_meters(from_cell) + layout.cell_center_meters(to_cell)) * 0.5
	center = _height_adjusted_point(layout, center, maxi(layout.elevation_level_at(from_cell), layout.elevation_level_at(to_cell)))
	var delta: Vector2i = to_cell - from_cell
	var draw_rotation: float = PI * 0.5 if delta.x != 0 else 0.0
	draw_set_transform(center, draw_rotation, Vector2.ONE)
	_draw_centered_texture(texture, Vector2.ZERO, MapArtCatalogType.site_art_size_meters(kind))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _cell_inside_building(layout: SiteLayoutDataType, cell: Vector2i) -> bool:
	for placement: Dictionary in layout.facility_placements:
		if int(placement.get("type", -1)) != SiteContentTypes.Facility.BUILDING:
			continue
		var origin: Variant = placement.get("origin", SiteLayoutDataType.INVALID_CELL)
		var size: Variant = placement.get("size", Vector2i.ZERO)
		if origin is Vector2i and size is Vector2i \
			and Rect2i(origin as Vector2i, size as Vector2i).has_point(cell):
			return true
	return false

func _draw_cliff_edge_accents(layout: SiteLayoutDataType) -> void:
	var cliff: Texture2D = MapArtCatalogType.site_texture("mountain_pass_cliff")
	if cliff == null:
		return
	var drawn: int = 0
	for y: int in range(2, SiteLayoutDataType.GRID_SIZE.y - 2, 6):
		for x: int in range(2, SiteLayoutDataType.GRID_SIZE.x - 2, 6):
			var cell: Vector2i = Vector2i(x, y)
			if (layout.surface_flags_at(cell) & SiteLayoutDataType.SURFACE_CLIFF) == 0 \
				or layout.height_edge_flags_at(cell) == 0:
				continue
			_draw_centered_texture(
				cliff,
				_height_adjusted_point(layout, layout.cell_center_meters(cell), layout.elevation_level_at(cell)),
				Vector2(7.0, 9.0)
			)
			drawn += 1
			if drawn >= 10:
				return

func _draw_party_flag(point: Vector2) -> void:
	draw_line(point + Vector2(0.0, 5.0), point + Vector2(0.0, -8.0), Color("f8e8b0"), 1.5)
	draw_colored_polygon(PackedVector2Array([point + Vector2(0.0, -8.0), point + Vector2(8.0, -5.0), point + Vector2(0.0, -2.0)]), Color("ffe066"))

func _draw_deferred_poi_anchor(center: Vector2) -> void:
	if not show_debug_overlay:
		return
	var footprint: Rect2 = Rect2(center - Vector2.ONE, Vector2.ONE * MapArtCatalogType.SITE_TILE_SIZE_METERS)
	draw_rect(footprint, Color("f0cf6d", 0.62), false, 0.9)
	draw_circle(center, 0.55, Color("f0cf6d", 0.88))

func _draw_centered_texture(texture: Texture2D, center: Vector2, size: Vector2) -> void:
	if texture != null:
		draw_texture_rect(texture, Rect2(center - size * 0.5, size), false)

func _draw_debug_overlay(layout: SiteLayoutDataType) -> void:
	var bounds: Rect2 = Rect2(Vector2(layout.bounds_meters.position), Vector2(layout.bounds_meters.size))
	for grid: int in range(0, SiteLayoutDataType.GRID_SIZE.x + 1, 5):
		var grid_x: float = bounds.position.x + float(grid * SiteLayoutDataType.CELL_SIZE_METERS)
		var grid_y: float = bounds.position.y + float(grid * SiteLayoutDataType.CELL_SIZE_METERS)
		draw_line(Vector2(grid_x, bounds.position.y), Vector2(grid_x, bounds.end.y), Color(1.0, 1.0, 1.0, 0.10), 0.35)
		draw_line(Vector2(bounds.position.x, grid_y), Vector2(bounds.end.x, grid_y), Color(1.0, 1.0, 1.0, 0.10), 0.35)
	var path: PackedVector2Array = PackedVector2Array()
	for point: Vector2i in layout.primary_path_meters:
		path.append(Vector2(point))
	draw_polyline(path, Color("f2c27e"), 2.0, true)
	for point: Vector2i in layout.landmark_points_meters:
		draw_circle(Vector2(point), 3.0, Color("ee836d"))
	draw_circle(Vector2(layout.entrance_local_meters), 2.0, Color("e8f0f2"))

func _draw_scale_guide(layout: SiteLayoutDataType) -> void:
	var bounds: Rect2 = Rect2(Vector2(layout.bounds_meters.position), Vector2(layout.bounds_meters.size))
	var tile_size: float = MapArtCatalogType.SITE_TILE_SIZE_METERS
	# A light 2m lattice makes the art-to-navigation contract inspectable.
	for grid_x: int in range(SiteLayoutDataType.GRID_SIZE.x + 1):
		var x: float = bounds.position.x + float(grid_x) * tile_size
		var major: bool = grid_x % 5 == 0
		draw_line(
			Vector2(x, bounds.position.y),
			Vector2(x, bounds.end.y),
			Color(1.0, 1.0, 1.0, 0.18 if major else 0.055),
			0.55 if major else 0.25
		)
	for grid_y: int in range(SiteLayoutDataType.GRID_SIZE.y + 1):
		var y: float = bounds.position.y + float(grid_y) * tile_size
		var major: bool = grid_y % 5 == 0
		draw_line(
			Vector2(bounds.position.x, y),
			Vector2(bounds.end.x, y),
			Color(1.0, 1.0, 1.0, 0.18 if major else 0.055),
			0.55 if major else 0.25
		)
	# Highlight one authoritative tile and place a human-sized silhouette inside
	# it.  This is a scale reference only; occupancy remains Runtime-owned.
	if SiteLayoutDataType.is_valid_cell(runtime_snapshot.party_site_local_cell):
		var cell: Vector2i = runtime_snapshot.party_site_local_cell
		var tile_origin: Vector2 = bounds.position + Vector2(cell * SiteLayoutDataType.CELL_SIZE_METERS)
		var tile_rect: Rect2 = Rect2(tile_origin, Vector2.ONE * tile_size)
		draw_rect(tile_rect, Color("ffe066", 0.22), false, 1.1)
		var person_size: Vector2 = MapArtCatalogType.PERSON_REFERENCE_SIZE_METERS
		draw_rect(
			Rect2(tile_rect.get_center() - person_size * 0.5, person_size),
			Color("ffe066", 0.78),
			true
		)
	# Two metres is deliberately visible even on a full-Site camera view.
	var ruler_origin: Vector2 = bounds.position + Vector2(4.0, 6.0)
	draw_line(ruler_origin, ruler_origin + Vector2(tile_size, 0.0), Color("f5f0d0", 0.95), 1.0)
	draw_line(ruler_origin + Vector2(0.0, -1.5), ruler_origin + Vector2(0.0, 1.5), Color("f5f0d0", 0.95), 1.0)
	draw_line(ruler_origin + Vector2(tile_size, -1.5), ruler_origin + Vector2(tile_size, 1.5), Color("f5f0d0", 0.95), 1.0)
	draw_string(
		ThemeDB.fallback_font,
		ruler_origin + Vector2(0.0, -2.0),
		"2m",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		8,
		Color("f5f0d0", 0.95)
	)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(1.1)
			get_viewport().set_input_as_handled()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(0.9)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F1:
			show_debug_overlay = not show_debug_overlay
			queue_redraw()
			debug_state_changed.emit(get_debug_state())
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F2:
			show_scale_guide = not show_scale_guide
			queue_redraw()
			debug_state_changed.emit(get_debug_state())
			get_viewport().set_input_as_handled()
			return
		if not key_event.pressed or key_event.echo:
			return
		var direction: Vector2i = Vector2i.ZERO
		match key_event.keycode:
			KEY_W, KEY_UP:
				direction = Vector2i.UP
			KEY_A, KEY_LEFT:
				direction = Vector2i.LEFT
			KEY_S, KEY_DOWN:
				direction = Vector2i.DOWN
			KEY_D, KEY_RIGHT:
				direction = Vector2i.RIGHT
		if direction != Vector2i.ZERO:
			move_requested.emit(direction)
			get_viewport().set_input_as_handled()
		return

func _set_zoom(factor: float) -> void:
	if camera == null or factor <= 0.0:
		return
	var next_zoom: float = clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2.ONE * next_zoom
	debug_state_changed.emit(get_debug_state())

func _build_layout_texture(layout: SiteLayoutDataType) -> Texture2D:
	if layout == null or not layout.has_visual_base():
		return null
	var image: Image = MapArtCatalogType.build_layout_base_image(
		layout,
		MapArtCatalogType.SITE_DETAIL_SURFACE_PIXELS
	)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]

func _format_meters(meters: Vector2i) -> String:
	return "(%dm, %dm)" % [meters.x, meters.y]

func _format_world_time(seconds: int) -> String:
	var day: int = floori(float(seconds) / 86400.0)
	var hour: int = floori(float(seconds % 86400) / 3600.0)
	var minute: int = floori(float(seconds % 3600) / 60.0)
	return "Day %d  %02d:%02d" % [day, hour, minute]
