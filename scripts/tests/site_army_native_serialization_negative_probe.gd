extends SceneTree

const OUTPUT := "res://output/site_army_5k_hot_close_20260926/native_serialization_negative_probe.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var cases := {
		"object": RefCounted.new(),
		"callable": Callable(self, "_run"),
		"signal": self.process_frame
	}
	var observations := {}
	for name: String in cases:
		var original: Variant = cases[name]
		var encoded: PackedByteArray = var_to_bytes(original)
		var decoded: Variant = bytes_to_var(encoded) if encoded.size() > 0 else null
		observations[name] = {
			"original_type": typeof(original),
			"bytes": encoded.size(),
			"decoded_type": typeof(decoded)
		}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(observations, "\t"))
	file.close()
	print("SERIALIZATION_NEGATIVE_PROBE ", OUTPUT, " ", observations)
	quit()
