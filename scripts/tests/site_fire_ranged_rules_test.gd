extends SceneTree
## Pure P1 numerical contracts only; no launch, collision backend, time owner or budget settlement claim.

const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")

func _initialize() -> void:
	_run.call_deferred()

func _offset(person: Dictionary = {}, distance: float = 4.0, moving: bool = false, multiplier: float = 1.0) -> Vector2:
	return Rules.fire_aim_offset(person, distance, moving, 42, 101, 7, 1, multiplier)

func _run() -> void:
	var bow := Rules.fire_ranged_profile("bow_01")
	var bolt := Rules.fire_ranged_profile("crossbow_01")
	var fire := Rules.fire_ranged_profile("bow_01", "FIRE_ARROW")
	assert(bow.ammo == "arrow" and bow.range == 8.0 and bow.speed == 10.0 and bow.hold == 0.25 and bow.cooldown == 2.0)
	assert(bolt.ammo == "bolt" and bolt.range == 10.0 and bolt.speed == 14.0 and bolt.hold == 0.4 and bolt.cooldown == 3.0)
	assert(bow.id == "normal_arrow_v1" and bolt.id == "normal_bolt_v1" and fire.id == "fire_arrow_v1")
	assert(fire.ammo == "fire_arrow" and fire.mode == "FIRE_ARROW" and fire.prepare == 0.8 and fire.scatter_multiplier == 1.15)
	assert(fire.range == 8.0 and fire.speed == 10.0 and fire.hold == 0.25 and fire.cooldown == 2.0)
	assert(is_equal_approx(float(fire.prepare) + float(fire.cooldown), 2.8))
	assert(fire.ember == 20.0 and fire.air_decay == 2.0 and fire.contact_rate == 10.0 and fire.contact_seconds == 2.0)
	assert(float(fire.contact_rate) * float(fire.contact_seconds) <= float(fire.ember), "The configured direct contact cannot supply an unbounded heat dose")
	for profile: Dictionary in [bow, bolt, fire]:
		assert(profile.gravity == 4.0 and profile.life == 4.0 and profile.kinetic_multiplier == 1.0 and profile.config_version == "fire_ranged_v1")
	for profile: Dictionary in [bow, bolt]:
		assert(profile.mode == "NORMAL" and profile.prepare == 0.0 and profile.scatter_multiplier == 1.0)
		assert(profile.ember == 0.0 and profile.air_decay == 0.0 and profile.contact_rate == 0.0 and profile.contact_seconds == 0.0)
	for material: String in ["", "_wood", "_stone", "_steel"]:
		assert(Rules.fire_ranged_profile("bow_01" + material, "FIRE_ARROW") == fire)
		assert(Rules.fire_ranged_profile("crossbow_01" + material) == bolt)
		assert(Rules.fire_ranged_profile("crossbow_01" + material, "FIRE_ARROW").is_empty())
	for weapon: String in ["none", "longsword_01", "siege_bolt", "missing_bow"]:
		assert(Rules.fire_ranged_profile(weapon).is_empty())
	assert(Rules.fire_ranged_profile("bow_01", "UNKNOWN").is_empty())
	var edited := fire.duplicate()
	edited.ember = 2000.0
	assert(Rules.fire_ranged_profile("bow_01", "FIRE_ARROW").ember == 20.0, "Each caller gets its own launch profile")

	# One fixed external numeric vector pins the versioned seed, not a second sampler implementation.
	var base := _offset()
	assert(base.distance_to(Vector2(0.05252690120465221, 0.06715377875796391)) < 0.000001)
	assert(base.length() > 0.0 and base.length() < 0.3064)
	assert(_offset() == base, "Repeated inspection of a committed sequence is deterministic, not another release")
	seed(735)
	var expected_global := randf()
	seed(735)
	assert(_offset() == base and randf() == expected_global, "The sampler cannot advance presentation/global RNG")
	for input: Array in [[43, 101, 7, 1], [42, 102, 7, 1], [42, 101, 8, 1], [42, 101, 7, 2]]:
		assert(Rules.fire_aim_offset({}, 4.0, false, input[0], input[1], input[2], input[3]) != base)
	assert(is_equal_approx(_offset({"ability": 70.0}).length() / base.length(), 0.2584 / 0.3064))
	assert(is_equal_approx(_offset({"training": 50.0}).length() / base.length(), 0.2824 / 0.3064))
	assert(is_equal_approx(_offset({"fatigue": 40.0}).length() / base.length(), 0.3544 / 0.3064))
	assert(is_equal_approx(_offset({"skill": "power"}).length() / base.length(), 0.2344 / 0.3064))
	assert(is_equal_approx(_offset({}, 4.0, true).length() / base.length(), 0.4024 / 0.3064))
	assert(is_equal_approx(_offset({}, 6.0).length() / base.length(), 0.4672 / 0.3064))
	assert(_offset({}, 4.0, false, 1.15).is_equal_approx(base * 1.15))
	assert(_offset({"ability": 1000.0, "training": 1000.0, "skill": "power"}) == _offset({"ability": 100.0, "training": 100.0, "skill": "power"}))
	assert(_offset({"ability": -1.0, "training": -1.0, "fatigue": 1000.0}) == _offset({"ability": 0.0, "training": 0.0, "fatigue": 100.0}))
	assert(_offset({"armor_stab": 100.0, "shield": true, "facility": true, "roll": 99.0}) == base)
	assert(_offset({}, 4.0, false, 0.0) == Vector2.ZERO)
	for sequence: int in [-1, 0]:
		assert(not Rules.fire_aim_offset({}, 4.0, false, 42, 101, 7, sequence).is_finite())
	for invalid: float in [-1.0, INF, NAN]:
		assert(not _offset({}, invalid).is_finite())
		assert(not _offset({}, 4.0, false, invalid).is_finite())
	for field: String in ["ability", "training", "fatigue"]:
		var invalid_person := {field: NAN}
		assert(not _offset(invalid_person).is_finite())

	# Same-height cardinal shot: XY remains straight at constant speed; only Z arcs.
	var origin := Vector3(0.0, 3.0, 1.0)
	var aim := Vector3(8.0, 3.0, 1.0)
	var flight := Rules.fire_trajectory(origin, aim, bow)
	assert(flight.total == 0.8 and flight.life == 4.0 and flight.gravity == 4.0)
	assert(flight.velocity.is_equal_approx(Vector3(10.0, 0.0, 1.6)))
	assert(Rules.fire_position(flight, 0.0) == origin)
	assert(Rules.fire_position(flight, 0.4).is_equal_approx(Vector3(4.0, 3.0, 1.32)))
	assert(Rules.fire_position(flight, 0.8).is_equal_approx(aim))
	assert(Rules.fire_position(flight, 1.0).is_equal_approx(Vector3(10.0, 3.0, 0.6)), "A miss continues in XY past nominal aim time while Z falls")
	var north := Rules.fire_trajectory(origin, Vector3(0.0, 11.0, 1.0), bow)
	assert(Rules.fire_position(north, 0.4).is_equal_approx(Vector3(0.0, 7.0, 1.32)), "Changing navigation bearing cannot rotate gravity out of the original Z height axis")
	var scattered_profile := bow.duplicate()
	scattered_profile.nominal_distance = 8.0
	var scattered_aim := Vector3(8.0, 3.25, 1.5)
	var before_profile := var_to_bytes(scattered_profile)
	var scattered := Rules.fire_trajectory(origin, scattered_aim, scattered_profile)
	assert(scattered.total == 0.8 and Rules.fire_position(scattered, 0.8).is_equal_approx(scattered_aim))
	assert(var_to_bytes(scattered_profile) == before_profile)
	var frozen := var_to_bytes(scattered)
	scattered_profile.gravity = 400.0
	scattered_aim = Vector3(30.0, 30.0, 30.0)
	assert(var_to_bytes(scattered) == frozen and not Rules.fire_position(scattered, 0.8).is_equal_approx(scattered_aim), "Later target/profile edits cannot steer the released flight")
	for hz: float in [30.0, 60.0, 120.0]:
		var elapsed := 0.0
		for _step in range(int(hz)):
			elapsed += 1.0 / hz
		assert(Rules.fire_position(flight, elapsed).is_equal_approx(Rules.fire_position(flight, 1.0)))
	assert(Rules.fire_position(flight, 4.0).is_finite())
	for time: float in [-1.0, 4.1, INF, NAN]:
		assert(not Rules.fire_position(flight, time).is_finite())
	assert(Rules.fire_trajectory(origin, origin, bow).is_empty())
	assert(Rules.fire_trajectory(Vector3.INF, aim, bow).is_empty())
	assert(Rules.fire_trajectory(origin, aim, {}).is_empty())
	assert(not Rules.fire_position({}, 0.0).is_finite())

	var shooter := {"weapon": "bow_01"}
	var body := Rules.fire_contact_result(shooter, {}, 0.35, false)
	assert(body.kind == "hit" and body.contact_kind == "BODY_HIT" and body.hp == 8.0 and body.stun == 8.0 and body.stagger == 0.35)
	assert(not body.knockback and not body.guard_break and not body.has("chance"))
	assert(Rules.fire_contact_result(shooter, {}, -0.35, false) == body)
	var graze := Rules.fire_contact_result(shooter, {}, 0.349999, false)
	assert(graze.kind == "graze" and graze.contact_kind == "BODY_GRAZE" and graze.hp == 4.0 and graze.stun == 4.0 and graze.stagger == 0.2)
	assert(Rules.fire_contact_result(shooter, {}, -0.349999, false) == graze)
	assert(body.contact_scale == 1.0 and graze.contact_scale == 0.5 and body.heat_transfer == 1.0)
	var shielded := Rules.fire_contact_result({"weapon": "bow_01", "skill": "power"}, {"skill": "brace"}, 0.0, true)
	assert(shielded.kind == "shield" and shielded.contact_kind == "SHIELD_CONTACT" and shielded.hp == 0.0 and shielded.stun == 0.0 and shielded.stagger == 0.0)
	assert(shielded.contact_scale == 1.0 and shielded.heat_transfer == 0.10)
	var braced := Rules.fire_contact_result(shooter, {"skill": "brace"}, 1.0, false)
	assert(is_equal_approx(float(braced.hp), 6.4) and is_equal_approx(float(braced.stun), 6.4) and braced.heat_transfer == body.heat_transfer)
	var powered := {"weapon": "bow_01", "skill": "power"}
	assert(Rules.fire_contact_result(powered, {}, 1.0, false).stun == 18.0)
	assert(Rules.fire_contact_result(powered, {}, 0.1, false).stun == 14.0)
	assert(is_equal_approx(float(Rules.fire_contact_result(powered, {"skill": "brace"}, 0.1, false).stun), 11.2))
	var kinetic_zero := Rules.fire_contact_result(shooter, {}, 1.0, false, 0.0)
	assert(kinetic_zero.hp == 0.0 and kinetic_zero.kind == "hit" and kinetic_zero.heat_transfer == body.heat_transfer, "Zero damage remains contact; heat is a separate finite owner budget")
	assert(Rules.fire_contact_result(shooter, {}, 1.0, false, 0.25).hp == 2.0)
	for old_modifier: Dictionary in [{"armor_stab": 100.0}, {"shield": true}, {"facility": true}, {"moving": true}, {"roll": 99.0}]:
		assert(Rules.fire_contact_result(shooter, old_modifier, 0.35, false) == body, "Only the actual collision and current armor/brace protect after release")
	assert(Rules.fire_contact_result({"weapon": "bow_01", "ability": 0.0, "training": 0.0, "fatigue": 100.0, "roll": 99.0}, {}, 0.35, false) == body)
	var armors := ["none", "outfit_medieval_chinese_01", "armor_light_leather_01", "armor_iron_01", "armor_mingguang_01"]
	var suffixes := ["_wood", "_stone", "", "_steel"]
	var hp_vectors := [[2.0, 1.0, 0.5, 0.25, 0.125], [4.0, 2.0, 1.0, 0.5, 0.25], [8.0, 4.0, 2.0, 1.0, 0.5], [16.0, 8.0, 4.0, 2.0, 1.0]]
	var tiers := 0
	for family: String in ["bow_01", "crossbow_01"]:
		for material_index in range(suffixes.size()):
			for armor_index in range(armors.size()):
				var source := {"weapon": family + str(suffixes[material_index])}
				var target := {"armor": armors[armor_index]}
				var exact := Rules.fire_contact_result(source, target, 1.0, false)
				var partial := Rules.fire_contact_result(source, target, 0.0, false)
				assert(exact.hp == hp_vectors[material_index][armor_index] and partial.hp == float(exact.hp) * 0.5)
				assert(exact.stun == 8.0 and partial.stun == 4.0)
				assert(is_equal_approx(float(exact.heat_transfer), [1.0, 0.5, 1.0 / 3.0, 0.25, 0.2][armor_index]))
				tiers += 1
	assert(Rules.fire_contact_result({"weapon": "bow_01_wood"}, {"armor": "armor_mingguang_01"}, 0.0, false).hp == 0.0625)
	for invalid: float in [1.1, -1.1, INF, NAN]:
		assert(Rules.fire_contact_result(shooter, {}, invalid, false).is_empty())
	for invalid: float in [-1.0, INF, NAN]:
		assert(Rules.fire_contact_result(shooter, {}, 1.0, false, invalid).is_empty())
	assert(Rules.fire_contact_result({"weapon": "longsword_01"}, {}, 1.0, false).is_empty())
	# The pre-migration helper remains available with its original literal baseline.
	assert(Rules.ranged_result(shooter, {}, 2.0, 65.0).kind == "miss")
	assert(Rules.ranged_result(shooter, {}, 2.0, 39.0).kind == "graze")
	print("SITE_FIRE_RANGED_RULES_PASS: profiles, per-factor stable scatter, isolated RNG, immutable parabola, geometric 0.35 contact, shield/brace/power and ", tiers, " material/armor pairs; pure rules only")
	quit(0)
