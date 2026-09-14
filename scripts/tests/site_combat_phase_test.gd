extends SceneTree
## Shared-loop ordering contract, with real projectile contact and packet commit.
const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

class PhaseLab extends TerrainLab:
	func _ready() -> void:
		set_process(false) # Real tree pause guard, without unrelated scene/UI construction.

class FixtureGeometry extends Collision:
	func body_shapes(actor: Variant) -> Array[PackedVector2Array]:
		return [capsule(actor.position, actor.position + Vector2(0, 5), 1.0)]
	func shield_shapes(_actor: Variant) -> Array[PackedVector2Array]:
		return []
	func armor_at(_actor: Variant, _point: Vector2, _kind: String) -> Vector2:
		return Vector2.ZERO

class PhaseActor extends TerrainTestCharacter:
	var peers: Array[TerrainTestCharacter] = []
	var samples := 0
	var releases := 0
	func _update_projectile(delta: float) -> void:
		for peer: TerrainTestCharacter in peers:
			assert(is_equal_approx(peer.visual_state.animation_time, visual_state.animation_time), "Contact sampled before all peers reached this step")
		samples += 1
		super._update_projectile(delta)
	func _launch_projectile() -> void:
		releases += 1
		assert(samples > 0, "New release must follow old projectile movement")

class PhaseArmy extends TerrainArmy:
	var peers: Array[TerrainTestCharacter] = []
	var elapsed := 0.0
	func prepare_combat(delta: float) -> void:
		elapsed += delta
	func sample_combat() -> void:
		for peer: TerrainTestCharacter in peers:
			assert(is_equal_approx(peer.visual_state.animation_time, elapsed), "Army and original actor pose times differ")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var map := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(map, "combat-phase-fixture")
	map.height_levels.fill(0)
	map.flags.fill(TerrainData.Flag.WALKABLE)
	map.static_blocked.fill(0)
	map.ramp_edges.fill(0)
	var lab := PhaseLab.new()
	root.add_child(lab)
	lab.terrain = map
	var a := PhaseActor.new()
	var b := PhaseActor.new()
	var army := PhaseArmy.new()
	for actor: PhaseActor in [a, b]:
		root.add_child(actor)
		actor.set_process(false)
		actor.data = map
		actor.person_id = 1 if actor == a else 2
		actor.faction_id = 0 if actor == a else 1
		actor._geometry = FixtureGeometry.new()
		actor.peers.assign([a, b])
		actor.combatants = func() -> Array[TerrainTestCharacter]: return [a, b]
		actor.contact_sink = func(packet: Dictionary) -> void: lab._combat_contacts.append(packet)
	assert(a.place(Vector2i(10, 10), true) and b.place(Vector2i(11, 10), true))
	army.peers.assign([a, b])
	lab.combat_armies.assign([army])
	for reverse_order: bool in [false, true]:
		for delta: float in [1.0 / 120.0, 0.5]:
			a.reset_combat()
			b.reset_combat()
			army.elapsed = 0.0
			lab.combat_actors.assign([b, a] if reverse_order else [a, b])
			a.projectiles.append({"position": b.position - Vector2(2, 0), "velocity": Vector2(420, 0), "remaining": 384.0,
				"ground": b.position - Vector2(2, 0), "ground_velocity": Vector2(420, 0), "source_cell": a.terrain_cell,
				"profile": SiteCombatRules.attack_profile(&"attack_bow"), "faction": a.faction_id})
			lab._advance_combat(delta)
			assert(b.hp == 80.0 and a.projectiles.is_empty(), "Actual torso hit must apply 20 once in either order/frame size: hp=%s" % b.hp)
			var calls := a.samples
			a.sample_combat()
			assert(a.samples == calls and a._pending_melee.is_empty(), "Repeated sampling cannot consume the same step twice")
			paused = true
			lab._advance_combat(1.0)
			paused = false
			assert(a.samples == calls and is_equal_approx(army.elapsed, delta))
	# New releases are not advanced retroactively within their release step.
	a._pending_projectile_delta = 1.0 / 120.0
	a._pending_release = true
	a.sample_combat()
	a.sample_combat()
	assert(a.releases == 1)
	# A projectile already in flight remains independent of a dead shooter.
	a.hp = 0.0
	var before := a.samples
	lab._advance_combat(1.0 / 120.0)
	assert(a.samples == before + 1)
	lab.combat_armies.clear()
	a.peers.clear()
	a.reset_combat()
	# 0.15 seconds must be eighteen 120 Hz steps, not a nineteenth float-tail step.
	for enabled: bool in [true, false]:
		a.set_guard(enabled)
		for step in range(18):
			a.advance_combat(1.0 / 120.0)
		assert(a.guard_transition_left == 0.0)
		assert(a.visual_state.animation_id == (&"guard" if enabled else &"idle"))
	a.guard_break_left = SiteCombatRules.GUARD_BREAK_SECONDS
	a.play_pose(&"guard_break")
	for step in range(48):
		a.advance_combat(1.0 / 120.0)
	assert(a.guard_break_left == 0.0 and a.visual_state.animation_id == &"idle")
	lab.free()
	army.free()
	a.queue_free()
	b.queue_free()
	await process_frame
	print("SITE COMBAT PHASE PASS: all poses before contacts; reverse actor order, slow frame, actual projectile once, pause, release order, dead-shooter sampling; fixture geometry, not GPU parity")
	quit(0)
