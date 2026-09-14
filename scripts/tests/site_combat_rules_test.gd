extends SceneTree

const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")
const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(8.0).timeout.connect(func() -> void: quit(1))
	_test_sustained_pose_loop()
	var blunt := {"power": 30.0, "impact": 35.0}
	var blocked := Rules.damage(blunt, 35.0, 10.0, 0)
	assert(blocked.hp == 0.0 and blocked.stun == 25.0)
	var weak := Rules.damage({"power": 20.0, "impact": 8.0}, 35.0, 10.0, 0)
	assert(weak.hp == 0.0 and weak.stun == 0.0, "No minimum chip damage or stun")
	var head := Rules.damage(blunt, 20.0, 10.0, 1)
	assert(head.hp == 15.0 and head.stun == 37.5)
	assert(Rules.damage(blunt, 0.0, 0.0, 6).hp == 22.5)
	var shield := Rules.damage(blunt, 0.0, 10.0, 0, true)
	assert(shield.hp == 0.0 and shield.stun == 7.5 and shield.guard_break)
	assert(Rules.damage({"power": 20.0, "impact": 12.0}, 0.0, 0.0, 0, true).stun == 3.0)
	for cap: float in [0.15, 0.20, 0.25]:
		var last := -1.0
		for value: float in [0.0, 1.0, 100.0, 200.0, 10000.0]:
			var reduced := Rules.diminishing(value, cap)
			assert(reduced >= last and reduced < cap)
			last = reduced
	var previous: Array[PackedVector2Array] = [Collision.capsule(Vector2.ZERO, Vector2(0, 5), 1)]
	var current: Array[PackedVector2Array] = [Collision.capsule(Vector2(20, 0), Vector2(20, 5), 1)]
	var bodies: Array[PackedVector2Array] = [Collision.capsule(Vector2(15, 0), Vector2(15, 5), 1), Collision.capsule(Vector2(5, 0), Vector2(5, 5), 1)]
	var contact := Collision.contact(previous, current, bodies)
	assert(contact.body == 1 and contact.fraction < 0.3, "Contact order is not body-array order")
	assert(Collision.contact([], previous, bodies).is_empty(), "Proximity is not a hit")
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "combat-rules-fixture")
	for y in range(8, 15):
		for x in range(8, 15):
			var index := data.index(Vector2i(x, y))
			data.height_levels[index] = 0
			data.flags[index] = TerrainData.Flag.WALKABLE
			data.static_blocked[index] = 0
	var a := TerrainTestCharacter.new()
	var b := TerrainTestCharacter.new()
	root.add_child(a)
	root.add_child(b)
	a.set_process(false)
	b.set_process(false)
	a.data = data
	b.data = data
	a.place(Vector2i(10, 10), true)
	b.place(Vector2i(11, 10), true)
	a.opponent = b
	b.opponent = a
	b.faction_id = 1
	a.facing = Vector2i.UP
	a._update_combat_ready()
	assert(a.facing == Vector2i.UP, "Player proximity never turns the body")
	b.apply_contact({"attacker": a, "shield": false, "result": blocked})
	assert(b.hp == 100.0 and b.stun == 25.0)
	b.advance_combat(3.0)
	assert(b.stun == 25.0)
	b.advance_combat(0.5)
	assert(b.stun == 20.0)
	b.apply_contact({"attacker": a, "shield": false, "result": {"hp": 7.5, "stun": 90.0, "guard_break": false}})
	assert(b.hp == 92.5 and b.knockout_left == 30.0 and not b.can_act())
	assert(not b.start_attack(a) and not b.step(Vector2i.DOWN) and not b.occupies_cell(b.terrain_cell))
	b.advance_combat(10.0)
	b.apply_contact({"attacker": a, "shield": false, "result": weak})
	assert(b.knockout_left == 20.0, "Zero-impact contact does not extend unconsciousness")
	b.apply_contact({"attacker": a, "shield": false, "result": blocked})
	assert(b.knockout_left == 30.0, "Positive new impact resets, not stacks, the KO timer")
	b.advance_combat(30.0)
	assert(not b.can_act() and b._getting_up and b.hp == 92.5 and b.stun == 30.0, "Waking never refills HP or snaps to idle")
	b.advance_combat(2.2)
	assert(b.can_act())
	b.apply_contact({"attacker": a, "shield": false, "result": {"hp": 100.0, "stun": 100.0, "guard_break": false}})
	assert(b.hp == 0.0 and b.knockout_left == 0.0 and b.combat_status == "Dead")
	b.advance_combat(100.0)
	assert(not b.can_act() and not a.start_rescue(b), "Death is not temporary unconsciousness")
	b.reset_combat()
	b.faction_id = a.faction_id
	b.knockout_left = 30.0
	b.stun = 100.0
	assert(a.start_rescue(b))
	a.advance_combat(3.9)
	assert(b.knockout_left == 30.0)
	a.advance_combat(0.2)
	assert(b._getting_up and not b.can_act() and b.stun == 30.0)
	b.advance_combat(2.2)
	assert(b.can_act())
	b.knockout_left = 30.0
	assert(a.start_rescue(b))
	a.apply_contact({"attacker": b, "shield": false, "result": blocked})
	assert(a._rescue_left == 0.0 and b._rescuer == null)
	assert(a.start_rescue(b))
	assert(a.step(Vector2i.UP), "Movement can interrupt rescue")
	assert(a._rescue_left == 0.0 and b._rescuer == null)
	a.place(Vector2i(10, 10), true)
	a.reset_combat()
	b.reset_combat()
	b.faction_id = 1
	assert(a.start_attack(b))
	assert(not a.start_attack(b) and not a.step(Vector2i.UP))
	var locked := a.action_time
	a.apply_contact({"attacker": b, "shield": false, "result": {"hp": 1.0, "stun": 0.0, "guard_break": false}})
	assert(a.action_time == locked, "Normal hits cannot cancel attack recovery")
	a.set_guard(true)
	assert(not a.guarding, "Guard cannot cancel recovery")
	a.advance_combat(2.0)
	assert(b.hp == 100.0, "Headless missing geometry cannot deal invented hits")
	a.set_guard(true)
	assert(a.guarding and a.guard_transition_left == 0.15)
	a.set_guard(false)
	assert(not a.guarding and not a.start_attack(b), "Lowering the guard takes time")
	a.advance_combat(0.15)
	assert(a.start_attack(b))
	var resolver := TerrainLab.new()
	var lethal := {"hp": 100.0, "stun": 0.0, "guard_break": false}
	a.reset_combat()
	b.reset_combat()
	resolver._combat_contacts.assign([
		{"target": b, "attacker": a, "result": lethal, "shield": false, "fraction": 0.5},
		{"target": a, "attacker": b, "result": lethal, "shield": false, "fraction": 0.5}])
	resolver._resolve_combat_contacts()
	assert(a.hp == 0.0 and b.hp == 0.0, "Equal-time legal attacks trade")
	a.reset_combat()
	b.reset_combat()
	resolver._combat_contacts[0].fraction = 0.25
	resolver._combat_contacts[1].fraction = 0.75
	resolver._resolve_combat_contacts()
	assert(a.hp == 100.0 and b.hp == 0.0, "Earlier death prevents a later melee contact")
	a.reset_combat()
	b.reset_combat()
	resolver._combat_contacts[1]["ranged"] = true
	resolver._resolve_combat_contacts()
	assert(a.hp == 0.0 and b.hp == 0.0, "Already-fired projectiles survive shooter death")
	resolver.free()
	a.queue_free()
	b.queue_free()
	await process_frame
	print("SITE COMBAT RULES PASS: armor, fractional HP, stun, death, wake/rescue and interruption, action locks, ordered trades, sustained pose loop defaults, no fake headless hits")
	quit(0)

func _test_sustained_pose_loop() -> void:
	var preview := HumanCharacter3DEditor.new()
	preview.loop_toggle = CheckBox.new()
	preview.add_child(preview.loop_toggle)
	for sustained: StringName in [&"idle", &"walk", &"run", &"guard", &"guard_weapon", &"guard_polearm", &"unconscious", &"ride_idle", &"ride_walk", &"ride_run"]:
		for once: StringName in [&"attack_bow", &"attack_crossbow", &"walk_slash", &"ride_slash", &"ride_thrust", &"guard_weapon_raise", &"guard_polearm_lower", &"guard_break", &"get_up", &"rescue", &"down"]:
			preview._selected_animation = once
			preview._apply_attack_loop_default()
			assert(not preview.loop_toggle.button_pressed, "One-shot must remain non-looping")
			preview._selected_animation = sustained
			preview._apply_attack_loop_default()
			assert(preview.loop_toggle.button_pressed, "Prior one-shot froze sustained pose: " + str(sustained))
	preview.free()
