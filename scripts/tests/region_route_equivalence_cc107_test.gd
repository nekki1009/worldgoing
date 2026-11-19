extends SceneTree
## Identical pure public Search fixtures run separately against exact HEAD/FIXED.
## The CLI variant labels output only and never changes fixtures or search inputs.

const Route = preload("res://scripts/region_lab/region_route.gd")
var rows: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _body() -> TerrainData:
	var data: TerrainData = TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.height_levels.fill(1)
	data.water_kind.resize(10000)
	data.water_kind.fill(0)
	data.water_body.resize(10000)
	data.water_body.fill(0)
	data.static_blocked.resize(10000)
	data.static_blocked.fill(0)
	return data

func _case(label: String, kinds: Array[String], mode: String, expected_ok: bool) -> void:
	var first := _body()
	var second := _body()
	var closed := _body()
	closed.flags.fill(0)
	if mode == "blocker": first.static_blocked[first.index(Vector2i(98, 50))] = 1
	if mode == "seam_ramp":
		second.height_levels.fill(2)
		for y: int in 100:
			first.ramp_edges[first.index(Vector2i(99, y))] = 1 << 1
			second.ramp_edges[second.index(Vector2i(0, y))] = 1 << 3
	if mode == "closed_goal": second.flags.fill(0)
	if mode == "prohibited_seam":
		for y: int in 100: first.ramp_edges[first.index(Vector2i(99, y))] = 1 << 5
	if mode == "closed_seam":
		for y: int in 100: first.flags[first.index(Vector2i(99, y))] = 0
	var goal_site: Vector2i = Vector2i(-1, 0) if mode == "west" else Vector2i(0, -1) if mode == "south" else Vector2i(1, 0)
	var start_cell: Vector2i = Vector2i(4, 50) if mode == "west" else Vector2i(50, 95) if mode == "south" else Vector2i(95, 50)
	var bodies: Dictionary = {Vector2i.ZERO: first, goal_site: second}
	var provider: Callable = func(site: Vector2i) -> Dictionary:
		return {"ok": true, "data": bodies.get(site, closed), "revision": label}
	var vehicles: Array[Dictionary] = []
	var poses := {}
	for index: int in kinds.size():
		var kind: String = kinds[index]
		var identity: String = "%s_%d" % [kind, index]
		var operator: Vector2i = start_cell if mode == "duplicate_carts" else start_cell + Vector2i(0, index * 3)
		var facing: Vector2i = Vector2i.LEFT if mode == "west" else Vector2i.DOWN if mode == "south" else Vector2i.RIGHT
		var anchor: Vector2i = SiteVehicleTransport.anchor_from_operator(kind, operator, facing)
		vehicles.append({"id": identity, "kind": kind, "cell": first.index(anchor), "facing": [facing.x, facing.y]})
		poses[identity] = {"anchor": [anchor.x, anchor.y], "operator": [operator.x, operator.y], "facing": [facing.x, facing.y]}
	var source: RegionData = RegionData.new()
	# Every queried Site has an explicit immutable provider body; no fallback IO.
	source.manifest = {"cc107_pure_fixture": label}
	source.manifest_hash = ("cc107_pure_fixture:" + label).sha256_text()
	var search: Route.Search = Route.Search.new()
	search.source = source
	search.start_site = Vector2i.ZERO
	search.goal_site = goal_site
	search.start_component = 0
	search.context = {"projection_mode": "slot_current", "effective_terrain": provider,
		"capabilities": {"mode": "land", "vehicle_kinds": kinds, "vehicles": vehicles,
			"vehicle_poses": poses, "start_cell": start_cell}}
	var result: Dictionary = search.run()
	if bool(result.get("ok", false)) != expected_ok:
		failures.append(label + ": unexpected original result " + str(result))
		push_error("CC107_ROUTE_EQUIVALENCE_FAIL: " + failures.back())
	# Retain all semantic output, costs, complete vehicle paths and expansion count.
	# Site-build counts reflect cache warmness and are excluded from equivalence.
	var stable: Dictionary = result.duplicate(true)
	stable.erase("site_builds")
	stable.erase("wall_ms")
	var bytes: PackedByteArray = var_to_bytes(stable)
	var row: Dictionary = {"case": label, "base64": Marshalls.raw_to_base64(bytes), "hex_text_sha256": bytes.hex_encode().sha256_text()}
	rows.append(row)
	print("CC107_ROUTE_EQUIVALENCE_CASE " + JSON.stringify(row))

func _run() -> void:
	_case("solo_flat", [], "flat", true)
	_case("cart_flat", ["cart"], "flat", true)
	_case("wagon_flat", ["wagon"], "flat", true)
	_case("cart_wagon_flat", ["cart", "wagon"], "flat", true)
	_case("wagon_blocker_detour", ["wagon"], "blocker", true)
	_case("wagon_reciprocal_seam_ramp", ["wagon"], "seam_ramp", true)
	_case("solo_closed_goal", [], "closed_goal", false)
	_case("solo_closed_seam", [], "closed_seam", false)
	_case("cart_blocker_detour", ["cart"], "blocker", true)
	_case("cart_wagon_blocker", ["cart", "wagon"], "blocker", true)
	_case("solo_reciprocal_seam_ramp", [], "seam_ramp", true)
	_case("wagon_closed_goal", ["wagon"], "closed_goal", false)
	_case("cart_closed_seam", ["cart"], "closed_seam", false)
	_case("wagon_prohibited_seam", ["wagon"], "prohibited_seam", false)
	_case("wagon_west", ["wagon"], "west", true)
	_case("wagon_south", ["wagon"], "south", true)
	_case("duplicate_carts", ["cart", "cart"], "duplicate_carts", true)
	var variant := "UNSPECIFIED"
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--cc107-equivalence-variant="): variant = arg.trim_prefix("--cc107-equivalence-variant=")
	print("CC107_ROUTE_EQUIVALENCE_REPORT " + JSON.stringify({"variant": variant, "cases": rows.size(), "failures": failures}))
	if failures.is_empty(): print("CC107_ROUTE_EQUIVALENCE_FIXTURES_PASS")
	quit(0 if failures.is_empty() else 1)
