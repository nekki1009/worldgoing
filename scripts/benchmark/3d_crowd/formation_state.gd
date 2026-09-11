class_name CrowdFormationState
extends RefCounted

## Formation-level tactical state. Soldiers never own movement or pathfinding.

var formation_id: int = -1
var center_position: Vector3 = Vector3.ZERO
var facing: float = 0.0
var destination: Vector3 = Vector3.ZERO
var movement_speed: float = 3.0
var formation_width: float = 12.5
var formation_depth: float = 12.5
var spacing: float = 1.25
var formation_type: StringName = &"Infantry"
var target_formation_id: int = -1
var movement_state: StringName = &"Idle"
var destination_cycle: int = 0
var active: bool = true
