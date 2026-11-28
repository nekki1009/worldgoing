extends RefCounted
## Captive (stripped) looks baked when the game is packed, so a new world does not bake them while it is played
## (Nekki 2026-11-28 「好」: a town baked them for more than 5 minutes after it opened, about 15 ms a frame, and froze
## 5-6 s when the bake ended). scripts/tools/bake_captivity_appearances.gd --seed-out=<SEED_ROOT> bakes a scenario's
## looks (scripts/tests/scenario_captive_looks_probe.gd lists them) into the usual user cache and stores each baked
## look under SEED_ROOT with an index. seed() copies a stored look back into the user cache, byte for byte, when the
## cache has no such look and the look was baked for the same atlas sources (the same cache directory); a look baked
## for other sources is left alone and the game bakes it as before. Nothing here reads or changes a recipe: the atlas
## reader admits the copied files exactly as it admits files it baked itself (same paths, same md5s).
## Stored names never start with a dot and never end in .png or .res, so the editor neither hides nor imports them;
## the index maps each stored name back to its original relative path.
## The seed is built on this machine and is not kept in git (Nekki 2026-11-28 C: no LFS budget left); without it a
## clone bakes the looks once while the game is played, paused (TerrainLab._atlas_bake_pause).
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const SEED_ROOT := "res://assets/characters/terrain_lab_army/captive_seed/v1"
const INDEX := SEED_ROOT + "/index.json"
const SCHEMA := 1

static var _seeded := false

## Copies every stored look whose cache directory is the current one and is missing there. Once a process; returns
## {copied, skipped, stale} counts (stale: baked for other sources).
static func seed() -> Dictionary:
	var counts := {"copied": 0, "skipped": 0, "stale": 0}
	if _seeded: return counts
	_seeded = true
	if not FileAccess.file_exists(INDEX): return counts
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not index is Dictionary or index.get("schema") != SCHEMA or not index.get("looks") is Array: return counts
	for look: Variant in index.looks:
		if not look is Dictionary or not look.get("files") is Array: continue
		var directory := _cache_directory(str(look.get("key", "")))
		if directory.is_empty() or directory != str(look.get("directory", "")):
			counts.stale += 1
			continue
		if FileAccess.file_exists(directory + "/manifest.json"):
			counts.skipped += 1
			continue
		var complete := true
		for entry: Variant in look.files:
			if not entry is Dictionary: complete = false; break
			var target := directory + "/" + str(entry.get("path", ""))
			var stored := SEED_ROOT + "/" + str(entry.get("stored", ""))
			var bytes := FileAccess.get_file_as_bytes(stored)
			if bytes.is_empty() or bytes.size() != int(entry.get("size", -1)):
				complete = false
				break
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
			var file := FileAccess.open(target, FileAccess.WRITE)
			if file == null:
				complete = false
				break
			file.store_buffer(bytes)
			file.close()
		if complete: counts.copied += 1
		else:
			# A partial copy is removed again: the reader would refuse it anyway, and the game bakes the look as before.
			for entry: Variant in look.files:
				if entry is Dictionary: DirAccess.remove_absolute(ProjectSettings.globalize_path(directory + "/" + str(entry.get("path", ""))))
	return counts

## Atlas._mixed_directory(key) without filling the atlas reader's static source and namespace caches: this runs when a
## Lab opens, before tests or tools that set those caches themselves (crowd_c2_atlas_visual_test freezes its sources).
static func _cache_directory(key: String) -> String:
	if key.is_empty(): return ""
	var sources: Dictionary = Atlas._mixed_sources if not Atlas._mixed_sources.is_empty() else Atlas.mixed_fingerprints()
	if sources.is_empty(): return ""
	var source_space: String = Atlas._mixed_namespace if not Atlas._mixed_namespace.is_empty() else JSON.stringify([sources, FileAccess.get_md5(Atlas.BASE_MANIFEST)], "", true).sha256_text()
	return Atlas._mixed_root + "/" + source_space + "/" + key

## The stored name of a file at `relative` (a path inside one look's cache directory).
static func stored_name(key: String, relative: String) -> String:
	var parts: PackedStringArray = relative.split("/")
	for i in range(parts.size()):
		if parts[i].begins_with("."): parts[i] = "dot_" + parts[i].substr(1)
	return key + "/" + "/".join(parts) + ".seed"
