extends SceneTree
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
var out := ""
var weapon_material := ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon-material="):
			weapon_material = argument.trim_prefix("--weapon-material=")
			assert(weapon_material in ["wood", "stone", "iron", "steel"])
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	create_timer(90.0 if weapon_material.is_empty() else 150.0).timeout.connect(func() -> void: push_error("Pixel test deadline"); quit(1))
	if not weapon_material.is_empty():
		# New 1057-case matrix: retain full per-pixel comparisons at 1:1 scale,
		# with an explicit canvas enclosing the original ground (900, 800).
		root.size = Vector2i(1280, 1000)
		root.content_scale_size = root.size
	out = "res://output/site_army_scale_20260914/pixels_%d" % int(Time.get_unix_time_from_system())
	if not weapon_material.is_empty(): out = "res://output/weapon_materials_npc_20260917/batch_pixels/" + weapon_material
	DirAccess.make_dir_recursive_absolute(out)
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	assert(TerrainArmy.load_combat_bake() and army._load_baked_soldier())
	var parity_samples := _check_sample_parity(army) if weapon_material.is_empty() else 0
	var batch := Batch.new()
	root.add_child(batch)
	batch.setup(army, 256)
	var invalid: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	invalid.equipment_dyes = {"helmet": "123456ff"} # No helmet is equipped in this recipe.
	assert(not batch.submit(0, Vector2.ZERO, invalid, "combat_idle", "down", 0.0))
	assert(not batch.submit(-1, Vector2.ZERO, {}, "combat_idle", "down", 0.0))
	assert(not batch.submit(0, Vector2.ZERO, {}, "combat_idle", "down", INF))
	_check_appearance_snapshots(batch)
	var sprite := Sprite2D.new()
	root.add_child(sprite)
	sprite.texture_filter = CharacterRenderContract.TEXTURE_FILTER
	var neighbour := Sprite2D.new()
	root.add_child(neighbour)
	neighbour.texture_filter = CharacterRenderContract.TEXTURE_FILTER
	var ground := Vector2(900.0, 800.0)
	var checked := 0
	var differences := []
	var weapons: Array = ["longsword_01", "bow_01", "crossbow_01"]
	if not weapon_material.is_empty():
		weapons.clear()
		for row: Dictionary in Atlas.RangedAtlas.Materials.OPTIONS:
			if row.get("material") == weapon_material: weapons.append(row.id)
	for weapon: String in weapons:
		var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		appearance.parts.weapon = weapon
		if weapon != "longsword_01" or not weapon_material.is_empty(): appearance.parts.shield = "none"
		# The published geometry has no helmet or cape: dyeing an absent slot
		# is correctly rejected by the original appearance admission contract.
		appearance.equipment_dyes = {"armor": "76a92dff", "boots": "8453b1ff", "outfit": "f4ca78ff"}
		var clips: Array = ["combat_idle", "combat_walk", "hit", "down", str(HumanCharacter3DEditor.WEAPON_ATTACK_MAP[HumanCharacter3DEditor.WeaponMaterials.family(StringName(weapon))])]
		if not weapon_material.is_empty():
			for guard: String in ["guard", "guard_raise", "guard_break"]: clips.append(Atlas.RangedAtlas.reference_clip(weapon, guard))
		for clip: String in clips:
			if clip == "hit":
				appearance = appearance.duplicate(true)
				TerrainLab.Site._freeze_appearance(appearance)
			for direction: String in ["down", "left", "up", "right"]:
				for elapsed: float in [0.0, 0.371, 0.9]:
					var frame: Dictionary
					if weapon == "longsword_01" and weapon_material.is_empty():
						var clock: Array = TerrainArmy._combat_bake.contact_clocks[clip][direction]
						var time := fposmod(elapsed, float(clock[1])) if bool(clock[2]) else minf(elapsed, float(clock[1]))
						frame = clock[3][0]
						for sample: Dictionary in clock[3]:
							if float(sample.sample_time) <= time + 0.000000001: frame = sample
						sprite.texture = army._soldier_frame_textures["%s|%s|%d" % [clip, direction, int(frame.frame)]]
					else:
						frame = Atlas.frame(appearance, clip, direction, elapsed)
						if frame.is_empty():
							push_error("Missing reference frame: %s %s %s %s; valid=%s dye=%s recipe=%s" % [weapon, clip, direction, elapsed, HumanCharacter3DEditor.valid_appearance(appearance), DyeAtlas.supports(appearance), not Atlas.RangedAtlas.recipe(appearance).is_empty()])
							quit(1)
							return
						sprite.texture = frame.texture
					sprite.scale = Vector2.ONE * army._soldier_map_scale
					sprite.position = ground - Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * army._soldier_map_scale
					if not DyeAtlas.apply(sprite, appearance):
						push_error("Reference dye admission failed at case %d: %s; entry=%s" % [checked, str(appearance), DyeAtlas.entry(appearance)])
						quit(1)
						return
					var neighbour_appearance := appearance.duplicate(true)
					neighbour_appearance.equipment_dyes.armor = "ee3366ff"
					neighbour.texture = sprite.texture
					neighbour.scale = sprite.scale
					neighbour.position = sprite.position + Vector2(12, 0)
					assert(DyeAtlas.apply(neighbour, neighbour_appearance))
					neighbour.show()
					sprite.show()
					batch.hide()
					await process_frame
					await RenderingServer.frame_post_draw
					var reference := root.get_texture().get_image()
					sprite.hide()
					neighbour.hide()
					batch.begin()
					if not batch.submit(0, ground, appearance, clip, direction, elapsed):
						push_error("Batch admission failed: %s %s %s" % [weapon, clip, direction])
						quit(1)
						return
					# Identical sample, different ground and palette: exercise reuse
					# while comparing the complete two-person overlap to real Sprites.
					assert(batch.submit(1, ground + Vector2(12, 0), neighbour_appearance, clip, direction, elapsed))
					_group_for_test(batch)
					batch.flush()
					batch.show()
					await process_frame
					await RenderingServer.frame_post_draw
					var actual := root.get_texture().get_image()
					checked += 1
					if checked in [1, 61, 121] or (not weapon_material.is_empty() and clip == "combat_idle" and direction == "down" and elapsed == 0.0):
						reference.save_png(out + "/" + weapon + "_reference.png")
						actual.save_png(out + "/" + weapon + "_batch.png")
					if reference.get_data() != actual.get_data():
						reference.save_png(out + "/reference.png")
						actual.save_png(out + "/batch.png")
						differences.append({"weapon": weapon, "clip": clip, "direction": direction, "time": elapsed})
						var file := FileAccess.open(out + "/result.json", FileAccess.WRITE)
						file.store_string(JSON.stringify({"checked": checked, "differences": differences}, "\t"))
						push_error("Batch pixel mismatch: " + str(differences.back()))
						quit(1)
						return
	if not await _mixed_overlap(army, batch, sprite): quit(1); return
	checked += 1
	print("ARMY_BATCH_PIXELS_PASS cases=", checked, " exact RGBA; paired sample reuse with independent dyes/grounds, mixed Sprite order; frozen renderer sample comparisons=", parity_samples)
	var file := FileAccess.open(out + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checked": checked, "differences": differences, "sample_parity_checks": parity_samples, "native_groups_exercised": true}, "\t"))
	quit()

func _check_sample_parity(army: TerrainArmy) -> int:
	var legacy_script := GDScript.new()
	legacy_script.source_code = FileAccess.get_file_as_string("res://scripts/tests/fixtures/terrain_army_batch_view_phase3.gd.txt")
	assert(legacy_script.reload() == OK)
	var reference: Node2D = legacy_script.new()
	var actual := Batch.new()
	root.add_child(reference)
	root.add_child(actual)
	reference.hide()
	actual.hide()
	reference.setup(army, 256)
	actual.setup(army, 256)
	var checked := 0
	for weapon: String in ["longsword_01", "bow_01", "crossbow_01"]:
		var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		appearance.parts.weapon = weapon
		if weapon != "longsword_01": appearance.parts.shield = "none"
		appearance.equipment_dyes = {"armor": "114477ff"}
		assert(actual.submit(0, Vector2.ZERO, appearance, "combat_idle", "down", 0.0))
		assert(reference.submit(0, Vector2.ZERO, appearance, "combat_idle", "down", 0.0))
		var page: Dictionary = reference._pages[int(reference._page[0])]
		for key: String in page.sequences:
			var clip := key.get_slice("|", 0)
			var direction := key.get_slice("|", 1)
			var frames: Array = page.samples[int(page.sequences[key])]
			var times: Array[float] = [0.0, float(frames[0].duration), float(frames[0].duration) * 1000.0 + 0.371]
			for frame: Dictionary in frames:
				for epsilon: float in [-0.000000002, 0.0, 0.000000002]:
					times.append(maxf(0.0, float(frame.sample_time) + epsilon))
			for time: float in times:
				reference.begin()
				actual.begin()
				assert(actual._last_page == -1)
				for index in range(4):
					# Consecutive equal clocks, then a distinct near-boundary clock.
					var sample_time := time if index < 3 else time + 0.000000002
					var ground := Vector2(900.125 + index * 6.0, 800.375 - index * 0.125)
					appearance.equipment_dyes.armor = "114477ff" if index % 2 == 0 else "ee3366ff"
					assert(reference.submit(index, ground, appearance, clip, direction, sample_time))
					assert(actual.submit(index, ground, appearance, clip, direction, sample_time))
					for column: String in ["_sequence", "_frames", "_positions", "_page", "_palette", "_rows", "rendered_count"]:
						assert(actual.get(column) == reference.get(column), "%s %s t=%.12f index=%d column=%s" % [weapon, key, time, index, column])
					checked += 1
					# A rejected call between equal valid samples must not poison reuse.
					assert(not actual.submit(255, ground, appearance, "missing_clip", direction, sample_time))
					assert(not actual.submit(-1, ground, appearance, clip, direction, sample_time))
					assert(not actual.submit(0, ground, appearance, clip, direction, NAN))
					assert(not actual.submit(0, ground, appearance, clip, direction, -1.0))
					assert(not reference.submit(255, ground, appearance, "missing_clip", direction, sample_time))
			# Compare the final uploaded buffers/bounds too, not just chosen frames.
			reference.flush()
			_group_for_test(actual)
			actual.flush()
			assert(actual._batches.keys() == reference._batches.keys())
			for batch_key: Vector2i in actual._batches:
				var left: MultiMesh = actual._batches[batch_key].multimesh
				var right: MultiMesh = reference._batches[batch_key].multimesh
				assert(left.buffer == right.buffer and left.custom_aabb == right.custom_aabb)
	# Guard aliases have separate input keys but the same original sequence rules.
	for alias: String in ["guard", "guard_unshielded", "guard_weapon", "guard_weapon_left", "guard_weapon_right"]:
		var accepted: bool = reference.submit(0, Vector2.ZERO, {}, alias, "right", 0.371)
		assert(actual.submit(0, Vector2.ZERO, {}, alias, "right", 0.371) == accepted)
		if accepted: assert(actual._frames == reference._frames and actual._positions == reference._positions)
	reference.queue_free()
	actual.queue_free()
	return checked

func _check_appearance_snapshots(batch: Node2D) -> void:
	var partial: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	partial.equipment_dyes = {"armor": "123456ff"}
	partial.make_read_only() # Nested dye values are deliberately still mutable.
	assert(not Batch._deep_read_only(partial))
	assert(batch.submit(250, Vector2.ZERO, partial, "combat_idle", "down", 0.0))
	var palette := int(batch._descriptors[250].palette)
	partial.equipment_dyes.armor = "654321ff"
	assert(batch.submit(250, Vector2.ZERO, partial, "combat_idle", "down", 0.0))
	assert(int(batch._descriptors[250].palette) != palette and not is_same(partial, batch._appearances[250]))
	var frozen := partial.duplicate(true)
	TerrainLab.Site._freeze_appearance(frozen)
	assert(Batch._deep_read_only(frozen))
	assert(batch.submit(251, Vector2.ZERO, frozen, "combat_idle", "down", 0.0))
	assert(is_same(frozen, batch._appearances[251]))
	var replacement := frozen.duplicate(true)
	replacement.equipment_dyes.armor = "0099aaff"
	TerrainLab.Site._freeze_appearance(replacement)
	assert(batch.submit(251, Vector2.ZERO, replacement, "combat_idle", "down", 0.0))
	assert(is_same(replacement, batch._appearances[251]))
	batch.begin()

func _mixed_overlap(army: TerrainArmy, batch: Node2D, previous: Sprite2D) -> bool:
	previous.hide()
	batch.hide()
	var sprites: Array[Sprite2D] = []
	var appearances: Array[Dictionary] = []
	var clips: Array[String] = ["hit", "combat_idle", "combat_walk", "walk_slash"]
	for index in range(4):
		var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		appearance.equipment_dyes = DyeAtlas.Dye.PRESETS["blue" if index % 2 == 0 else "red"].colors.duplicate()
		appearance.equipment_dyes.erase("helmet")
		appearance.equipment_dyes.erase("cape")
		if index == 2:
			appearance.parts.weapon = "bow_01"
			appearance.parts.shield = "none"
		appearances.append(appearance)
		var frame: Dictionary = Atlas.frame(appearance, clips[index], "right", 0.0) if index == 2 else TerrainArmy._combat_bake.contact_clocks[clips[index]].right[3][0]
		var item := Sprite2D.new()
		root.add_child(item)
		item.texture_filter = CharacterRenderContract.TEXTURE_FILTER
		item.texture = frame.texture if index == 2 else army._soldier_frame_textures["%s|right|0" % clips[index]]
		item.scale = Vector2.ONE * army._soldier_map_scale
		item.position = Vector2(900 + index * 6, 800) - Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * army._soldier_map_scale
		item.z_index = 22
		assert(DyeAtlas.apply(item, appearance))
		sprites.append(item)
	await process_frame
	await RenderingServer.frame_post_draw
	var reference := root.get_texture().get_image()
	batch.begin()
	for index in range(4):
		if index == 1:
			batch.submit_sprite(index, Vector2(906, 800), sprites[index])
		else:
			sprites[index].hide()
			assert(batch.submit(index, Vector2(900 + index * 6, 800), appearances[index], clips[index], "right", 0.0))
	_group_for_test(batch)
	batch.flush()
	batch.show()
	await process_frame
	await RenderingServer.frame_post_draw
	var actual := root.get_texture().get_image()
	reference.save_png(out + "/mixed_reference.png")
	actual.save_png(out + "/mixed_batch.png")
	if reference.get_data() != actual.get_data():
		push_error("Mixed Sprite/batch same-row overlap changed")
		return false
	return true

# Feed the already admitted presentation columns through the new grouping
# boundary, including interleaved original Sprites. No gameplay state is faked.
func _group_for_test(batch: Node2D) -> void:
	var expected: Dictionary = batch._rows.duplicate(true)
	batch._native_mask.resize(batch._page.size())
	batch._native_mask.fill(0)
	batch._native_rows.resize(batch._page.size())
	batch._rows = {}
	batch.rendered_count = 0
	batch.native_prepared_count = 0
	for row: int in expected:
		expected[row].sort()
		for index: int in expected[row]:
			if batch._page[index] >= 0:
				batch._native_mask[index] = 1
				batch._native_rows[index] = row
			else:
				if not batch._rows.has(row): batch._rows[row] = []
				batch._rows[row].append(index)
	batch.finish_prepared_groups()
	assert(batch._groups_ready and var_to_bytes(batch._rows) == var_to_bytes(expected))
