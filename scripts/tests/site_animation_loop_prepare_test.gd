extends SceneTree
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const BEFORE := "res://output/site_army_loop_prepare_20260916/before/human_character_3d_editor.gd.txt"
const PREPARE := "func _prepare_animation_loop_defaults() -> void:\n"

static func install_replay_control() -> void:
	var script := load(EDITOR) as GDScript
	assert(script.source_code.count(PREPARE) == 1)
	script.source_code = script.source_code.replace(PREPARE, PREPARE + "\tif not has_meta(&\"loaded_loop_modes\"):\n\t\tvar modes := {}\n\t\tfor clip: StringName in animation_player.get_animation_list(): modes[clip] = animation_player.get_animation(clip).loop_mode\n\t\tset_meta(&\"loaded_loop_modes\", modes)\n\t\tset_meta(&\"loaded_loop_toggle\", loop_toggle.button_pressed)\n\tif loop_prepare_reference: return\n") + "\nvar loop_prepare_reference := true\n"
	assert(script.reload(true) == OK)

func _initialize() -> void:
	var script := load(EDITOR) as GDScript
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func _apply_attack_loop_default\\([^\\n]*\\n.*?(?=^func )") == OK)
	var original := matcher.search(FileAccess.get_file_as_string(BEFORE)).get_string()
	script.source_code += "\n" + original.replace("func _apply_attack_loop_default(", "func _original_loop_default(")
	assert(script.reload(true) == OK)
	var editor := HumanCharacter3DEditor.new()
	editor.loop_toggle = CheckBox.new()
	editor.add_child(editor.loop_toggle)
	var clips: Array[StringName] = [&"unknown", &"hit", &"hit_back", &"knockback", &"guard_custom_raise", &"guard_custom_lower", &"guard_custom_break"]
	for slot: Dictionary in HumanCharacter3DEditor.ANIMATION_SLOTS: clips.append(slot.id)
	var rules := 0
	for clip: StringName in clips:
		for previous: bool in [false, true]:
			editor._selected_animation = clip
			editor.loop_toggle.set_pressed_no_signal(previous)
			editor.call("_original_loop_default")
			var expected := editor.loop_toggle.button_pressed
			editor.loop_toggle.set_pressed_no_signal(previous)
			editor._apply_attack_loop_default()
			assert(editor.loop_toggle.button_pressed == expected)
			rules += 1
	editor.animation_player = AnimationPlayer.new()
	editor.add_child(editor.animation_player)
	var library := AnimationLibrary.new()
	assert(editor.animation_player.add_animation_library(&"", library) == OK)
	var current := Animation.new()
	current.loop_mode = Animation.LOOP_PINGPONG
	var hit := Animation.new()
	var attack := Animation.new()
	attack.loop_mode = Animation.LOOP_LINEAR
	for item: Array in [[&"idle", current], [&"guard", current], [&"hit", hit], [&"attack_axe", attack]]:
		assert(library.add_animation(item[0], item[1]) == OK)
		editor._available_animation_ids[item[0]] = true
	editor._available_animation_ids[&"missing"] = false
	editor.animation_player.assigned_animation = &"idle"
	editor._selected_animation = &"idle"
	editor.loop_toggle.set_pressed_no_signal(true)
	var notices := {"hit": 0, "attack": 0}
	hit.changed.connect(func() -> void: notices.hit += 1)
	attack.changed.connect(func() -> void: notices.attack += 1)
	var before := _state(editor)
	editor._prepare_animation_loop_defaults()
	assert(_state(editor) == before, "Keep current playback, current Resource aliases and UI")
	assert(hit.loop_mode == Animation.LOOP_LINEAR and attack.loop_mode == Animation.LOOP_NONE)
	assert(notices == {"hit": 1, "attack": 1}, "Preserve Resource notifications; no signal suppression")
	editor._prepare_animation_loop_defaults()
	assert(notices == {"hit": 1, "attack": 1}, "Actual-equal requests must remain no-op")
	editor.loop_toggle.set_pressed_no_signal(false)
	editor._prepare_animation_loop_defaults()
	assert(hit.loop_mode == Animation.LOOP_NONE and notices.hit == 2)
	hit.loop_mode = Animation.LOOP_PINGPONG
	editor.animation_player.play(&"idle")
	editor.animation_player.queue(&"hit")
	before = _state(editor)
	editor._prepare_animation_loop_defaults()
	assert(_state(editor) == before and hit.loop_mode == Animation.LOOP_PINGPONG)
	editor.animation_player.clear_queue()
	editor.animation_player.animation_set_next(&"idle", &"hit")
	editor._prepare_animation_loop_defaults()
	assert(hit.loop_mode == Animation.LOOP_PINGPONG)
	editor.free()
	print("LOOP_PREPARE_PASS original_loop_rules=", rules, "; active Resource aliases/UI/playback unchanged; missing clip; original changed notifications; repeated requests; inherited hit loop preference; queued/chained fallback")
	quit(0)

func _state(editor: HumanCharacter3DEditor) -> Array:
	var player := editor.animation_player
	return [editor._selected_animation, editor.loop_toggle.button_pressed, player.assigned_animation, player.current_animation,
		player.current_animation_position, player.is_playing(), player.get_queue(), player.get_animation(&"idle").loop_mode, player.get_animation(&"guard").loop_mode]
