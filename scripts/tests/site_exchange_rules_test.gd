extends SceneTree

const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	assert(Rules.weapon_level("none") == 0)
	assert(Rules.weapon_level("spear_01_wood") == 1)
	assert(Rules.weapon_level("dagger_01_stone") == 2)
	assert(Rules.weapon_level("longsword_01") == 3)
	assert(Rules.weapon_level("hammer_01_steel") == 4)
	assert(Rules.armor_level("none") == 0)
	assert(Rules.armor_level("outfit_underlayer_01") == 0, "The underwear slot is not armor")
	assert(Rules.armor_level("outfit_medieval_chinese_01") == 1)
	assert(Rules.armor_level("armor_light_leather_01") == 2)
	assert(Rules.armor_level("armor_iron_01") == 3)
	assert(Rules.armor_level("armor_mingguang_01") == 4)
	assert(Rules.armor_level("armor_steel_01") == 4)
	assert(Rules.exchange_stun("spear_01_steel") == 8.0)
	assert(Rules.exchange_stun("longsword_01_stone") == 12.0)
	assert(Rules.exchange_stun("hammer_01_wood") == 35.0)
	var tier_weapons := ["none", "longsword_01_wood", "longsword_01_stone", "longsword_01", "longsword_01_steel"]
	var tier_armors := ["none", "outfit_medieval_chinese_01", "armor_light_leather_01", "armor_iron_01", "armor_mingguang_01"]
	for weapon_tier in range(tier_weapons.size()):
		for armor_tier in range(tier_armors.size()):
			var expected := pow(2.0, weapon_tier - armor_tier)
			assert(is_equal_approx(Rules.exchange_hp(tier_weapons[weapon_tier], tier_armors[armor_tier]), expected))
			assert(is_equal_approx(Rules.exchange_hp(tier_weapons[weapon_tier], tier_armors[armor_tier], true), expected * 2.0))
	var a := {"ability": 50.0, "weapon": "longsword_01", "armor": "armor_iron_01"}
	var b := {"ability": 50.0, "weapon": "spear_01", "armor": "armor_iron_01"}
	var draw := Rules.exchange_result(a, b)
	assert(draw.winner == 0 and draw.kind == "draw")
	assert(draw.hp == 0.0 and draw.stun == 0.0 and draw.hp_a == 0.0 and draw.hp_b == 0.0)
	assert(draw.stun_a == 8.0 and draw.stun_b == 12.0 and draw.stagger == 0.0)
	assert(draw.hold == 0.3 and not draw.knockback)
	assert(draw.fatigue_a == 0.0 and draw.fatigue_b == 0.0, "Draw only adds weapon stun")
	for edge: float in [-5.0, 5.0]:
		assert(Rules.exchange_result(a, b, edge).kind == "draw", "Draw includes both five-point boundaries")
	var small := Rules.exchange_result({"ability": 50.0, "weapon": "longsword_01_steel", "armor": "armor_light_leather_01"},
		{"ability": 50.0, "weapon": "spear_01_wood", "armor": "armor_iron_01"}, 6.0)
	assert(small.winner == 1 and small.kind == "small" and small.hp == 2.0)
	assert(small.hp_a == 0.0 and small.hp_b == 2.0 and small.stun_a == 0.0 and small.stun_b == 12.0)
	assert(small.stun == 12.0 and small.stagger == 0.35 and small.hold == 0.0 and not small.knockback)
	assert(small.fatigue_a == 0.5 and small.fatigue_b == 0.5)
	var reduced := Rules.exchange_result({"ability": 50.0, "weapon": "longsword_01_steel", "armor": "armor_light_leather_01"},
		{"ability": 56.0, "weapon": "spear_01_wood", "armor": "armor_iron_01"})
	assert(reduced.winner == -1 and reduced.kind == "small" and is_equal_approx(reduced.hp, 0.5))
	assert(is_equal_approx(reduced.hp_a, 0.5) and reduced.hp_b == 0.0 and reduced.stun_a == 8.0 and reduced.stun_b == 0.0)
	var big := Rules.exchange_result({"ability": 75.0, "weapon": "hammer_01_steel", "armor": "armor_light_leather_01"}, b)
	assert(big.winner == 1 and big.kind == "big" and big.hp == 4.0)
	assert(big.hp_a == 0.0 and big.hp_b == 4.0 and big.stun_a == 0.0 and big.stun_b == 35.0)
	assert(big.stun == 35.0 and big.stagger == 0.65 and big.knockback)
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
	assert(power.winner == 1 and power.hp == 1.0 and power.stun == 45.0 and power.stun_b == 45.0)
	var power_big := Rules.exchange_result({"ability": 60.0, "skill": "power"}, {})
	assert(power_big.kind == "big" and power_big.hp == 2.0 and power_big.stun == 45.0)
	var braced := Rules.exchange_result({"ability": 100.0}, {"skill": "brace"})
	assert(braced.kind == "big" and braced.hp == 2.0 and not braced.knockback, "Brace suppresses displacement, not HP or stagger")
	assert(braced.stun == 35.0 and braced.stagger == 0.65)
	assert(Rules.exchange_result({"skill": "power"}, {"ability": 100.0}).stun == 35.0, "A losing power never changes the winner's stun")
	var skilled_draw := Rules.exchange_result({"skill": "power"}, {"skill": "brace"})
	assert(skilled_draw.stun == 0.0 and skilled_draw.stun_a == 35.0 and skilled_draw.stun_b == 35.0)
	assert(Rules.exchange_result({"skill": "unknown"}, {}) == Rules.exchange_result({}, {}))
	var combinations := 0
	for ability_a in range(0, 101, 10):
		for ability_b in range(0, 101, 10):
			for roll: float in [-10.0, -5.0, 0.0, 5.0, 10.0]:
				var left := {"ability": float(ability_a), "fatigue": 40.0, "encirclement": 2, "skill": "power",
					"weapon": "axe_01_steel", "armor": "armor_light_leather_01"}
				var right := {"ability": float(ability_b), "training": 30.0, "facility": 6.0, "skill": "brace",
					"weapon": "spear_01_wood", "armor": "armor_mingguang_01"}
				var forward := Rules.exchange_result(left, right, roll)
				var reverse := Rules.exchange_result(right, left, -roll)
				assert(forward.winner == -reverse.winner and forward.margin == -reverse.margin)
				for field: String in ["kind", "hp", "stun", "stagger", "hold", "knockback", "guard_break"]:
					assert(forward[field] == reverse[field], "Mirror changed effect: " + field)
				assert(forward.hp_a == reverse.hp_b and forward.hp_b == reverse.hp_a)
				assert(forward.stun_a == reverse.stun_b and forward.stun_b == reverse.stun_a)
				assert(forward.fatigue_a == reverse.fatigue_b and forward.fatigue_b == reverse.fatigue_a)
				assert(forward.score_a == reverse.score_b and forward.score_b == reverse.score_a)
				if forward.winner == 0:
					assert(forward.hp == 0.0 and forward.stun == 0.0)
					assert(forward.hp_a == 0.0 and forward.hp_b == 0.0)
					assert(forward.stun_a == Rules.exchange_stun(str(right.weapon)))
					assert(forward.stun_b == Rules.exchange_stun(str(left.weapon)))
				else:
					var winner: Dictionary = left if forward.winner == 1 else right
					var loser: Dictionary = right if forward.winner == 1 else left
					var expected_hp := pow(2.0, Rules.weapon_level(str(winner.weapon)) - Rules.armor_level(str(loser.armor))) \
						* (2.0 if forward.kind == "big" else 1.0)
					assert(is_equal_approx(forward.hp, expected_hp))
					assert(forward.stun == Rules.exchange_stun(str(winner.weapon)) + (10.0 if str(winner.skill) == "power" else 0.0))
					assert(is_equal_approx(forward["hp_b" if forward.winner == 1 else "hp_a"], expected_hp))
					assert(forward["hp_a" if forward.winner == 1 else "hp_b"] == 0.0)
				combinations += 1
	# The exact-contact reference remains unchanged and has different damage rules.
	assert(Rules.damage({"power": 30.0, "impact": 35.0}, 20.0, 10.0, 1).hp == 15.0)
	print("SITE EXCHANGE RULES PASS: directional equipment levels, weapon stun, draw stun, thresholds, skills, %d mirrored exchanges, legacy damage preserved" % combinations)
	quit(0)
