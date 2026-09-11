class_name CrowdSoldierState
extends RefCounted

## Pure-data schema for one soldier.
##
## BattleCrowdSimulation stores the live 10,000-row collection as packed SoA
## columns instead of allocating 10,000 RefCounted rows. This class documents
## the row contract and remains available for future squad-level tooling.

var soldier_id: int = -1
var formation_id: int = -1
var slot_index: int = -1
var local_position: Vector3 = Vector3.ZERO
var world_position: Vector3 = Vector3.ZERO
var facing: float = 0.0
var animation_state: int = 0
var visual_variant: int = 0
var alive: bool = true
var animation_phase: float = 0.0
