extends "res://scripts/tests/site_actor_preview_rotation_test.gd"
## Same original actor/18-case GPU replay, changing only component discovery.
const QueryChecks = preload("res://scripts/tests/site_editor_component_search_test.gd")
var component_queries := 0

func _initialize() -> void:
	# Inherited extended replay deadline is 33s; use the canonical 45s helper.
	super._initialize()
	output_root = "res://output/site_army_scale_phase13_20260915/actor_components"
	output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
	result_prefix = "SITE_ACTOR_COMPONENT_SEARCH"
	capture_modes = ["phase12_all_nodes", "native_prefix"]
	candidate_scope = "Frozen phase12 component discovery versus native literal-prefix prefilter; original 18-case actor replay with 54 exact substep state/bone/hair pairs and 18 complete RGBA/cosmetic pairs, including mounts and equipment transitions. No reduced samples or visibility, no FPS claim."

func _run() -> void:
	QueryChecks.install_reference()
	await super._run()

func _configure_candidate(enabled: bool) -> void:
	actor.editor.set("phase12_component_search", not enabled)
	actor.editor.exact_preview_rotation_guard_enabled = true
	actor.editor.lazy_combat_visual_bones_enabled = true
	actor.batch_cloth_updates_enabled = true

func _collision_snapshot() -> Dictionary:
	var mode: bool = actor.editor.get("phase12_component_search")
	# Exercise every authored component, not just the currently equipped pieces.
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		for component: Dictionary in slot.get("options", []):
			QueryChecks.compare_query(actor.editor, component.get("prefixes", []))
			component_queries += 1
	for component: Dictionary in HumanCharacter3DEditor.HAIR_OPTIONS[body_index]:
		QueryChecks.compare_query(actor.editor, component.prefixes)
		component_queries += 1
	actor.editor.set("phase12_component_search", mode)
	report.component_queries = component_queries
	return super._collision_snapshot()
