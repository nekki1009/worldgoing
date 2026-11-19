"""Line-by-line Python transliteration of the GDScript rule functions the C++ port must match.

Source files (worldgoing, 2026-09-29 checkout):
  scripts/terrain_lab/site_combat_rules.gd  exchange_score / exchange_result / exchange_hp / exchange_stun /
                                            weapon_level / armor_level / armor_profile / attack_profile /
                                            ranged_result / ranged_cells / diminishing
  scripts/ui/weapon_materials.gd            family / material / ATTACKS
  scripts/terrain_lab/terrain_lab.gd        exchange roll noise (_resolve_exchanges) and ranged roll noise
                                            (_resolve_ranged_arrival)
This file intentionally keeps the GDScript structure (dicts, asset-name strings) so the review of
"is this the same rule" is a side-by-side read. It generates random vectors, evaluates them here,
and compares with the C++ harness output (tests/rules_vectors.cpp).
"""
import json, math, random, subprocess, sys

ATTACKS = {"longsword_01": "walk_slash", "spear_01": "attack_spear", "axe_01": "attack_axe",
           "wood_axe_01": "attack_axe", "hammer_01": "attack_hammer", "dagger_01": "attack_dagger",
           "bow_01": "attack_bow", "crossbow_01": "attack_crossbow", "pickaxe_01": "attack_axe",
           "tool_hammer_01": "attack_hammer", "shovel_01": "attack_spear", "none": "attack_unarmed"}

def family(asset):
    if asset in ATTACKS: return asset
    for m in ["wood", "stone", "steel"]:
        base = asset[:-len("_" + m)] if asset.endswith("_" + m) else asset
        if base != asset and base in ATTACKS: return base
    return "none"

def material(asset):
    if asset == "none" or family(asset) == "none": return ""
    return "iron" if asset in ATTACKS else asset.split("_")[-1]

def is_ranged(asset): return family(asset) in ["bow_01", "crossbow_01"]

def clampf(v, a, b): return max(a, min(b, v))

def weapon_level(asset): return {"": 0, "wood": 1, "stone": 2, "iron": 3, "steel": 4}.get(material(asset), 0)

def armor_level(asset):
    if "mingguang" in asset or "steel" in asset: return 4
    if "iron" in asset: return 3
    if "leather" in asset: return 2
    if asset.startswith("outfit_medieval_"): return 1
    return 0

def attack_profile(clip):
    kind = "slash"
    if clip in ["attack_spear", "ride_thrust", "attack_dagger", "attack_bow", "attack_crossbow"]: kind = "stab"
    elif clip in ["attack_hammer", "attack_unarmed"]: kind = "blunt"
    return {"kind": kind, "power": 30.0 if clip in ["attack_jump_heavy", "attack_axe", "attack_hammer"] else 20.0,
            "impact": {"slash": 12.0, "stab": 8.0, "blunt": 35.0}[kind]}

def armor_profile(item):
    if "mingguang" in item or "steel" in item: return {"slash": 35.0, "stab": 25.0, "blunt": 15.0, "cushion": 10.0}
    if "iron" in item: return {"slash": 25.0, "stab": 18.0, "blunt": 10.0, "cushion": 6.0}
    if "leather" in item: return {"slash": 12.0, "stab": 6.0, "blunt": 4.0, "cushion": 4.0}
    if item.startswith("outfit_"): return {"slash": 1.0, "stab": 0.0, "blunt": 0.0, "cushion": 2.0}
    return {"slash": 0.0, "stab": 0.0, "blunt": 0.0, "cushion": 0.0}

def exchange_attack_clip(asset): return ATTACKS.get(family(asset), "attack_unarmed")
def exchange_stun(asset): return float(attack_profile(exchange_attack_clip(asset))["impact"])
def exchange_hp(weapon, armor, big=False): return math.pow(2.0, weapon_level(weapon) - armor_level(armor)) * (2.0 if big else 1.0)

def exchange_score(p):
    skill_bonus = 15.0 if p.get("skill", "") in ["brace", "power"] else 0.0
    return clampf(float(p.get("ability", 50.0)), 0.0, 100.0) \
        + clampf(float(p.get("training", 0.0)), 0.0, 100.0) * 0.2 \
        + (clampf(float(p.get("morale", 100.0)), 0.0, 100.0) - 100.0) * 0.1 \
        - clampf(float(p.get("fatigue", 0.0)), 0.0, 100.0) * 0.2 \
        + float(p.get("armorbonus", 0.0)) + float(p.get("facility", 0.0)) + skill_bonus

def exchange_result(a, b, roll=0.0):
    sa, sb = exchange_score(a), exchange_score(b)
    margin = sa - sb + clampf(roll, -10.0, 10.0)
    r = {"winner": 0, "kind": "draw", "hp_a": 0.0, "hp_b": 0.0,
         "stun_a": exchange_stun(b.get("weapon", "none")), "stun_b": exchange_stun(a.get("weapon", "none")),
         "stagger": 0.0, "hold": 0.3, "knockback": False, "fatigue_a": 0.0, "fatigue_b": 0.0, "margin": margin}
    if abs(margin) <= 5.0: return r
    a_wins = margin > 0.0
    big = abs(margin) >= 25.0
    w, l = (a, b) if a_wins else (b, a)
    r["winner"] = 1 if a_wins else -1
    r["kind"] = "big" if big else "small"
    r["fatigue_a"] = 0.5; r["fatigue_b"] = 0.5
    hp = exchange_hp(w.get("weapon", "none"), l.get("armor", "none"), big)
    stun = exchange_stun(w.get("weapon", "none")) + (10.0 if w.get("skill", "") == "power" else 0.0)
    r["hp_b"] = hp if a_wins else 0.0
    r["hp_a"] = 0.0 if a_wins else hp
    r["stun_b"] = stun if a_wins else 0.0
    r["stun_a"] = 0.0 if a_wins else stun
    r["stagger"] = 0.65 if big else 0.35
    r["hold"] = 0.0
    r["knockback"] = big and l.get("skill", "") != "brace"
    if big: r["fatigue_b" if a_wins else "fatigue_a"] += 0.5
    return r

def ranged_result(shooter, defender, distance, roll):
    r = {"kind": "miss", "hp": 0.0, "stun": 0.0, "stagger": 0.0, "chance": 0.0}
    weapon = shooter.get("weapon", "none")
    if not is_ranged(weapon) or not math.isfinite(distance) or distance <= 1.0 or distance > 10.0 \
            or not math.isfinite(roll) or roll < 0.0 or roll >= 100.0:
        return r
    power = shooter.get("skill", "") == "power"
    chance = 65.0 + (clampf(float(shooter.get("ability", 50.0)), 0.0, 100.0) - 50.0) * 0.5 \
        + clampf(float(shooter.get("training", 0.0)), 0.0, 100.0) * 0.1 \
        - clampf(float(shooter.get("fatigue", 0.0)), 0.0, 100.0) * 0.25 \
        - max(0.0, distance - 2.0) * 4.0 + (15.0 if power else 0.0) \
        - (20.0 if defender.get("moving", False) else 0.0) \
        - (15.0 if defender.get("shield", False) else 0.0) \
        - max(0.0, float(defender.get("armor_stab", 0.0))) * 0.2 \
        - (20.0 if defender.get("facility", False) else 0.0) \
        - (15.0 if defender.get("skill", "") == "brace" else 0.0)
    chance = clampf(chance, 5.0, 95.0)
    r["chance"] = chance
    if roll >= chance: return r
    hit = roll < chance * 0.6
    r["kind"] = "hit" if hit else "graze"
    scale = 1.0 if hit else 0.5
    r["hp"] = exchange_hp(weapon, defender.get("armor", "none")) * scale
    r["stun"] = exchange_stun(weapon) * scale + (10.0 if power else 0.0)
    r["stagger"] = 0.35 if hit else 0.2
    return r

def sign(v): return (v > 0) - (v < 0)

def ranged_cells(source, goal):
    cells = []
    ox, oy = goal[0] - source[0], goal[1] - source[1]
    if (ox, oy) == (0, 0) or ox * ox + oy * oy > 100: return cells
    nx, ny = abs(ox), abs(oy)
    dx, dy = (sign(ox), 0), (0, sign(oy))
    ix = iy = 0
    cur = source
    while ix < nx or iy < ny:
        xb, yb = (2 * ix + 1) * ny, (2 * iy + 1) * nx
        if xb == yb:
            cells.append((cur[0] + dx[0], cur[1] + dx[1]))
            cells.append((cur[0] + dy[0], cur[1] + dy[1]))
            cur = (cur[0] + dx[0] + dy[0], cur[1] + dx[1] + dy[1]); ix += 1; iy += 1
        elif xb < yb:
            cur = (cur[0] + dx[0], cur[1]); ix += 1
        else:
            cur = (cur[0], cur[1] + dy[1]); iy += 1
        cells.append(cur)
    return cells

M64 = (1 << 64) - 1
def i64(v):
    v &= M64
    return v - (1 << 64) if v >> 63 else v
def posmod(a, b): return a % b  # Python % is already the GDScript posmod for positive b

def exchange_roll(a_id, b_id, rnd, seed):
    low, high = min(a_id, b_id), max(a_id, b_id)
    noise = i64(i64(low * 73856093) ^ i64(high * 19349663) ^ i64(rnd * 83492791) ^ seed)
    return float(posmod(noise, 21) - 10) * (1.0 if a_id == low else -1.0)

def ranged_roll(shooter_id, shot_id, target_id, seed):
    noise = i64(i64(shooter_id * 73856093) ^ i64(shot_id * 83492791) ^ i64(target_id * 19349663) ^ seed)
    return float(posmod(noise, 10000)) / 100.0

def diminishing(v, cap):
    v = max(0.0, v); return cap * v / (100.0 + v)

# ----------------------------------------------------------------- vector generation / compare
WEAPONS = ["none", "longsword_01", "longsword_01_wood", "longsword_01_stone", "longsword_01_steel", "spear_01",
           "spear_01_wood", "axe_01_steel", "hammer_01", "hammer_01_stone", "dagger_01_wood", "bow_01", "bow_01_wood",
           "crossbow_01", "crossbow_01_steel", "pickaxe_01", "tool_hammer_01_wood", "shovel_01_steel", "wood_axe_01"]
ARMORS = ["none", "outfit_medieval_tunic", "armor_leather_cn", "armor_iron_jp", "armor_steel_west",
          "armor_mingguang_cn", "underwear_basic"]
FAM = {"none": 0, "longsword_01": 1, "spear_01": 2, "axe_01": 3, "wood_axe_01": 4, "hammer_01": 5, "dagger_01": 6,
       "bow_01": 7, "crossbow_01": 8, "pickaxe_01": 9, "tool_hammer_01": 10, "shovel_01": 11}
MAT = {"": 0, "wood": 1, "stone": 2, "iron": 3, "steel": 4}
def armor_code(a):
    if "mingguang" in a: return 5
    if "steel" in a: return 4
    if "iron" in a: return 3
    if "leather" in a: return 2
    if a.startswith("outfit_"): return 1
    return 0
SK = {"": 0, "brace": 1, "power": 2}

def person(rng):
    w, a = rng.choice(WEAPONS), rng.choice(ARMORS)
    shield = rng.random() < 0.3
    return {"ability": rng.choice([50.0, rng.uniform(-20, 130)]), "training": rng.uniform(-10, 120),
            "morale": rng.uniform(-10, 120), "fatigue": rng.uniform(-10, 120),
            "armorbonus": armor_profile(a)["slash"] * 0.25 + (4.0 if shield else 0.0),
            "facility": rng.choice([0.0, 0.0, 10.0]), "skill": rng.choice(["", "", "brace", "power"]),
            "weapon": w, "armor": a, "shield": shield}

def encode(p):
    return [p["ability"], p["training"], p["morale"], p["fatigue"], p["armorbonus"], float(p["facility"]), SK[p["skill"]],
            FAM[family(p["weapon"])], MAT[material(p["weapon"])], armor_code(p["armor"]), int(p["shield"])]

def main():
    exe = sys.argv[1]
    rng = random.Random(20260929)
    lines, expect = [], []
    for _ in range(5000):
        a, b = person(rng), person(rng)
        roll = rng.choice([rng.uniform(-15, 15), float(rng.randint(-10, 10))])
        lines.append("X " + " ".join(repr(v) for v in encode(a) + encode(b) + [roll]))
        r = exchange_result(a, b, roll)
        expect.append(("X", [r["winner"], {"draw": 0, "small": 1, "big": 2}[r["kind"]], r["hp_a"], r["hp_b"], r["stun_a"],
                             r["stun_b"], r["stagger"], r["hold"], int(r["knockback"]), r["fatigue_a"], r["fatigue_b"], r["margin"]]))
    for _ in range(5000):
        s, d = person(rng), person(rng)
        s["weapon"] = rng.choice(WEAPONS)
        d["moving"] = rng.random() < 0.3
        d["facility"] = rng.random() < 0.2
        d["armor_stab"] = armor_profile(d["armor"])["stab"]
        dist = rng.choice([rng.uniform(0.5, 11), math.sqrt(rng.randint(1, 100))])
        roll = rng.uniform(-1, 101)
        lines.append("R " + " ".join(repr(v) for v in encode(s) + encode(d) + [int(d["moving"]), int(d["facility"]), dist, roll]))
        r = ranged_result(s, d, dist, roll)
        expect.append(("R", [{"miss": 0, "hit": 1, "graze": 2}[r["kind"]], r["hp"], r["stun"], r["stagger"], r["chance"]]))
    for _ in range(3000):
        s = (rng.randint(-5, 300), rng.randint(-5, 300))
        g = (s[0] + rng.randint(-11, 11), s[1] + rng.randint(-11, 11))
        lines.append(f"C {s[0]} {s[1]} {g[0]} {g[1]}")
        expect.append(("C", [c for cell in ranged_cells(s, g) for c in cell]))
    for _ in range(3000):
        a, b = rng.randint(0, 1 << 40), rng.randint(0, 1 << 40)
        rnd, seed = rng.randint(0, 1 << 30), rng.randint(0, 1 << 31)
        lines.append(f"N {a} {b} {rnd} {seed}")
        expect.append(("N", [exchange_roll(a, b, rnd, seed), ranged_roll(a, rnd, b, seed)]))
    for _ in range(500):
        v, cap = rng.uniform(-50, 500), rng.choice([0.15, 0.20, 0.25])
        lines.append(f"D {v!r} {cap!r}")
        expect.append(("D", [diminishing(v, cap)]))
    out = subprocess.run([exe], input="\n".join(lines) + "\n", capture_output=True, text=True, check=True).stdout.split("\n")
    bad = 0
    counts = {}
    for (kind, exp), got_line in zip(expect, out):
        got = [float(x) for x in got_line.split()[1:]]
        counts[kind] = counts.get(kind, 0) + 1
        if len(got) != len(exp) or any(abs(float(e) - g) > 1e-9 * max(1.0, abs(float(e))) for e, g in zip(exp, got)):
            bad += 1
            if bad <= 10: print("MISMATCH", kind, exp, got)
    print(json.dumps({"vectors": counts, "mismatches": bad}))
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
