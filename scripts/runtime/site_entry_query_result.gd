class_name SiteEntryQueryResult
extends RefCounted

const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")

var can_enter: bool = false
var failure_reason: int = TravelFailureReasonType.Code.NONE
var party_id: String = ""
var site_id: String = ""
var poi_id: String = ""
var poi: WorldPOIData
var site_definition: SiteData
var world_cell: Vector2i = Vector2i(-1, -1)
var region_cell: Vector2i = Vector2i(-1, -1)
