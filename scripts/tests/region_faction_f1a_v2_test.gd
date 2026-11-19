extends "res://scripts/tests/region_faction_f1a_test.gd"
## Actual original pure typed-party join + original Slot transition/publication.
## No hand-written joined phase, replaced decoder, movement/Native or sea proof.
const Travel = preload("res://scripts/region_lab/region_travel.gd")
const Clock = preload("res://scripts/region_lab/region_gameplay_clock.gd")

class ObservedSlot extends RegionSaveSlot:
	var party_reads := 0
	var change_after_read := ""
	var changed_bytes: PackedByteArray = PackedByteArray()
	func _faction_read_party(path: String) -> Dictionary:
		party_reads += 1
		var loaded: Variant = super._faction_read_party(path)
		if loaded.ok and path == change_after_read:
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			if file == null: return fail("SAVE_IO")
			file.store_buffer(changed_bytes); file.close()
			change_after_read = ""
		return loaded

func _slot() -> ObservedSlot:
	var slot: ObservedSlot = ObservedSlot.new()
	slot.folder = "user://tests/faction_f1a_v2_" + Crypto.new().generate_random_bytes(8).hex_encode()
	slot.source = RegionData.new()
	slot.pin = {"format": 1, "world_instance_id": "test", "slot_id": "test", "atlas_id": "test", "base_revision": "test", "manifest_sha256": "a".repeat(64), "ramp_rule_revision": "test", "grid_contract_version": 1}
	return slot

func _write_party(slot: RegionSaveSlot, party: Dictionary, relative: String) -> Dictionary:
	var document: Variant = slot._region_party_document(str(party.party_id), party)
	if not check(document.ok, "original party document producer"): return {}
	var written: Variant = slot._write_new_document(slot.folder.path_join(relative), document.payload)
	if not check(written.ok, "original immutable document writer"): return {}
	return {"path": relative, "sha256": FileAccess.get_sha256(slot.folder.path_join(relative))}

func _journey(party: Dictionary, proof: Dictionary) -> Dictionary:
	var normalized: Variant = RegionSaveSlot._normalize_travel_journey({"version": 1, "kind": Travel.KIND, "token": str(party.party_id),
		"party_path": proof.path, "party_sha256": proof.sha256, "departure_game_seconds": 0.0, "origin": [0, 0],
		"position": {"site": [0, 0], "component": 0}, "plan_path": "", "plan_sha256": "", "plan_started_game_seconds": 0.0, "plans": 0})
	if not check(normalized.ok, "original complete journey validator"): return {}
	return normalized.journey

func _rewrite(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "bounded same-path content-change fixture"): return false
	file.store_buffer(bytes); file.close()
	return check(FileAccess.get_file_as_bytes(path) == bytes, "fixture bytes written exactly")

func _fixture_body(identity: int, ko: float = 0.0) -> Dictionary:
	return {"person_id": identity, "hp": 100.0, "ko": ko, "member": true,
		"captive": false, "departed": false, "fatigue": 0.0, "fatigue_rest": 0.0,
		"cargo": {}, "item_state": Travel.Runtime.new_item_state("person:%d" % identity),
		"cell": [50 + identity, 50], "pose": "unconscious" if ko > 0.0 else "idle"}

func _fixture_state(site: String, identity_namespace: String, offset: int = 0) -> Dictionary:
	var local: Variant = 1 + offset
	var state: Dictionary = {"id": site, "next_person_id": local + 1, "army_next_team": local + 1,
		"next_vehicle": local + 1, "next_item": local + 1, "next_loot": local + 1,
		"actors": {}, "armies": [{"team_id": local, "faction_id": 0, "units": [_fixture_body(local)]}],
		"vehicles": {str(local): {"id": str(local), "team_id": local, "operator_id": local,
			"kind": "cart", "cell": 5050, "facing": [1, 0], "cargo": {},
			"holder": {"version": 1, "holder": "vehicle:" + str(local), "equipped": {}, "item_ids": [str(local)]}}},
		"item_records": {str(local): {"id": str(local), "holder": "vehicle:" + str(local), "definition": "token", "original_owner": local}},
		"item_definitions": {"token": {"id": "token"}}, "ground_loot": {},
		"team_supply": {}, "person_supply": {}, "equipment_nations": {}, "corps": {},
		"controlled_person_id": local}
	return Travel.prepare_identity(state, identity_namespace).state

func _fixture_party(state: Dictionary, token: String = "travel_test") -> Dictionary:
	var local: int = int(state.armies[0].units[0].person_id)
	var content: Variant = state.duplicate(true)
	content.counters = {"next_person_id": local + 1, "army_next_team": local + 1, "next_vehicle": local + 1, "next_item": local + 1, "next_loot": local + 1}
	return {"version": Travel.VERSION, "kind": "travel_party", "party_id": token,
		"controller": "player", "leader_person_id": local, "person_ids": [local],
		"team_ids": [int(state.armies[0].team_id)], "vehicle_ids": state.vehicles.keys(),
		"origin_site_id": state.id, "content": content, "mode": "land",
		"upkeep": {"version": 1, "at": 0.0, "resting": false, "carriers": {}, "events": [], "sequence": 0}}


func _run() -> void:
	var slot: ObservedSlot = _slot()
	if not check(slot._recover_control().ok, "original empty recovery"): return
	var player: Dictionary = _fixture_party(_fixture_state("A", "world:A"), "player_live")
	var npc: Dictionary = _fixture_party(_fixture_state("B", "world:B"), "npc_join")
	npc.controller = "npc"; npc.content.controlled_person_id = -1
	npc.content.armies[0].faction_id = 900
	npc.content.settlement = {"last_fall": {"from": 9011, "to": 900}}
	var player_proof: Dictionary = _write_party(slot, player, "travel/player_live/party_source.json")
	if failed: return
	var npc_proof: Dictionary = _write_party(slot, npc, "travel/npc_join/party_source.json")
	if failed: return
	var journey: Dictionary = _journey(player, player_proof)
	if failed: return
	var states: Array[Dictionary] = [player.content, npc.content]
	var receipts: Array[Dictionary] = [receipt("party:player_live"), receipt("party:npc_join")]
	var migration: Variant = Query.migration(states, receipts, [12000], {}, 0.0, true)
	if not check(migration.ok, "original migration with explicit reserved highwater"): return
	var clock: Variant = slot.control.duplicate(true)
	clock.region_gameplay = Clock.empty_registry()
	clock.faction_registry = migration.registry
	# Original Clock owner indexes require String; named assignment creates StringName.
	clock.region_gameplay.parties["npc_join"] = slot._region_family_source_npc_reference(npc, journey, str(npc_proof.path), str(npc_proof.sha256), {})
	if not check(clock.region_gameplay.parties.keys()[0] is String and Clock.validate_registry(clock.region_gameplay, float(clock.logical_game_seconds)).ok,
			"legal original String owner reference passes the unchanged Region schema"): return
	var invalid_owner_clock: Dictionary = clock.duplicate(true)
	var invalid_reference: Dictionary = invalid_owner_clock.region_gameplay.parties["npc_join"]
	invalid_owner_clock.region_gameplay.parties.erase("npc_join")
	invalid_owner_clock.region_gameplay.parties[StringName("npc_join")] = invalid_reference
	var invalid_owner_bytes: PackedByteArray = var_to_bytes(invalid_owner_clock)
	var owner_rejected: Dictionary = Clock.validate_registry(invalid_owner_clock.region_gameplay, float(invalid_owner_clock.logical_game_seconds))
	if not check(not owner_rejected.ok and owner_rejected.code == "REGION_SCHEMA" and slot.party_reads == 0
			and var_to_bytes(invalid_owner_clock) == invalid_owner_bytes, "StringName owner key still refuses without decoding parties or mutating the candidate"): return
	var published: Variant = slot._publish({}, clock, "", journey)
	# DIAG_ONLY: original result and already-existing counters; no extra owner calls.
	print("F1A_V4_DIAG v2_first_publication ", JSON.stringify({
		"published": {"ok": published.get("ok"), "code": published.get("code"), "message": published.get("message")},
		"party_reads": slot.party_reads, "expected_party_reads": 2,
		"registry_present": slot.control.has("faction_registry"),
		"next_faction_id_raw": slot.control.get("faction_registry", {}).get("next_faction_id"),
		"expected_next_faction_id": 12001, "generation": slot._marker.get("generation"),
		"source_cache_size": slot._faction_source_cache.size(), "journey": journey,
		"npc_reference": clock.region_gameplay.parties.npc_join}, "", true))
	if not check(published.ok and slot.party_reads == 2 and slot.control.faction_registry.next_faction_id == 12001, "first source validation decodes each real document once"): return
	# A same-generation recovery validates disk and retains the exact RAM owners.
	var published_marker: Dictionary = slot._marker
	var published_control: Dictionary = slot.control
	var published_bytes: PackedByteArray = var_to_bytes([slot.control, slot._marker])
	var recovered_marker: Dictionary = slot._recover_control()
	if not check(recovered_marker.ok and slot.party_reads == 2 and is_same(slot._marker, published_marker)
			and is_same(slot.control, published_control) and var_to_bytes([slot.control, slot._marker]) == published_bytes,
			"validated same-generation recovery retains typed original control and marker owners"): return
	var generation: int = int(slot._marker.generation)
	var warm: Variant = slot._publish({}, slot.control, "", journey)
	if not check(warm.ok and slot.party_reads == 2 and int(slot._marker.generation) == generation + 1, "recover + publish reuse validated same content summaries"): return
	var original_npc: PackedByteArray = FileAccess.get_file_as_bytes(slot.folder.path_join(str(npc_proof.path)))
	var changed: Variant = npc.duplicate(true)
	changed.content.settlement.last_fall.from = 13000
	var changed_proof: Dictionary = _write_party(slot, changed, "travel/npc_join/party_changed.json")
	if failed: return
	var changed_bytes: PackedByteArray = FileAccess.get_file_as_bytes(slot.folder.path_join(str(changed_proof.path)))
	if not _rewrite(slot.folder.path_join(str(npc_proof.path)), changed_bytes): return
	slot._faction_source_cache.erase(slot._faction_cache_context() + ":party:" + slot.folder.path_join(str(npc_proof.path)) + ":" + str(npc_proof.sha256)) # Force the deliberately mutated source to miss.
	var before_reads: int = slot.party_reads
	var old_scan: Variant = slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false)
	if not check(not old_scan.ok and old_scan.code == "CORRUPT_SAVE" and slot.party_reads == before_reads + 1, "forced cold miss rejects mutated same-path bytes under original recorded SHA"): return
	before_reads = slot.party_reads # The rejected old-SHA miss performed one real read.
	var changed_clock: Variant = slot.control.duplicate(true)
	changed_clock.region_gameplay.parties.npc_join.party_sha256 = str(changed_proof.sha256)
	var one_changed: Variant = slot._faction_scan({}, changed_clock, journey, slot.faction_registry_view(), [], false)
	if not check(one_changed.ok and slot.party_reads == before_reads + 1 and one_changed.registry.next_faction_id == 13001, "exactly one changed content source revalidates and raises historical highwater"): return
	var recovery_before: PackedByteArray = var_to_bytes([slot.control, slot._marker])
	slot._recover_known_commit.clear()
	slot._faction_source_cache.clear()
	var bad_recovery: Variant = slot._recover_control()
	if not check(not bad_recovery.ok and var_to_bytes([slot.control, slot._marker]) == recovery_before, "forced cold latest-source recovery rejects corruption and preserves live control"): return
	if not _rewrite(slot.folder.path_join(str(npc_proof.path)), original_npc): return
	var missing: Variant = slot.folder.path_join(str(npc_proof.path))
	if not check(DirAccess.rename_absolute(missing, missing + ".missing") == OK, "missing-source fixture"): return
	slot._faction_source_cache.clear()
	var missing_scan: Variant = slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false)
	if not check(not missing_scan.ok and missing_scan.code == "CORRUPT_SAVE", "missing file rejects on explicit source-cache miss"): return
	if not check(DirAccess.rename_absolute(missing + ".missing", missing) == OK, "restore original source fixture"): return
	var bad_clock: Variant = slot.control.duplicate(true)
	bad_clock.region_gameplay.parties.npc_join.party_sha256 = "b".repeat(64)
	if not check(slot._faction_scan({}, bad_clock, journey, slot.faction_registry_view(), [], false).code == "CORRUPT_SAVE", "wrong expected hash never uses cached state"): return
	var cache_key: Variant = slot._faction_cache_context() + ":party:" + slot.folder.path_join(str(npc_proof.path)) + ":" + str(npc_proof.sha256)
	if not check(slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false).ok, "restored source fully validates before cache integrity probe"): return
	slot._faction_source_cache[cache_key].summary.owner = "poisoned"
	before_reads = slot.party_reads
	var invalid_cache: Variant = slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false)
	if not check(invalid_cache.ok and slot.party_reads == before_reads + 1, "invalid cached summary is discarded and original decoder revalidates"): return
	slot._faction_source_cache[cache_key] = "invalid"
	before_reads = slot.party_reads
	var invalid_shape: Variant = slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false)
	if not check(invalid_shape.ok and slot.party_reads == before_reads + 1, "invalid cache entry type is discarded without a script cast error"): return
	var no_owner: Variant = slot.faction_registry_view()
	no_owner.entries["900"].nation_ref = {"type": "nation", "namespace": "absent-owner", "lineage": 1}
	no_owner.entries["900"].erase("duty_ai")
	before_reads = slot.party_reads
	var context_recheck: Variant = slot._faction_scan({}, slot.control, journey, no_owner, [], false)
	if not check(not context_recheck.ok and context_recheck.code == "CORRUPT_SAVE" and slot.party_reads == before_reads, "cached source cannot authorize a new unmatched current registry nation binding"): return
	# A real original decoder succeeds, then the test changes its input file.
	# No candidate source summary may be recorded under the pre-read SHA.
	slot._faction_source_cache.clear()
	slot.change_after_read = missing; slot.changed_bytes = changed_bytes
	var raced: Variant = slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false)
	if not check(not raced.ok and raced.code == "CORRUPT_SAVE" and not slot._faction_source_cache.has(cache_key), "post-validation content change rejects and never primes old-SHA cache"): return
	if not _rewrite(missing, original_npc): return
	var revalidated: Variant = slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false)
	if not check(revalidated.ok, "source restored via full original validation"): return
	var pin_before: Variant = slot.pin.duplicate(true)
	slot.pin.manifest_sha256 = "b".repeat(64)
	var other_pin: Variant = slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false)
	if not check(not other_pin.ok and slot._faction_source_cache.is_empty(), "pin/context change invalidates all cached facts and original pin validator rejects"): return
	slot.pin = pin_before
	var player_before: PackedByteArray = var_to_bytes(player)
	var npc_before: PackedByteArray = var_to_bytes(npc)
	var joined: Variant = Travel.join_party(player, npc, int(slot._marker.generation) + 1)
	if not check(joined.ok and var_to_bytes(player) == player_before and var_to_bytes(npc) == npc_before, "actual original join API combines two detached original closures"): return
	if not check(Travel.census(joined.party).people.size() == 2 and Travel.census(joined.party).vehicles.size() == 2 and joined.party.content.item_records.size() == 2, "joined party retains two bodies, vehicles and real items uniquely"): return
	var mapped_item: String = str(joined.mapping.maps.item["1"])
	var mapped_vehicle: String = str(joined.mapping.maps.vehicle["1"])
	if not check(joined.party.content.item_records[mapped_item].holder == "vehicle:" + mapped_vehicle and joined.party.content.vehicles[mapped_vehicle].holder.item_ids == [mapped_item], "original join maps each real item into its unique real holder"): return
	var joined_proof: Dictionary = _write_party(slot, joined.party, "travel/player_live/party_joined.json")
	if failed: return
	var joined_journey: Dictionary = _journey(joined.party, joined_proof)
	if failed: return
	var next_clock: Variant = slot.control.duplicate(true)
	var transitioned: Variant = slot._region_join_npc_party_reference(next_clock, "npc_join", "player_live", joined.mapping, npc_proof)
	if not check(transitioned.ok and next_clock.region_gameplay.parties.npc_join.phase == "joined" and next_clock.region_gameplay.parties.npc_join.entered_party == "player_live", "original Slot producer creates joined phase from actual join mapping/source proof"): return
	var join_publish: Variant = slot._publish({}, next_clock, "", joined_journey)
	if not check(join_publish.ok and slot.control.faction_registry.next_faction_id == 12001 and slot.control.faction_registry.entries.has("9011"), "joined archive remains historical highwater; current entered_party publishes"): return
	var reopened: ObservedSlot = ObservedSlot.new()
	reopened.folder = slot.folder; reopened.source = slot.source; reopened.pin = slot.pin.duplicate(true)
	var reopened_state: Variant = reopened._recover_control()
	if not check(reopened_state.ok and reopened.party_reads == 2 and reopened.region_registry().parties.npc_join.phase == "joined", "cold reopen fully validates actual joined current/history documents"): return
	var subsequent: Variant = reopened._publish({}, reopened.control, "", reopened.region_travel_journey())
	if not check(subsequent.ok and reopened.party_reads == 2 and reopened.control.faction_registry.next_faction_id == 12001, "subsequent publish checks current phase/registry without repeated source decode"): return
	var marker: Variant = reopened.folder.path_join("commits/%020d.json" % int(reopened._marker.generation))
	var marker_sha: String = FileAccess.get_sha256(marker)
	var current_bytes: PackedByteArray = var_to_bytes([reopened.control, reopened._marker])
	var unknown: Variant = reopened.control.duplicate(true)
	unknown.region_gameplay.parties.npc_join.phase = "unknown"
	var unknown_bytes: PackedByteArray = var_to_bytes(unknown)
	var unknown_reads: int = reopened.party_reads
	var refused: Variant = reopened._publish({}, unknown, "", reopened.region_travel_journey())
	if not check(not refused.ok and refused.code == "FACTION_SCAN_INCOMPLETE" and FileAccess.get_sha256(marker) == marker_sha and var_to_bytes([reopened.control, reopened._marker]) == current_bytes, "unknown phase cannot borrow warm cache or publish a marker"): return
	if not check(reopened.party_reads == unknown_reads and var_to_bytes(unknown) == unknown_bytes
			and not FileAccess.file_exists(reopened.folder.path_join("commits/%020d.json" % (int(reopened._marker.generation) + 1))),
			"unknown phase leaves candidate and decoder count unchanged and creates no next-generation commit"): return
	var absent: Variant = reopened.control.duplicate(true)
	absent.region_gameplay.parties.npc_join.entered_party = "missing"
	if not check(reopened._publish({}, absent, "", reopened.region_travel_journey()).code == "FACTION_SCAN_INCOMPLETE" and FileAccess.get_sha256(marker) == marker_sha, "joined missing actual destination rejects even with cached original archive"): return
	var failed_registry: Variant = reopened.control.duplicate(true)
	failed_registry.faction_registry.version = 99
	if not check(not reopened._publish({}, failed_registry, "", reopened.region_travel_journey()).ok and FileAccess.get_sha256(marker) == marker_sha, "failed current-registry publication remains rejected after cache warmup"): return
	# The original in-memory clock publisher may lead the last saved generation.
	# Produce a valid interval through the original API, without assigning clocks.
	var ahead_marker: Dictionary = reopened._marker
	var ahead_control: Dictionary = reopened.control
	var ahead_interval: Dictionary = RegionSaveSlot.preview_fire_interval(ahead_control.fire_clock,
		float(ahead_control.logical_game_seconds), 1.0 / 60.0, 1.0, 0.0)
	if not check(ahead_interval.ok, "original clock interval admits the ahead-live-control fixture"): return
	var ahead_game: float = reopened.advance_world_time(float(ahead_interval.game_end) - float(ahead_interval.game_begin))
	RegionSaveSlot.append_completed_fire_interval(ahead_control.fire_clock, ahead_interval)
	if not check(ahead_game == float(ahead_interval.game_end) and ahead_game > float(ahead_marker.control.logical_game_seconds)
			and RegionSaveSlot.validate_fire_clock(ahead_control.fire_clock, ahead_game).ok,
			"original publisher creates an ahead live clock with a valid fire journal"): return
	var ahead_bytes: PackedByteArray = var_to_bytes([reopened.control, reopened._marker])
	var ahead_recovered: Dictionary = reopened._recover_control()
	if not check(ahead_recovered.ok and is_same(reopened.control, ahead_control) and is_same(reopened._marker, ahead_marker)
			and var_to_bytes([reopened.control, reopened._marker]) == ahead_bytes,
			"validated same generation retains exact marker independently of ahead live control"): return
	var ahead_unknown: Dictionary = reopened.control.duplicate(true)
	ahead_unknown.region_gameplay.parties.npc_join.phase = "unknown"
	var ahead_unknown_bytes: PackedByteArray = var_to_bytes(ahead_unknown)
	var ahead_reads: int = reopened.party_reads
	var ahead_refused: Dictionary = reopened._publish({}, ahead_unknown, "", reopened.region_travel_journey())
	if not check(not ahead_refused.ok and ahead_refused.code == "FACTION_SCAN_INCOMPLETE"
			and reopened.party_reads == ahead_reads and var_to_bytes(ahead_unknown) == ahead_unknown_bytes
			and var_to_bytes([reopened.control, reopened._marker]) == ahead_bytes
			and FileAccess.get_sha256(marker) == marker_sha
			and not FileAccess.file_exists(reopened.folder.path_join("commits/%020d.json" % (int(reopened._marker.generation) + 1))),
			"unknown phase refuses with ahead live control and retains exact owners without a new marker"): return
	# A non-equivalent RAM marker must never be retained by the new branch.
	var clean_transfer: String = str(reopened._marker.transfer_token)
	var ahead_control_bytes: PackedByteArray = var_to_bytes(reopened.control)
	var damaged_marker: Dictionary = reopened._marker
	damaged_marker.transfer_token = "unvalidated RAM marker"
	var repaired_marker: Dictionary = reopened._recover_control()
	if not check(repaired_marker.ok and not is_same(reopened._marker, damaged_marker)
			and str(reopened._marker.transfer_token) == clean_transfer and int(reopened._marker.generation) == int(ahead_marker.generation)
			and var_to_bytes(reopened.control) == ahead_control_bytes and FileAccess.get_sha256(marker) == marker_sha,
			"non-equivalent RAM marker is replaced by the validated record while ahead control remains"): return
	# A genuine competing writer publishes the next generation; the stale caller
	# must recover it and return the original conflict without another commit.
	var stale_generation: int = int(reopened._marker.generation)
	var peer: ObservedSlot = ObservedSlot.new()
	peer.folder = reopened.folder; peer.source = reopened.source; peer.pin = reopened.pin.duplicate(true)
	if not check(peer._recover_control().ok, "competing original Slot fully recovers the actual saved generation"): return
	var peer_published: Dictionary = peer._publish({}, peer.control, "", peer.region_travel_journey())
	if not check(peer_published.ok and int(peer._marker.generation) == stale_generation + 1,
			"competing original Slot publishes a genuine next-generation marker"): return
	var peer_path: String = reopened.folder.path_join("commits/%020d.json" % (stale_generation + 1))
	var peer_sha: String = FileAccess.get_sha256(peer_path)
	var stale_refused: Dictionary = reopened._publish({}, reopened.control, "", reopened.region_travel_journey())
	if not check(not stale_refused.ok and stale_refused.code == "CONFLICT" and int(reopened._marker.generation) == stale_generation + 1
			and var_to_bytes(reopened.control) == ahead_control_bytes and FileAccess.get_sha256(peer_path) == peer_sha
			and not FileAccess.file_exists(reopened.folder.path_join("commits/%020d.json" % (stale_generation + 2))),
			"newer generation is recovered and conflicts instead of retaining stale or contaminated marker"): return
	if not check(fault.read().is_empty() and Time.get_ticks_msec() <= deadline, "sticky first error and original 90-second deadline preserved"): return
	print("REGION_FACTION_F1A_V2_PASS ", checks, " actual typed NPC join/Slot publication/reopen and source-cache contracts; no movement/sea/Native/performance proof")
	quit(0)
