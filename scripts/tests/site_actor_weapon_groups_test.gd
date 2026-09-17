extends "res://scripts/tests/site_actor_preview_rotation_test.gd"
const Checks = preload("res://scripts/tests/site_weapon_component_groups_test.gd")

func _initialize() -> void:
	super._initialize()
	output_root = "res://output/site_army_actor_spikes_20260916/actor_weapon_groups"
	output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
	result_prefix = "SITE_ACTOR_WEAPON_GROUPS"
	capture_modes = ["individual_queries", "grouped_query"]
	candidate_scope = "Original weapon lookup versus one current-hierarchy traversal; original 18-case/54-substep exact state, bones, morphs, hair, gear, mounts and full RGBA. No cache, animation/physics change or FPS claim."

func _run() -> void:
	if "--prefix-index" in OS.get_cmdline_user_args():
		output_root = "res://output/site_army_weapon_prefix_20260916/actor"
		output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
		capture_modes = ["previous_grouped_query", "prefix_index"]
		candidate_scope = "Previous production grouped lookup versus call-local prefix index; same 18-case/54-substep exact states and full RGBA; no retained cache or animation changes."
		Checks.install_reference("res://output/site_army_weapon_prefix_20260916/before/human_character_3d_editor.gd.txt")
	else:
		Checks.install_reference()
	await super._run()

func _configure_candidate(enabled: bool) -> void:
	actor.editor.set("weapon_groups_reference", not enabled)
	actor.editor.exact_preview_rotation_guard_enabled = true
	actor.editor.lazy_combat_visual_bones_enabled = true
	actor.batch_cloth_updates_enabled = true

func _collision_snapshot() -> Dictionary:
	Checks.compare(actor.editor, actor.editor._part_definition(&"weapon").get("options", []))
	return super._collision_snapshot()

func _fallback_checks(item: Dictionary) -> bool:
	if not super._fallback_checks(item): return false
	var costs: Array = []
	for reference: bool in [true, false, false, true]:
		actor.editor.set("weapon_groups_reference", reference)
		var begin := Time.get_ticks_usec()
		for repeat in range(100): actor.editor._update_weapon_sheath_state()
		costs.append({"reference": reference, "usec_per_call": (Time.get_ticks_usec() - begin) / 100.0})
	actor.editor.set("weapon_groups_reference", false)
	report.weapon_update_microbench = costs
	return true
