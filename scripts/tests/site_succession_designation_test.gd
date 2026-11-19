extends SceneTree
## R5 S1: designated heir data (pure rules and the nation validator). No succession transaction, no holder change.
## The command's head-executor authority needs a live lab and is covered by the lab-level test in a later pass.

const Succession = preload("res://scripts/terrain_lab/site_succession.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	var head := 7
	var heir := 8
	var stranger := 9
	var dead := 10
	var offices: Dictionary = SiteOffices.default_offices("nation", head, false)
	var seat_id: String = str(SiteOffices.head_position(offices).id)
	var seat_ids: Array = [seat_id]
	var members: Dictionary = {head: true, heir: true, dead: true}
	var alive := func(identity: int) -> bool: return identity != dead
	var record: Dictionary = Succession.empty_record()
	var before: PackedByteArray = var_to_bytes(record)
	# Designation: a live member, not the seated head, on the head seat.
	var designated: Dictionary = Succession.designate(record, seat_id, heir, seat_ids, members, head, alive)
	if not bool(designated.ok): _fail("designating a live member heir succeeds: %s" % str(designated))
	if int(designated.record.heirs[seat_id]) != heir: _fail("the heir is stored on the head seat")
	if var_to_bytes(record) != before: _fail("designation never mutates the stored record")
	# Refusals leave the record byte-identical.
	var refusals: Array = [
		[seat_id, head, "DUPLICATE_HOLDER"],
		[seat_id, stranger, "NO_TARGET"],
		[seat_id, dead, "NO_TARGET"],
		["pos_999", heir, "NO_TARGET"],
	]
	for case: Array in refusals:
		var refused: Dictionary = Succession.designate(record, str(case[0]), int(case[1]), seat_ids, members, head, alive)
		if str(refused.code) != str(case[2]) or bool(refused.ok): _fail("refusal %s: %s" % [str(case), str(refused)])
		if var_to_bytes(record) != before: _fail("refusal leaves the record byte-identical: %s" % str(case))
	# Validator: strict shape, a known head seat, and a current member.
	var nation: Dictionary = {"members": [head, heir], "standards": {}, "offices": offices}
	var known: Dictionary = {head: true, heir: true}
	if not Orders.valid_nations({"n1": nation}, {}, known): _fail("a nation without succession still validates")
	nation.succession = designated.record
	if not Orders.valid_nations({"n1": nation}, {}, known): _fail("a nation with a valid designated heir validates")
	var bad_member: Dictionary = designated.record.duplicate(true)
	bad_member.heirs[seat_id] = stranger
	nation.succession = bad_member
	if Orders.valid_nations({"n1": nation}, {}, known): _fail("a heir who is not a member is refused")
	var bad_seat: Dictionary = designated.record.duplicate(true)
	bad_seat.heirs["pos_999"] = heir
	nation.succession = bad_seat
	if Orders.valid_nations({"n1": nation}, {}, known): _fail("a heir on an unknown seat is refused")
	var bad_version: Dictionary = designated.record.duplicate(true)
	bad_version.version = 2
	nation.succession = bad_version
	if Orders.valid_nations({"n1": nation}, {}, known): _fail("an unknown succession version refuses the whole nation")
	var bad_extra: Dictionary = designated.record.duplicate(true)
	bad_extra.extra = 1
	nation.succession = bad_extra
	if Orders.valid_nations({"n1": nation}, {}, known): _fail("an extra key refuses the whole nation")
	# Save round trip: JSON numbers load as floats; normalize restores exact integers and the validator accepts it.
	var text: String = JSON.stringify(designated.record)
	var loaded: Variant = JSON.parse_string(text)
	if not loaded is Dictionary: _fail("the record survives JSON")
	if not Succession.valid_record(loaded, seat_ids, members): _fail("a float-loaded heir id validates before normalize")
	Succession.normalize_numbers(loaded)
	if not (loaded.heirs[seat_id] is int) or int(loaded.heirs[seat_id]) != heir: _fail("normalize restores an exact integer heir id")
	nation.succession = loaded
	if not Orders.valid_nations({"n1": nation}, {}, known): _fail("the reloaded nation validates")
	# Missing section loads empty: no heir, valid.
	nation.erase("succession")
	if not Orders.valid_nations({"n1": nation}, {}, known): _fail("a missing succession section loads as empty")
	print("SITE SUCCESSION DESIGNATION PASS: heir designated on the head seat (data only); refusals byte-identical; the nation validator refuses non-member, unknown-seat, unknown-version and extra-key records; JSON float ids normalize; a missing section loads empty.")
	quit(0)
