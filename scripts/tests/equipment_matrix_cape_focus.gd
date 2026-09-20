extends "res://scripts/tests/equipment_matrix_visual.gd"
## Opposite views distinguish an open arm slot from actual cloth penetration.
func run() -> void:
	root.size = Vector2i(1440,1000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	editor = Editor.new(); root.add_child(editor); editor.open()
	for body in 2:
		sex = "female" if body else "male"
		editor._load_body_model(body,"res://assets/characters/human/q35/equipment_matrix/candidate_"+sex+".glb")
		editor.preview_viewport.size = Vector2i(1100,1300)
		assert(editor.restore_appearance(Editor.default_appearance(body)))
		choose(&"helmet",&"helmet_western_steel_01")
		choose(&"armor",&"armor_light_leather_01")
		choose(&"boots",&"boots_leather_01")
		choose(&"outfit",&"outfit_chinese_lining_01")
		choose(&"cape",&"cape_japanese_01")
		choose(&"weapon",&"longsword_01");choose(&"shield",&"none")
		for row in [[&"run",2.0/12.0],[&"attack_jump_heavy",8.0/12.0]]:
			pose(row[0],row[1])
			for angle in [0.0,90.0,180.0,270.0]:
				await capture("focus_"+str(row[0])+"_"+str(int(angle)),angle)
	var file := FileAccess.open(OUT+"/focus_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"PASS","captures":captures},"  "));file.close()
	editor.queue_free();await process_frame
	quit(0)
