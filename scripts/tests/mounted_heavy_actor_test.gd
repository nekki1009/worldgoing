extends SceneTree
## CPU owner test. Does not instantiate the character editor or claim GPU coverage.
const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const OUT := "res://output/equipment_matrix_20260918/mounted/actor_contract.json"
var checks := 0
var actors: Array[TerrainTestCharacter] = []
var failed := false

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func() -> void: _check(false, "internal deadline"))
	call_deferred("run")

func _check(ok: bool, reason: String) -> bool:
	checks += 1
	if not ok:
		failed = true
		push_error("MOUNTED_HEAVY_ACTOR_FAIL: " + reason)
	return ok

func _advance(actor: TerrainTestCharacter, seconds: float) -> void:
	var left := seconds
	while left > 0.000000001:
		var delta := minf(left, 1.0 / 30.0)
		actor.advance_combat(delta, true)
		left -= delta

func _fresh(actor: TerrainTestCharacter, mounted: bool, weapon: String) -> void:
	actor.reset_combat()
	actor.place(Vector2i(10, 10), true)
	actor._saved_appearance = HumanCharacter3DEditor.default_appearance()
	actor._saved_appearance.parts.weapon = weapon
	actor.visual_state.mounted = mounted
	actor.play_pose(&"idle")
	actor.ammo_inventory = {"arrow": 7, "bolt": 9}

func run() -> void:
	_check(DisplayServer.get_name() == "headless", "CPU only")
	var data := TerrainData.new()
	data.allocate(Vector2i(32, 32))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "mounted-heavy-actor")
	data.static_blocked.fill(0)
	for mounted: bool in [false, true]:
		var actor := TerrainTestCharacter.new()
		root.add_child(actor)
		actor.set_process(false)
		actor.data = data
		actor.exchange_enabled = true
		actor.combat_mode_query = func() -> bool: return true
		actors.append(actor)
		for row: Dictionary in HumanCharacter3DEditor.WeaponMaterials.OPTIONS:
			var weapon := str(row.id)
			_fresh(actor, mounted, weapon)
			actor.apply_exchange(Vector2i(10, 11), {"role": "winner", "kind": "big", "hp": 0.0, "stun": 0.0, "fatigue": 0.5})
			var expected: StringName = &"ride_heavy" if mounted else &"attack_jump_heavy"
			_check(actor.visual_state.animation_id == expected and actor.is_mounted() == mounted, weapon + " heavy route")
			_check(actor.action_time == 0 and actor.exchange_cooldown == 1.0 and actor.hp == 100, "existing heavy rules")
			_check(Timings.events(expected).release == -1, "generic strike has no release")
			_advance(actor, 0.8)
			_check(is_equal_approx(actor.visual_state.animation_time, 70.0 / 24.0), "one-shot terminal sample")
			_check(actor.ammo_inventory == {"arrow": 7, "bolt": 9} and actor.projectiles.is_empty(), "no unexpected shot")
			_advance(actor, .05)
			_check(actor.visual_state.animation_id == (&"ride_idle" if mounted else &"idle") and actor.is_mounted() == mounted, "recover to original mount state")
			_fresh(actor, mounted, weapon)
			actor.apply_exchange(Vector2i(10, 11), {"role": "loser", "kind": "big", "hp": 2.0, "stun": 18.0, "fatigue": .5, "stagger": .65, "knockback": false})
			_check(actor.visual_state.animation_id == (&"ride_guard_break" if mounted else &"hit") and actor.is_mounted() == mounted, "braced heavy loss stays seated")
			_check(actor.hp == 98.0 and actor.stun == 18.0 and actor.exchange_stagger == .65 and not actor.is_moving(), "braced damage and hold unchanged")
			_advance(actor, .72)
			if mounted:
				_check(is_equal_approx(actor.visual_state.animation_time, .4), "mounted break reaches authored end")
			_advance(actor, .04)
			_check(actor.is_mounted() == mounted, "break recovery remains mounted")
		_fresh(actor, mounted, "longsword_01")
		actor.apply_exchange(Vector2i(10, 11), {"role": "loser", "kind": "big", "hp": 2.0, "stun": 18.0, "stagger": .65, "knockback": true})
		_check(actor.is_moving() and actor.terrain_cell == Vector2i(10, 9) and actor.is_mounted() == mounted, "original knockback reservation retained")
		_fresh(actor, mounted, "bow_01_steel")
		actor.exchange_enabled = false
		actor.apply_contact({"shield": true, "result": {"hp": 0.0, "stun": 1.0, "guard_break": true}})
		_check(actor.visual_state.animation_id == (&"ride_guard_break" if mounted else &"guard_break") and actor.is_mounted() == mounted, "actual contact break route")
		_check(actor.guard_break_left == SiteCombatRules.GUARD_BREAK_SECONDS, "guard-break rule unchanged")
		_advance(actor, .4)
		_check(actor.guard_break_left == 0 and actor.is_mounted() == mounted, "contact break ends without dismount")
	var result := {"status": "FAIL" if failed else "PASS", "checks": checks, "surface": "headless actor; GPU pending"}
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	for actor: TerrainTestCharacter in actors:
		actor.free()
	print("MOUNTED_HEAVY_ACTOR_", result.status, " ", checks)
	quit(1 if failed else 0)
