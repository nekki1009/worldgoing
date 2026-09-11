class_name CrowdPromotionBenchmarkHUD
extends CanvasLayer

var controller: CrowdPromotionBenchmarkController
var metrics_label: Label

func setup(target_controller: CrowdPromotionBenchmarkController) -> void:
	controller = target_controller
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(380.0, 0.0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Crowd → SPECIAL Near Promotion"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var controls := HBoxContainer.new()
	for budget: int in [0, 16, 32, 64, 128]:
		var button := Button.new()
		button.text = "Near %d" % budget
		button.pressed.connect(_request_budget.bind(budget))
		controls.add_child(button)
	var focus_a := Button.new()
	focus_a.text = "Focus 0"
	focus_a.pressed.connect(_request_focus.bind(0))
	controls.add_child(focus_a)
	var focus_b := Button.new()
	focus_b.text = "Focus 100"
	focus_b.pressed.connect(_request_focus.bind(100))
	controls.add_child(focus_b)
	box.add_child(controls)
	var path_controls := HBoxContainer.new()
	for path: Dictionary in [
		{"label": "Current per-instance", "path": 0},
		{"label": "Formation parent", "path": 1}
	]:
		var path_button := Button.new()
		path_button.text = path.label
		path_button.pressed.connect(_request_render_path.bind(int(path.path)))
		path_controls.add_child(path_button)
	box.add_child(path_controls)
	var reset_button := Button.new()
	reset_button.text = "Reset deterministic state"
	reset_button.pressed.connect(_request_reset)
	box.add_child(reset_button)
	metrics_label = Label.new()
	metrics_label.text = "Initializing..."
	metrics_label.add_theme_font_size_override("font_size", 13)
	box.add_child(metrics_label)
	var help := Label.new()
	help.text = "WASD pan · wheel zoom · production budget 64 · stress budget 128"
	help.add_theme_color_override("font_color", Color("b7c7d1"))
	box.add_child(help)

func set_budget_selection(_budget: int) -> void:
	# Buttons are intentionally stateless; the live metric is authoritative.
	pass

func update_metrics(metrics: Dictionary) -> void:
	if metrics_label == null:
		return
	metrics_label.text = (
		"FPS %6.1f  Frame %6.2f ms  Worst %6.2f ms\n"
		+ "Crowd %d soldiers / %d formations\n"
		+ "Near %d / Pool %d   Mid %d   Far %d\n"
		+ "Promote +%d  Demote -%d   Totals +%d / -%d\n"
		+ "Chunks %d   Crowd visible %d / total %d\n"
		+ "Render path %s   Formation batches %d   Visible formations %d\n"
		+ "Formation updates %d   Instance transforms %d   Slot writes %d\n"
		+ "Lazy position queries %d   Culling %s\n"
		+ "CPU sim %5.2f  policy %5.2f  pool %5.2f  anim %5.2f  renderer %5.2f ms\n"
		+ "Skeletons %d  AnimationPlayers %d  Budget %d\n"
		+ "SPECIAL %s  LOD0 %d  LOD1 %d  Bundle misses %d\n"
		+ "Rigid batch %s  updates %d  uploads %d  structural %d\n"
		+ "Shadow %s  LOD changes %d  shadow changes %d\n"
		+ "Draw calls %s   Triangles %s\n"
		+ "Seed %d   %s"
	) % [
		metrics.get("fps", 0.0), metrics.get("frame_ms", 0.0), metrics.get("worst_frame_ms", 0.0),
		metrics.get("total_soldiers", 0), metrics.get("formations", 0),
		metrics.get("near", 0), metrics.get("capacity", 0), metrics.get("mid", 0), metrics.get("far", 0),
		metrics.get("promotions", 0), metrics.get("demotions", 0),
		metrics.get("total_promotions", 0), metrics.get("total_demotions", 0),
		metrics.get("visible_chunks", 0), metrics.get("visible_crowd_instances", 0),
		metrics.get("crowd_instances", 0),
		metrics.get("render_path", "CURRENT_PER_INSTANCE"), metrics.get("formation_batch_nodes", 0),
		metrics.get("visible_formations", 0), metrics.get("formation_transform_updates", 0),
		metrics.get("instance_transform_updates", 0), metrics.get("formation_slot_transform_writes", 0),
		metrics.get("lazy_world_position_queries", 0), metrics.get("formation_culling", "N/A"),
		metrics.get("simulation_ms", 0.0), metrics.get("policy_ms", 0.0),
		metrics.get("pool_ms", 0.0), metrics.get("animation_ms", 0.0), metrics.get("renderer_ms", 0.0),
		metrics.get("skeletons", 0), metrics.get("animation_players", 0), metrics.get("near_budget", 0),
		metrics.get("special_render_mode", "MODULAR"), metrics.get("bundle_lod0_active", 0),
		metrics.get("bundle_lod1_active", 0), metrics.get("bundle_cache_misses", 0),
		"ON" if metrics.get("rigid_batch_enabled", false) else "OFF",
		metrics.get("rigid_transform_updates", 0), metrics.get("rigid_upload_calls", 0),
		metrics.get("rigid_structural_changes", 0), metrics.get("shadow_budget", "ALL"),
		metrics.get("lod_transitions", 0), metrics.get("shadow_transitions", 0),
		metrics.get("draw_calls", "N/A"), metrics.get("triangles", "N/A"),
		metrics.get("seed", 0), "PAUSED" if metrics.get("paused", false) else "RUNNING"
	]

func _request_budget(budget: int) -> void:
	if controller != null:
		controller.set_near_actor_budget(budget)

func _request_focus(soldier_id: int) -> void:
	if controller != null:
		controller.focus_on_soldier(soldier_id)

func _request_render_path(path: int) -> void:
	if controller != null:
		controller.set_crowd_render_path(path)

func _request_reset() -> void:
	if controller != null:
		controller.reset_deterministic_state()
