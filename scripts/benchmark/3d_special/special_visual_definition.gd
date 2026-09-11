class_name SpecialVisualDefinition
extends RefCounted

enum Slot { BODY, HEAD, HAIR, ARMOR, HELMET, WEAPON, SHIELD }
enum BodyRegion { HEAD, TORSO, ARMS, HANDS, LEGS, FEET }

var slot: int = Slot.BODY
var visual_id: StringName = &""
var mesh: Mesh
var region_meshes: Array = []
var material: Material
var compatible_rig: StringName = &"HumanRig_v1"
var hide_body_regions: PackedInt32Array = PackedInt32Array()
var attachment_socket: StringName = &""
var equipment_kind: StringName = &""
var hides_hair: bool = false

func is_compatible() -> bool:
	return compatible_rig == &"HumanRig_v1"
