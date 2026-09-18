class_name SiteVehicleView
extends Node2D

## Presentation only. SiteVehicleTransport owns records, positions and movement.
const ASSETS := "res://assets/vehicles/logistics/v1/"
const Contract = preload("res://scripts/ui/character_render_contract.gd")
var lab: Node
var _atlas: Texture2D
var _frames: Dictionary = {}
var _scale := 1.0
var _sprites: Dictionary = {}

func setup(value: Node) -> void:
	lab = value
	texture_filter = Contract.TEXTURE_FILTER
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
	if lab == null or lab.terrain == null or _atlas == null: return
	var records: Dictionary = lab.terrain.site.get("vehicles", {})
	for identity: String in _sprites.keys():
		if not records.has(identity):
			_sprites[identity].queue_free()
			_sprites.erase(identity)
	for identity: String in records:
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
		sprite.position = state.position
		sprite.z_index = 10 + floori(sprite.position.y / 64.0)
		sprite.set_meta("vehicle_frame", key)

func _process(_delta: float) -> void:
	refresh()
