extends RefCounted
## Three optional work sequences beside the unchanged required EquipmentAtlas.
## Same original capture/page/dye reader; no person or render/time authority.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Capture = preload("site_siege_work_capture.gd")
const Clips = preload("site_siege_work_clips.gd")
static var _directories := {} # Explicitly admitted append asset paths, never person state.

static func fingerprints() -> Dictionary:
	var result := Atlas.mixed_fingerprints()
	for path: String in ["res://scripts/terrain_lab/site_siege_work_capture.gd", "res://scripts/terrain_lab/site_siege_work_clips.gd", "res://scripts/terrain_lab/terrain_army_atlas_capture.gd"]:
		var digest := FileAccess.get_md5(path)
		if digest.length() != 32: return {}
		result[path] = digest
	return result

static func plan(appearance: Dictionary) -> Dictionary:
	var original := Atlas.mixed_plan(appearance)
	if original.is_empty(): return {}
	var selection: Array[Dictionary] = []
	for clip: String in Clips.ALIASES:
		# Original MixedCapture validates its known selection IDs/rate/count.
		# An explicit custom pose uses new private work tracks, not an idle alias.
		selection.append({"id": Clips.ALIASES[clip], "pose": clip, "samples": 8.0, "rate": 24.0, "combat_ready": false})
	return {"key": original.key, "appearance": original.appearance, "clips": selection,
		"directions": original.directions, "recipe_total": 96, "source_manifest_md5": original.source_manifest_md5,
		"required_original_clips": original.clips}

static func _read(appearance: Dictionary, dir_path: String) -> Dictionary:
	var wanted := plan(appearance)
	if wanted.is_empty(): return {}
	var sources := fingerprints()
	var recipe := Atlas._single_page_recipe(wanted.appearance, dir_path, "terrain_army_mixed_recipe", sources, 31, wanted)
	if recipe.is_empty(): return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir_path + "/manifest.json"))
	var dye: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir_path + "/dye.json"))
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir_path + "/siege_append.json"))
	var dye_sources := Atlas.DyeAtlas.fingerprints()
	for path: String in sources: dye_sources[path] = sources[path]
	if not dye is Dictionary or dye.get("schema_version") != 1 or dye.get("complete") != true or dye.get("slots") != Atlas.DyeAtlas.Dye.SLOTS or dye.get("source_fingerprints") != dye_sources or dye.get("appearance") != wanted.appearance or dye.get("source_manifest") != dir_path + "/manifest.json" or dye.get("source_manifest_md5") != FileAccess.get_md5(dir_path + "/manifest.json") or dye.get("frame_count") != 96: return {}
	if not metadata is Dictionary or metadata.get("schema_version") != 1 or metadata.get("kind") != "terrain_army_siege_work_append" or metadata.get("aliases") != Clips.ALIASES or metadata.get("lengths") != Clips.DURATIONS or metadata.get("source_fingerprints") != sources or metadata.get("required_original_clips") != wanted.required_original_clips: return {}
	if not raw is Dictionary or not Atlas._inside(str(dye.get("mask_path", "")), dir_path + "/") or dye.get("mask_md5") != FileAccess.get_md5(str(dye.mask_path)): return {}
	if dye.get("width") != raw.pages[0].width or dye.get("height") != raw.pages[0].height: return {}
	for clip: String in Clips.ALIASES:
		for direction: Dictionary in wanted.directions:
			var sequence: Array = recipe.sequences[str(Clips.ALIASES[clip]) + "|" + str(direction.id)]
			if sequence.size() != 8 or not is_equal_approx(float(sequence[0].duration), float(Clips.DURATIONS[clip])): return {}
	recipe["dye"] = dye
	recipe["append_path"] = dir_path
	return recipe

static func admit(appearance: Dictionary, dir_path: String) -> bool:
	# Preparation/load boundary only. Never discover or publish assets per frame.
	if not Atlas.supports(appearance): return false
	var recipe := _read(appearance, dir_path)
	if recipe.is_empty(): return false
	var wanted := plan(appearance)
	_directories[str(wanted.key)] = {"directory": dir_path, "recipe": recipe}
	return true

static func prepare(host: Node, appearance: Dictionary, output: String) -> bool:
	if not is_instance_valid(host) or not host.is_inside_tree() or DisplayServer.get_name() == "headless": return false
	# Keep every original mandatory clip and exact equipment recipe admitted.
	if not Atlas.supports(appearance) and not await Atlas.prepare_recipe(host, appearance): return false
	var wanted := plan(appearance)
	if wanted.is_empty() or not (output.begins_with("res://output/") or output == directory(appearance)) or FileAccess.file_exists(output + "/manifest.json"): return false
	var sources := fingerprints()
	var dyes := Atlas.DyeAtlas.fingerprints()
	for path: String in sources: dyes[path] = sources[path]
	var capture := Capture.new()
	capture.timeout_seconds = 105.0
	host.add_child(capture)
	var done: bool = await capture.capture(wanted, output, sources, dyes)
	if is_instance_valid(capture): capture.queue_free()
	if not done: return false
	var file := FileAccess.open(output + "/siege_append.json", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"schema_version": 1, "kind": "terrain_army_siege_work_append", "aliases": Clips.ALIASES,
		"lengths": Clips.DURATIONS, "required_original_clips": wanted.required_original_clips,
		"source_fingerprints": sources, "old_required_assets": "unchanged; ordinary frames remain in the original EquipmentAtlas", "fallback": "original page-aware Sprite2D/BatchView.submit_sprite"}, "\t"))
	file.close()
	return admit(appearance, output)

static func directory(appearance: Dictionary) -> String:
	var wanted := plan(appearance)
	var sources := fingerprints()
	if wanted.is_empty() or sources.is_empty(): return ""
	var namespace_key := JSON.stringify(["siege_work_append_v1", sources, wanted.source_manifest_md5], "", true).sha256_text()
	return Atlas._mixed_root + "/" + namespace_key + "/" + str(wanted.key)

static func ready(appearance: Dictionary) -> bool:
	return _directories.has(Atlas._mixed_key(appearance))

static func ensure(host: Node, appearance: Dictionary) -> bool:
	# Explicit command/load preparation boundary. No per-frame capture.
	if ready(appearance): return true
	var output := directory(appearance)
	if output.is_empty(): return false
	if FileAccess.file_exists(output + "/manifest.json"): return admit(appearance, output)
	return await prepare(host, appearance, output)

static func frame(appearance: Dictionary, clip: String, direction: String, time: float) -> Dictionary:
	if not Clips.ALIASES.has(clip) or not is_finite(time) or time < 0.0: return {}
	var key := Atlas._mixed_key(appearance)
	var admitted: Dictionary = _directories.get(key, {})
	if admitted.is_empty(): return {}
	var recipe: Dictionary = admitted.recipe
	var frames: Array = recipe.sequences.get(str(Clips.ALIASES[clip]) + "|" + direction, [])
	if frames.is_empty(): return {}
	var elapsed := fposmod(time, float(Clips.DURATIONS[clip]))
	var selected: Dictionary = frames[0]
	for candidate: Dictionary in frames:
		if float(candidate.sample_time) > elapsed + 0.000000001: break
		selected = candidate
	var texture := Atlas._page(selected._page)
	if texture == null: return {}
	var image := AtlasTexture.new()
	image.atlas = texture
	image.region = Rect2(float(selected.rect.x), float(selected.rect.y), float(selected.rect.w), float(selected.rect.h))
	return {"clip": clip, "frame": selected.frame, "texture": image, "map_scale": recipe.map_scale, "anchor_offset": selected.anchor_offset, "sample_time": selected.sample_time, "dye": recipe.dye, "append_path": recipe.append_path}

static func apply(sprite: Sprite2D, appearance: Dictionary, frame_value: Dictionary) -> bool:
	if frame_value.is_empty(): return false
	if sprite.get_meta("siege_work_frame", "") != str(frame_value.append_path): sprite.remove_meta("equipment_dye_appearance")
	if not Atlas.DyeAtlas.apply_record(sprite, appearance, frame_value.dye): return false
	sprite.texture = frame_value.texture
	sprite.set_meta("siege_work_frame", str(frame_value.append_path))
	return true
