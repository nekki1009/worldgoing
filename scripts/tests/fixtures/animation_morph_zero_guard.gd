extends RefCounted
## Test-process candidate only. Original editor/assets on disk stay untouched.
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"

static func install(count_writes: bool = false) -> void:
	var script := load(EDITOR) as GDScript
	var method := RegEx.new()
	assert(method.compile("(?ms)^func _play_selected_animation\\([^\\n]*\\n.*?(?=^func )") == OK)
	assert(method.search_all(script.source_code).size() == 1)
	var original := method.search(script.source_code).get_string()
	var loops := RegEx.new()
	assert(loops.compile("(?m)^(\\t+)for shape in (cloth|armor)\\.get_blend_shape_count\\(\\):$") == OK)
	var matches := loops.search_all(original)
	assert(matches.size() == 3)
	var candidate := original
	for match_index in range(matches.size() - 1, -1, -1):
		var found := matches[match_index]
		var indent: String = found.get_string(1)
		var node: String = found.get_string(2)
		# Check before the original name filter too: already-positive-zero shapes
		# need neither a name query nor a write. Preserve -0 normalization.
		var replacement: String = found.get_string() + "\n" + indent + "\tif morph_zero_guard_enabled and %s.get_blend_shape_value(shape) == 0.0 and 1.0 / %s.get_blend_shape_value(shape) > 0.0:\n" % [node, node] + indent + "\t\tcontinue"
		candidate = candidate.left(found.get_start()) + replacement + candidate.substr(found.get_end())
	if count_writes:
		var setter := RegEx.new()
		assert(setter.compile("(?m)^(\\t+)(cloth|armor)\\.set_blend_shape_value\\(shape, 0\\.0\\)$") == OK)
		candidate = setter.sub(candidate, "$1morph_zero_writes += 1\n$0", true)
	script.source_code = script.source_code.replace(original, candidate) + "\nvar morph_zero_guard_enabled := true\nvar morph_zero_writes := 0\n"
	assert(script.reload(true) == OK)
