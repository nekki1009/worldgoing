extends SceneTree

const View = preload("res://scripts/terrain_lab/site_vehicle_view.gd")
const Contract = preload("res://scripts/ui/character_render_contract.gd")
const ASSETS := "res://assets/vehicles/logistics/v1/"

class FakeManager extends RefCounted:
	var phase := 0.0
	var moving := false
	var facing := Vector2i.DOWN
	func render_state(record: Dictionary) -> Dictionary:
		return {"position":Vector2(160, 224), "facing":facing, "moving":moving,
			"progress":phase, "kind":record.kind, "operator_id":1}
class FakeTerrain extends RefCounted:
	var site := {"vehicles":{"cart1":{"id":"cart1", "kind":"cart"}, "wagon1":{"id":"wagon1", "kind":"wagon"}}}
class FakeController extends RefCounted:
	var vehicles := FakeManager.new()
class FakeLab extends Node:
	var terrain := FakeTerrain.new()
	var site_controller := FakeController.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "vehicles_atlas.json"))
	var texture := load(ASSETS + "vehicles_atlas.res") as Texture2D
	var atlas := texture.get_image()
	assert(manifest.frames.size() == 72)
	assert(is_equal_approx(float(manifest.pixels_per_metre), Contract.MAP_PIXELS_PER_METRE))
	var keys: Dictionary = {}
	var phases: Dictionary = {}
	for frame: Dictionary in manifest.frames:
		var key := "%s/%s/%s/%d" % [frame.kind, frame.clip, frame.direction, int(frame.frame)]
		assert(not keys.has(key))
		keys[key] = true
		var rect := Rect2i(int(frame.rect[0]), int(frame.rect[1]), int(frame.rect[2]), int(frame.rect[3]))
		assert(Rect2i(Vector2i.ZERO, atlas.get_size()).encloses(rect))
		var picture := atlas.get_region(rect)
		assert(picture.get_used_rect().has_area())
		if frame.clip == "move":
			var group := "%s/%s" % [frame.kind, frame.direction]
			if not phases.has(group): phases[group] = {}
			phases[group][hash(picture.get_data())] = true
	for group: String in phases:
		assert(phases[group].size() >= 4, "Movement must contain real distinct wheel/horse poses: " + group)
	var lab := FakeLab.new()
	root.add_child(lab)
	var view := View.new()
	lab.add_child(view)
	view.setup(lab)
	assert(view._sprites.size() == 2)
	var original: Dictionary = lab.terrain.site.duplicate(true)
	for direction: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]:
		lab.site_controller.vehicles.facing = direction
		lab.site_controller.vehicles.moving = true
		for step in range(8):
			lab.site_controller.vehicles.phase = float(step) / 8.0
			view.refresh()
			for sprite: Sprite2D in view._sprites.values():
				assert(sprite.position == Vector2(160, 224))
				assert(sprite.z_index == 13)
				assert(str(sprite.get_meta("vehicle_frame")).ends_with("/%d" % step))
	assert(lab.terrain.site == original, "Rendering must never mutate records")
	lab.site_controller.vehicles.moving = false
	lab.site_controller.vehicles.phase = 0.9
	view.refresh()
	assert(view._sprites.cart1.get_meta("vehicle_frame") == "cart/idle/right/0")
	lab.terrain.site.vehicles.erase("cart1")
	view.refresh()
	assert(view._sprites.size() == 1)
	lab.free()
	print("SITE VEHICLE VIEW PASS frames=72 directions=4 immutable_records=true no_private_clock=true")
	quit(0)
