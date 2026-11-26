extends SceneTree
## Probe (2026-11-27, 開局速度 B): a digest of every authored projection (RegionData.project_terrain "author_initial") of
## the shipped demo A package, for a before/after comparison of a projection change: the terrain fingerprint, the
## boundary fields refresh_boundary writes (cliff drops, ramp edges, flags, the ramp visual halo) and the Site state.
## Two runs (old code, new code) must print the same PROJECTION_DIGEST lines.
## Output: PROJECTION_DIGEST lines, PROJECTION_DIGEST_TIME, PROJECTION_DIGEST_DONE.
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

func _initialize() -> void:
	_run.call_deferred()

func _hash(value: Variant) -> String:
	return str(value).sha256_text().substr(0, 16)

func _run() -> void:
	var source := RegionData.new()
	if not source.load_manifest(PACKAGE).get("ok", false):
		print("PROJECTION_DIGEST load failed")
		quit(1)
		return
	var started := Time.get_ticks_msec()
	var sites: Array = source.author_initial_context().get("expected_initial_sites", [])
	for pair: Variant in sites:
		var site := Vector2i(int(pair[0]), int(pair[1]))
		var projected: Dictionary = source.project_terrain(site, "author_initial")
		if not bool(projected.get("ok", false)):
			print("PROJECTION_DIGEST %s refused %s" % [str(site), str(projected.get("code", ""))])
			continue
		var data: TerrainData = projected.data
		print("PROJECTION_DIGEST %s %s cliffs %s ramps %s flags %s halo %s state %s base %s revision %s" % [str(site), data.fingerprint().substr(0, 16),
			_hash(data.cliff_drops), _hash(data.ramp_edges), _hash(data.flags),
			JSON.stringify(data.parameters.get("ramp_visual_halo", {}), "", true, true).sha256_text().substr(0, 16),
			JSON.stringify(data.site, "", true, true).sha256_text().substr(0, 16),
			JSON.stringify(projected.base, "", true, true).sha256_text().substr(0, 16), str(projected.get("revision", "")).substr(0, 16)])
	# A refusal must stay a refusal: a Site whose neighbour is outside the source content.
	var edge: Dictionary = source.project_terrain(Vector2i(-5, -5), "author_initial")
	print("PROJECTION_DIGEST outside %s %s" % [str(edge.get("ok", false)), str(edge.get("code", ""))])
	print("PROJECTION_DIGEST_TIME %d Sites in %.0f s" % [sites.size(), (Time.get_ticks_msec() - started) / 1000.0])
	print("PROJECTION_DIGEST_DONE")
	quit(0)
