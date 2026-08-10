class_name BattleRuntimeState
extends RefCounted

var base_snapshot: BattleSiteSnapshot
var formations: Dictionary = {}
var orders: Dictionary = {}
var pending_orders: Array[BattleOrderData] = []
var dispatches: Dictionary = {}
var commander_formation_ids: Dictionary = {}
var clearance_blocked: PackedByteArray = PackedByteArray()
var revision: int = 0
var elapsed_seconds: float = 0.0
var order_sequence: int = 0

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

func add_order(order: BattleOrderData) -> bool:
	if order == null or order.order_id.is_empty():
		return false
	orders[order.order_id] = order
	return true

func find_order(order_id: String) -> BattleOrderData:
	var value: Variant = orders.get(order_id, null)
	return value as BattleOrderData if value is BattleOrderData else null

func add_dispatch(dispatch: BattleDispatchData) -> bool:
	if dispatch == null or dispatch.order_id.is_empty():
		return false
	dispatches[dispatch.order_id] = dispatch
	return true

func find_dispatch(order_id: String) -> BattleDispatchData:
	var value: Variant = dispatches.get(order_id, null)
	return value as BattleDispatchData if value is BattleDispatchData else null

func has_dispatch_for_target(target_formation_id: String) -> bool:
	for value: Variant in dispatches.values():
		if value is BattleDispatchData \
			and (value as BattleDispatchData).target_formation_id == target_formation_id \
			and (value as BattleDispatchData).state == BattleOrderData.State.EN_ROUTE:
			return true
	return false

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
	result.orders.clear()
	var order_keys: Array[String] = []
	for key: Variant in orders.keys():
		order_keys.append(str(key))
	order_keys.sort()
	for key: String in order_keys:
		result.orders.append((orders[key] as BattleOrderData).copy())
	result.dispatches.clear()
	var dispatch_keys: Array[String] = []
	for key: Variant in dispatches.keys():
		dispatch_keys.append(str(key))
	dispatch_keys.sort()
	for key: String in dispatch_keys:
		result.dispatches.append((dispatches[key] as BattleDispatchData).copy())
	return result
