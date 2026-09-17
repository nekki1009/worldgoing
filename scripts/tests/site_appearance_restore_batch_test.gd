extends "res://scripts/tests/site_actor_preview_rotation_test.gd"
## Same 18 cases / 54 exact substeps / 18 RGBA frames per gender, plus restore.
var restore_base: Dictionary
var restore_pass := 0
var restore_costs: Array = []
var lining_batch := false

func _initialize() -> void:
	lining_batch = "--lining-batch" in OS.get_cmdline_user_args()
	if lining_batch:
		preload("res://scripts/tests/fixtures/appearance_lining_batch_install.gd").install(true)
	else:
		preload("res://scripts/tests/fixtures/appearance_weapon_batch_install.gd").install(true)
	super._initialize()
	output_root = "res://output/site_appearance_restore_20260917/actor"
	if lining_batch: output_root = "res://output/site_appearance_lining_20260917/actor"
	output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
	result_prefix = "SITE_APPEARANCE_RESTORE"
	capture_modes = ["original", "batched_weapons"]
	candidate_scope = "Synchronous restore only: skip unrelated per-slot weapon refresh; immediate weapon/shield/animation, invalid/partial failure, direct selection retained. Exact original actor state and full RGBA, not FPS."
	if lining_batch:
		capture_modes = ["original", "batched_lining"]
		candidate_scope = "Previous accepted weapon batching unchanged. Only skip unrelated lining refresh inside base synchronous restore; first face/outfit/armor/boots remain immediate. Same complete exact matrix."

func _configure_candidate(enabled: bool) -> void:
	if restore_base.is_empty(): restore_base = actor.editor.capture_appearance().duplicate(true)
	actor.editor.set("_appearance_restore_reference", not enabled)
	actor.editor.exact_preview_rotation_guard_enabled = true
	actor.editor.lazy_combat_visual_bones_enabled = true
	actor.batch_cloth_updates_enabled = true
	restore_pass = int(enabled)

func _prime_case(item: Dictionary) -> bool:
	if not super._prime_case(item): return false
	var target: Dictionary = actor.editor.capture_appearance()
	# Retain the parent's complete armored collision matrix, including travel cape.
	# Equipment stripping is checked separately below, never passed as absent armor.
	target.equipment_dyes = {"armor": "123456ff", "boots": "654321ff"}
	var before: int = actor.editor.get("_weapon_refresh_calls")
	var begin := Time.get_ticks_usec()
	if not actor.editor.restore_appearance(target): return false
	restore_costs.append({"candidate": bool(restore_pass), "case": item.label, "usec": Time.get_ticks_usec() - begin,
		"weapon_refreshes": int(actor.editor.get("_weapon_refresh_calls")) - before})
	assert(not bool(actor.editor.get("_restoring_appearance_parts")))
	return true

func _fallback_checks(item: Dictionary) -> bool:
	if not super._fallback_checks(item): return false
	var expected := {}
	var stripped_expected := {}
	for reference: bool in [true, false]:
		actor.editor.set("_appearance_restore_reference", reference)
		assert(actor.editor.restore_appearance(restore_base))
		if lining_batch:
			var face := actor.editor.part_options[&"face"] as OptionButton
			var lining_calls: int = actor.editor.get("_lining_refresh_calls")
			var early_state := _cosmetic_snapshot()
			face.set_item_disabled(face.selected, true)
			assert(not actor.editor.restore_appearance(restore_base))
			face.set_item_disabled(face.selected, false)
			assert(not bool(actor.editor.get("_restoring_appearance_parts")))
			assert(int(actor.editor.get("_lining_refresh_calls")) == lining_calls)
			assert(_cosmetic_snapshot() == early_state, "First-slot failure must not refresh lining")
		var target := restore_base.duplicate(true)
		target.parts.armor = "none"
		var boots := actor.editor.part_options[&"boots"] as OptionButton
		boots.set_item_disabled(boots.selected, true)
		assert(not actor.editor.restore_appearance(target))
		boots.set_item_disabled(boots.selected, false)
		assert(not bool(actor.editor.get("_restoring_appearance_parts")))
		var state := _cosmetic_snapshot()
		if reference: expected = state
		else: assert(state == expected, "Late selector failure changed partial state")
		var before: int = actor.editor.get("_weapon_refresh_calls")
		var before_lining: int = actor.editor.get("_lining_refresh_calls") if lining_batch else 0
		assert(actor.editor.select_part_by_id(&"armor", &"none"))
		assert(int(actor.editor.get("_weapon_refresh_calls")) == before + 1, "Direct selections must still refresh")
		if lining_batch: assert(int(actor.editor.get("_lining_refresh_calls")) == before_lining + 1)
		var invalid := target.duplicate(true)
		invalid.parts.boots = "not_a_boot"
		before = actor.editor.get("_weapon_refresh_calls")
		assert(not actor.editor.restore_appearance(invalid) and int(actor.editor.get("_weapon_refresh_calls")) == before)
		assert(actor.editor.restore_appearance(restore_base))
		var stripped := restore_base.duplicate(true)
		for slot: String in ["armor", "helmet", "outfit", "boots", "cape", "weapon", "shield"]:
			stripped.parts[slot] = "none"
		stripped.equipment_dyes = {}
		before = actor.editor.get("_weapon_refresh_calls")
		var begin := Time.get_ticks_usec()
		assert(actor.editor.restore_appearance(stripped))
		restore_costs.append({"candidate": not reference, "case": "stripped_equipment", "usec": Time.get_ticks_usec() - begin,
			"weapon_refreshes": int(actor.editor.get("_weapon_refresh_calls")) - before})
		assert(not bool(actor.editor.get("_restoring_appearance_parts")))
		var stripped_state := _cosmetic_snapshot()
		stripped_state.collision = actor._geometry.pose_snapshot(actor, actor.editor._resolve_weapon_attack_animation())
		stripped_state.bones = []
		for index: int in skeleton.get_bone_count():
			stripped_state.bones.append([skeleton.get_bone_pose(index), skeleton.get_bone_global_pose(index)])
		assert(not stripped_state.collision.body.is_empty() and stripped_state.collision.armor.is_empty())
		if reference: stripped_expected = stripped_state
		else: assert(stripped_state == stripped_expected, "Stripped equipment state changed")
	report.restore_costs = restore_costs
	report.partial_failure_pairs = 1
	report.stripped_equipment_state_pairs = 1
	return true
