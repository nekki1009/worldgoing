extends SceneTree
## Probe (2026-11-27, 開局速度 B): what loading the Taiwan source and the demo A author package costs, by part.
## Output: MANIFEST_COST lines and MANIFEST_COST_DONE.
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

func _initialize() -> void:
	_run.call_deferred()

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0

func _run() -> void:
	for round: int in range(2):
		var t := Time.get_ticks_usec()
		var base := RegionData.new()
		var loaded: Dictionary = base.load_manifest(RegionData.DEFAULT_MANIFEST)
		print("MANIFEST_COST round %d Taiwan source %s in %.0f ms" % [round, str(loaded.get("ok", false)), _ms(t)])
		t = Time.get_ticks_usec()
		var author := RegionData.new()
		var package: Dictionary = author.load_manifest(PACKAGE)
		print("MANIFEST_COST round %d demo A package %s in %.0f ms" % [round, str(package.get("ok", false)), _ms(t)])
	# The summary byte checks alone, as load_manifest runs them.
	var text := FileAccess.get_file_as_string(RegionData.DEFAULT_MANIFEST)
	var parsed: Dictionary = JSON.parse_string(text)
	var source := RegionData.new()
	var t2 := Time.get_ticks_usec()
	var read: Dictionary = source._read_verified(RegionData.DEFAULT_MANIFEST.get_base_dir(), parsed.summary, RegionData.MAX_SUMMARY_BYTES)
	print("MANIFEST_COST summary read+hash %.0f ms, %d bytes" % [_ms(t2), (read.get("bytes", PackedByteArray()) as PackedByteArray).size()])
	t2 = Time.get_ticks_usec()
	var bad := 0
	for value: int in read.get("bytes", PackedByteArray()):
		if value < 0 or value >= 16: bad += 1
	print("MANIFEST_COST summary byte loop %.0f ms" % _ms(t2))
	print("MANIFEST_COST_DONE")
	quit(0)
