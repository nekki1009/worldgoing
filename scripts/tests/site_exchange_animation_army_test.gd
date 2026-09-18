extends SceneTree
## Presentation time borrows the original row without changing its action/grid owner.

const Visual = preload("res://scripts/terrain_lab/character_exchange_timings.gd")
const Authored = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const STEP := 1.0 / 30.0

class CountingArmy extends TerrainArmy:
	var visual_resolutions := 0
	func _exchange_visual_pose(index: int) -> String:
		visual_resolutions += 1
		return super._exchange_visual_pose(index)

func _initialize() -> void:
	run.call_deferred()

func _outcome(role: String, big: bool = false) -> Dictionary:
	return {"role": role, "kind": "draw" if role == "draw" else ("big" if big else "small"),
		"hp": (2.0 if big else 1.0) if role == "loser" else 0.0,
		"stun": (18.0 if big else 8.0) if role == "loser" else 0.0,
		"stagger": (0.65 if big else 0.35) if role == "loser" else (0.3 if role == "draw" else 0.0),
		"knockback": role == "loser" and big, "fatigue": 0.0 if role == "draw" else 0.5, "other_identity": 9999}

func _arrow(hp: float = 1.0, stun: float = 0.0) -> Dictionary:
	return {"shield": false, "result": {"kind": "hit", "hp": hp, "stun": stun,
		"stagger": 0.35, "knockback": false}}

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	_check_explicit_actions()
	var data := TerrainData.new()
	data.allocate(Vector2i(32, 32))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "exchange-animation-army")
	data.height_levels.fill(0)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var army := CountingArmy.new()
	root.add_child(army)
	army.set_process(false)
	army.exchange_enabled = true
	army.roster_size = 8
	var selected: Array[Vector2i] = []
	for index in range(8):
		selected.append(Vector2i(10 + index * 2, 10))
	assert(army.deploy_at(data, null, null, selected) and army.enable_combat(false))
	assert(army._uses_live_presenter(0) and not army._uses_live_presenter(1), "Original female/live and ordinary/atlas rows share this presentation clock")
	# A resolved winner starts near authored contact; both render consumers sample
	# the same original animation source, not the old full-clip-to-one-second scale.
	for index in [0, 1]:
		army.apply_exchange(index, selected[index] + Vector2i.RIGHT, _outcome("winner"))
		var row: Dictionary = army.combat_units[index]
		assert(row.hp == 100.0 and row.exchange_cooldown == 1.0 and row.exchange_stagger == 0.0)
		assert(row.pose == "walk_slash" and row.exchange_pose_duration == 1.0 and row.exchange_visual.left == 0.85)
		var source := Visual.authored_duration(&"walk_slash")
		assert(is_equal_approx(float(army.contact_sample(index)[1]), Visual.sample_time(&"walk_slash", 0.0, source)))
		assert(float(army.contact_sample(index)[1]) > 1.0, "The result cannot replay the old seconds of anticipation")
		army.visual_resolutions = 0
		var sample := army.contact_sample(index)
		assert(sample.size() == 5 and army.visual_resolutions == 1, "A five-field sample resolves presentation once, without a cross-frame cache")
		army.visual_resolutions = 0
		army.combat_frame(index)
		assert(army.visual_resolutions == 1, "One atlas frame cannot repeatedly resolve the same original row")
		var pose := army._exchange_visual_pose(index)
		assert(army._combat_clip(index) == army._combat_clip(index, pose))
		assert(army._exchange_visual_facing(index) == army._exchange_visual_facing(index, pose))
		assert(army._exchange_animation_time(index, source) == army._exchange_animation_time(index, source, pose), "Passing same-call values cannot alter source time")
	var saved_visual: Dictionary = army.combat_units[1].exchange_visual
	var before_pause := saved_visual.duplicate(true)
	paused = true
	army.prepare_combat(0.5)
	assert(saved_visual == before_pause)
	paused = false
	for _tick in range(24):
		army.prepare_combat(STEP)
	for index in [0, 1]:
		var frame := army.combat_frame(index)
		assert(frame.clip == "walk_slash" and is_equal_approx(float(frame.sample_time), float(frame.duration)), "The actual final atlas sample must be visible before visual expiry")
		assert(is_equal_approx(float(army.contact_sample(index)[1]), float(frame.duration)), "Live seek and baked final frame share the endpoint")
		assert(army.combat_units[index].exchange_cooldown > 0.0)
	army.prepare_combat(STEP * 2.0)
	assert(not army.combat_units[1].has("exchange_visual"))
	assert(army.combat_units[1].attack and army.combat_units[1].exchange_cooldown > 0.0,
		"Visual completion cannot shorten the original one-second gameplay action")
	assert(army._exchange_visual_pose(1) == "idle", "Ending the short visual cannot restart the still-active old long attack")
	army.prepare_combat(1.0 - STEP * 26.0)
	assert(army.exchange_ready(1) and army.combat_units[1].exchange_cooldown == 0.0)
	# Big winners use the authored jump on both the live captain and ordinary
	# shared-atlas renderer; this is presentation only, never a damage profile.
	for index in [0, 1]:
		army.apply_exchange(index, selected[index] + Vector2i.RIGHT, _outcome("winner", true))
		assert(army.combat_units[index].pose == "attack_jump_heavy")
		assert(army._exchange_visual_pose(index) == "attack_jump_heavy")
		assert(army.contact_sample(index)[0] == &"attack_jump_heavy")
		assert(army.combat_frame(index).clip == "attack_jump_heavy")
	army.prepare_combat(1.0)

	# Original reservation/facing changes immediately. Only the first .1 seconds
	# of the strike retain visual facing, and their age never jumps or rewinds.
	army.apply_exchange(2, selected[2] + Vector2i.RIGHT, _outcome("winner"))
	army.prepare_combat(STEP)
	var source_before := float(army.contact_sample(2)[1])
	assert(army._reserve_combat_step(2, selected[2] + Vector2i.UP))
	assert(army.combat_units[2].pose == "walk" and not army.combat_units[2].attack and army.facing[2] == Vector2i.UP)
	assert(army.moving_to[2] == selected[2] + Vector2i.UP and army._reserved_cells[army.moving_to[2]] == 2)
	assert(army._exchange_visual_facing(2) == Vector2i.RIGHT and is_equal_approx(float(army.contact_sample(2)[1]), source_before))
	assert(is_equal_approx(float(army.combat_units[2].exchange_visual.left), Visual.MOVE_CORE_SECONDS - STEP))
	army.prepare_combat(STEP * 2.0)
	assert(not army.combat_units[2].has("exchange_visual") and army._exchange_visual_pose(2) == "walk")
	assert(army._exchange_visual_facing(2) == Vector2i.UP and army.moving_to[2] != TerrainArmy.INVALID_CELL)
	army.apply_exchange(3, selected[3] + Vector2i.RIGHT, _outcome("winner"))
	army.prepare_combat(0.2)
	assert(army._reserve_combat_step(3, selected[3] + Vector2i.UP))
	assert(not army.combat_units[3].has("exchange_visual"), "A late step cannot append another .1 seconds of sliding attack recovery")
	army.prepare_combat(1.0)

	# .45/.75 are display windows only; the original .35/.65 movement locks stay.
	army.apply_exchange(4, selected[4] + Vector2i.DOWN, _outcome("loser"))
	assert(army.combat_units[4].hp == 99.0 and army.combat_units[4].exchange_stagger == 0.35)
	army.prepare_combat(0.35)
	assert(army.combat_units[4].pose == "idle" and army._exchange_visual_pose(4) == "hit")
	assert(army._reserve_combat_step(4, selected[4] + Vector2i.UP), "Reaction visuals cannot extend a completed gameplay stagger")
	army.prepare_combat(0.1)
	assert(not army.combat_units[4].has("exchange_visual"))
	army.apply_exchange(5, selected[5] + Vector2i.DOWN, _outcome("loser", true))
	assert(army.combat_units[5].hp == 98.0 and army.combat_units[5].exchange_stagger == 0.65)
	assert(army.moving_to[5] == selected[5] + Vector2i.UP and army.combat_units[5].exchange_visual.left == 0.75)
	army.prepare_combat(0.65)
	assert(army.combat_units[5].pose == "idle" and army._exchange_visual_pose(5) == "knockback")
	assert(army.cells[5] == selected[5] + Vector2i.UP and army.combat_units[5].exchange_stagger == 0.0)
	army.prepare_combat(0.1)
	assert(not army.combat_units[5].has("exchange_visual"))

	# Same/lighter arrows retain one finite reaction, but each real hit still
	# deducts HP and refreshes the original stagger exactly as before.
	army.ranged_apply_hit(6, selected[6] + Vector2i.RIGHT, _arrow())
	army.prepare_combat(0.2)
	var reaction: Dictionary = army.combat_units[6].exchange_visual
	var reaction_before := reaction.duplicate(true)
	army.ranged_apply_hit(6, selected[6] + Vector2i.RIGHT, _arrow(2.0))
	assert(army.combat_units[6].hp == 97.0 and army.combat_units[6].exchange_stagger == 0.35 and army.combat_units[6].age == 0.0)
	assert(is_same(reaction, army.combat_units[6].exchange_visual) and reaction == reaction_before, "A second arrow cannot restart the displayed hit")
	army.prepare_combat(0.25)
	assert(not army.combat_units[6].has("exchange_visual") and army._exchange_visual_pose(6) == "idle")
	army.ranged_apply_hit(6, selected[6] + Vector2i.RIGHT, _arrow())
	assert(army._exchange_visual_pose(6) == "hit")
	army.apply_exchange(6, selected[6] + Vector2i.DOWN, _outcome("loser", true))
	assert(army._exchange_visual_pose(6) == "knockback" and army.combat_units[6].exchange_visual.age == 0.0,
		"A newly resolved stronger reaction immediately replaces an active small hit")
	army.prepare_combat(0.1)
	reaction = army.combat_units[6].exchange_visual
	reaction_before = reaction.duplicate(true)
	army.ranged_apply_hit(6, selected[6] + Vector2i.RIGHT, _arrow())
	assert(is_same(reaction, army.combat_units[6].exchange_visual) and reaction == reaction_before and army._exchange_visual_pose(6) == "knockback")
	army.combat_units[6].hp = 1.0
	army.ranged_apply_hit(6, selected[6] + Vector2i.RIGHT, _arrow(2.0))
	assert(army.combat_units[6].hp == 0.0 and army.combat_units[6].pose == "down" and not army.combat_units[6].has("exchange_visual"))
	army.ranged_apply_hit(7, selected[7] + Vector2i.RIGHT, _arrow())
	army.combat_units[7].stun = 99.0
	army.ranged_apply_hit(7, selected[7] + Vector2i.RIGHT, _arrow(1.0, 2.0))
	assert(army.combat_units[7].ko > 0.0 and army._exchange_visual_pose(7) == "down" and not army.combat_units[7].has("exchange_visual"))
	army._wake_unit(7)
	army.prepare_combat(0.25)
	var getting_up_age := float(army.combat_units[7].age)
	army.ranged_apply_hit(7, selected[7] + Vector2i.RIGHT, _arrow())
	assert(army.combat_units[7].pose == "get_up" and army.combat_units[7].age == getting_up_age and not army.combat_units[7].has("exchange_visual"))
	army.apply_exchange(0, army.cells[0] + Vector2i.RIGHT, _outcome("draw"))
	assert(army.combat_units[0].hp == 100.0 and army.combat_units[0].exchange_visual.left == 0.3)
	army.prepare_combat(0.3)
	assert(army.combat_units[0].pose == "idle" and not army.combat_units[0].has("exchange_visual"))
	assert(army._reserve_combat_step(0, army.cells[0] + Vector2i.LEFT))
	army.apply_exchange(0, army.cells[0] + Vector2i.RIGHT, _outcome("draw"))
	assert(army.combat_units[0].exchange_visual.left == Visual.DRAW_SECONDS, "An existing step cannot shorten the draw's defense to the attack-only movement core")
	army.prepare_combat(Visual.MOVE_CORE_SECONDS)
	assert(army._exchange_visual_pose(0) == "guard" and army.combat_units[0].exchange_visual.left > 0.0)
	army.prepare_combat(Visual.DRAW_SECONDS)

	# Original snapshot/gameplay fields survive; a transient renderer payload is
	# omitted and is also ignored on restore, never replayed as a queued action.
	army.apply_exchange(1, army.cells[1] + Vector2i.RIGHT, _outcome("winner"))
	army.settle_combat_command()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	for row: Dictionary in saved.units:
		assert(not row.has("exchange_visual"))
	assert(TerrainArmy.valid_combat_state(saved, data))
	saved.units[1].exchange_visual = {"pose": "untrusted", "age": "invalid"}
	var restored := TerrainArmy.new()
	root.add_child(restored)
	restored.set_process(false)
	restored.exchange_enabled = true
	restored.restore_combat_state(saved, data, null, null)
	assert(not restored.combat_units[1].has("exchange_visual") and restored.combat_units[1].exchange_cooldown == army.combat_units[1].exchange_cooldown)
	assert(restored.cells == army.cells and restored.moving_to == army.moving_to and restored.combat_units[6].hp == 0.0)
	restored.clear()
	restored.free()
	# Opting out still samples the original exact-mode pose/age and keeps its
	# attack movement lock; this test does not start the old geometry renderer.
	army.exchange_enabled = false
	army.combat_units[1].age = 0.25
	assert(is_equal_approx(float(army.contact_sample(1)[1]), Authored.sample_time(&"walk_slash", 0.25, 0.0, 0.0)))
	assert(not army._reserve_combat_step(1, army.cells[1] + Vector2i.UP))
	army.clear()
	army.free()
	assert(TerrainArmy._contact_source == null)
	print("SITE_EXCHANGE_ANIMATION_ARMY_PASS: shared atlas/live source clock, contact-first complete short window, unchanged cooldown/HP/stagger/movement, visual facing/core, finite arrow reactions, life priority, transient save boundary, legacy clock")
	quit(0)

func _check_explicit_actions() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(20, 20))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "exchange-animation-explicit-actions")
	data.height_levels.fill(0)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	army.exchange_enabled = true
	army.roster_size = 3
	var selected: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]
	assert(army.deploy_at(data, null, null, selected) and army.enable_combat(false))
	for clip: String in ["walk_slash", "attack_crossbow"]:
		# Isolate an unfinished presentation, not a fabricated completed attack:
		# the original attack=true guard is unchanged and tested below.
		army._begin_exchange_visual(1, clip)
		assert(army.set_unit_guard(1, true) and not army.combat_units[1].has("exchange_visual"))
		assert(army.combat_frame(1).clip == "guard_raise" and army.contact_sample(1)[0] == &"guard_raise")
		army.prepare_combat(SiteCombatRules.GUARD_TRANSITION)
		assert(army.combat_units[1].pose == "guard" and army._exchange_visual_pose(1) == "guard")
		assert(army.combat_frame(1).clip == "guard" and army.contact_sample(1)[0] == &"guard")
		army.prepare_combat(0.2)
		assert(army._exchange_visual_pose(1) == "guard" and not army.combat_units[1].has("exchange_visual"), "A completed raise cannot revive old attack/ranged recovery")
		army._begin_exchange_visual(1, clip)
		assert(army.set_unit_guard(1, false) and not army.combat_units[1].has("exchange_visual"))
		army.prepare_combat(SiteCombatRules.GUARD_TRANSITION)
		assert(army.combat_units[1].pose == "idle" and army._exchange_visual_pose(1) == "idle")
	army.apply_exchange(1, selected[1] + Vector2i.UP, _outcome("winner"))
	assert(not army.set_unit_guard(1, true) and army.combat_units[1].has("exchange_visual"), "Rejected commands cannot cancel a valid visual or bypass the old attack lock")
	army.prepare_combat(1.0)
	army.apply_exchange(1, selected[1] + Vector2i.UP, _outcome("loser"))
	army.prepare_combat(0.35)
	assert(army.combat_units[1].pose == "idle" and army._exchange_visual_pose(1) == "hit")
	assert(army.set_unit_guard(1, true) and not army.combat_units[1].has("exchange_visual"), "Actual leftover reaction display must yield when a legal manual guard begins")
	army.prepare_combat(SiteCombatRules.GUARD_TRANSITION)
	assert(army.combat_frame(1).clip == "guard" and army.contact_sample(1)[0] == &"guard")
	assert(army.set_unit_guard(1, false))
	army.prepare_combat(SiteCombatRules.GUARD_TRANSITION)
	army.apply_unit_contact(2, {"shield": false, "result": {"hp": 0.0, "stun": 110.0, "guard_break": false}})
	army._begin_exchange_visual(1, "walk_slash")
	assert(army.start_unit_rescue(1, 2) and not army.combat_units[1].has("exchange_visual"))
	assert(army.combat_frame(1).clip == "rescue" and army.contact_sample(1)[0] == &"rescue")
	army._cancel_unit_rescue(1)
	army.prepare_combat(0.1)
	assert(army._exchange_visual_pose(1) == "idle" and not army.combat_units[1].has("exchange_visual"), "Cancelling help cannot uncover a previous attack")
	army.clear()
	army.free()
