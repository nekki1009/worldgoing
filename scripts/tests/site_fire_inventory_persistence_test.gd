extends "res://scripts/tests/site_fire_inventory_components_test.gd"
## Original stock adapter plus strict JSON validation; no save admission.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_INVENTORY_PERSISTENCE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _run() -> void:
	var f := _fixture()
	var key := _paid_feature(f, "warehouse", Vector2i(20, 20), Vector2i.ONE, {"material": "stone"})
	if key.is_empty(): _finish(false, "original warehouse"); return
	var storage := SiteStockpiles.ensure_storage(f.data, key, 1)
	if not _check(storage.ok, "Original stock holder created"): _finish(false); return
	storage.stock.cargo.wood = 5 # Explicit finite stock genesis.
	f.lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": 50.0}}, {})
	var request := _loss_request(f, key, {"wood": 1}, [])
	var loss := SiteRuntime.apply_inventory_loss(f.data, request)
	if not _check(loss.ok and storage.stock.cargo.wood == 4, "Original adapter debits once and records receipt", loss): _finish(false); return
	var captured := SiteRuntime.capture_fire_snapshot(f.data, 0.0)
	if not _check(captured.ok, "Runtime captures inventory receipt within same owner", captured): _finish(false); return
	var parsed: Variant = JSON.parse_string(JSON.stringify(captured.state, "", true, true))
	var wire: Dictionary = parsed
	var original := var_to_bytes(f.data.site)
	var checked := SiteRuntime.validate_fire_snapshot(f.data, wire, 0.0)
	if not _check(checked.ok and var_to_bytes(f.data.site) == original, "JSON receipt validates without consuming stock", checked): _finish(false); return
	var event := str(request.event_id)
	var bad: Dictionary = wire.duplicate(true)
	bad.inventory_receipts[event].resources.wood = 2
	if not _check(not SiteRuntime.validate_fire_snapshot(f.data, bad, 0.0).ok and var_to_bytes(f.data.site) == original,
		"Inflated historical loss rejects without live mutation"): _finish(false); return
	bad = wire.duplicate(true); bad.inventory_receipts[event].resources = {"stone": 1}
	if not _check(not SiteRuntime.validate_fire_snapshot(f.data, bad, 0.0).ok, "Noncombustible historical loss rejects"): _finish(false); return
	bad = wire.duplicate(true); bad.inventory_pending = {event: request.duplicate(true)}
	if not _check(not SiteRuntime.validate_fire_snapshot(f.data, bad, 0.0).ok, "Committed event cannot also remain pending"): _finish(false); return
	bad = wire.duplicate(true); bad.contents_remainders = {key: 1.0}
	if not _check(not SiteRuntime.validate_fire_snapshot(f.data, bad, 0.0).ok, "Fraction cannot hide an unconsumed whole item"): _finish(false); return
	var repeat := SiteRuntime.apply_inventory_loss(f.data, request)
	if not _check(repeat.ok and repeat.duplicate and storage.stock.cargo.wood == 4 and var_to_bytes(f.data.site) == original,
		"Validated receipt still suppresses the original duplicate request"): _finish(false); return
	_close(f)
	_finish(not failed, "inventory schema leaf only; full all-owner round trip remains required")
