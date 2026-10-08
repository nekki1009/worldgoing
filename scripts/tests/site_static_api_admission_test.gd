extends SceneTree
## Static API capability/dispatch regression only; no operation or source proof.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

func _initialize() -> void:
	var original: Script = Runtime
	var found := false
	for method: Dictionary in original.get_script_method_list():
		if str(method.get("name", "")) == "technology_remaining_work": found = true
	assert(found, "The original static method is present in its script API")
	var variant_ref: Variant = original
	var checked: Dictionary = variant_ref.call("technology_remaining_work", null, {}, {})
	assert(checked.get("ok") == false and checked.get("code") == "INVALID_TECHNOLOGY", "Static dispatch runs its true argument guard")
	print("SCRIPT_STATIC_API_ADMISSION_PASS method_list=true resource_has_method=", original.has_method("technology_remaining_work"), "; original static dispatch; no source or operation completion claim")
	quit(0)
