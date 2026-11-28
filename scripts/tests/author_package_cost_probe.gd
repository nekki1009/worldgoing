extends SceneTree
## Probe (2026-11-27, 開局速度 B): the parts of RegionData.load_author_package on the shipped demo A package, run in its
## order with the same calls: the manifest parse and digest, the dependency reads (size + SHA-256), each package file's
## read, hash and JSON parse, the natural source load, the static/scenario checks, and the static Site builds.
## Output: AUTHOR_PACKAGE_COST lines and AUTHOR_PACKAGE_COST_DONE.
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

func _initialize() -> void:
	_run.call_deferred()

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0

func _run() -> void:
	var parts := {}
	var t := Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACKAGE))
	var shape_ok := RegionData._author_manifest_shape(parsed)
	var digest_ok: bool = RegionData.author_package_digest(parsed) == parsed.package_digest
	parts["manifest_parse_digest"] = _ms(t)
	t = Time.get_ticks_usec()
	var dependency_bytes := 0
	var natural: Dictionary = {}
	for entry: Dictionary in parsed.dependencies:
		var checked: Dictionary = RegionData._read_author_file(str(entry.path), entry, RegionData.AUTHOR_DEPENDENCY_BYTES)
		dependency_bytes += int(entry.bytes)
		print("AUTHOR_PACKAGE_COST dependency %s %d bytes ok %s" % [str(entry.path), int(entry.bytes), str(checked.get("ok", false))])
		if entry.id == parsed.natural_source: natural = entry
	parts["dependency_reads"] = _ms(t)
	var read_ms := 0.0
	var json_ms := 0.0
	var records: Array[Dictionary] = []
	for entry: Dictionary in parsed.files:
		t = Time.get_ticks_usec()
		var checked: Dictionary = RegionData._read_author_file(PACKAGE.get_base_dir().path_join(str(entry.path)), entry, RegionData.AUTHOR_FILE_BYTES)
		read_ms += _ms(t)
		t = Time.get_ticks_usec()
		var content: Variant = JSON.parse_string(checked.bytes.get_string_from_utf8())
		json_ms += _ms(t)
		records.append({"entry": entry, "content": content})
	parts["file_reads_hash"] = read_ms
	parts["file_json_parse"] = json_ms
	t = Time.get_ticks_usec()
	var candidate := RegionData.new()
	JSON.parse_string(FileAccess.get_file_as_string(str(natural.path)))
	var loaded: Dictionary = candidate.load_manifest(str(natural.path))
	parts["natural_load"] = _ms(t)
	var static_valid_ms := 0.0
	var static_norm_ms := 0.0
	var scenario_ms := 0.0
	var initial_ms := 0.0
	for record: Dictionary in records:
		var entry: Dictionary = record.entry
		var key: String = "%d:%d" % [int(entry.site[0]), int(entry.site[1])]
		var content: Dictionary = record.content
		if entry.kind == "static":
			t = Time.get_ticks_usec()
			candidate.author_static_valid(content)
			static_valid_ms += _ms(t)
			t = Time.get_ticks_usec()
			candidate._author_static[key] = RegionData.author_static_normalized(content)
			static_norm_ms += _ms(t)
		elif entry.kind == "scenario":
			t = Time.get_ticks_usec()
			RegionData.author_scenario_valid(content)
			candidate._author_scenario = content.duplicate(true)
			scenario_ms += _ms(t)
		else:
			t = Time.get_ticks_usec()
			candidate._author_initial[key] = content.duplicate(true)
			initial_ms += _ms(t)
	parts["static_valid"] = static_valid_ms
	parts["static_normalized"] = static_norm_ms
	parts["scenario_valid"] = scenario_ms
	parts["initial_copies"] = initial_ms
	candidate._author_pin = {"scenario_id": str(parsed.scenario_id), "scenario_revision": int(parsed.revision), "scenario_package_sha256": str(parsed.package_digest)}
	t = Time.get_ticks_usec()
	var builds := 0
	for key: String in candidate._author_static:
		var pair: PackedStringArray = key.split(":")
		candidate.make_terrain_data(int(pair[0]), int(pair[1]))
		builds += 1
	parts["static_builds_%d" % builds] = _ms(t)
	var text := ""
	var total := 0.0
	for name: String in parts:
		text += " %s %.0f," % [name, parts[name]]
		total += float(parts[name])
	print("AUTHOR_PACKAGE_COST shape %s digest %s natural %s, dependencies %d bytes, total %.0f ms:%s" % [str(shape_ok), str(digest_ok), str(loaded.get("ok", false)), dependency_bytes, total, text])
	print("AUTHOR_PACKAGE_COST_DONE")
	quit(0)
