extends SceneTree
## Original Window + original Actor/Family/Settlement/PA query guards only.
## No research/output, shared work, Store, Native or visual close is claimed.
const F07Fixture = preload("res://scripts/tests/site_f07_research_test.gd")
const WindowOwner = preload("res://scripts/terrain_lab/site_tech_window.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SITE_TECHNOLOGY_WINDOW_SCOPE_FAIL: " + message)

func select_node(window: SiteTechWindow, identity: String) -> void:
	for index: int in window._scope_node.item_count:
		if window._scope_node.get_item_metadata(index) == identity:
			window._scope_node.select(index)
			window.refresh()
			return
	check(false, "Original node absent from the formal Window: " + identity)

func run() -> void:
	var fixture = F07Fixture.Fixture.new()
	var lab = TerrainLab.new()
	lab.restore_only = true # No original UI frame/update or simulation is run.
	lab.terrain = fixture.terrain
	# The F07 fixture allocates terrain by hand; real worlds size the feature index
	# in Env. Building previews behind the Window read it.
	if lab.terrain.feature_at.size() != lab.terrain.surface_types.size():
		lab.terrain.feature_at.resize(lab.terrain.surface_types.size())
		lab.terrain.feature_at.fill(0)
	# Founding below reads real land conditions; give the hand fixture one explicit,
	# uniform soil (as it already gives uniform walkable flags).
	for land_name: String in ["fertility", "moisture", "drainage", "foundation", "groundwater"]:
		var land = lab.terrain.get(land_name)
		if land.size() != lab.terrain.surface_types.size():
			land.resize(lab.terrain.surface_types.size())
			land.fill(50)
			lab.terrain.set(land_name, land)
	lab.character = fixture.character
	lab.npc = fixture.npc
	lab.combat_actors.append(fixture.character)
	lab.combat_actors.append(fixture.npc)
	lab.site_controller = fixture.site_controller
	fixture.site_controller.lab = lab
	# The real controller initialises its vehicle transport on bind; stock reads
	# (productive sources, preview_build/found) go through it.
	fixture.site_controller.vehicles.init(fixture.site_controller)
	fixture.site_controller.person_actions = fixture.actions
	fixture.actions.init(lab)
	var column = VBoxContainer.new()
	root.add_child(column)
	var window = WindowOwner.new()
	var before = fixture.commit_snapshot()
	window.install(fixture.site_controller, column)
	# The Window also lists the 12 nation nodes (N01-N12) added to the catalog.
	check(window._scope_node.item_count == 40, "All 15 family, 13 settlement and 12 nation nodes are visible")
	check(window._buttons.has("F07BeginTrial") and window._buttons.has("F07BeginLesson"), "Original F07 inputs are retained")
	# F03, F07 and F04 were accepted on 2026-11-06; F05 (still a candidate) is the undelivered node this boundary covers.
	select_node(window, "F05")
	check(not bool(Catalog.get_node("F05").enabled), "This fixture covers the undelivered F05 activation boundary")
	check(window._scope_buttons.ScopeGrantBudget.disabled and window._scope_buttons.ScopeBeginPhase.disabled, "Undelivered node cannot collect research budget or begin work")
	check(not window._scope_submit_query().ok and window._scope_submit_query().code == "NOT_DELIVERED", "Submitting rechecks delivery rather than trusting a disabled button")
	window._scope_prepare("first") # Forced signal path must still be harmless.
	check(fixture.commit_snapshot() == before, "Opening/querying/forced disabled input leave original state byte-identical")
	var held: Dictionary = lab.terrain.site
	lab.terrain.site = held.duplicate(true)
	check(not window._scope_submit_query(true).ok and window._scope_submit_query(true).code == "STALE_SOURCE", "Equal replacement Site is not the original held reference")
	lab.terrain.site = held
	lab.terrain.site.controlled_person_id = 2
	check(not window._scope_submit_query(true).ok, "Actual control change invalidates all held input")
	lab.terrain.site.controlled_person_id = 1
	window.context_changed()
	window.refresh()
	var registered_family: Dictionary = lab.terrain.site.family
	lab.terrain.site.erase("family")
	lab.terrain.site["features"] = {}
	lab.terrain.site["next_feature"] = 1
	lab.terrain.site["zones"] = []
	lab.terrain.site["notices"] = []
	lab.terrain.site.inventory["stone"] = 20
	var cells: Array[int] = []
	for y: int in range(6, 11):
		for x: int in range(6, 11): cells.append(lab.terrain.index(Vector2i(x, y)))
	var founded = Settlement.found(lab, 1, cells, {"quarter": 0}, Callable(), "原中心")
	check(founded.ok, "Original founding command supplies the real settlement record: " + str(founded))
	if founded.ok:
		before = fixture.commit_snapshot()
		check(not fixture.actions.scope_technology_query("F03").ok, "An unregistered family remains unregistered")
		var settlement_query = fixture.actions.scope_technology_query("S01")
		check(settlement_query.ok and settlement_query.scope == "settlement", "Original settlement query is independent of family registration")
		select_node(window, "S01")
		check(window._scope_context.get("scope") == "settlement", "F07 early UNREGISTERED does not hide settlement state")
		check(fixture.commit_snapshot() == before, "Settlement Window refresh does not create family/technology or migrate offices")
	lab.terrain.site["family"] = registered_family
	column.free()
	lab.site_controller = null
	lab.combat_actors.clear()
	fixture.close()
	lab.free()
	print("SITE_TECHNOLOGY_WINDOW_SCOPE_%s: checks=%d failures=%d; original queries and input rejection only; runtime/Native/visual/Store excluded" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
