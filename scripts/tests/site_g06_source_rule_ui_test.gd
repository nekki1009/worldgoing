extends SceneTree

const DisabledCatalogContract = preload("res://scripts/tests/fixtures/disabled_catalog_test_contract.gd")
var _disabled_contract: Variant = DisabledCatalogContract.new()

func _finalize() -> void:
	OS.remove_logger(_disabled_contract)

func _process(_delta: float) -> bool:
	_disabled_contract.poll(self)
	return false

## Original UI controls/RegionData reader/RegionEntry draft seam, NOT OS/GPU.
const Entry = preload("res://scripts/region_lab/region_entry.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const NEW_PATH := "res://assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.terrain_mapped_potential_v1.json"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	OS.add_logger(_disabled_contract)
	_run.call_deferred()

func _check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		push_error(text)

func _run() -> void:
	if not _disabled_contract.begin(self, ["F04", "F06", "F11", "F12"]): return
	if _disabled_contract.profile == "formal_disabled":
		_check(["F04", "F06", "F11", "F12"].all(func(id: String) -> bool: return not bool(Catalog.get_node(id).get("enabled", false))), "Formal disabled profile retains all four disabled categories")
		if not _disabled_contract.poll(self): return
		_check(RegionSaveSlot.new()._initial_technology_categories() == [], "Formal disabled profile starts with no technology categories")
		if not _disabled_contract.poll(self): return
	else:
		_check(["F04", "F06", "F11", "F12"].all(func(id: String) -> bool: return bool(Catalog.get_node(id).get("enabled", false))), "Isolated accepted four-category catalog required; fixture never changes it")
		if not _disabled_contract.poll(self): return
		_check(RegionSaveSlot.new()._initial_technology_categories() == ["F04", "F06", "F11", "F12"], "Positive-only candidate derives exactly four from real catalog; existing formal default is still []")
		if not _disabled_contract.poll(self): return
	var choices: Array[Dictionary] = Entry.new_world_source_choices()
	if _disabled_contract.profile == "formal_disabled":
		_check(choices.size() == 1 and choices[0].path == RegionData.DEFAULT_MANIFEST, "Formal disabled publication exposes exactly the genuine original source")
		if not _disabled_contract.poll(self): return
	else:
		_check(choices.size() == 2 and choices[0].path == RegionData.DEFAULT_MANIFEST and choices[1].path == NEW_PATH, "UI exposes both exact genuine immutable source pairs")
		if not _disabled_contract.poll(self): return
	var original_draft: Dictionary = Entry.draft.duplicate(true)
	var original_pending: Dictionary = Entry.pending.duplicate(true)
	var original_mode: String = Entry.region_mode
	Entry.draft = {}
	var menu: Control = (load("res://scenes/main_menu/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	if not _disabled_contract.poll(self): return
	menu.call("show_page", "map")
	var selector: OptionButton = menu.find_child("TaiwanSourceRule", true, false) as OptionButton
	if _disabled_contract.profile == "formal_disabled":
		_check(selector != null and selector.item_count == 1 and selector.is_visible_in_tree() and selector.get_item_metadata(0) == RegionData.DEFAULT_MANIFEST, "Real formal map page exposes exactly one original source and no unpublished candidate")
		if not _disabled_contract.poll(self): return
	else:
		_check(selector != null and selector.item_count == 2 and selector.is_visible_in_tree(), "Real original New Game map page has a visible source selector")
		if not _disabled_contract.poll(self): return
	if selector != null:
		if _disabled_contract.profile == "formal_disabled":
			selector.select(0)
			selector.item_selected.emit(0)
			_check(Entry.draft.get("manifest") == RegionData.DEFAULT_MANIFEST and not Entry.draft.has("site"), "Actual formal selector signals only the original source and requires a fresh start selection")
			if not _disabled_contract.poll(self): return
		else:
			selector.select(1)
			selector.item_selected.emit(1)
			_check(Entry.draft.get("manifest") == NEW_PATH and not Entry.draft.has("site"), "Actual original selector signals the source and requires a fresh original start selection")
			if not _disabled_contract.poll(self): return
	Entry.region_mode = "pick_start"
	var picker: Control = (load(Entry.REGION_SCENE) as PackedScene).instantiate()
	root.add_child(picker)
	await process_frame
	if not _disabled_contract.poll(self): return
	var source: RegionData = picker.get("source")
	if _disabled_contract.profile == "formal_disabled":
		_check(source.manifest_hash == "e3108aad1cbfd5118af08fd699ac03bf64d19b5bc9d186154dc9a5fea279f7b8" and source.resource_manifest_hash == "a6b9c68722c9755f4b99a0704eebd5368b6dd2fe431a7eca78a48e8fd6ee49cf", "Actual formal picker reads the exact original geography/resource pair")
		if not _disabled_contract.poll(self): return
	else:
		_check(source.manifest_hash == "cdf59e3247c9db3eb1e5399f7346014f8dec5c2f90bb977fd41ea35bc3444446" and source.resource_manifest_hash == "9acfdc50025eac0c296880102af57cc9d1faef34cc24486eef1594fcc07bd5ef", "Actual original picker uses the selected full geography/resource pair")
		if not _disabled_contract.poll(self): return
	if _disabled_contract.profile == "formal_disabled":
		_check(Entry.request_new_world(Vector2i(1170, 13252), {}, "source selector", "", RegionData.DEFAULT_MANIFEST) and Entry.pending.manifest == RegionData.DEFAULT_MANIFEST, "Original formal pending request carries exactly the selected released source")
		if not _disabled_contract.poll(self): return
	else:
		_check(Entry.request_new_world(Vector2i(1170, 13252), {}, "source selector", "", NEW_PATH) and Entry.pending.manifest == NEW_PATH, "Original pending Controller request carries exactly that selected source")
		if not _disabled_contract.poll(self): return
	var before: PackedByteArray = var_to_bytes(Entry.pending)
	if _disabled_contract.profile == "formal_disabled":
		_check(not Entry.request_new_world(Vector2i(1170, 13252), {}, "unpublished source", "", NEW_PATH) and var_to_bytes(Entry.pending) == before, "Registered but unpublished candidate rejects atomically without replacing the legitimate original pending request")
		if not _disabled_contract.poll(self): return
	_check(not Entry.request_new_world(Vector2i(1170, 13252), {}, "bad source", "", "res://unregistered_source.json") and var_to_bytes(Entry.pending) == before, "Unregistered source rejects atomically without replacing a legitimate pending request")
	if not _disabled_contract.poll(self): return
	picker.free()
	menu.free()
	Entry.draft = original_draft
	Entry.pending = original_pending
	Entry.region_mode = original_mode
	await process_frame
	if not _disabled_contract.ready(self): return
	print("SITE_G06_SOURCE_RULE_UI_%s: checks=%d real selector/original draft/paired reader/pending refusal; original fullworld production in separate first-earned tests; GPU/public release excluded" % ["PASS" if failures.is_empty() else "FAIL", checks])
	if _disabled_contract.profile == "formal_disabled":
		if not _disabled_contract.emit_disabled(self, "site_g06_source_rule_ui_test", 16): return
	quit(0 if failures.is_empty() else 1)
