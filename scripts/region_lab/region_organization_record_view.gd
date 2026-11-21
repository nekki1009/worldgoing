extends RefCounted
## A revocable private read view; never owns a body or retains a live Lab/Data.
var _slot: WeakRef
var _ticket: Dictionary
var _kind: String
var _key: String
var _epoch: int

func _init(slot: RefCounted, ticket: Dictionary, kind: String, key: String, epoch: int) -> void:
	_slot = weakref(slot)
	_ticket = ticket.duplicate(true)
	_kind = kind
	_key = key
	_epoch = epoch

func read() -> Dictionary:
	var slot: RefCounted = _slot.get_ref()
	if slot == null: return {"ok": false, "code": "ORGANIZATION_STAGE_CLOSED"}
	return slot.call("_read_organization_edit_record", _ticket, _kind, _key, _epoch)
