extends SceneTree
## T6 S3: pure treaty-rate lookup (Q12 A). Five states, relation rules, strict treaty shape,
## boundary minutes, and no mutation of the inputs. No Site, no Node, no Region Slot.

const Treaty = preload("res://scripts/terrain_lab/site_trade_treaty_rate.gd")

const SIGNED := 100
const EXPIRES := 200

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_TRADE_TREATY_RATE_FAIL: " + message)
	quit(1)
	return false

func _trade(percent: int, expires: int, status: String) -> Dictionary:
	return {"kind": "trade", "a": 1, "b": 2, "tax_percent": percent, "expires_minute": expires, "signed_minute": SIGNED, "status": status}

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_TRADE_TREATY_RATE_TIMEOUT"); quit(1))

	# Pair key is order-insensitive.
	if not _check(Treaty.pair_key(7, 3) == "3:7" and Treaty.pair_key(3, 7) == "3:7", "pair key order-insensitive"): return

	# Relation: same faction is peace; unrecorded pair is hostile; recorded values must be known.
	if not _check(Treaty.relation_of({}, 4, 4).relation == "peace", "same faction is peace"): return
	if not _check(Treaty.relation_of({}, 1, 2).relation == "hostile", "unrecorded pair is hostile"): return
	if not _check(Treaty.relation_of({"1:2": "peace"}, 2, 1).relation == "peace", "recorded peace found in either order"): return
	if not _check(Treaty.relation_of({"1:2": "allied"}, 1, 2).code == "INVALID", "unknown recorded relation refused"): return
	if not _check(Treaty.relation_of({}, -1, 2).code == "INVALID" and Treaty.relation_of({}, 1, 2.5).code == "INVALID", "bad faction ids refused"): return
	if not _check(Treaty.relation_of("nope", 1, 2).code == "INVALID", "non-dictionary relation table refused"): return

	# Q12 A state 1: never signed under peace uses the base rate and trades.
	var never: Dictionary = Treaty.trade_terms("peace", null, 30, 150)
	if not _check(never.ok and never.state == "none" and never.tax_percent == 30, "never signed: peace baseline"): return

	# State 2: active trade agreement changes only the tax percent.
	var active: Dictionary = Treaty.trade_terms("peace", _trade(12, EXPIRES, "active"), 30, 150)
	if not _check(active.ok and active.state == "active" and active.tax_percent == 12, "active: treaty rate replaces base"): return
	var no_expiry: Dictionary = Treaty.trade_terms("peace", _trade(0, -1, "active"), 30, 999999)
	if not _check(no_expiry.ok and no_expiry.state == "active" and no_expiry.tax_percent == 0, "active without expiry, rate 0"): return

	# State 3: expired returns to the base rate, still trades. Boundary: minute == expires is expired.
	var before_expiry: Dictionary = Treaty.trade_terms("peace", _trade(12, EXPIRES, "active"), 30, EXPIRES - 1)
	if not _check(before_expiry.state == "active", "one minute before expiry is still active"): return
	var at_expiry: Dictionary = Treaty.trade_terms("peace", _trade(12, EXPIRES, "active"), 30, EXPIRES)
	if not _check(at_expiry.ok and at_expiry.state == "expired" and at_expiry.tax_percent == 30, "at expiry: baseline, not banned"): return

	# State 4: revoked returns to the base rate while peace continues.
	var revoked: Dictionary = Treaty.trade_terms("peace", _trade(12, -1, "revoked"), 30, 150)
	if not _check(revoked.ok and revoked.state == "revoked" and revoked.tax_percent == 30, "revoked: baseline under peace"): return

	# State 5: war (hostile) refuses trade, even with an active treaty on record.
	var war: Dictionary = Treaty.trade_terms("hostile", _trade(12, EXPIRES, "active"), 30, 150)
	if not _check(not war.ok and war.code == "HOSTILE", "war refuses trade despite treaty"): return
	var no_relation: Dictionary = Treaty.trade_terms("hostile", null, 30, 150)
	if not _check(no_relation.code == "HOSTILE", "no relation refuses trade"): return

	# Unknown inputs are refused, not defaulted.
	if not _check(Treaty.trade_terms("allied", null, 30, 150).code == "INVALID", "unknown relation string refused"): return
	if not _check(Treaty.trade_terms("peace", null, 51, 150).code == "INVALID", "base rate 51 refused"): return
	if not _check(Treaty.trade_terms("peace", null, 2.5, 150).code == "INVALID", "base rate 2.5 refused"): return
	if not _check(Treaty.trade_terms("peace", null, 30, -1).code == "INVALID", "negative minute refused"): return
	if not _check(Treaty.trade_terms("peace", _trade(12, EXPIRES, "active"), 30, SIGNED - 1).code == "INVALID", "treaty before signing refused"): return

	# Strict treaty shape.
	if not _check(Treaty.valid_trade_treaty(_trade(50, EXPIRES, "active")), "rate 50 with expiry is valid"): return
	if not _check(not Treaty.valid_trade_treaty(_trade(51, EXPIRES, "active")), "rate 51 refused"): return
	if not _check(not Treaty.valid_trade_treaty(_trade(12, SIGNED, "active")), "expiry must be after signing"): return
	if not _check(not Treaty.valid_trade_treaty(_trade(12, -2, "active")), "expiry below -1 refused"): return
	if not _check(not Treaty.valid_trade_treaty(_trade(12, EXPIRES, "suspended")), "unknown status refused"): return
	var kind_bad: Dictionary = _trade(12, EXPIRES, "active")
	kind_bad.kind = "ceasefire"
	if not _check(not Treaty.valid_trade_treaty(kind_bad), "non-trade kind refused"): return
	var extra: Dictionary = _trade(12, EXPIRES, "active")
	extra.note = "extra"
	if not _check(not Treaty.valid_trade_treaty(extra), "extra key refused"): return
	var reversed: Dictionary = _trade(12, EXPIRES, "active")
	reversed.a = 2
	reversed.b = 1
	if not _check(not Treaty.valid_trade_treaty(reversed), "pair must be stored a < b"): return
	if not _check(not Treaty.valid_trade_treaty(null) and not Treaty.valid_trade_treaty([]), "non-dictionary treaty refused"): return

	# Inputs are never mutated.
	var treaty: Dictionary = _trade(12, EXPIRES, "active")
	var relations: Dictionary = {"1:2": "peace"}
	var before_text: String = JSON.stringify([treaty, relations])
	Treaty.trade_terms("peace", treaty, 30, 150)
	Treaty.relation_of(relations, 2, 1)
	if not _check(JSON.stringify([treaty, relations]) == before_text, "inputs unchanged"): return

	print("SITE_TRADE_TREATY_RATE_OK")
	quit(0)
