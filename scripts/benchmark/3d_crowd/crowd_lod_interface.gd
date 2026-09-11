class_name CrowdLodInterface
extends RefCounted

## Presentation-only distance policy. Simulation never changes when a band changes.

enum Band { NEAR, MID, FAR }

const LOD_NEAR_DISTANCE: float = 45.0
const LOD_MID_DISTANCE: float = 180.0
const LOD_FAR_DISTANCE: float = 480.0

var near_distance: float = LOD_NEAR_DISTANCE
var mid_distance: float = LOD_MID_DISTANCE
var far_distance: float = LOD_FAR_DISTANCE

func classify_distance(distance: float) -> int:
	if distance <= near_distance:
		return Band.NEAR
	if distance <= mid_distance:
		return Band.MID
	return Band.FAR

func band_name(band: int) -> StringName:
	match band:
		Band.NEAR:
			return &"Near"
		Band.MID:
			return &"Mid"
		_:
			return &"Far"
