class_name BattleSiteSnapshot
extends RefCounted

enum FailureReason {
	NONE,
	RUNTIME_UNAVAILABLE,
	INVALID_DESTINATION,
	IMPASSABLE,
	TRAVEL_IN_PROGRESS,
	INVALID_PARTICIPANT,
}

var success: bool = false
var failure_reason: int = FailureReason.NONE
var context: BattleSiteContext
var site_layouts: Array[SiteLayoutData] = []
var footprint_cells: Array[Dictionary] = []
var size_meters: Vector2 = Vector2.ZERO
var bounds_meters: Rect2 = Rect2()
var center_cell: Dictionary = {}
var center_terrain: int = -1
var attacker_deployment: Dictionary = {}
var defender_deployment: Dictionary = {}
var terrain_debug_representation: String = ""
var terrain_hash: String = ""
var preview_hash: String = ""
var active_battle: bool = false
var revision: int = 0
var formations: Array[BattleFormationData] = []

func has_preview() -> bool:
	return success and context != null \
		and site_layouts.size() == 9 \
		and footprint_cells.size() == 9

func copy() -> BattleSiteSnapshot:
	var result: BattleSiteSnapshot = BattleSiteSnapshot.new()
	result.success = success
	result.failure_reason = failure_reason
	result.context = context
	result.site_layouts.clear()
	for layout: SiteLayoutData in site_layouts:
		result.site_layouts.append(layout.copy())
	result.footprint_cells = footprint_cells.duplicate(true)
	result.size_meters = size_meters
	result.bounds_meters = bounds_meters
	result.center_cell = center_cell.duplicate(true)
	result.center_terrain = center_terrain
	result.attacker_deployment = attacker_deployment.duplicate(true)
	result.defender_deployment = defender_deployment.duplicate(true)
	result.terrain_debug_representation = terrain_debug_representation
	result.terrain_hash = terrain_hash
	result.preview_hash = preview_hash
	result.active_battle = active_battle
	result.revision = revision
	for formation: BattleFormationData in formations:
		result.formations.append(formation.copy())
	return result

static func failure_code(reason: int) -> String:
	match reason:
		FailureReason.RUNTIME_UNAVAILABLE:
			return "RUNTIME_UNAVAILABLE"
		FailureReason.INVALID_DESTINATION:
			return "INVALID_DESTINATION"
		FailureReason.IMPASSABLE:
			return "IMPASSABLE"
		FailureReason.TRAVEL_IN_PROGRESS:
			return "TRAVEL_IN_PROGRESS"
		FailureReason.INVALID_PARTICIPANT:
			return "INVALID_PARTICIPANT"
		_:
			return "NONE"
