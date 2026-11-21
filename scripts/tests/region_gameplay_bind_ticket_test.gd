extends SceneTree
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("REGION_GAMEPLAY_BIND_TICKET_FAIL: " + message)

func _initialize() -> void:
	var lab := TerrainLab.new()
	var original := TerrainData.new()
	original.site = {"id": "ticket:old", "inventory": {"grain": 29}}
	lab.terrain = original
	var candidate := TerrainData.new()
	candidate.site = {"id": "ticket:new", "region_snapshot": {}}
	var absent := lab._region_bind_ticket_admission(candidate, {})
	check(not absent.ok and absent.code == "REGION_BIND_TICKET_REQUIRED", "A hot payload never authorizes its own public bind")
	lab.bind_terrain(candidate)
	check(lab.terrain == original and original.site.inventory.grain == 29, "Missing ticket rejects before clearing original people or stock")
	var forged := lab._region_bind_ticket_admission(candidate, {"region_bind_token": "foreign"})
	check(not forged.ok and forged.code == "STALE_REGION_BIND_TICKET", "An external token has no private original preparation")
	lab.bind_terrain(candidate, {"ok": true, "crowd_site": null, "region_bind_token": "foreign"})
	check(lab.terrain == original, "Forged prepared flags cannot replace the original Site")
	var token := "only-this-private-child"
	lab._region_owner_bind_tickets[token] = {"kind": "bootstrap", "data": candidate,
		"body_hash": Checkpoint.state_hash(candidate.site), "context": {}, "owners": {}}
	var wrong_mode := lab._region_bind_ticket_admission(candidate, {"region_bind_token": token})
	check(not wrong_mode.ok and wrong_mode.code == "INVALID_REGION_BIND_TICKET", "A bootstrap ticket cannot publish to the main live scene")
	lab.restore_only = true
	var changed := TerrainData.new()
	changed.site = candidate.site.duplicate(true)
	check(not lab._region_bind_ticket_admission(changed, {"region_bind_token": token}).ok, "Equal caller copies are not the prepared original candidate")
	candidate.site.inventory = {"grain": 1}
	var stale := lab._region_bind_ticket_admission(candidate, {"region_bind_token": token})
	check(not stale.ok and stale.code == "STALE_REGION_BIND_TICKET", "Changing a prepared body invalidates the ticket before mutation")
	lab.bind_terrain(candidate, {"ok": true, "crowd_site": null, "region_bind_token": token})
	check(lab.terrain == original and original.site.inventory.grain == 29, "A stale body leaves the original source intact")
	check(lab._region_bound_data == null and lab._region_owner_restore_receipt.is_empty(), "Rejected preparation never emits a bound owner receipt")
	var plain := TerrainData.new()
	plain.site = {"id": "ordinary"}
	var ordinary := lab._region_bind_ticket_admission(plain, {})
	check(ordinary.ok and not ordinary.trusted, "Ordinary snapshots retain their original guarded path")
	lab.free()
	if not failed: print("REGION_GAMEPLAY_BIND_TICKET_PASS checks=%d scope=prepublication_admission_only" % checks)
	quit(1 if failed else 0)
