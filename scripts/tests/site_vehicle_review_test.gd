extends SceneTree

## Independent review probes. Never alters the live main scene or source fixtures.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const SOURCE := "res://output/logistics_vehicles_20260918/core/"
const OUT := "res://output/logistics_vehicles_20260918/review/"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 15000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Independent vehicle review deadline")
		quit(90)
	return false

func _load_forged(data: TerrainData, fixture: String, output_name: String) -> bool:
	# Recompute the normal envelope checksum to exercise semantic validation,
	# rather than merely proving the checksum or the save-side guard rejects it.
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + fixture))
	var payload: Dictionary = JSON.parse_string(str(envelope.payload))
	payload.state = data.site
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(OUT + output_name, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checksum":body.sha256_text(), "payload":body}, "\t"))
	file.close()
	return bool(Store.load_site(OUT + output_name).ok)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var findings: Array[Dictionary] = []
	var moving := Store.load_site(SOURCE + "moving.json")
	assert(moving.ok, str(moving))
	var data: TerrainData = moving.data
	var vehicle: Dictionary
	for candidate: Dictionary in data.site.vehicles.values():
		if not candidate.move.is_empty(): vehicle = candidate
	assert(not vehicle.is_empty())
	# The human still has an original in-flight destination. Removing only the
	# paired vehicle step must not be accepted as a legal stopped cart.
	vehicle.move = {}
	vehicle.stop_pending = false
	var saved := Store.save(data, OUT + "forged_missing_paired_step.json")
	var loaded_ok := _load_forged(data, "moving.json", "forged_missing_paired_step.json")
	findings.append({"probe":"moving_operator_without_vehicle_step", "unexpected_save_accept":saved.ok,
		"unexpected_load_accept":loaded_ok, "result":saved})

	var parked := Store.load_site(SOURCE + "parked.json")
	assert(parked.ok, str(parked))
	data = parked.data
	for candidate: Dictionary in data.site.vehicles.values():
		if candidate.kind == "cart": vehicle = candidate
	vehicle.cargo = {"grain":100}
	var owner_id := int(data.site.armies[0].units[0].person_id)
	var created := Runtime.create_equipment(data, vehicle.holder, "review:vehicle-worn-sword",
		{"slot":"weapon", "asset":"longsword_01", "tint":[1.0,1.0,1.0,1.0]}, owner_id, "weapon")
	assert(created.ok)
	saved = Store.save(data, OUT + "forged_vehicle_wears_equipment.json")
	loaded_ok = _load_forged(data, "parked.json", "forged_vehicle_wears_equipment.json")
	findings.append({"probe":"vehicle_wears_equipment_to_exceed_capacity", "unexpected_save_accept":saved.ok,
		"unexpected_load_accept":loaded_ok, "physical_count":101, "reported_load":Runtime.carried_load(data.site,vehicle.cargo,vehicle.holder), "result":saved})
	var file := FileAccess.open(OUT + "result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(findings,"\t") + "\n")
	var failure := false
	for finding: Dictionary in findings:
		print("VEHICLE_REVIEW ", JSON.stringify(finding))
		failure = failure or bool(finding.unexpected_save_accept) or bool(finding.unexpected_load_accept)
	if failure: push_error("Independent vehicle review confirmed invalid save acceptance; see review/result.json")
	quit(1 if failure else 0)
