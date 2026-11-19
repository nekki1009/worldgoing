extends SceneTree
## GPU admission and real preparation wait loops; no atlas images are fabricated.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const Editor = preload("res://scripts/ui/human_character_3d_editor.gd")
var checks := 0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("Atlas host lifetime deadline"); quit(1))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	assert(ok, message)

func _waiter(host: Node, appearance: Dictionary, crowd_entry: bool, state: Dictionary) -> void:
	state.started = true
	state.result = await Crowd.prepare_captivity_recipe(host, appearance) if crowd_entry else await Atlas.prepare_recipe(host, appearance)
	state.done = true

func _lost_host(appearance: Dictionary, crowd_entry: bool) -> void:
	var host := Node.new()
	var gate := Node.new() # Occupy the existing shared slot; no capture is published.
	root.add_child(host)
	root.add_child(gate)
	Atlas._preparation = gate
	var state := {"started": false, "done": false, "result": true}
	_waiter.call_deferred(host, appearance, crowd_entry, state)
	while not state.started: await process_frame
	check(not state.done, "Cold request waits for the occupied shared slot")
	gate.free()
	host.free()
	await process_frame
	check(state.done and not state.result, "Removed host completes as cancelled after the shared slot is released")
	check(not is_instance_valid(Atlas._preparation), "Removed host creates no orphan capture")
	Atlas._preparation = null

func _run() -> void:
	check(DisplayServer.get_name() != "headless", "Real GPU preparation admission required")
	var mixed := Editor.default_appearance(1)
	for slot: Dictionary in Editor.PART_SLOTS:
		if slot.id != "helmet": continue
		for part: Dictionary in slot.options:
			if part.get("material") == "steel" and part.get("culture") == "japanese": mixed.parts.helmet = str(part.id)
	check(not Atlas.mixed_plan(mixed).is_empty() and not Atlas.supports(mixed), "Valid uncached mixed appearance")
	await _lost_host(mixed, false)
	var legacy: Dictionary = Atlas._base.appearance.duplicate(true)
	check(Atlas.supports(legacy) and Atlas.mixed_recipe(legacy).is_empty(), "Existing legacy appearance needs a cold single-page crowd recipe")
	await _lost_host(legacy, true)
	print("ATLAS_PREPARATION_HOST_LIFETIME_PASS checks=", checks)
	quit(0)
