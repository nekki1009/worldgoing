extends RefCounted
## Pure validation and ordering for RegionSaveSlot's original registry.
## No clock, person, item or Site is owned by this helper.

const VERSION := 1
const MODES := ["live", "formula_active", "cold_exact", "materializing", "dematerializing", "committed-unbound"]
const REGISTRY_FIELDS := ["version", "revision", "next_sequence", "parties", "battles", "modes", "events", "observations", "reports", "evaluation"]
const EVENT_FIELDS := ["id", "kind", "at", "sequence", "player", "owner", "status", "payload"]
const EVENT_KINDS := ["player_arrival", "player_encounter", "player_death", "life", "supply", "work", "attack", "arrival", "reinforcement", "battle", "intel", "evaluation", "tactical"]

static func fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func seconds(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0

static func whole(value: Variant, minimum: int = 0) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= 2147483647.0

static func empty_registry() -> Dictionary:
	return {"version": VERSION, "revision": 0, "next_sequence": 1, "parties": {}, "battles": {}, "modes": {}, "events": [], "observations": {}, "reports": [], "evaluation": {}}

static func validate_registry(raw: Variant, world: float) -> Dictionary:
	if not raw is Dictionary or raw.size() != REGISTRY_FIELDS.size() or not seconds(world):
		return fail("REGION_SCHEMA", "Region 登記版本／欄位非法")
	for field: String in REGISTRY_FIELDS:
		if not raw.has(field): return fail("REGION_SCHEMA", "Region 登記缺必要欄位")
	if not whole(raw.version, 1) or int(raw.version) != VERSION or not whole(raw.revision) or not whole(raw.next_sequence, 1):
		return fail("REGION_SCHEMA", "Region revision／事件序號非法")
	for field: String in ["parties", "battles", "modes", "observations", "evaluation"]:
		if not raw[field] is Dictionary or raw[field].size() > 65536: return fail("REGION_SCHEMA", "Region 原 owner 索引非法")
	if not raw.events is Array or raw.events.size() > 65536 or not raw.reports is Array or raw.reports.size() > 65536:
		return fail("REGION_SCHEMA", "Region 事件／情報佇列非法")
	var report_owner: Script = load("res://scripts/region_lab/region_gameplay_ai.gd")
	var report_schema: Dictionary = report_owner.call("validate_reports", raw, world)
	if not report_schema.get("ok", false): return report_schema
	var ids := {}
	var sequences := {}
	for event: Variant in raw.events:
		var checked := validate_event(event)
		if not checked.ok: return checked
		if ids.has(event.id) or sequences.has(int(event.sequence)) or int(event.sequence) >= int(raw.next_sequence):
			return fail("REGION_SCHEMA", "Region 事件重號／序號超前")
		if str(event.status) == "complete" and not reached(float(event.at), world):
			return fail("REGION_SCHEMA", "Region 已完成事件超前世界")
		ids[event.id] = true
		sequences[int(event.sequence)] = true
	for owner: Variant in raw.modes:
		if not owner is String or owner.is_empty(): return fail("REGION_SCHEMA", "模式 owner 非法")
		var checked := validate_mode(raw.modes[owner], str(owner), world)
		if not checked.ok: return checked
	for field: String in ["parties", "battles"]:
		for identity: Variant in raw[field]:
			if not identity is String or identity.is_empty() or not raw[field][identity] is Dictionary:
				return fail("REGION_SCHEMA", "Region owner 引用非法")
	for battle: Dictionary in raw.battles.values():
		if str(battle.get("kind", "")) != "siege": continue
		var rules: Script = load("res://scripts/region_lab/region_gameplay_battle.gd") as Script
		var raw_admission: Variant = rules.call("validate_siege_metadata", battle.get("siege"))
		if not raw_admission is Dictionary: return fail("INVALID_SIEGE_SOURCE", "原攻城快照准入未回傳合法結果")
		var admitted: Dictionary = raw_admission
		if not admitted.ok or str(battle.get("phase", "")) != str(battle.siege.phase) or str(battle.get("site_id", "")) != str(battle.siege.source.owner) or float(battle.siege.source.game_seconds) > world + 0.00000001 or str(battle.get("mode", "")) not in ["cold_exact", "materializing", "live", "dematerializing", "committed-unbound"]:
			return fail("INVALID_SIEGE_SOURCE", "原四階段 siege source／version／phase 未准入")
	return {"ok": true}

static func validate_event(event: Variant) -> Dictionary:
	if not event is Dictionary or event.size() != EVENT_FIELDS.size(): return fail("REGION_EVENT", "事件欄位非法")
	for field: String in EVENT_FIELDS:
		if not event.has(field): return fail("REGION_EVENT", "事件缺必要欄位")
	if not event.id is String or event.id.is_empty() or event.kind not in EVENT_KINDS or not seconds(event.at) or not whole(event.sequence, 1) or not event.player is bool or not event.owner is String or event.owner.is_empty() or event.status not in ["pending", "complete"] or not event.payload is Dictionary:
		return fail("REGION_EVENT", "事件種類／時間／原 owner 非法")
	return {"ok": true}

static func priority(event: Dictionary) -> int:
	if bool(event.player): return 0
	match str(event.kind):
		"life", "supply", "work", "attack": return 10
		"arrival", "reinforcement": return 20
		"battle": return 30
		"intel": return 40
		"evaluation": return 50
		"tactical": return 5
	return 60

static func before(left: Dictionary, right: Dictionary) -> bool:
	if float(left.at) != float(right.at): return float(left.at) < float(right.at)
	if priority(left) != priority(right): return priority(left) < priority(right)
	if str(left.owner) != str(right.owner): return str(left.owner) < str(right.owner)
	return int(left.sequence) < int(right.sequence)

static func queue_event(registry: Dictionary, identity: String, kind: String, at: float, owner: String, payload: Dictionary = {}, player: bool = false) -> Dictionary:
	for prior: Dictionary in registry.events:
		if str(prior.id) != identity: continue
		if str(prior.kind) != kind or float(prior.at) != at or str(prior.owner) != owner or bool(prior.player) != player or prior.payload != payload:
			return fail("REGION_EVENT_CONFLICT", "原事件號已有不同內容")
		return {"ok": true, "event": prior, "duplicate": true}
	var event := {"id": identity, "kind": kind, "at": at, "sequence": int(registry.next_sequence), "player": player, "owner": owner, "status": "pending", "payload": payload.duplicate(true)}
	var checked := validate_event(event)
	if not checked.ok: return checked
	if int(registry.next_sequence) >= 2147483647: return fail("REGION_EVENT", "事件序號用盡")
	registry.events.append(event)
	registry.next_sequence = int(registry.next_sequence) + 1
	return {"ok": true, "event": event, "duplicate": false}

## The one rule for "this event's time has been reached at world". The dispatcher
## (pending_at), the consumer (complete_event), the registry check and the
## checkpoint context validator (site_region_checkpoint.gd) all use it, so an
## event the dispatcher hands out can also be listed in a context at that world.
static func reached(at: float, world: float) -> bool:
	return at <= world + 0.00000001

static func pending_at(registry: Dictionary, world: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in registry.events:
		if str(event.status) == "pending" and reached(float(event.at), world): result.append(event)
	result.sort_custom(before)
	return result

static func _held_player_death(event: Dictionary, held_player_death_ids: Array[String]) -> bool:
	if held_player_death_ids.is_empty() or not event.get("id") is String or not held_player_death_ids.has(str(event.id)): return false
	if event.get("status") != "pending" or not event.get("player") is bool or event.player != true or event.get("kind") not in ["player_death", "life"]: return false
	var payload: Variant = event.get("payload")
	if not payload is Dictionary or not payload.get("controlled") is bool or payload.controlled != true or not payload.get("death") is bool or payload.death != true: return false
	var effect_receipt: Variant = payload.get("effect_receipt")
	return effect_receipt is Dictionary and effect_receipt.get("effects_complete") is bool and effect_receipt.effects_complete == true

static func next_endpoint(registry: Dictionary, begin: float, end: float, held_player_death_ids: Array[String] = []) -> float:
	var result: float = end
	for event: Dictionary in registry.events:
		if str(event.status) == "pending" and not _held_player_death(event, held_player_death_ids): result = minf(result, maxf(begin, float(event.at)))
	return result

static func complete_event(registry: Dictionary, identity: String, world: float) -> Dictionary:
	for event: Dictionary in registry.events:
		if str(event.id) != identity: continue
		if not reached(float(event.at), world): return fail("REGION_EVENT", "未到事件時間不能消費")
		var duplicate := str(event.status) == "complete"
		event.status = "complete"
		return {"ok": true, "duplicate": duplicate}
	return fail("REGION_EVENT", "找不到原事件")

static func player_barrier(registry: Dictionary, world: float, held_player_death_ids: Array[String] = []) -> Dictionary:
	for event: Dictionary in pending_at(registry, world):
		if bool(event.player) and not _held_player_death(event, held_player_death_ids): return event
	return {}

static func validate_mode(value: Variant, owner: String, world: float) -> Dictionary:
	const FIELDS := ["version", "mode", "revision", "generation", "backend", "consumer", "activation", "game_seconds", "action_seconds", "tactical_until_action"]
	if not value is Dictionary or value.size() != FIELDS.size(): return fail("REGION_MODE", "模式欄位非法")
	for field: String in FIELDS:
		if not value.has(field): return fail("REGION_MODE", "模式缺必要欄位")
	if int(value.get("version", -1)) != VERSION or value.mode not in MODES or not whole(value.revision) or not whole(value.generation) or value.backend not in ["gd", "native"] or not value.consumer is String or value.consumer.is_empty() or not value.activation is Dictionary:
		return fail("REGION_MODE", "模式／來源／後端非法")
	for field: String in ["game_seconds", "action_seconds", "tactical_until_action"]:
		if not seconds(value[field]): return fail("REGION_MODE", "模式完成端點非法")
	if float(value.game_seconds) > world + 0.00000001: return fail("REGION_MODE", "模式水印超前世界")
	if not value.activation.is_empty() and (str(value.activation.get("owner", "")) != owner or str(value.activation.get("mode", "")) != str(value.mode) or int(value.activation.get("mode_revision", -1)) != int(value.revision)):
		return fail("REGION_MODE", "模式啟用收據來源不同")
	return {"ok": true}

static func activate_mode(registry: Dictionary, owner: String, mode: String, generation: int, backend: String, consumer: String, game: float, action: float, receipt: Dictionary) -> Dictionary:
	if mode not in MODES or owner.is_empty() or not seconds(game) or not seconds(action): return fail("REGION_MODE", "模式啟用非法")
	var prior: Dictionary = registry.modes.get(owner, {})
	var revision := int(prior.get("revision", -1)) + 1
	var value := {"version": VERSION, "mode": mode, "revision": revision, "generation": generation, "backend": backend, "consumer": consumer, "activation": {}, "game_seconds": game, "action_seconds": action, "tactical_until_action": action}
	if mode in ["live", "cold_exact", "formula_active"]:
		if receipt.get("ok") != true or receipt.get("complete") != true or str(receipt.get("owner", "")) != owner or str(receipt.get("mode", "")) != mode or int(receipt.get("generation", -1)) != generation or str(receipt.get("backend", "")) != backend or str(receipt.get("consumer", "")) != consumer:
			return fail("REGION_ACTIVATION", "原 consumer 啟用未完成")
		value.activation = receipt.duplicate(true)
		value.activation.mode_revision = revision
	var checked := validate_mode(value, owner, game)
	if not checked.ok: return checked
	registry.modes[owner] = value
	return {"ok": true, "mode": value}

static func begin_permit(registry: Dictionary, owner: String, mode: String, generation: int, world: float, action: float, consumer: String, held_player_death_ids: Array[String] = []) -> Dictionary:
	var value: Dictionary = registry.modes.get(owner, {})
	var checked: Dictionary = validate_mode(value, owner, world)
	if not checked.ok: return checked
	if str(value.mode) != mode or mode not in ["live", "cold_exact", "formula_active"] or int(value.generation) != generation or str(value.consumer) != consumer or value.activation.get("complete") != true:
		return fail("REGION_PERMIT", "來源／模式／原 consumer 未准入")
	if absf(float(value.game_seconds) - world) > 0.00000001 or absf(float(value.action_seconds) - action) > 0.00000001:
		return fail("REGION_PERMIT", "原 consumer 與世界完成端點不同")
	if not player_barrier(registry, world, held_player_death_ids).is_empty(): return fail("PLAYER_BARRIER", "玩家事件尚未處理，不能推新區間")
	return {"ok": true, "owner": owner, "mode": mode, "mode_revision": int(value.revision), "generation": generation, "runtime_revision": int(registry.revision), "world_game_seconds": world, "action_seconds": action, "consumer": consumer, "backend": str(value.backend)}

static func check_permit(registry: Dictionary, permit: Dictionary, generation: int, world: float, action: float) -> Dictionary:
	var value: Dictionary = registry.modes.get(str(permit.get("owner", "")), {})
	if not value.is_empty() and int(permit.get("generation", -1)) == generation and int(permit.get("runtime_revision", -1)) == int(registry.revision) and int(permit.get("mode_revision", -1)) == int(value.revision) and str(permit.get("mode", "")) == str(value.mode) and str(permit.get("consumer", "")) == str(value.consumer) and str(permit.get("backend", "")) == str(value.backend) and permit.get("world_game_seconds") == world and permit.get("action_seconds") == action:
		return {"ok": true}
	return fail("STALE_REGION_PERMIT", "原步 permit 已過期；不發布半份區間")

static func tactical_seconds(registry: Dictionary, action: float, elapsed: float, local: float = 0.0) -> float:
	var result := clampf(local, 0.0, elapsed)
	for value: Dictionary in registry.modes.values():
		if str(value.mode) in ["live", "formula_active", "cold_exact"] and value.activation.get("complete") == true:
			result = maxf(result, clampf(float(value.tactical_until_action) - action, 0.0, elapsed))
	return result

## TCM (Nekki 11/15 M1 A): one Site rate; `tactical` is kept for the callers' signature only.
static func action_for_game(delta_game: float, scale: float, _tactical: float = 0.0) -> float:
	return delta_game / scale / 60.0

static func clip_interval(registry: Dictionary, world: float, action: float, elapsed: float, scale: float, local_tactical: float = 0.0, held_player_death_ids: Array[String] = []) -> Dictionary:
	if not seconds(world) or not seconds(action) or not seconds(elapsed) or elapsed <= 0.0 or scale not in [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]: return fail("REGION_INTERVAL", "共同區間非法")
	var tactical: float = tactical_seconds(registry, action, elapsed, local_tactical)
	var delta_game: float = 60.0 * elapsed * scale # TCM (Nekki 11/15 M1 A): one Site rate; tactical is the combat share only
	var endpoint: float = next_endpoint(registry, world, world + delta_game, held_player_death_ids)
	if endpoint <= world + 0.0000000001: return {"ok": true, "pending": true, "action_seconds": 0.0, "game_seconds": 0.0, "tactical_seconds": 0.0, "game_end": world}
	var clipped: float = elapsed
	# An uncut interval already owns its exact ACTION input.
	if endpoint < world + delta_game:
		clipped = minf(elapsed, action_for_game(endpoint - world, scale, tactical))
	var clipped_tactical: float = minf(tactical, clipped)
	var game: float = 60.0 * clipped * scale # TCM: one Site rate
	return {"ok": true, "pending": false, "action_seconds": clipped, "game_seconds": game, "tactical_seconds": clipped_tactical, "game_end": world + game}
