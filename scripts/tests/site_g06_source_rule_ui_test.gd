extends SceneTree
## Original UI controls/RegionData reader/RegionEntry draft seam, NOT OS/GPU.
const Entry = preload("res://scripts/region_lab/region_entry.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const NEW_PATH := "res://assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.terrain_mapped_potential_v1.json"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		push_error(text)

func _run() -> void:
	_check(["F04", "F06", "F11", "F12"].all(func(id: String) -> bool: return bool(Catalog.get_node(id).get("enabled", false))), "Isolated accepted four-category catalog required; fixture never changes it")
	_check(RegionSaveSlot.new()._initial_technology_categories() == ["F04", "F06", "F11", "F12"], "Positive-only candidate derives exactly four from real catalog; existing formal default is still []")
	var choices: Array[Dictionary] = Entry.new_world_source_choices()
	_check(choices.size() == 2 and choices[0].path == RegionData.DEFAULT_MANIFEST and choices[1].path == NEW_PATH, "UI exposes both exact genuine immutable source pairs")
	var original_draft := Entry.draft.duplicate(true)
	var original_pending := Entry.pending.duplicate(true)
	var original_mode := Entry.region_mode
	Entry.draft = {}
	var menu: Control = (load("res://scenes/main_menu/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	menu.call("show_page", "map")
	var selector: OptionButton = menu.find_child("TaiwanSourceRule", true, false) as OptionButton
	_check(selector != null and selector.item_count == 2 and selector.is_visible_in_tree(), "Real original New Game map page has a visible source selector")
	if selector != null:
		selector.select(1)
		selector.item_selected.emit(1)
		_check(Entry.draft.get("manifest") == NEW_PATH and not Entry.draft.has("site"), "Actual original selector signals the source and requires a fresh original start selection")
	Entry.region_mode = "pick_start"
	var picker: Control = (load(Entry.REGION_SCENE) as PackedScene).instantiate()
	root.add_child(picker)
	await process_frame
	var source: RegionData = picker.get("source")
	_check(source.manifest_hash == "cdf59e3247c9db3eb1e5399f7346014f8dec5c2f90bb977fd41ea35bc3444446" and source.resource_manifest_hash == "9acfdc50025eac0c296880102af57cc9d1faef34cc24486eef1594fcc07bd5ef", "Actual original picker uses the selected full geography/resource pair")
	_check(Entry.request_new_world(Vector2i(1170, 13252), {}, "source selector", "", NEW_PATH) and Entry.pending.manifest == NEW_PATH, "Original pending Controller request carries exactly that selected source")
	var before: PackedByteArray = var_to_bytes(Entry.pending)
	_check(not Entry.request_new_world(Vector2i(1170, 13252), {}, "bad source", "", "res://unregistered_source.json") and var_to_bytes(Entry.pending) == before, "Unregistered source rejects atomically without replacing a legitimate pending request")
	picker.free()
	menu.free()
	Entry.draft = original_draft
	Entry.pending = original_pending
	Entry.region_mode = original_mode
	print("SITE_G06_SOURCE_RULE_UI_%s: checks=%d real selector/original draft/paired reader/pending refusal; original fullworld production in separate first-earned tests; GPU/public release excluded" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
