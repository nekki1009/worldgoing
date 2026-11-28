extends SceneTree
## Probe (2026-11-27, 開局速度): a second RegionData of the same pinned manifest takes the source tile the first one
## read and checked (RegionData._shared_tiles). Builds the same Site on two fresh loads of the Taiwan source and on a
## third after the first two are freed, and compares the builds' fingerprints and the first-build times.
## Output: SHARED_TILE lines and SHARED_TILE_DONE.
const SITE := Vector2i(1165, 13247)

func _initialize() -> void:
	_run.call_deferred()

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0

func _build(label: String) -> String:
	var source := RegionData.new()
	var t := Time.get_ticks_usec()
	source.load_manifest(RegionData.DEFAULT_MANIFEST)
	var load_ms := _ms(t)
	t = Time.get_ticks_usec()
	var built: Dictionary = source.make_terrain_data(SITE.x, SITE.y)
	var build_ms := _ms(t)
	t = Time.get_ticks_usec()
	source.make_terrain_data(SITE.x, SITE.y + 1)
	var again_ms := _ms(t)
	var fingerprint: String = (built.data as TerrainData).fingerprint() if built.get("ok", false) else "refused"
	print("SHARED_TILE %s: load %.0f ms, first build %.0f ms, next build %.0f ms, fingerprint %s" % [label, load_ms, build_ms, again_ms, fingerprint.substr(0, 16)])
	return fingerprint

func _run() -> void:
	var first := _build("first instance")
	var second := _build("second instance")
	var third := _build("third instance")
	print("SHARED_TILE same builds %s" % str(first == second and second == third and first != "refused"))
	print("SHARED_TILE_DONE")
	quit(0)
