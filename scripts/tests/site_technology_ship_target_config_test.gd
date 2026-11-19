extends "res://scripts/tests/site_technology_settlement_ship_test.gd"
## Strict bound-target negative atop actual paid S12 order; NOT_RUN.

func _strict_paid_ship_target_configuration() -> void:
	var f := _ship_order_fixture()
	var id := _adopt_ship_order(f)
	_deliver_ship_order(f, id)
	_check(Runtime.begin_settlement_ship_operation(f.data, str(f.settlement_id), id).ok, "Actual original finite order starts its genuine paid two-station hull")
	_place_ship_workers(f)
	_shipyard_work_point(f, 30.0)
	_check(Runtime.stop_settlement_ship_order(f.data, str(f.settlement_id), id, int(f.control)).ok, "Original head parks the actual named tasks without releasing paid stock")
	var yard: Dictionary = f.data.site.features[f.yard]
	var config: Dictionary = yard.technology_shipyard_work
	var paid = yard.tech_batch.duplicate(true)
	var materials = Stocks.storage(f.data, str(f.yard)).cargo.duplicate(true)
	f.lab.site_controller._capture_positions()
	_check(ShipStore.save(f.data, "user://technology_ship_bound_config.json").ok, "Actual suspended finite hull/config admits strict original cold save")
	yard.erase("technology_shipyard_work")
	var before := var_to_bytes(f.data.site)
	_check(Runtime.valid_technology_shipyard_work(yard), "Legacy optional config absence still remains valid for an ordinary unconfigured host")
	_check(not Runtime.valid_settlement_ship_target(f.data, str(f.yard), yard) and not Runtime.validate_technology_target_storage(f.data, str(f.yard), yard).ok, "A bound S12 paid hull requires its actual explicit two-station configuration")
	_check(not ShipStore.save(f.data, "user://technology_ship_bound_config_bad.json").ok and var_to_bytes(f.data.site) == before, "Cold admission cannot normalize away missing required configuration or mutate original state")
	yard.technology_shipyard_work = config
	_check(Runtime.begin_settlement_ship_operation(f.data, str(f.settlement_id), id).ok and yard.tech_batch == paid and Stocks.storage(f.data, str(f.yard)).cargo == materials, "Restored same original configuration really resumes both actual tasks without redebit")
	_cleanup_fixture(f.lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _strict_paid_ship_target_configuration()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_SHIP_TARGET_CONFIG_PASS: %d checks; actual bounded paid cold target/config absence rejection/true no-redebit resume; NOT wholeLab Native all40" % checks)
	quit(0)
