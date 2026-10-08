class_name SiteVehicleView
extends Node2D

## Presentation only. SiteVehicleTransport owns records, positions and movement.
const ASSETS := "res://assets/vehicles/logistics/v1/"
const SIEGE_ASSETS := "res://assets/vehicles/siege/v1/"
const SiegeMask = preload("res://assets/vehicles/siege/v1/siege_art_mask.gdshader")
const DAMAGED_TINT := Color(0.72, 0.57, 0.42, 1.0)
const Contract = preload("res://scripts/ui/character_render_contract.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const SHIP_ASSETS := "res://assets/vehicles/ships/v1/"
var lab: Node
var _atlas: Texture2D
var _frames: Dictionary = {}
var _scale := 1.0
var _sprites: Dictionary = {}
var _siege_nodes: Dictionary = {}
var _bolt_nodes: Dictionary = {}
var _ship_nodes: Dictionary = {}
var _ship_loot_nodes: Dictionary = {}
var _ship_art: Dictionary = {}
var _ship_art_frames: Dictionary = {}
var _ship_art_textures: Dictionary = {}
var _ship_art_shader: Shader
var _ship_art_invalid := false
var _siege_art: Dictionary = {}
var _siege_frames: Dictionary = {}
var _siege_textures: Dictionary = {}
var _bolt_texture: Texture2D
var _bolt_region := Rect2()
var _stone_texture: Texture2D
var _stone_region := Rect2()
var _rope_texture: Texture2D
var _rope_region := Rect2()
var _ladder_nodes: Dictionary = {}

func setup(value: Node) -> void:
	lab = value
	# Same-row vehicle art precedes the original actors, like SiteResources.
	var actor_root: Node = lab.get("character")
	if get_parent() == lab and is_instance_valid(actor_root):
		lab.move_child(self, actor_root.get_index())
	texture_filter = Contract.TEXTURE_FILTER
	_load_siege_art()
	_load_ship_art()
	if not FileAccess.file_exists(ASSETS + "vehicles_atlas.json"):
		push_error("Missing baked logistics vehicle atlas; run bake_logistics_vehicles.gd")
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "vehicles_atlas.json"))
	_atlas = load(ASSETS + "vehicles_atlas.res") as Texture2D
	_scale = float(manifest.map_scale)
	for frame: Dictionary in manifest.frames:
		_frames["%s/%s/%s/%d" % [frame.kind, frame.clip, frame.direction, int(frame.frame)]] = frame
	refresh()

func refresh() -> void:
	if lab == null or lab.terrain == null: return
	var records: Dictionary = lab.terrain.site.get("vehicles", {})
	for identity: String in _siege_nodes.keys():
		if not records.has(identity) or not SiteRuntime.SIEGE_DEFINITIONS.has(str(records[identity].kind)):
			_siege_nodes[identity].queue_free()
			_siege_nodes.erase(identity)
	for identity: String in _sprites.keys():
		if not records.has(identity) or (SiteRuntime.SIEGE_DEFINITIONS.has(str(records[identity].kind)) or str(records[identity].kind) == "ship"):
			_sprites[identity].queue_free()
			_sprites.erase(identity)
	for identity: String in _ship_nodes.keys():
		if not records.has(identity) or str(records[identity].kind) != "ship":
			_ship_nodes[identity].queue_free()
			_ship_nodes.erase(identity)
	for identity: String in records:
		if str(records[identity].kind) == "ship":
			_refresh_ship(identity, records[identity])
			continue
		if SiteRuntime.SIEGE_DEFINITIONS.has(str(records[identity].kind)):
			_refresh_ballista(identity, records[identity])
			continue
		if _atlas == null: continue
		var state: Dictionary = lab.site_controller.vehicles.render_state(records[identity])
		if state.is_empty(): continue
		var facing: Vector2i = state.facing
		var direction := "down"
		if facing.x < 0: direction = "left"
		elif facing.x > 0: direction = "right"
		elif facing.y < 0: direction = "up"
		var moving := bool(state.moving)
		var frame_number := mini(7, floori(clampf(float(state.progress), 0.0, 1.0) * 8.0)) if moving else 0
		var key := "%s/%s/%s/%d" % [state.kind, "move" if moving else "idle", direction, frame_number]
		if not _frames.has(key): continue
		var frame: Dictionary = _frames[key]
		var sprite: Sprite2D = _sprites.get(identity)
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.name = "Vehicle_" + identity.validate_node_name()
			sprite.texture = _atlas
			sprite.region_enabled = true
			sprite.centered = false
			sprite.scale = Vector2.ONE * _scale
			add_child(sprite)
			_sprites[identity] = sprite
		sprite.region_rect = Rect2(float(frame.rect[0]), float(frame.rect[1]), float(frame.rect[2]), float(frame.rect[3]))
		sprite.offset = -Vector2(float(frame.anchor[0]), float(frame.anchor[1]))
		sprite.position = state.position + lab.terrain.surface_visual_offset_at(state.position)
		sprite.z_index = 10 + floori(float(state.position.y) / 64.0)
		sprite.set_meta("vehicle_frame", key)
	_refresh_bolts()
	_refresh_ladders()
	_refresh_ship_loot()

# Original ship presenter: approved art over unchanged Transport pose/claims.
func _refresh_ship(identity: String, vehicle: Dictionary) -> void:
	var node: Node2D = _ship_nodes.get(identity)
	if int(vehicle.get("cell", -1)) < 0 or _ship_in_journey(identity):
		if node != null: node.visible = false
		return
	if node == null:
		node = Node2D.new()
		node.name = "Ship_" + identity.validate_node_name()
		node.set_meta("ship_debug_geometry", true)
		add_child(node)
		_ship_nodes[identity] = node
		_grey_polygon(node, "Hull", PackedVector2Array(), Color(0.29, 0.39, 0.47, 0.72))
		var status: Label = Label.new()
		status.name = "Status"
		status.add_theme_font_size_override("font_size", 13)
		node.add_child(status)
	node.visible = true
	_load_ship_art()
	if _ship_art_invalid:
		node.visible = false
		return
	var spec: Dictionary = Ship.definition(str(vehicle.ship_type))
	var formal: bool = _refresh_ship_art(identity, vehicle, node)
	if not formal:
		# Gray presentation exists only while original PNG/manifest is missing.
		var entry: Dictionary = _ship_art.get(str(vehicle.ship_type), {})
		if not entry.is_empty() and FileAccess.file_exists(SHIP_ASSETS + str(entry.get("source", ""))):
			_ship_art_invalid = true
			node.visible = false
			push_error("Malformed published ship frame/mask; retain original simulation")
			return
		var points: PackedVector2Array = PackedVector2Array()
		for local: Vector2 in [Vector2(-0.45, -0.45), Vector2(float(spec.width) - 0.55, -0.45), Vector2(float(spec.width) - 0.55, float(spec.length) - 1.0), Vector2(float(spec.width - 1) * 0.5, float(spec.length) - 0.55), Vector2(-0.45, float(spec.length) - 1.0)]:
			points.append(lab.site_controller.vehicles.ship_local_ground(vehicle, local))
		(node.get_node("Hull") as Polygon2D).polygon = points
		(node.get_node("Hull") as Polygon2D).visible = true
		node.set_meta("ship_debug_geometry", true)
		node.set_meta("ship_formal_art", false)
		for name_value: String in ["Body", "Foreground", "TurnBody", "TurnForeground"]:
			var old_sprite: Sprite2D = node.get_node_or_null(name_value)
			if old_sprite != null: old_sprite.visible = false
	node.z_index = 1
	var label: Label = node.get_node("Status")
	label.position = lab.site_controller.vehicles.ship_local_ground(vehicle, Vector2.ZERO) + Vector2(0, 18)
	label.text = "船 #%s · %s\n人 %d/%d · 物 %.2f/%d" % [identity, vehicle.ship_type,
		lab.site_controller.vehicles.ship_people(vehicle).size(), int(spec.max_people),
		lab.site_controller.vehicles.ship_load(identity), int(spec.capacity)]
	label.z_index = 200

func _refresh_ship_loot() -> void:
	var containers: Dictionary = lab.terrain.site.get("ground_loot", {})
	for identity: String in _ship_loot_nodes.keys():
		if not containers.has(identity) or not containers[identity].has("vehicle_id"):
			_ship_loot_nodes[identity].queue_free()
			_ship_loot_nodes.erase(identity)
	for identity: String in containers:
		var container: Dictionary = containers[identity]
		if not container.has("vehicle_id"): continue
		var boat: Dictionary = lab.terrain.site.get("vehicles", {}).get(str(container.get("vehicle_id", "")), {})
		if boat.is_empty() or int(boat.get("cell", -1)) < 0 or _ship_in_journey(str(boat.get("id", ""))):
			if _ship_loot_nodes.has(identity): _ship_loot_nodes[identity].visible = false
			continue
		var point: Vector2 = lab.site_controller.vehicles.ship_loot_ground(container)
		if point.x < 0.0:
			if _ship_loot_nodes.has(identity): _ship_loot_nodes[identity].visible = false
			continue
		var node: Node2D = _ship_loot_nodes.get(identity)
		if node == null:
			node = Node2D.new()
			node.name = "ShipLoot_" + identity.validate_node_name()
			add_child(node)
			_ship_loot_nodes[identity] = node
			_grey_polygon(node, "OriginalLoot", PackedVector2Array([Vector2(-6, -4), Vector2(6, -4), Vector2(6, 4), Vector2(-6, 4)]), Color(0.83, 0.68, 0.35))
			node.set_meta("container_id", identity)
		node.visible = true
		node.position = point
		node.z_index = 10 + floori(point.y / TerrainRenderer.CELL_PIXELS)

func _grey_polygon(parent: Node2D, name_value: String, points: PackedVector2Array, color: Color) -> Polygon2D:
	var shape := Polygon2D.new()
	shape.name = name_value
	shape.polygon = points
	shape.color = color
	parent.add_child(shape)
	return shape

func _load_siege_art() -> void:
	if not _siege_art.is_empty(): return
	var path := SIEGE_ASSETS + "siege_art.json"
	if not FileAccess.file_exists(path):
		push_error("Missing approved siege art manifest: " + path)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary or int(manifest.get("schema_version", 0)) != 1:
		push_error("Invalid siege art manifest")
		return
	_siege_art = manifest.get("entries", {})
	_bolt_texture = load(SIEGE_ASSETS + "siege_bolt.png") as Texture2D
	var bolt: Dictionary = manifest.get("bolt", {})
	var rect: Array = bolt.get("region", [])
	if rect.size() == 4: _bolt_region = _siege_rect(rect)
	var stone: Dictionary = manifest.get("stone", {})
	if stone.has("source"):
		_stone_texture = load(SIEGE_ASSETS + str(stone.source)) as Texture2D
		_stone_region = _siege_rect(stone.region)
	var rope: Dictionary = manifest.get("turn_rope", {})
	if rope.has("source"):
		_rope_texture = load(SIEGE_ASSETS + str(rope.source)) as Texture2D
		_rope_region = _siege_rect(rope.region)

func _siege_rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))

func siege_art_frame(kind: String, facing: Vector2i, state: String = "") -> Dictionary:
	_load_siege_art()
	var direction := "down"
	if facing.x < 0: direction = "left"
	elif facing.x > 0: direction = "right"
	elif facing.y < 0: direction = "up"
	var key := kind + "/" + direction + ("/" + state if not state.is_empty() else "")
	if _siege_frames.has(key): return _siege_frames[key]
	var definition: Dictionary = _siege_art.get(kind, {})
	var frame: Dictionary = definition.get("states", {}).get(state, {}).get("frames", {}).get(direction, {}) if not state.is_empty() else {}
	if frame.is_empty(): frame = definition.get("frames", {}).get(direction, {})
	if frame.is_empty(): return {}
	var source: String = SIEGE_ASSETS + str(frame.get("source", definition.get("source", "")))
	var texture: Texture2D = _siege_textures.get(source)
	if texture == null:
		texture = load(source) as Texture2D
		if texture == null: return {}
		_siege_textures[source] = texture
	var exclusions: Array[Rect2] = []
	for rect: Array in frame.get("exclude_rects", []): exclusions.append(_siege_rect(rect))
	var reference: Array = definition.get("reference_region", [0, 0, 0, 0])
	var point: Array = frame.pivot
	var result := {"texture": texture, "region": _siege_rect(frame.region),
		"pivot": Vector2(float(point[0]), float(point[1])), "scale": float(frame.scale),
		"direction": direction, "state": state, "source": source, "exclusions": exclusions,
		"reference_region": _siege_rect(reference),
		"image_size": Vector2i(texture.get_width(), texture.get_height()),
		"scale_xy": Vector2(float(frame.get("scale_xy", [frame.scale, frame.scale])[0]), float(frame.get("scale_xy", [frame.scale, frame.scale])[1])),
		"parts": frame.get("parts", {}), "deck_region": _siege_rect(frame.get("deck_region", [0, 0, 0, 0])),
		"deck_height_pixels": float(frame.get("deck_height_pixels", 0))}
	if frame.has("muzzle"): result.muzzle = Vector2(float(frame.muzzle[0]), float(frame.muzzle[1]))
	for attachment: String in ["lower_attachment", "upper_attachment"]:
		if frame.has(attachment): result[attachment] = Vector2(float(frame[attachment][0]), float(frame[attachment][1]))
	_siege_frames[key] = result
	return result

func _set_siege_sprite(sprite: Sprite2D, kind: String, facing: Vector2i, state: String = "") -> bool:
	var frame := siege_art_frame(kind, facing, state)
	if frame.is_empty(): return false
	var key := kind + "/" + str(frame.direction) + ("/" + state if not state.is_empty() else "")
	return _set_siege_frame(sprite, frame, key)

func _set_siege_frame(sprite: Sprite2D, frame: Dictionary, key: String) -> bool:
	if frame.is_empty(): return false
	if str(sprite.get_meta("siege_art_frame", "")) == key: return true
	sprite.texture = frame.texture
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	sprite.region_rect = frame.region
	sprite.centered = false
	sprite.offset = -frame.pivot
	sprite.scale = frame.get("scale_xy", Vector2.ONE * float(frame.scale))
	sprite.rotation = 0.0
	sprite.set_meta("siege_art_frame", key)
	sprite.set_meta("siege_art_exclusions", frame.exclusions)
	if frame.exclusions.is_empty():
		sprite.material = null
	else:
		var mask := ShaderMaterial.new()
		mask.shader = SiegeMask
		var size: Vector2 = Vector2(frame.image_size)
		for index in range(frame.exclusions.size()):
			var rect: Rect2 = frame.exclusions[index]
			mask.set_shader_parameter("exclude_%d" % index,
				Vector4(rect.position.x / size.x, rect.position.y / size.y, rect.end.x / size.x, rect.end.y / size.y))
		sprite.material = mask
	return true

func show_pure_preview(kind: String, facing: Vector2i, parent: Node2D, point: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	if not _set_siege_sprite(sprite, kind, facing):
		sprite.free()
		return null
	parent.add_child(sprite)
	sprite.position = point
	return sprite

func _refresh_ballista(identity: String, vehicle: Dictionary) -> void:
	# All five vehicle kinds share the original record and presenter lifecycle.
	var kind := str(vehicle.kind)
	var spec: Dictionary = SiteRuntime.SIEGE_DEFINITIONS.get(kind, {})
	if spec.is_empty(): return
	var node: Node2D = _siege_nodes.get(identity)
	if node == null:
		node = Node2D.new()
		node.name = "Siege_" + identity.validate_node_name()
		add_child(node)
		_siege_nodes[identity] = node
		for name_value: String in ["Body", "TurnTarget"]:
			var sprite := Sprite2D.new()
			sprite.name = name_value
			node.add_child(sprite)
		node.set_meta("siege_generated_art", true)
	var render: Dictionary = lab.site_controller.vehicles.render_state(vehicle)
	var facing: Vector2i = render.facing
	var state := "wrecked" if float(vehicle.hp) <= 0.0 else ("damaged" if float(vehicle.hp) < float(spec.max_hp) * 0.5 else "")
	if kind == "siege_tower" and state.is_empty() and vehicle.get("deployed_pose", {}).is_empty(): state = "mobile"
	if kind == "siege_tower" and not vehicle.get("deployed_pose", {}).is_empty():
		var tower_geometry: Dictionary = SiteRuntime.siege_tower_geometry(lab.terrain, vehicle)
		if not bool(tower_geometry.support_valid) or str(vehicle.phase) == "disabled": state = "wrecked"
	# Damage changes colour, preserving the approved normal footprint/heading.
	# A mobile tower keeps its original mobile body; wrecks retain collapsed art.
	var art_state: String = state
	if state == "damaged":
		art_state = "mobile" if kind == "siege_tower" and vehicle.get("deployed_pose", {}).is_empty() else ""
	var body: Sprite2D = node.get_node("Body")
	var next: Sprite2D = node.get_node("TurnTarget")
	if not _set_siege_sprite(body, kind, facing, art_state): return
	node.rotation = 0.0
	body.modulate = Color.WHITE
	next.visible = false
	var direction := Vector2(facing)
	var action: Dictionary = vehicle.get("action", {})
	if str(action.get("stage", "")) == "rotate":
		var target := Vector2i(int(action.facing[0]), int(action.facing[1]))
		var progress := clampf(float(action.elapsed) / float(spec.turn_seconds), 0.0, 1.0)
		direction = Vector2.from_angle(lerp_angle(Vector2(facing).angle(), Vector2(target).angle(), progress))
		if _set_siege_sprite(next, kind, target, art_state):
			next.visible = true
			next.modulate = Color(1.0, 1.0, 1.0, progress)
			body.modulate.a = 1.0 - progress
	var size: Vector2i = spec.size
	var centre := (direction * float(size.y - 1) + Vector2(-direction.y, direction.x) * float(size.x - 1)) * TerrainRenderer.CELL_PIXELS * 0.5
	body.position = centre
	next.position = centre
	var ground: Vector2 = render.position
	# A deployed top does not lift its own wheeled foundation into the air.
	var cell: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var base := int(lab.terrain.height_levels[lab.terrain.index(cell)]) if kind == "siege_tower" else int(lab.terrain.effective_height(cell))
	node.position = ground - Vector2(0, 48.0 * base)
	node.z_index = 10 + floori(ground.y / TerrainRenderer.CELL_PIXELS)
	node.modulate = Color(0.65, 0.75, 0.85, 0.65) if str(vehicle.phase) == "building" else (DAMAGED_TINT if state == "damaged" else Color.WHITE)
	node.set_meta("siege_art_direction", str(siege_art_frame(kind, facing, art_state).direction))
	node.set_meta("siege_art_state", state)
	if kind == "siege_tower":
		var lowest_row := cell.y
		for physical: Vector2i in SiteRuntime.siege_tower_physical_cells(lab.terrain, vehicle): lowest_row = mini(lowest_row, physical.y)
		node.z_index = 9 + lowest_row
	_refresh_tower_parts(node, vehicle, facing, state)
	_refresh_ram_mechanism(node, vehicle, facing, state)
	_refresh_turn_ropes(node, vehicle)

func _component_art_frame(raw: Dictionary) -> Dictionary:
	if raw.is_empty(): return {}
	var source := SIEGE_ASSETS + str(raw.source)
	var texture: Texture2D = _siege_textures.get(source)
	if texture == null:
		texture = load(source) as Texture2D
		if texture == null: return {}
		_siege_textures[source] = texture
	var exclusions: Array[Rect2] = []
	for rect: Array in raw.get("exclude_rects", []): exclusions.append(_siege_rect(rect))
	var scale_values: Array = raw.get("scale_xy", [raw.scale, raw.scale])
	return {"texture": texture, "region": _siege_rect(raw.region), "pivot": Vector2(float(raw.pivot[0]), float(raw.pivot[1])),
		"scale": float(raw.scale), "scale_xy": Vector2(float(scale_values[0]), float(scale_values[1])),
		"exclusions": exclusions, "image_size": Vector2i(texture.get_width(), texture.get_height())}

func _siege_part_sprite(node: Node2D, name_value: String) -> Sprite2D:
	var sprite: Sprite2D = node.get_node_or_null(name_value)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = name_value
		sprite.set_meta("siege_generated_art", true)
		node.add_child(sprite)
	return sprite

func _refresh_tower_parts(node: Node2D, vehicle: Dictionary, facing: Vector2i, state: String) -> void:
	for name_value: String in ["Bridge", "Entry0", "Entry1"]:
		var old: Sprite2D = node.get_node_or_null(name_value)
		if old != null: old.visible = false
	if str(vehicle.kind) != "siege_tower" or state == "wrecked": return
	var action: Dictionary = vehicle.get("action", {})
	var stage := str(action.get("stage", ""))
	var progress := 1.0 if not vehicle.get("deployed_pose", {}).is_empty() else 0.0
	if stage == "tower_deploy": progress = clampf(float(action.elapsed) / 15.0, 0.0, 1.0)
	elif stage == "tower_retract": progress = 1.0 - clampf(float(action.elapsed) / 10.0, 0.0, 1.0)
	if progress <= 0.0: return
	# A local pure-query candidate exposes planned cells during the original
	# timed deployment; it never publishes navigation before the real commit.
	var query: Dictionary = vehicle
	if query.get("deployed_pose", {}).is_empty():
		query = vehicle.duplicate(true)
		query.deployed_pose = SiteRuntime.siege_tower_pose(lab.terrain, vehicle)
		query.phase = "deployed"
	var geometry: Dictionary = SiteRuntime.siege_tower_geometry(lab.terrain, query)
	if not bool(geometry.support_valid) or geometry.entry.size() != 2 or geometry.bridge.size() != 3: return
	var frame: Dictionary = siege_art_frame("siege_tower", facing)
	var base := int(query.deployed_pose.level)
	for index in range(3):
		var part := "bridge" if index == 0 else "entry_%d" % (index - 1)
		var raw: Dictionary = frame.get("parts", {}).get(part, {})
		var sprite := _siege_part_sprite(node, "Bridge" if index == 0 else "Entry%d" % (index - 1))
		if not _set_siege_frame(sprite, _component_art_frame(raw), "tower/" + str(frame.direction) + "/" + state + "/" + part): continue
		var anchor: Vector2 = Vector2(geometry.bridge[1] if index == 0 else geometry.entry[index - 1])
		var height: int = int(geometry.heights[lab.terrain.index(Vector2i(anchor))])
		sprite.position = (anchor + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, height * 48.0) - node.position
		if index > 0:
			# Each generated stair includes its ramp and original upper landing.
			# DOWN needs the 64px landing; the other projected ramps remain 112px.
			var previous: Vector2i = Vector2i(anchor) - facing
			var lower_height: int = int(geometry.heights.get(lab.terrain.index(previous), base))
			var rise: int = height - lower_height
			var projected_depth: float = absf(float(facing.x) * TerrainRenderer.CELL_PIXELS) + absf(float(facing.y) * TerrainRenderer.CELL_PIXELS - float(rise) * 48.0)
			if facing == Vector2i.DOWN: projected_depth = TerrainRenderer.CELL_PIXELS
			sprite.scale.y = projected_depth / sprite.region_rect.size.y
			if facing != Vector2i.DOWN: sprite.position.y += float(rise) * 24.0
		sprite.visible = true
		sprite.modulate = Color(1, 1, 1, progress)
		sprite.set_meta("original_surface_cell", Vector2i(anchor))
		sprite.set_meta("original_surface_height", height)
		sprite.set_meta("original_deploy_progress", progress)

func _refresh_ram_mechanism(node: Node2D, vehicle: Dictionary, facing: Vector2i, state: String) -> void:
	var old: Sprite2D = node.get_node_or_null("RamBeam")
	if old != null: old.visible = false
	if str(vehicle.kind) != "ram" or state == "wrecked": return
	var direction := str(siege_art_frame("ram", facing).direction)
	var components: Dictionary = _siege_art.get("ram", {}).get("components", {})
	var chassis: Dictionary = components.get("chassis", {}).get("frames", {}).get(direction, {})
	var timber: Dictionary = components.get("beam", {}).get("frames", {}).get(direction, {})
	if chassis.is_empty() or timber.is_empty(): return
	var body: Sprite2D = node.get_node("Body")
	if not _set_siege_frame(body, _component_art_frame(chassis), "ram/chassis/" + direction): return
	var beam := _siege_part_sprite(node, "RamBeam")
	if not _set_siege_frame(beam, _component_art_frame(timber), "ram/beam/" + direction): return
	var action: Dictionary = vehicle.get("action", {})
	var stage := str(action.get("stage", ""))
	var multiplier := maxf(0.000001, float(action.get("multiplier", 1.0)))
	var fraction := 0.0
	if stage == "preparing": fraction = -0.35 * sin(clampf(float(action.elapsed) * multiplier / 2.0, 0.0, 1.0) * PI * 0.5)
	elif stage == "collision": fraction = clampf(float(action.elapsed) * multiplier / 0.25, 0.0, 1.0)
	elif stage == "recovering": fraction = 1.0 - clampf(float(action.elapsed) * multiplier / 0.75, 0.0, 1.0)
	# This is the same contact-head centre used by TerrainLab._siege_ram_shapes.
	var heading := Vector2(facing)
	# Body already follows the original Transport interpolation; the beam must
	# share that same frame while translating or cross-fading a committed turn.
	beam.position = body.position + heading * (1.5 + fraction) * TerrainRenderer.CELL_PIXELS - Vector2(0, 48)
	beam.visible = true
	beam.modulate = body.modulate
	beam.set_meta("original_collision_fraction", fraction)
	beam.set_meta("original_contact_center", node.position + beam.position)

func _refresh_turn_ropes(node: Node2D, vehicle: Dictionary) -> void:
	var holder: Node2D = node.get_node_or_null("TurnRopes")
	if holder == null:
		holder = Node2D.new()
		holder.name = "TurnRopes"
		node.add_child(holder)
	holder.visible = _rope_texture != null and str(vehicle.get("action", {}).get("stage", "")) in ["approach", "rotate"]
	if not holder.visible: return
	var contacts := SiteRuntime.siege_turn_contacts(lab.terrain, vehicle)
	while holder.get_child_count() < contacts.size():
		var rope := Sprite2D.new()
		rope.texture = _rope_texture
		rope.region_enabled = true
		rope.region_filter_clip_enabled = true
		rope.region_rect = _rope_region
		rope.set_meta("siege_generated_rope", true)
		holder.add_child(rope)
	for index in range(holder.get_child_count()):
		var rope: Sprite2D = holder.get_child(index)
		rope.visible = index < contacts.size() and vehicle.crew_slots.has(str(index))
		if not rope.visible: continue
		var contact: Dictionary = contacts[index]
		var person: Dictionary = lab.site_controller.person_actions._person(int(vehicle.crew_slots[str(index)]))
		rope.visible = not person.is_empty() and person.cell == contact.station and person.get("moving_to", TerrainArmy.INVALID_CELL) == TerrainArmy.INVALID_CELL
		if not rope.visible: continue
		var start: Vector2 = (Vector2(contact.station) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS + lab.terrain.surface_visual_offset(contact.station) - Vector2(0, 24)
		var end: Vector2 = contact.attachment * TerrainRenderer.CELL_PIXELS + lab.terrain.surface_visual_offset_at(contact.attachment * TerrainRenderer.CELL_PIXELS) - Vector2(0, 24)
		rope.position = (start + end) * 0.5 - node.position
		rope.rotation = (end - start).angle()
		rope.scale = Vector2(start.distance_to(end) / _rope_region.size.x, 4.0 / _rope_region.size.y)

func _refresh_ladders() -> void:
	var features: Dictionary = lab.terrain.site.get("features", {})
	var live := {}
	for identity: String in features:
		var feature: Dictionary = features[identity]
		if str(feature.kind) != "siege_ladder": continue
		live[identity] = true
		var sprite: Sprite2D = _ladder_nodes.get(identity)
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.name = "SiegeLadder_" + identity.validate_node_name()
			add_child(sprite)
			_ladder_nodes[identity] = sprite
		var geometry: Dictionary = SiteRuntime.feature_geometry(lab.terrain, feature)
		if not geometry.has("stair_lower") or not geometry.has("stair_upper"): continue
		var facing: Vector2i = geometry.stair_upper.cell - geometry.stair_lower.cell
		var broken := false
		var damaged := false
		for part: Dictionary in geometry.parts.values():
			if float(part.hp) <= 0.0: broken = true
			elif float(part.hp) < float(part.max_hp) * 0.5: damaged = true
		var state := "wrecked" if broken else (("damaged" if damaged else "") if str(feature.get("ladder", {}).get("phase", "folded")) == "deployed" else "folded")
		var art_state: String = "" if state == "damaged" else state
		if not _set_siege_sprite(sprite, "siege_ladder", facing, art_state): continue
		var anchor: Vector2i = geometry.stair_lower.cell
		var ground := (Vector2(anchor) + Vector2.ONE * 0.5 + Vector2(facing) * 0.5) * TerrainRenderer.CELL_PIXELS
		sprite.position = ground - Vector2(0, 48.0 * int(feature.get("level", 0)))
		if state.is_empty() or state == "damaged":
			var frame: Dictionary = siege_art_frame("siege_ladder", facing, art_state)
			if frame.has("lower_attachment") and frame.has("upper_attachment"):
				# Only this generated Sprite maps its toe/hook to the original
				# navigable entry and upper platform. No surface or person moves.
				var low: Vector2 = (Vector2(geometry.external_lower.cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, int(geometry.external_lower.height) * 48.0)
				var high: Vector2 = (Vector2(geometry.stair_upper.cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, int(geometry.stair_upper.height) * 48.0)
				# The hook bears on the neighbouring wall near edge, half a cell
				# beyond the unchanged upper navigation centre at the same height.
				var painted_hook: Vector2 = high + Vector2(facing) * TerrainRenderer.CELL_PIXELS * 0.5
				var delta: Vector2 = painted_hook - low
				var source_delta: Vector2 = frame.upper_attachment - frame.lower_attachment
				var projected_scale: Vector2 = frame.scale_xy
				if absf(source_delta.x) > 0.01: projected_scale.x = delta.x / source_delta.x
				elif absf(delta.x) > 0.01: continue
				if absf(source_delta.y) > 0.01: projected_scale.y = delta.y / source_delta.y
				elif absf(delta.y) > 0.01: continue
				if projected_scale.x <= 0.0 or projected_scale.y <= 0.0: continue
				sprite.scale = projected_scale
				sprite.position = low - (frame.lower_attachment - frame.pivot) * projected_scale
		sprite.z_index = 10 + floori(ground.y / TerrainRenderer.CELL_PIXELS)
		if state.is_empty() or state == "damaged":
			# Original people sort by ground row; both true ladder endpoints bound its own walkers.
			sprite.z_index = 10 + mini(geometry.external_lower.cell.y, geometry.external_upper.cell.y)
		sprite.modulate = Color(0.65, 0.75, 0.85, 0.65) if str(feature.stage) == "building" else (DAMAGED_TINT if damaged and not broken else Color.WHITE)
	for identity: String in _ladder_nodes.keys():
		if not live.has(identity):
			_ladder_nodes[identity].queue_free()
			_ladder_nodes.erase(identity)

func _refresh_bolts() -> void:
	var flights: Variant = lab.get("siege_projectiles")
	if not flights is Array: return
	var live := {}
	for flight: Dictionary in flights:
		var stone := str(flight.get("rule", {}).get("projectile", "bolt")) == "stone"
		var texture := _stone_texture if stone else _bolt_texture
		var region := _stone_region if stone else _bolt_region
		if texture == null or not region.has_area(): continue
		var identity := str(flight.attack_id)
		live[identity] = true
		var bolt: Sprite2D = _bolt_nodes.get(identity)
		if bolt == null:
			bolt = Sprite2D.new()
			bolt.name = "SiegeStone" if stone else "HeavyBolt"
			bolt.texture = texture
			bolt.region_enabled = true
			bolt.region_filter_clip_enabled = true
			bolt.region_rect = region
			bolt.centered = false
			bolt.offset = -region.size * 0.5
			bolt.set_meta("siege_generated_stone" if stone else "siege_generated_bolt", true)
			add_child(bolt)
			_bolt_nodes[identity] = bolt
		var size := Vector2(128.0, 160.0) * float(flight.rule.radius_cells) if stone else Vector2(12.0, 6.0)
		bolt.scale = size / region.size
		bolt.position = flight.position
		bolt.rotation = 0.0 if stone else (flight.screen_goal - flight.screen_origin).angle()
		bolt.z_index = 12 + floori(float(flight.position.y) / TerrainRenderer.CELL_PIXELS)
	for identity: String in _bolt_nodes.keys():
		if not live.has(identity):
			_bolt_nodes[identity].queue_free()
			_bolt_nodes.erase(identity)

func _process(_delta: float) -> void:
	refresh()

func _load_ship_art() -> void:
	if not _ship_art.is_empty() or _ship_art_invalid: return
	var path: String = SHIP_ASSETS + "ship_art.json"
	if not FileAccess.file_exists(path): return # Known original gray geometry fallback.
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or int(value.get("schema_version", 0)) != 1 or int(value.get("definition_version", 0)) != Ship.VERSION or not value.get("entries") is Dictionary or value.entries.size() != Ship.KINDS.size():
		_ship_art_invalid = true
		push_error("Invalid formal ship art manifest; preserve original scene and assets")
		return
	var shader_path: String = SHIP_ASSETS + "ship_art_mask.gdshader"
	if not FileAccess.file_exists(shader_path):
		_ship_art_invalid = true
		push_error("Missing formal ship front-rail mask")
		return
	var shader: Shader = load(shader_path) as Shader
	if shader == null:
		_ship_art_invalid = true
		push_error("Invalid formal ship front-rail shader")
		return
	var entries: Dictionary = value.entries
	for kind: String in Ship.KINDS:
		var entry: Variant = entries.get(kind)
		var spec: Dictionary = Ship.definition(kind)
		var hull_metres: Variant = entry.get("hull_metres") if entry is Dictionary else null
		if not entry is Dictionary or entry.is_empty() or not hull_metres is Array or hull_metres.size() != 2 \
			or (not hull_metres[0] is int and not hull_metres[0] is float) or (not hull_metres[1] is int and not hull_metres[1] is float) \
			or float(hull_metres[0]) != float(int(spec.width) * 2) or float(hull_metres[1]) != float(int(spec.length) * 2) \
			or not entry.get("frames") is Dictionary or entry.frames.size() != 4:
			_ship_art_invalid = true
			push_error("Formal ship manifest does not retain all original hulls and directions: " + kind)
			return
	_ship_art_shader = shader
	_ship_art = entries

func ship_art_frame(kind: String, facing: Vector2i) -> Dictionary:
	_load_ship_art()
	var direction: String = "down"
	if facing.x < 0: direction = "left"
	elif facing.x > 0: direction = "right"
	elif facing.y < 0: direction = "up"
	var key: String = kind + "/" + direction
	if _ship_art_frames.has(key): return _ship_art_frames[key]
	var definition: Dictionary = _ship_art.get(kind, {})
	var frame: Dictionary = definition.get("frames", {}).get(direction, {})
	if frame.is_empty(): return {}
	var name_value: String = str(definition.get("source", ""))
	if name_value.get_file() != name_value or not name_value.ends_with(".png"): return {}
	var source: String = SHIP_ASSETS + name_value
	if not FileAccess.file_exists(source): return {}
	var texture: Texture2D = _ship_art_textures.get(source)
	if texture == null:
		texture = load(source) as Texture2D
		if texture == null: return {}
		var size_values: Variant = definition.get("source_size")
		if not size_values is Array or size_values.size() != 2 \
			or (not size_values[0] is int and not size_values[0] is float) or (not size_values[1] is int and not size_values[1] is float) \
			or float(size_values[0]) != float(texture.get_width()) or float(size_values[1]) != float(texture.get_height()) \
			or FileAccess.get_sha256(source).to_upper() != str(definition.get("source_sha256", "")):
			_ship_art_invalid = true
			push_error("Formal ship PNG differs from the approved unchanged source: " + kind)
			return {}
		_ship_art_textures[source] = texture
	var region_values: Array = frame.get("region", [])
	var reference_values: Array = frame.get("reference_region", [])
	if region_values.size() != 4 or reference_values.size() != 4: return {}
	var region: Rect2 = _siege_rect(region_values)
	var reference: Rect2 = _siege_rect(reference_values)
	if not region.has_area() or not reference.has_area() or not Rect2(Vector2.ZERO, Vector2(texture.get_width(), texture.get_height())).encloses(region) or not region.encloses(reference): return {}
	var polygons: Array = frame.get("front_occluders", [])
	if polygons.is_empty() or polygons.size() > 4: return {}
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(64)
	for polygon_index: int in polygons.size():
		var polygon: Variant = polygons[polygon_index]
		if not polygon is Array or polygon.size() < 3 or polygon.size() > 16: return {}
		counts[polygon_index] = polygon.size()
		for vertex: int in polygon.size():
			var values: Variant = polygon[vertex]
			if not values is Array or values.size() != 2: return {}
			var point: Vector2 = Vector2(float(values[0]), float(values[1]))
			if not point.is_finite() or point.x < region.position.x or point.y < region.position.y or point.x > region.end.x or point.y > region.end.y: return {}
			points[polygon_index * 16 + vertex] = point
	var materials: Array[ShaderMaterial] = []
	for foreground: bool in [false, true]:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = _ship_art_shader
		mat.set_shader_parameter("sheet_size", Vector2(texture.get_width(), texture.get_height()))
		mat.set_shader_parameter("polygon_counts", counts)
		mat.set_shader_parameter("polygon_points", points)
		mat.set_shader_parameter("foreground", foreground)
		materials.append(mat)
	var result: Dictionary = {"texture": texture, "region": region, "reference_region": reference,
		"body_material": materials[0], "front_material": materials[1], "direction": direction,
		"source": source, "source_sha256": str(definition.get("source_sha256", "")), "front_occluders": polygons}
	_ship_art_frames[key] = result
	return result

func _ship_in_journey(identity: String) -> bool:
	return lab != null and lab.site_controller != null and lab.site_controller.has_method("ship_vehicle_in_journey") and bool(lab.site_controller.call("ship_vehicle_in_journey", identity))

func _ship_pose_rectangle(kind: String, pose: Dictionary) -> Rect2:
	var spec: Dictionary = Ship.definition(kind)
	var direction: Vector2 = pose.direction
	var right: Vector2 = Vector2(-direction.y, direction.x)
	var pivot: Vector2 = Vector2(pose.anchor) + Vector2.ONE * 0.5
	var minimum: Vector2 = pivot
	var maximum: Vector2 = pivot
	for local: Vector2 in [Vector2(-0.5, -0.5), Vector2(float(spec.width) - 0.5, -0.5), Vector2(float(spec.width) - 0.5, float(spec.length) - 0.5), Vector2(-0.5, float(spec.length) - 0.5)]:
		var point: Vector2 = pivot + right * local.x + direction * local.y
		minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
		maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))
	# True outside corners rotate with people; cardinal extents retain full cells.
	return Rect2(minimum * TerrainRenderer.CELL_PIXELS, (maximum - minimum) * TerrainRenderer.CELL_PIXELS)

func _ship_art_sprite(node: Node2D, name_value: String) -> Sprite2D:
	var sprite: Sprite2D = node.get_node_or_null(name_value)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = name_value
		sprite.texture_filter = Contract.TEXTURE_FILTER
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_filter_clip_enabled = true
		sprite.z_as_relative = false
		node.add_child(sprite)
	return sprite

func _set_ship_art(sprite: Sprite2D, frame: Dictionary, kind: String, pose: Dictionary, rectangle: Rect2, surface: Vector2, foreground: bool, weight: float) -> void:
	var reference: Rect2 = frame.reference_region
	var region: Rect2 = frame.region
	var facing: Vector2 = Vector2.DOWN
	match str(frame.direction):
		"up": facing = Vector2.UP
		"right": facing = Vector2.RIGHT
		"left": facing = Vector2.LEFT
	var source_rectangle: Rect2 = _ship_pose_rectangle(kind, {"anchor":Vector2.ZERO, "direction":facing})
	var scale_value: Vector2 = source_rectangle.size / reference.size
	var reference_pivot: Vector2 = reference.position + (Vector2.ONE * 0.5 * TerrainRenderer.CELL_PIXELS - source_rectangle.position) / scale_value
	var rotation_value: float = facing.angle_to(Vector2(pose.direction))
	var pivot: Vector2 = (Vector2(pose.anchor) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS + surface
	sprite.texture = frame.texture
	sprite.region_rect = region
	sprite.scale = scale_value
	sprite.position = pivot - ((reference_pivot - region.position) * scale_value).rotated(rotation_value)
	sprite.offset = Vector2.ZERO
	sprite.rotation = rotation_value # Only the difference from this actual source pose.
	sprite.material = frame.front_material if foreground else frame.body_material
	sprite.modulate = Color(1, 1, 1, weight)
	sprite.z_index = 12 + floori(rectangle.end.y / TerrainRenderer.CELL_PIXELS) if foreground else 1
	sprite.visible = weight > 0.0
	sprite.set_meta("ship_art_frame", frame.direction)
	sprite.set_meta("ship_art_source", frame.source)
	sprite.set_meta("ship_art_role", "foreground" if foreground else "hull")

func _refresh_ship_art(_identity: String, vehicle: Dictionary, node: Node2D) -> bool:
	_load_ship_art()
	if _ship_art.is_empty(): return false
	var facing: Vector2i = Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var frame: Dictionary = ship_art_frame(str(vehicle.ship_type), facing)
	if frame.is_empty(): return false
	var pose: Dictionary = lab.site_controller.vehicles.ship_render_pose(vehicle)
	var rectangle: Rect2 = _ship_pose_rectangle(str(vehicle.ship_type), pose)
	var ground: Vector2 = (Vector2(pose.anchor) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	var surface: Vector2 = lab.terrain.surface_visual_offset_at(ground)
	rectangle.position += surface
	var next: Dictionary = {}
	var blend: float = 0.0
	var move: Dictionary = vehicle.get("move", {})
	if not move.is_empty():
		var target: Vector2i = Vector2i(int(move.facing[0]), int(move.facing[1]))
		if target != facing:
			next = ship_art_frame(str(vehicle.ship_type), target)
			if not next.is_empty(): blend = float(pose.progress)
	_set_ship_art(_ship_art_sprite(node, "Body"), frame, str(vehicle.ship_type), pose, rectangle, surface, false, 1.0 - blend)
	_set_ship_art(_ship_art_sprite(node, "Foreground"), frame, str(vehicle.ship_type), pose, rectangle, surface, true, 1.0 - blend)
	var target_body: Sprite2D = _ship_art_sprite(node, "TurnBody")
	var target_front: Sprite2D = _ship_art_sprite(node, "TurnForeground")
	target_body.visible = false
	target_front.visible = false
	if not next.is_empty():
		_set_ship_art(target_body, next, str(vehicle.ship_type), pose, rectangle, surface, false, blend)
		_set_ship_art(target_front, next, str(vehicle.ship_type), pose, rectangle, surface, true, blend)
	(node.get_node("Hull") as Polygon2D).visible = false
	node.set_meta("ship_debug_geometry", false)
	node.set_meta("ship_formal_art", true)
	node.set_meta("ship_footprint_rectangle", rectangle)
	node.set_meta("ship_art_blend", blend)
	return true

