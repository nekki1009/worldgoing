extends SceneTree
## Probe (2026-11-27, 開局速度 B): a digest of every fixed-base Site build for a before/after comparison of a build
## change. Builds (RegionData.make_terrain_data) the demo A package's initial Sites with their eight neighbours, and a
## 5×5 lattice of plain Taiwan Sites in five source tiles, and prints for each its terrain fingerprint and the hashes of
## resource_base, static_blocked, feature_at and the base record. Two runs (old code, new code) must print the same
## FIXED_DIGEST lines. With -- --parallel every Site is first built on worker threads (RegionData.prebuild_fixed_bases)
## and digested from RegionRoute's memo; it must print the same lines as a serial run.
## Output: FIXED_DIGEST lines, FIXED_DIGEST_TIME, FIXED_DIGEST_DONE.
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"
const TILES := [Vector2i(11, 132), Vector2i(12, 131), Vector2i(13, 130), Vector2i(13, 127), Vector2i(12, 135)]

func _initialize() -> void:
	_run.call_deferred()

func _digest(built: Dictionary) -> String:
	if not bool(built.get("ok", false)): return "refused %s" % str(built.get("code", ""))
	var data: TerrainData = built.data
	return "%s res %s blocked %s features %s base %s" % [data.fingerprint().substr(0, 16),
		JSON.stringify(data.resource_base, "", true, true).sha256_text().substr(0, 16),
		data.static_blocked.hex_encode().sha256_text().substr(0, 16) if data.static_blocked is PackedByteArray else str(data.static_blocked).sha256_text().substr(0, 16),
		str(data.feature_at).sha256_text().substr(0, 16),
		JSON.stringify(built.base, "", true, true).sha256_text().substr(0, 16)]

func _build(source: RegionData, site: Vector2i, parallel: bool) -> Dictionary:
	return RegionRoute.fresh_fixed_base(source, site) if parallel else source.make_terrain_data(site.x, site.y)

func _run() -> void:
	var parallel := "--parallel" in OS.get_cmdline_user_args()
	var started := Time.get_ticks_msec()
	var build_ms := 0.0
	var count := 0
	var author := RegionData.new()
	if not author.load_manifest(PACKAGE).get("ok", false):
		print("FIXED_DIGEST package refused")
		quit(1)
		return
	var seen := {}
	var authored: Array[Vector2i] = []
	for pair: Variant in author.author_initial_context().get("expected_initial_sites", []):
		var site := Vector2i(int(pair[0]), int(pair[1]))
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var at := site + Vector2i(dx, dy)
				if not seen.has(at):
					seen[at] = true
					authored.append(at)
	authored.sort()
	if parallel:
		var t0 := Time.get_ticks_usec()
		author.prebuild_fixed_bases(authored)
		build_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	for site: Vector2i in authored:
		var t := Time.get_ticks_usec()
		var built: Dictionary = _build(author, site, parallel)
		build_ms += float(Time.get_ticks_usec() - t) / 1000.0
		count += 1
		print("FIXED_DIGEST author %s %s" % [str(site), _digest(built)])
	var natural := RegionData.new()
	if not natural.load_manifest(RegionData.DEFAULT_MANIFEST).get("ok", false):
		print("FIXED_DIGEST natural refused")
		quit(1)
		return
	var plain: Array[Vector2i] = []
	for tile: Vector2i in TILES:
		for row: int in range(5):
			for column: int in range(5):
				var site := Vector2i(tile.x * 100 + 10 + column * 20, tile.y * 100 + 10 + row * 20)
				var summary: Dictionary = natural.get_site_summary(site.x, site.y)
				if not bool(summary.get("ok", false)) or summary.get("status") == "outside_content" or int(summary.get("class_id", 0)) == 0:
					print("FIXED_DIGEST natural %s skipped" % str(site))
					continue
				plain.append(site)
	if parallel:
		var t0 := Time.get_ticks_usec()
		natural.prebuild_fixed_bases(plain)
		build_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	for site: Vector2i in plain:
		var t := Time.get_ticks_usec()
		var built: Dictionary = _build(natural, site, parallel)
		build_ms += float(Time.get_ticks_usec() - t) / 1000.0
		count += 1
		print("FIXED_DIGEST natural %s %s" % [str(site), _digest(built)])
	print("FIXED_DIGEST_TIME %d builds %.0f ms (%.0f ms each), run %.0f s" % [count, build_ms, build_ms / maxf(1.0, count), (Time.get_ticks_msec() - started) / 1000.0])
	print("FIXED_DIGEST_DONE")
	quit(0)
