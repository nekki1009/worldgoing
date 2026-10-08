extends RefCounted
## Removable telemetry only. All measured methods still run on their original Nodes.
var enabled: bool = false
var frames: Dictionary = {}

func add(phase: String, started: int) -> void:
	if not enabled: return
	var frame: int = Engine.get_process_frames()
	if not frames.has(frame): frames[frame] = {}
	frames[frame][phase] = float(frames[frame].get(phase, 0.0)) + float(Time.get_ticks_usec() - started) / 1000.0

func take(frame: int) -> Dictionary:
	var sample: Dictionary = frames.get(frame, {})
	frames.erase(frame)
	# Never retain frames from setup or a previous measurement window.
	for earlier: int in frames.keys():
		if earlier < frame: frames.erase(earlier)
	return sample
