class_name CrowdFormationSlotGenerator
extends RefCounted

static func local_position(
	slot_index: int,
	columns: int = 10,
	rows: int = 10,
	spacing: float = 1.25
) -> Vector3:
	var column: int = posmod(slot_index, columns)
	var row: int = floori(float(slot_index) / float(columns))
	var x: float = (float(column) - float(columns - 1) * 0.5) * spacing
	var z: float = (float(row) - float(rows - 1) * 0.5) * spacing
	return Vector3(x, 0.0, z)
