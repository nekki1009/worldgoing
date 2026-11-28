extends SceneTree
## 示範劇本 A step 5: builds the shipped package res://assets/scenarios/demo_a/demo_a.json with demo_a_generator:
## 30 settlements (3 market towns), 15 bandit bands, seed 20261122, on the Taiwan source near the default start
## (Nekki 11/22). The New Game scenario list finds it there (RegionEntry.scenario_packages). Rebuilding writes the same
## file names again. Run headless (about 16 minutes):
##   godot --headless --path <project> -s res://scripts/scenarios/build_demo_a.gd
## Prints DEMO_A_BUILT …; quit(1) on a refusal.
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const FOLDER := "res://assets/scenarios/demo_a"
const SETTLEMENTS := 30
const BANDS := 15
const TOWNS := 3
const SEED := 20261122

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	push_error("DEMO_A_BUILD_FAIL: %s %s" % [message, str(detail)])
	quit(1)

func _run() -> void:
	if not DirAccess.dir_exists_absolute(FOLDER) and DirAccess.make_dir_recursive_absolute(FOLDER) != OK:
		_fail("package folder", FOLDER)
		return
	var natural := RegionData.new()
	var loaded: Dictionary = natural.load_manifest(RegionData.DEFAULT_MANIFEST)
	if not loaded.get("ok", false):
		_fail("the Taiwan source", loaded)
		return
	var built: Dictionary = Generator.generate(natural, FOLDER, "demo_a.json", SETTLEMENTS, BANDS, TOWNS, SEED)
	if not built.get("ok", false):
		_fail("generate", built)
		return
	# The built package loads as the game will load it.
	var package := RegionData.new()
	var check: Dictionary = package.load_manifest(str(built.path))
	if not check.get("ok", false):
		_fail("the package loads", check)
		return
	print("DEMO_A_BUILT path=%s start=%s sites=%d settlements=%d bands=%d residents=%d bandits=%d seconds=%.1f" % [str(built.path), str(built.start),
		package.author_initial_context().expected_initial_sites.size(), built.settlements.size(), built.lairs.size(), int(built.residents), int(built.bandits), float(built.seconds)])
	quit(0)
