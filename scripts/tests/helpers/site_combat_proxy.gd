extends "res://scripts/terrain_lab/terrain_weapon_collision.gd"
## Test-only coarse collision contract, NOT exact mesh collision. Pure local
## geometry from compact offline tracks; original people/clocks/contact resolver
## remain owners. No AnimationPlayer/Skeleton/mesh reads for collision sampling.
const PROFILE_PATH := "res://output/site_combat_proxy_20260914/profile.bin"
var tracks: Dictionary = {}
var profile_sources: Dictionary = {}
var appearance: Dictionary = {}
var samples := 0
var cache_hits := 0
var unsupported := 0
var _sample_cache: Dictionary = {}

func load_profile() -> bool:
	var file := FileAccess.open_compressed(PROFILE_PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return false
	var data: Variant = file.get_var(false)
	file.close()
	if not data is Dictionary or data.get("schema") != 1 or data.get("test_only") != true:
		return false
	for path: String in data.sources:
		if FileAccess.get_sha256(path) != data.sources[path]:
			return false
	tracks = data.tracks
	profile_sources = data.sources
	appearance = data.appearance
	return not tracks.is_empty()

func sample(clip: String, time: float, direction: Vector2i, aim: Vector2, weight: float, recipe: Dictionary) -> Dictionary:
	samples += 1
	var shielded := str(recipe.parts.shield) != "none"
	var weapon := str(recipe.parts.weapon)
	var track_key := clip + "|" + str({Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.UP: "up", Vector2i.RIGHT: "right"}.get(direction, ""))
	if bool(recipe.mounted) or not tracks.has(track_key) or not is_finite(time) or not aim.is_finite():
		unsupported += 1
		push_error("COMBAT_PROXY_UNSUPPORTED " + track_key)
		return {}
	var track: Dictionary = tracks[track_key]
	var elapsed := fposmod(time, float(track.duration)) if bool(track.loop) else clampf(time, 0.0, float(track.duration))
	var key := [track_key, elapsed, aim, weight, shielded, weapon]
	if _sample_cache.has(key):
		cache_hits += 1
		return _sample_cache[key]
	var times: PackedFloat64Array = track.times
	var low := 0
	var high := times.size()
	while low + 1 < high:
		var middle := (low + high) >> 1
		if times[middle] <= elapsed:
			low = middle
		else:
			high = middle
	var next := mini(low + 1, times.size() - 1)
	var next_time := times[next]
	if low == times.size() - 1 and bool(track.loop):
		next = 0
		next_time = float(track.duration)
	var blend := clampf((elapsed - times[low]) / (next_time - times[low]), 0.0, 1.0) if next_time > times[low] else 0.0
	var result := {}
	for kind: String in ["body", "weapon", "shield", "parry"]:
		result[kind] = _between(track.frames[low][kind], track.frames[next][kind], blend)
	if not shielded:
		result.shield = [] as Array[PackedVector2Array]
	if weapon == "none" and clip != "attack_unarmed":
		result.weapon = [] as Array[PackedVector2Array]
	# Guard only. The offline table contains parry outlines even outside guard.
	if shielded or clip not in ["guard_unshielded", "guard_spear", "guard_weapon", "guard_polearm"] or weapon in ["none", "bow_01", "crossbow_01"]:
		result.parry = [] as Array[PackedVector2Array]
	result.shoulder = polygon_bounds(result.body[4]).get_center()
	if weight > 0.0 and not result.weapon.is_empty():
		# Explicit simplified aim rule: bias the sampled weapon toward the
		# saved aim around the shoulder, capped at 60 degrees; not native arm IK.
		var tip := polygon_bounds(result.weapon[0]).get_center() - Vector2(result.shoulder)
		var target := aim - Vector2(result.shoulder)
		if tip.length_squared() > 0.0001 and target.length_squared() > 0.0001:
			var angle := clampf(tip.angle_to(target), -PI / 3.0, PI / 3.0) * clampf(weight, 0.0, 1.0)
			var rotation := Transform2D(angle, Vector2.ZERO)
			rotation.origin = Vector2(result.shoulder) - rotation * Vector2(result.shoulder)
			for index in result.weapon.size():
				result.weapon[index] = rotation * PackedVector2Array(result.weapon[index])
	var points := PackedVector2Array()
	for kind: String in ["body", "shield", "parry"]:
		for shape: PackedVector2Array in result[kind]:
			points.append_array(shape)
	result.hurt_bounds = polygon_bounds(points)
	# Pure data has no editor history: bounded eviction cannot change a result.
	if _sample_cache.size() >= 128:
		_sample_cache.clear()
	_sample_cache[key] = result
	return result

func _between(a: Array, b: Array, weight: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	# Visibility transitions have no corresponding polygon: keep the preceding
	# key until the transition. Fixed four-corner boxes otherwise interpolate.
	if a.size() != b.size():
		result.assign(a)
		return result
	for index in a.size():
		var points := PackedVector2Array()
		for corner in 4:
			points.append(Vector2(a[index][corner]).lerp(Vector2(b[index][corner]), weight))
		result.append(points)
	return result

func army_sample(team: TerrainArmy, index: int) -> Dictionary:
	var inputs := team._contact_inputs(index)
	return sample(team._combat_clip(index), float(inputs.sample[1]), team.facing[index], inputs.sample[3], float(inputs.sample[4]), inputs.appearance)

func actor_sample(actor: TerrainTestCharacter) -> Dictionary:
	var recipe := actor.editor.capture_appearance()
	var clip := str(actor.visual_state.animation_id)
	if actor.combat_ready and clip in ["idle", "walk", "run"]:
		clip = "combat_" + clip
	if clip == "guard_weapon":
		clip = "guard_unshielded"
	elif clip == "guard_polearm":
		clip = "guard_spear"
	var origin := actor.global_position + actor._attack_offset + actor._stance_offset
	var aim := Vector2.ZERO
	var weight := 0.0
	if actor._strike_at >= 0.0 and actor.facing == Vector2i.DOWN:
		aim = actor._attack_aim_point - origin
		var fraction := actor.visual_state.animation_time / actor._clip_duration
		weight = smoothstep(0.18, 0.40, fraction) * (1.0 - smoothstep(0.65, 0.90, fraction))
	return sample(clip, actor.visual_state.animation_time, actor.facing, aim, weight, recipe)

func actor_shapes(actor: TerrainTestCharacter, kind: String) -> Array[PackedVector2Array]:
	var value := actor_sample(actor)
	return shifted(value.get(kind, []), actor.global_position + actor._attack_offset + actor._stance_offset)

func body_shapes(actor: Variant) -> Array[PackedVector2Array]:
	return actor_shapes(actor, "body")

func weapon_shapes(actor: Variant, _clip: StringName, parrying: bool = false) -> Array[PackedVector2Array]:
	return actor_shapes(actor, "parry" if parrying else "weapon")

func shield_shapes(actor: Variant) -> Array[PackedVector2Array]:
	return actor_shapes(actor, "shield")

func protection(recipe: Dictionary, body_index: int, kind: String) -> Vector2:
	# Shared prototype balance: head=helmet; torso/arms=armor+outfit;
	# thighs=outfit; shins/feet=boots. No triangle-level holes or mesh fitting.
	var slots: Array = ["helmet"] if body_index == 1 else (["armor", "outfit"] if body_index < 6 else (["boots"] if body_index in [7, 9] else ["outfit"]))
	var result := Vector2.ZERO
	for slot: String in slots:
		var item := str(recipe.parts[slot])
		if item != "none":
			var values := SiteCombatRules.armor_profile(item)
			result += Vector2(float(values.get(kind, 0.0)), float(values.cushion))
	return result
