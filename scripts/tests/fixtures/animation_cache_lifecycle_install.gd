extends RefCounted
## Compatibility entrypoint for existing regression tests; no source injection.
static func install() -> void:
	assert(ClassDB.class_has_method("AnimationPlayer", "set_clear_cache_on_stop_enabled"), "Isolated cache-retention engine required")

static func assert_captain(team: TerrainArmy) -> void:
	var editor: HumanCharacter3DEditor = team._unit_editor(0)
	assert(editor != null and editor.animation_player != null)
	assert(not editor.animation_player.call("is_clear_cache_on_stop_enabled"))
	print("CACHE_RETENTION_CAPTAIN ", editor.get_path(), " production_policy=true")
