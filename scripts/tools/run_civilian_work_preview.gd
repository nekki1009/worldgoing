extends SceneTree
## Entry point for the CIV-A3 preview: --script res://scripts/tools/run_civilian_work_preview.gd (visual mode).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await preload("res://scripts/tools/preview_civilian_work_clips.gd").run_main(self)
