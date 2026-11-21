extends SceneTree
## 開始遊戲效能 (copy on write), GPU (visual: the raw model cache is a real-renderer path). Three crowd-body presenters
## are built as CrowdSite._gain_body builds them (TerrainTestCharacter.prepare_contact_visual): A with copy on write off
## (the old per-presenter deep copy of every clip), B and C with it on. Checks:
## - B and C share most clips with the cache; every clip's loop mode equals A's after loading;
## - playing a one-shot clip on B copies only that clip for B: C's clip stays shared and unchanged, and B's loop mode
##   equals A's after the same call;
## - a resolved jump through TerrainTestCharacter's own write changes B's copy, never the shared clip;
## - sampled poses: for several clips and times the skeleton of B equals A's;
## - the load is faster than the deep copy (reported, with a loose bound).
## Output: RUNTIME_PRESENTER_COW_PASS on success; quit(1) on any failure or the deadline.

const Editor = preload("res://scripts/terrain_lab/runtime_human_character_3d_editor.gd")
var checks := 0
var _done := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String) -> void:
	if _done: return
	_done = true
	printerr("RUNTIME_PRESENTER_COW_FAIL: ", message)
	quit(1)

func _check(ok: bool, label: String, detail: Variant = "") -> bool:
	checks += 1
	if ok:
		print("RUNTIME_PRESENTER_COW OK %d: %s" % [checks, label])
		return true
	_fail("%s %s" % [label, str(detail)])
	return false

func _body(host: Node, appearance: Dictionary) -> TerrainTestCharacter:
	var body := TerrainTestCharacter.new()
	body.exchange_enabled = true
	body.combat_driven_by_lab = true
	host.add_child(body)
	if not body.prepare_contact_visual(appearance): return null
	return body

func _loops(editor: HumanCharacter3DEditor) -> Dictionary:
	var result := {}
	for clip: StringName in editor.animation_player.get_animation_list(): result[clip] = editor.animation_player.get_animation(clip).loop_mode
	return result

func _pose(editor: HumanCharacter3DEditor, clip: StringName, time: float) -> Array:
	editor.select_animation_by_id(clip)
	editor.set_playing(false)
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	editor.animation_player.seek(time, true)
	editor.animation_player.advance(0.0)
	var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var out: Array = []
	for bone: int in range(skeleton.get_bone_count()): out.append(skeleton.get_bone_pose(bone))
	return out

func _same_pose(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for k: int in range(a.size()):
		var x: Transform3D = a[k]
		var y: Transform3D = b[k]
		if not x.is_equal_approx(y): return false
	return true

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "GPU required (the raw model cache is a real-renderer path)"): return
	if not _check(TerrainArmy.load_combat_bake(), "the combat bake loads"): return
	var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var host := Node2D.new()
	root.add_child(host)
	# The first presenter of the cache parses the model and (copy on write) sets the shared loop defaults; time the next.
	Editor.copy_on_write_enabled = true
	var warm := _body(host, appearance)
	if not _check(warm != null, "a warm-up presenter loads"): return
	Editor.copy_on_write_enabled = false
	var t := Time.get_ticks_usec()
	var a := _body(host, appearance)
	var deep_ms := (Time.get_ticks_usec() - t) / 1000.0
	Editor.copy_on_write_enabled = true
	t = Time.get_ticks_usec()
	var b := _body(host, appearance)
	var cow_ms := (Time.get_ticks_usec() - t) / 1000.0
	var c := _body(host, appearance)
	if not _check(a != null and b != null and c != null, "the three presenters load"): return
	var ea: HumanCharacter3DEditor = a.editor
	var eb: HumanCharacter3DEditor = b.editor
	var ec: HumanCharacter3DEditor = c.editor
	var clips: Array = eb.animation_player.get_animation_list()
	var shared := clips.filter(func(clip: StringName) -> bool: return eb.shares_animation(clip))
	if not _check(shared.size() >= clips.size() - 8 and not ea.shares_animation(&"run"), "B shares most clips with the cache; A (deep copy) shares none", [shared.size(), clips.size()]): return
	if not _check(_loops(eb) == _loops(ea) and _loops(ec) == _loops(ea), "every clip's loop mode equals the deep-copy presenter's after loading"): return
	# A one-shot clip played as the selection (the editor's loop toggle is on): B copies that clip only.
	# A clip the editor selects under its own name (attack_sword, for one, is selected as walk_slash).
	var one_shot := &""
	for candidate: StringName in [&"attack_axe", &"attack_spear", &"attack_hammer", &"hit"]:
		if eb.animation_player.has_animation(candidate) and eb._normalize_animation_id(candidate) == candidate and eb.animation_player.get_animation(candidate).loop_mode == Animation.LOOP_NONE:
			one_shot = candidate
			break
	if not _check(one_shot != &"", "a one-shot clip selected under its own name exists"): return
	var before_c: int = ec.animation_player.get_animation(one_shot).loop_mode
	if not _check(eb.shares_animation(one_shot), "the one-shot clip starts shared", one_shot): return
	eb.select_animation_by_id(one_shot)
	ea.select_animation_by_id(one_shot)
	if not _check(eb.animation_player.get_animation(one_shot).loop_mode == ea.animation_player.get_animation(one_shot).loop_mode,
		"selecting it gives B the deep copy's loop mode (the selection sets the toggle to the clip's default: nothing to copy)", [eb.animation_player.get_animation(one_shot).loop_mode, ea.animation_player.get_animation(one_shot).loop_mode, eb.shares_animation(one_shot)]): return
	# The editor's loop toggle turned on for it (the Lab's own editor window): the write that copies B's clip.
	for editor: HumanCharacter3DEditor in [eb, ea]:
		editor.loop_toggle.set_pressed_no_signal(true)
		editor._play_selected_animation()
	if not _check(not eb.shares_animation(one_shot) and eb.animation_player.get_animation(one_shot).loop_mode == Animation.LOOP_LINEAR and ea.animation_player.get_animation(one_shot).loop_mode == Animation.LOOP_LINEAR,
		"a loop-toggle write copies B's clip first, with the loop mode the deep copy gets", [eb.shares_animation(one_shot), eb.animation_player.get_animation(one_shot).loop_mode, ea.animation_player.get_animation(one_shot).loop_mode]): return
	if not _check(ec.shares_animation(one_shot) and ec.animation_player.get_animation(one_shot).loop_mode == before_c, "C's clip stays shared and unchanged"): return
	if not _check(eb.animation_player.get_animation(one_shot) != ec.animation_player.get_animation(one_shot), "B and C now hold different resources for it"): return
	# The resolved jump write of TerrainTestCharacter (ride clips share; the reduced jump is always the presenter's own).
	for clip: StringName in [&"ride_heavy", &"ride_guard_break", &"attack_jump_heavy"]:
		if not eb.animation_player.has_animation(clip): continue
		var shared_before := ec.animation_player.get_animation(clip).loop_mode
		eb.select_animation_by_id(clip)
		if eb.animation_player.get_animation(clip).loop_mode != Animation.LOOP_NONE:
			var own: Animation = eb.ensure_private_animation(clip)
			own.loop_mode = Animation.LOOP_NONE
		if not _check(ec.animation_player.get_animation(clip).loop_mode == shared_before, "a write to B's %s never reaches C" % clip): return
	# Sampled poses equal the deep copy's.
	for probe: Array in [[&"idle", 0.4], [&"walk", 0.3], [&"run", 0.2], [one_shot, 0.25], [&"guard", 0.1], [&"hit", 0.15], [&"down", 0.5]]:
		var clip: StringName = probe[0]
		if not ea.animation_player.has_animation(clip): continue
		if not _check(_same_pose(_pose(eb, clip, float(probe[1])), _pose(ea, clip, float(probe[1]))), "B samples the same %s pose as the deep copy at %.2f s" % [clip, float(probe[1])]): return
	print("RUNTIME_PRESENTER_COW load deep=%.0f ms copy_on_write=%.0f ms" % [deep_ms, cow_ms])
	if not _check(cow_ms < deep_ms, "the copy-on-write load is faster than the deep copy", [deep_ms, cow_ms]): return
	print("RUNTIME_PRESENTER_COW_PASS: ", checks, " checks")
	_done = true
	quit(0)
