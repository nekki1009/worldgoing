extends RefCounted
## 開始遊戲效能計畫 P0 (project library perf/start-game-perf-plan.md §4, §6): a stage timer for the start chain, on only
## with the user argument --perf-trace (off, every call returns at once and nothing is kept). Each mark records the time
## since the first mark and the Performance monitors; flush writes the marks and the time between consecutive marks to
## user://perf/<label>_<unix>.json and prints one PERF_TRACE line, then starts over. Static, so it spans scene changes.

const MONITORS := {"static_mb": Performance.MEMORY_STATIC, "video_mb": Performance.RENDER_VIDEO_MEM_USED,
	"texture_mb": Performance.RENDER_TEXTURE_MEM_USED, "buffer_mb": Performance.RENDER_BUFFER_MEM_USED}
const COUNTS := {"objects": Performance.OBJECT_COUNT, "nodes": Performance.OBJECT_NODE_COUNT}
const ROOT := "user://perf"
const StartProgress = preload("res://scripts/terrain_lab/start_progress.gd")

static var _marks: Array = []
static var _origin := -1

static func enabled() -> bool:
	return OS.get_cmdline_user_args().has("--perf-trace")

static func mark(stage: String) -> void:
	StartProgress.stage(stage) # The loading screen follows the same stages, with or without --perf-trace.
	if not enabled(): return
	var now := Time.get_ticks_usec()
	if _origin < 0: _origin = now
	var row := {"stage": stage, "ms": snappedf(float(now - _origin) / 1000.0, 0.01)}
	for key: String in MONITORS: row[key] = snappedf(float(Performance.get_monitor(MONITORS[key])) / 1048576.0, 0.1)
	for key: String in COUNTS: row[key] = int(Performance.get_monitor(COUNTS[key]))
	_marks.append(row)

## Writes and prints the marks since the last flush under `label`; {} when off or nothing was marked.
static func flush(label: String) -> Dictionary:
	if not enabled() or _marks.is_empty(): return {}
	var steps := {}
	for index: int in range(1, _marks.size()):
		steps["%s→%s" % [_marks[index - 1].stage, _marks[index].stage]] = snappedf(float(_marks[index].ms) - float(_marks[index - 1].ms), 0.01)
	var report := {"version": 1, "label": label, "total_ms": float(_marks[-1].ms), "steps": steps, "marks": _marks.duplicate(true)}
	DirAccess.make_dir_recursive_absolute(ROOT)
	var file := FileAccess.open(ROOT.path_join("%s_%d.json" % [label, int(Time.get_unix_time_from_system())]), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("PERF_TRACE ", label, " ", JSON.stringify({"total_ms": report.total_ms, "steps": steps, "peak_nodes": _marks.map(func(row: Dictionary) -> int: return int(row.nodes)).max()}))
	_marks.clear()
	_origin = -1
	return report
