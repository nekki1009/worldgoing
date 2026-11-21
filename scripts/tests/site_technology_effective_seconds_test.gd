extends SceneTree
## Row 45 option (b): a finite public iron_armor receipt compares the batch's
## production-equivalent effective seconds; work_seconds keeps its meaning.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
var checks := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SITE_TECHNOLOGY_EFFECTIVE_SECONDS_FAIL: " + message)

func _initialize() -> void:
	_receipt_rule()
	_ledger_recording()
	_batch_bound()
	print("SITE_TECHNOLOGY_EFFECTIVE_SECONDS_%s: checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _receipt_rule() -> void:
	_check(is_equal_approx(Runtime.max_building_productivity(), 1.5), "The bound uses the best civil grade's productivity (grade 3 = 1.5)")
	_check(Orders.public_receipt_effective_ok({"work_seconds": 900.0}, "iron_armor"), "An older receipt without the key keeps its accepted meaning")
	_check(not Orders.public_receipt_effective_ok({"work_seconds": 600.0}, "iron_armor"), "A grade-1 workshop still needs the full 900 s of work")
	_check(Orders.public_receipt_effective_ok({"work_seconds": 600.0, "effective_seconds": 900.0}, "iron_armor"), "A grade-3 workshop completes with 600 s of work at 1.5x")
	_check(not Orders.public_receipt_effective_ok({"work_seconds": 600.0, "effective_seconds": 950.0}, "iron_armor"), "A forged effective value above work x 1.5 is refused")
	_check(not Orders.public_receipt_effective_ok({"work_seconds": 0.0, "effective_seconds": 0.0}, "iron_armor"), "Production filled without recorded work is refused")
	_check(not Orders.public_receipt_effective_ok({"work_seconds": 900.0, "effective_seconds": -1.0}, "iron_armor"), "A negative effective value is refused")
	_check(not Orders.public_receipt_effective_ok({"work_seconds": 900.0, "effective_seconds": 900.0}, "house_build"), "Only iron_armor receipts may carry effective_seconds")

func _ledger_recording() -> void:
	var grade3 := {"kind": "smithy", "stage": "complete", "technology_order": {"nation_id": "n1", "order_id": "public_1"},
		"tech_batch": {"operator_id": 4, "work_seconds": 0.0}}
	for _step: int in 4:
		var minutes := 2.5
		Runtime.technology_record_work(grade3, minutes, 4, Runtime.feature_production_minutes(minutes, 1.0, 1.5))
	_check(is_equal_approx(float(grade3.tech_batch.work_seconds), 600.0) and is_equal_approx(float(grade3.tech_batch.effective_seconds), 900.0),
		"Grade 3: 600 physical seconds record 900 effective seconds from the same production value")
	var grade1 := {"kind": "smithy", "stage": "complete", "technology_order": {"nation_id": "n1", "order_id": "public_1"},
		"tech_batch": {"operator_id": 4, "work_seconds": 0.0}}
	Runtime.technology_record_work(grade1, 10.0, 4, Runtime.feature_production_minutes(10.0, 1.0, 1.0))
	_check(is_equal_approx(float(grade1.tech_batch.effective_seconds), float(grade1.tech_batch.work_seconds)), "Grade 1: effective equals physical work")
	var dry := {"kind": "smithy", "stage": "complete", "technology_order": {"nation_id": "n1", "order_id": "public_1"},
		"tech_batch": {"operator_id": 4, "work_seconds": 0.0}}
	Runtime.technology_record_work(dry, 10.0, 4, Runtime.feature_production_minutes(10.0, 0.5, 1.5))
	_check(is_equal_approx(float(dry.tech_batch.effective_seconds), 450.0), "Water shortage lowers effective work in the same step factor")
	var farm := {"kind": "farm", "stage": "complete", "tech_batch": {"operator_id": 4, "work_seconds": 0.0}}
	Runtime.technology_record_work(farm, 10.0, 4, Runtime.feature_production_minutes(10.0, 1.0, 3.0))
	_check(not farm.tech_batch.has("effective_seconds"), "Farm and pasture batches never carry effective_seconds")
	var legacy := {"kind": "smithy", "stage": "complete", "technology_order": {"nation_id": "n1", "order_id": "public_1"},
		"tech_batch": {"operator_id": 4, "work_seconds": 300.0}}
	Runtime.technology_record_work(legacy, 5.0, 4, Runtime.feature_production_minutes(5.0, 1.0, 1.5))
	_check(is_equal_approx(float(legacy.tech_batch.effective_seconds), 300.0 + 450.0), "An older batch continues from effective = its earlier work_seconds")

func _batch_bound() -> void:
	var data := TerrainData.new()
	data.site = {"id": "effective-site", "features": {"1": {"kind": "smithy"}, "2": {"kind": "farm"}}}
	var batch := {"version": 1, "id": 1, "site_id": "effective-site", "feature_id": "1", "operator_id": 4, "recipe_id": "iron_armor",
		"materials": {"iron": 4}, "source_holder": "feature:3", "source_version": 0, "work_seconds": 600.0, "token": {}, "payment_id": "p"}
	_check(Runtime.valid_technology_batch(batch, data, "1"), "An older batch without the key stays valid")
	var bounded := batch.duplicate(true)
	bounded["effective_seconds"] = 900.0
	_check(Runtime.valid_technology_batch(bounded, data, "1"), "effective_seconds up to work x 1.5 is valid")
	var forged := batch.duplicate(true)
	forged["effective_seconds"] = 901.0
	_check(not Runtime.valid_technology_batch(forged, data, "1"), "A saved effective_seconds above its physical bound is refused")
	var on_farm := batch.duplicate(true)
	on_farm.feature_id = "2"
	on_farm["effective_seconds"] = 600.0
	_check(not Runtime.valid_technology_batch(on_farm, data, "2"), "A farm batch may not carry effective_seconds")
