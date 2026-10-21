extends SceneTree
const Registry = preload("res://scripts/region_lab/region_organization_registry.gd")
const Edit = preload("res://scripts/region_lab/region_organization_edit.gd")
var failures: Array[String] = []
var checks: int = 0
var fake_calls: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func fake_validator() -> bool:
	fake_calls += 1
	return true

func state(site: String, person: int) -> Dictionary:
	return {"id": site, "actors": {"player": {"person_id": person}}, "armies": [], "item_definitions": {},
		"equipment_nations": {"original": {"military_head": person, "members": [person], "standards": {}}},
		"family": {"version": 4, "complete": true, "name": site, "lineage_id": 1, "offices": SiteOffices.default_offices("family", -1, false),
			"members": [{"site_id": site, "person_id": person, "path": "", "label": site, "age_years": -1}]}}

func _initialize() -> void:
	var a: Dictionary = state("a", 1)
	var b: Dictionary = state("b", 2)
	var people: Dictionary = RegionSaveSlot.person_migration("world", [{"projection": RegionSaveSlot.person_projection(a), "location": {"kind": "site", "id": "a"}}, {"projection": RegionSaveSlot.person_projection(b), "location": {"kind": "site", "id": "b"}}])
	if not people.ok:
		check(false, "Original P6-A fixture admission")
		finish()
		return
	var proposal: Dictionary = Registry.migrate_sources("world", 4, [{"kind": "site", "owner": "site:a", "historical": false, "state": a}, {"kind": "site", "owner": "site:b", "historical": false, "state": b}], people.allocator, RegionSaveSlot.person_allocator_valid)
	if not proposal.ok:
		check(false, "Original B1 organization admission: " + str(proposal))
		finish()
		return
	var contexts: Dictionary = {"site:a": a, "site:b": b}
	var admitted: Dictionary = Edit.validate(proposal.registry, proposal.registry, contexts, proposal.bindings, proposal.identities, people.allocator)
	if not admitted.ok:
		check(false, "Original record schema admission: " + str(admitted))
		finish()
		return
	var original_bytes: PackedByteArray = var_to_bytes([proposal, contexts, people])
	var edit: Dictionary = Edit.create(proposal.registry, contexts)
	var checkpoint: Dictionary = Edit.checkpoint(edit)
	var key: String = str(edit.registry.families.keys()[0])
	var pointer: Dictionary = edit.registry.families[key].record
	var record_before: PackedByteArray = var_to_bytes(pointer)
	Edit.replace_record(edit, "family", key, pointer)
	check(is_same(pointer, edit.registry.families[key].record) and var_to_bytes(pointer) == record_before and edit.revision == 1, "Self-replacement copies before clearing and retains the actual record object")
	var named: Dictionary = pointer.duplicate(true)
	named.name = "private-name"
	var candidate: Dictionary = edit.registry.duplicate(true)
	candidate.families[key].record = named
	admitted = Edit.validate(candidate, edit.base, contexts, proposal.bindings, proposal.identities, people.allocator)
	check(admitted.ok, "Original family schema admits a private name edit")
	Edit.replace_record(edit, "family", key, named)
	check(is_same(pointer, edit.registry.families[key].record) and pointer.name == "private-name", "Accepted update preserves the shared private dictionary")
	var identities_before: PackedByteArray = var_to_bytes(proposal.identities)
	Edit.delete_record(edit, "family", key)
	var removed: Dictionary = Edit.checkpoint(edit)
	check(not edit.registry.families.has(key) and int(edit.epochs[key]) == 1, "Delete retires the private record once")
	Edit.rollback(edit, checkpoint)
	check(is_same(pointer, edit.registry.families[key].record) and var_to_bytes(pointer) == record_before and int(edit.epochs[key]) == 2 and edit.revision == 4, "Rollback restores original pointer/content with a fresh lifetime and monotonic revision")
	check(Registry.same(edit.registry, proposal.registry) and edit.registry.families.keys() == proposal.registry.families.keys(), "Rollback restores registry body, typed metadata and key order")
	Edit.rollback(edit, removed)
	check(not edit.registry.families.has(key) and int(edit.epochs[key]) == 3 and edit.revision == 5, "Rollback to a deleted checkpoint retires the restored lifetime")
	Edit.rollback(edit, checkpoint)
	check(int(edit.epochs[key]) == 4 and edit.revision == 6 and var_to_bytes(proposal.identities) == identities_before, "Repeated restore never reissues original typed refs or sequences")
	var unknown: Dictionary = proposal.registry.duplicate(true)
	unknown.families[key].record.members[0].person_id = 99
	var unknown_result: Dictionary = Edit.validate(unknown, edit.base, contexts, proposal.bindings, proposal.identities, people.allocator)
	check(not unknown_result.ok and unknown_result.code == "UNKNOWN_ORGANIZATION_PERSON", "Unknown membership refuses through original Person closure")
	var keys: Array = proposal.registry.families.keys()
	var duplicate: Dictionary = proposal.registry.duplicate(true)
	duplicate.families[keys[1]].record.members = duplicate.families[keys[0]].record.members.duplicate(true)
	var duplicate_result: Dictionary = Edit.validate(duplicate, edit.base, contexts, proposal.bindings, proposal.identities, people.allocator)
	check(not duplicate_result.ok and duplicate_result.code == "DUPLICATE_FAMILY_MEMBERSHIP", "One original person cannot enter two private family records")
	var forged: Dictionary = proposal.registry.duplicate(true)
	forged.families[key].record.records_validator = Callable(self, "fake_validator")
	forged.families[key].record.fully_validated = true
	var forged_result: Dictionary = Edit.validate(forged, edit.base, contexts, proposal.bindings, proposal.identities, people.allocator)
	check(not forged_result.ok and fake_calls == 0, "Caller validator/readiness fields never execute or confer schema qualification")
	var identity: Dictionary = proposal.registry.duplicate(true)
	identity.families[key].record.lineage_id = 2
	var identity_result: Dictionary = Edit.validate(identity, edit.base, contexts, proposal.bindings, proposal.identities, people.allocator)
	check(not identity_result.ok and identity_result.code == "ORGANIZATION_EDIT_IDENTITY", "Existing record identity cannot be changed by a body update")
	var nation_key: String = str(edit.registry.nations.keys()[0])
	var nation_pointer: Dictionary = edit.registry.nations[nation_key].record
	Edit.replace_record(edit, "nation", nation_key, nation_pointer)
	Edit.delete_record(edit, "nation", nation_key)
	Edit.rollback(edit, checkpoint)
	check(is_same(nation_pointer, edit.registry.nations[nation_key].record), "Nation self-replacement/delete/restore retains its original private record object")
	check(var_to_bytes([proposal, contexts, people]) == original_bytes, "All original source/schema/person inputs remain unchanged")
	finish()

func finish() -> void:
	print("REGION_ORGANIZATION_EDIT_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
