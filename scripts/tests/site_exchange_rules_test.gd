extends SceneTree

const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var a := {"ability": 50.0}
	var b := {"ability": 50.0}
	var draw := Rules.exchange_result(a, b)
	assert(draw.winner == 0 and draw.kind == "draw")
	assert(draw.hp == 0.0 and draw.stun == 0.0 and draw.stagger == 0.0)
	assert(draw.hold == 0.3 and not draw.knockback)
	assert(draw.fatigue_a == 0.5 and draw.fatigue_b == 0.5)
	for edge: float in [-5.0, 5.0]:
		assert(Rules.exchange_result(a, b, edge).kind == "draw", "Draw includes both five-point boundaries")
	var small := Rules.exchange_result(a, b, 6.0)
	assert(small.winner == 1 and small.kind == "small" and small.hp == 1.0)
	assert(small.stun == 8.0 and small.stagger == 0.35 and small.hold == 0.0 and not small.knockback)
	assert(small.fatigue_a == 0.5 and small.fatigue_b == 0.5)
	var big := Rules.exchange_result({"ability": 75.0}, b)
	assert(big.winner == 1 and big.kind == "big" and big.hp == 2.0)
	assert(big.stun == 18.0 and big.stagger == 0.65 and big.knockback)
	assert(big.fatigue_a == 0.5 and big.fatigue_b == 1.0)
	assert(Rules.exchange_result({"ability": 74.99}, b).kind == "small", "Big win starts at exactly 25 points")
	assert(Rules.exchange_result(a, b, 1000.0) == Rules.exchange_result(a, b, 10.0), "The supplied roll stays bounded")
	assert(Rules.exchange_result(a, b, -1000.0) == Rules.exchange_result(a, b, -10.0))
	assert(Rules.exchange_score({}) == 50.0, "Old people receive the explicit neutral baseline")
	assert(Rules.exchange_score({"training": 100.0}) == 70.0)
	assert(Rules.exchange_score({"fatigue": 100.0}) == 30.0)
	assert(Rules.exchange_score({"morale": 0.0}) == 40.0)
	assert(Rules.exchange_score({"armorbonus": 4.0, "facility": 6.0}) == 60.0)
	for sectors in range(5):
		assert(Rules.exchange_score({"encirclement": sectors}) == 50.0 - float(maxi(sectors - 1, 0)) * 8.0)
	assert(Rules.exchange_score({"encirclement": 20}) == 26.0, "Four cardinal directions cap the surrounding penalty")
	assert(Rules.exchange_score({"ability": -20.0, "training": -1.0, "fatigue": -1.0, "morale": 120.0}) == 0.0)
	assert(Rules.exchange_score({"ability": 200.0, "training": 200.0, "fatigue": 200.0, "morale": -1.0}) == 90.0)
	var tired := Rules.exchange_result({"fatigue": 100.0}, {})
	assert(tired.winner == -1 and tired.kind == "small")
	assert(Rules.exchange_result({"encirclement": 4}, {}, -1.0).kind == "big")
	assert(Rules.exchange_result({"facility": 6.0}, {}).winner == 1)
	assert(Rules.exchange_result({"armorbonus": 6.0}, {}).winner == 1)
	var power := Rules.exchange_result({"skill": "power"}, {})
	assert(power.winner == 1 and power.hp == 1.0 and power.stun == 18.0)
	var power_big := Rules.exchange_result({"ability": 60.0, "skill": "power"}, {})
	assert(power_big.kind == "big" and power_big.hp == 2.0 and power_big.stun == 28.0)
	var braced := Rules.exchange_result({"ability": 100.0}, {"skill": "brace"})
	assert(braced.kind == "big" and braced.hp == 2.0 and not braced.knockback, "Brace suppresses displacement, not HP or stagger")
	assert(braced.stun == 18.0 and braced.stagger == 0.65)
	assert(Rules.exchange_result({"skill": "power"}, {"ability": 100.0}).stun == 18.0, "A losing power never changes the winner's stun")
	assert(Rules.exchange_result({"skill": "power"}, {"skill": "brace"}).stun == 0.0)
	assert(Rules.exchange_result({"skill": "unknown"}, {}) == draw)
	var combinations := 0
	for ability_a in range(0, 101, 10):
		for ability_b in range(0, 101, 10):
			for roll: float in [-10.0, -5.0, 0.0, 5.0, 10.0]:
				var left := {"ability": float(ability_a), "fatigue": 40.0, "encirclement": 2, "skill": "power"}
				var right := {"ability": float(ability_b), "training": 30.0, "facility": 6.0, "skill": "brace"}
				var forward := Rules.exchange_result(left, right, roll)
				var reverse := Rules.exchange_result(right, left, -roll)
				assert(forward.winner == -reverse.winner and forward.margin == -reverse.margin)
				for field: String in ["kind", "hp", "stun", "stagger", "hold", "knockback", "guard_break"]:
					assert(forward[field] == reverse[field], "Mirror changed effect: " + field)
				assert(forward.fatigue_a == reverse.fatigue_b and forward.fatigue_b == reverse.fatigue_a)
				assert(forward.score_a == reverse.score_b and forward.score_b == reverse.score_a)
				assert(forward.hp in [0.0, 1.0, 2.0], "Only the three approved HP results are possible")
				combinations += 1
	# The exact-contact reference remains unchanged and has different damage rules.
	assert(Rules.damage({"power": 30.0, "impact": 35.0}, 20.0, 10.0, 1).hp == 15.0)
	print("SITE EXCHANGE RULES PASS: exact 0/1/2 HP, thresholds, bounded roll, score modifiers, skill effects, %d mirrored exchanges, legacy damage preserved" % combinations)
	quit(0)
