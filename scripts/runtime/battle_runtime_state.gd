class_name BattleRuntimeState
extends RefCounted

var base_snapshot: BattleSiteSnapshot
var formations: Dictionary = {}
var clearance_blocked: PackedByteArray = PackedByteArray()
var revision: int = 0
var elapsed_seconds: float = 0.0

func _init(p_snapshot: BattleSiteSnapshot = null) -> void:
	base_snapshot = p_snapshot.copy() if p_snapshot != null else null

func is_valid() -> bool:
	return base_snapshot != null and base_snapshot.has_preview()

func add_formation(formation: BattleFormationData) -> bool:
	if formation == null or formation.formation_id.is_empty():
		return false
	formations[formation.formation_id] = formation
	return true

func find_formation(formation_id: String) -> BattleFormationData:
	var value: Variant = formations.get(formation_id, null)
	return value as BattleFormationData if value is BattleFormationData else null

func snapshot() -> BattleSiteSnapshot:
	if not is_valid():
		return null
	var result: BattleSiteSnapshot = base_snapshot.copy()
	result.active_battle = true
	result.revision = revision
	result.formations.clear()
	var keys: Array[String] = []
	for key: Variant in formations.keys():
		keys.append(str(key))
	keys.sort()
	for key: String in keys:
		result.formations.append((formations[key] as BattleFormationData).copy())
	return result
