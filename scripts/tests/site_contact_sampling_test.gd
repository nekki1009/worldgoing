extends SceneTree

const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

class CountingGeometry extends Collision:
	var projections := 0
	var shields: Array[PackedVector2Array] = []
	var parry_shapes: Array[PackedVector2Array] = []
	func body_shapes(actor: Variant) -> Array[PackedVector2Array]:
		projections += 1
		return [capsule(actor.position, actor.position + Vector2(0, 5), 1.0)]
	func shield_shapes(_actor: Variant) -> Array[PackedVector2Array]:
		return shields
	func weapon_shapes(_actor: Variant, _clip: StringName, _parrying: bool = false) -> Array[PackedVector2Array]:
		return parry_shapes

class SamplingArmy extends TerrainArmy:
	var fixture: TerrainLab
	var previous: Array[PackedVector2Array]
	var current: Array[PackedVector2Array]
	var batches := 0
	var last_hits: Array[Dictionary]
	func sample_combat() -> void:
		batches += 1
		for attempt in range(8):
			last_hits = fixture._collect_unit_contacts(previous, current, Vector2i(10, 10), Vector2.ZERO, self, -1)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var lab := TerrainLab.new() # Do not construct the unrelated UI/renderer.
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "contact-sampling-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	lab.terrain = data
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.person_id = 1
	actor.data = data
	actor.terrain_cell = Vector2i(10, 10)
	lab.combat_actors.assign([actor])
	if DisplayServer.get_name() == "headless":
		check_batch_lifetime(lab, actor)
	else:
		actor.initialize_visual()
		actor.place(Vector2i(50, 50), true)
		actor.editor.set_playing(false)
		profile_live_geometry(lab, actor)
	lab.combat_armies.clear()
	lab.free()
	actor.queue_free()
	await process_frame
	print("SITE CONTACT SAMPLING PASS: exact hit results, batch-local geometry only; not a full battle/FPS benchmark")
	quit(0)

func check_batch_lifetime(lab: TerrainLab, actor: TerrainTestCharacter) -> void:
	var geometry := CountingGeometry.new()
	actor._geometry = geometry
	actor.position = Vector2(15, 0)
	var army := SamplingArmy.new()
	army.fixture = lab
	army.previous = [Collision.capsule(Vector2.ZERO, Vector2(0, 5), 1.0)]
	army.current = [Collision.capsule(Vector2(20, 0), Vector2(20, 5), 1.0)]
	lab.combat_armies.assign([army])
	var direct := lab._collect_unit_contacts(army.previous, army.current, Vector2i(10, 10), Vector2.ZERO, army, -1)
	assert(direct.size() == 1 and geometry.projections == 1)
	lab._advance_combat(1.0 / 120.0)
	assert(army.last_hits == direct and geometry.projections == 2, "Eight army queries must share exactly one projection")
	assert(not lab._sampling_army_contacts and lab._army_contact_geometry.is_empty(), "No geometry survives the collection phase")
	actor.position = Vector2(500, 0)
	lab._advance_combat(1.0 / 120.0)
	assert(army.last_hits.is_empty() and geometry.projections == 3, "A new step must observe movement")
	actor.position = Vector2(15, 0)
	assert(lab._collect_unit_contacts(army.previous, army.current, Vector2i(10, 10), Vector2.ZERO, army, -1) == direct)
	assert(geometry.projections == 4, "Calls outside the army batch must never use an old snapshot")
	var before := geometry.projections
	var old_batches := army.batches
	lab._advance_combat(0.05)
	assert(army.batches - old_batches >= 6 and geometry.projections - before == army.batches - old_batches, "Slow frames still refresh on every action substep")
	geometry.shields = [Collision.capsule(Vector2(5, 0), Vector2(5, 5), 1.0)]
	var pose := actor.incoming_geometry()
	var shield_hit := actor.incoming_contact(army.previous, army.current, false, pose)
	assert(shield_hit.shield and shield_hit.block_kind == "shield")
	assert(shield_hit == actor.incoming_contact(army.previous, army.current))
	geometry.shields.clear()
	# Exercise the actual unshielded-guard selection without loading a model.
	actor.editor = HumanCharacter3DEditor.new()
	var option := OptionButton.new()
	option.add_item("Longsword")
	option.set_item_metadata(0, "longsword_01")
	actor.editor.part_options[&"weapon"] = option
	actor.guarding = true
	geometry.parry_shapes = [Collision.capsule(Vector2(5, 0), Vector2(5, 5), 1.0)]
	pose = actor.incoming_geometry()
	var parried := actor.incoming_contact(army.previous, army.current, false, pose)
	assert(parried.shield and parried.block_kind == "parry")
	assert(parried == actor.incoming_contact(army.previous, army.current))
	assert(not actor.incoming_contact(army.previous, army.current, true, pose).shield, "Melee parry cannot stop ranged contact")
	actor.guard_break_left = 0.4
	assert(not actor.incoming_contact(army.previous, army.current).shield, "New projections must observe broken guard")
	option.free()
	actor.editor.free()
	actor.editor = null
	lab.combat_armies.clear()
	army.free()

func profile_live_geometry(lab: TerrainLab, actor: TerrainTestCharacter) -> void:
	var far: Array[PackedVector2Array] = [Collision.capsule(Vector2.ZERO, Vector2(20, 0), 1.0)]
	# Same loaded model, pose, terrain and twelve queries in both paths. Warm
	# mesh arrays first; report CPU query time, never infer FPS from this probe.
	assert(lab._collect_unit_contacts([], far, Vector2i(10, 10), Vector2.ZERO, null, -1).is_empty())
	var started := Time.get_ticks_usec()
	for attempt in range(12):
		assert(lab._collect_unit_contacts([], far, Vector2i(10, 10), Vector2.ZERO, null, -1).is_empty())
	var uncached_us := Time.get_ticks_usec() - started
	print("CONTACT PROFILE: 12 live uncached queries = ", uncached_us, "us")
	lab._sampling_army_contacts = true
	started = Time.get_ticks_usec()
	for attempt in range(12):
		assert(lab._collect_unit_contacts([], far, Vector2i(10, 10), Vector2.ZERO, null, -1).is_empty())
	var sampled_us := Time.get_ticks_usec() - started
	assert(lab._army_contact_geometry.size() == 1)
	lab._sampling_army_contacts = false
	lab._army_contact_geometry.clear()
	print("CONTACT PROFILE: same 12 queries / one projection = ", sampled_us, "us")
	# Compare every real body/shield probe plus an actual sweep, not only misses.
	var pose := actor.incoming_geometry()
	assert(not pose.body.is_empty() and not pose.shield.is_empty())
	for shape: PackedVector2Array in pose.body + pose.shield:
		var current: Array[PackedVector2Array] = [shape]
		var previous := Collision.shifted(current, Vector2(-30, 0))
		for ranged: bool in [false, true]:
			var direct := actor.incoming_contact(previous, current, ranged)
			assert(not direct.is_empty())
			assert(direct == actor.incoming_contact(previous, current, ranged, pose), "Live projected contact/order/point must be identical")
