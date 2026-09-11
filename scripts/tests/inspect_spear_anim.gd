extends Node3D

func _ready() -> void:
    print("GODOT_SPEAR_SHIELD_INSPECT_START")
    var editor_scene = load("res://scenes/tests/human_character_3d_editor.tscn")
    if not editor_scene:
        print("FAIL: could not load editor scene")
        get_tree().quit(1)
        return
        
    var editor = editor_scene.instantiate()
    add_child(editor)
    await get_tree().process_frame
    await get_tree().process_frame
    
    var anim_player: AnimationPlayer = null
    for node in editor.find_children("*", "AnimationPlayer", true, false):
        anim_player = node
        break
        
    if anim_player:
        print("Found AnimationPlayer: ", anim_player.name)
        print("Animations available: ", anim_player.get_animation_list())
    else:
        print("FAIL: no AnimationPlayer found")
        get_tree().quit(1)
        return
        
    var anim = anim_player.get_animation("attack_spear")
    if anim:
        print("attack_spear length: ", anim.length, " loop: ", anim.loop_mode)
        for i in range(anim.get_track_count()):
            var path = str(anim.track_get_path(i))
            if "J_Bip_L_" in path or "J_Bip_R_" in path:
                print("  track: ", path, " keys: ", anim.track_get_key_count(i))
    else:
        print("FAIL: attack_spear animation not found!")
        
    get_tree().quit(0)
