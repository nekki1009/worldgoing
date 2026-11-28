// worldgoing crowd10k - numerical combat rules, ported line by line from
//   scripts/terrain_lab/site_combat_rules.gd   (SiteCombatRules, exchange policy v1 + 2026-09-25 rounds)
//   scripts/terrain_lab/person_fatigue.gd      (PersonFatigue)
//   scripts/ui/weapon_materials.gd             (family / material / attack clip)
// All rule math is double precision like GDScript float. No state, no RNG: rolls are the
// original deterministic integer hashes (Site seed, person ids, round / shot serial).
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace wg {
namespace rules {

// ------------------------------------------------------------------ constants
constexpr double STUN_LIMIT = 100.0;
constexpr double STUN_GRACE = 3.0;
constexpr double STUN_RECOVERY = 10.0;
constexpr double KNOCKOUT_GAME_SECONDS = 4.0 * 3600.0;
constexpr double RESCUED_KNOCKOUT_GAME_SECONDS = 3600.0;
constexpr double GETUP_SECONDS = 2.2;   // CharacterCombatTimings.POSE_SECONDS.get_up
constexpr double RESCUE_SECONDS = 4.0;  // POSE_SECONDS.rescue
constexpr double WAKE_STUN = 30.0;      // D72: natural wake sets stun to 30
// 2026-09-29 user decision: an unconscious person keeps losing HP until rescued or captured.
// 25 HP per game hour: a full-HP body bleeds out in 4 game hours, i.e. about when it would wake.
constexpr double KO_BLEED_PER_GAME_HOUR = 25.0;

constexpr double EXCHANGE_ROUND_SECONDS = 1.0;
constexpr double EXCHANGE_DRAW_MARGIN = 5.0;
constexpr double EXCHANGE_BIG_MARGIN = 25.0;
constexpr double EXCHANGE_ROLL_LIMIT = 10.0;
constexpr double EXCHANGE_TRAINING_WEIGHT = 0.2;
constexpr double EXCHANGE_FATIGUE_WEIGHT = 0.2;
constexpr double EXCHANGE_MORALE_WEIGHT = 0.1;
constexpr double EXCHANGE_SMALL_STAGGER = 0.35;
constexpr double EXCHANGE_BIG_STAGGER = 0.65;
constexpr double EXCHANGE_DRAW_HOLD = 0.3;
constexpr double EXCHANGE_FATIGUE = 0.5;
constexpr double EXCHANGE_BIG_LOSER_FATIGUE = 0.5;
constexpr double EXCHANGE_SKILL_BONUS = 15.0;
constexpr double EXCHANGE_POWER_STUN = 10.0;
constexpr double EXCHANGE_SKILL_COOLDOWN = 8.0;
constexpr double RANGED_MAX_RANGE = 10.0;
constexpr double TROOP_COMBAT_ABILITY = 50.0; // TerrainArmy.TROOP_COMBAT_ABILITY

// PersonFatigue
constexpr double FATIGUE_LIMIT = 100.0;
constexpr double FATIGUE_THRESHOLD = 30.0;
constexpr double FATIGUE_MAX_SLOWDOWN = 0.30;
constexpr double FATIGUE_RUN_RATE = 0.10;              // per game second (6 / game minute)
constexpr double FATIGUE_RECOVERY_RATE = 20.0 / 3600.0; // per game second
constexpr double FATIGUE_REST_DELAY = 30.0;

// Institutions v1 sec.4 morale
constexpr double MORALE_DEATH = 40.0;
constexpr double MORALE_KO = 20.0;
constexpr double MORALE_COMMAND_LOSS = 10.0;
constexpr double MORALE_ROUT = 20.0;
constexpr double MORALE_RALLY = 50.0;
constexpr double MORALE_RESUPPLY_PER_HOUR = 5.0;
constexpr double RALLY_REST_SECONDS = 30.0 * 60.0;
constexpr double THREAT_CELLS = 8.0;                   // D74 threat distance

// D74 pursuit
constexpr double PURSUIT_CELLS = 20.0;
constexpr double PURSUIT_SECONDS = 20.0;

// Captivity (institutions sec.6)
constexpr double CAPTURE_SECONDS = 4.0;
constexpr int GUARD_CAPACITY = 4;
constexpr double GUARD_CELLS = 4.0;
constexpr double ESCAPE_SECONDS = 30.0;

// ------------------------------------------------------------------ equipment
enum Family : uint8_t { F_NONE = 0, F_LONGSWORD, F_SPEAR, F_AXE, F_WOOD_AXE, F_HAMMER, F_DAGGER, F_BOW, F_CROSSBOW,
	F_PICKAXE, F_TOOL_HAMMER, F_SHOVEL };
enum Material : uint8_t { M_NONE = 0, M_WOOD = 1, M_STONE = 2, M_IRON = 3, M_STEEL = 4 };
// Armor catalogue classes as SiteCombatRules.armor_level / armor_profile read the asset name.
enum Armor : uint8_t { A_NONE = 0, A_OUTFIT = 1, A_LEATHER = 2, A_IRON = 3, A_STEEL = 4, A_MINGGUANG = 5 };
enum Kind : uint8_t { K_SLASH = 0, K_STAB = 1, K_BLUNT = 2 };
enum Skill : uint8_t { SK_NONE = 0, SK_BRACE = 1, SK_POWER = 2 };

struct Equip {
	uint8_t family = F_NONE, material = M_NONE, armor = A_NONE;
	bool shield = false;
};

// WeaponMaterials.ATTACKS -> SiteCombatRules.attack_profile kind
inline Kind attack_kind(uint8_t family) {
	switch (family) {
	case F_SPEAR: case F_DAGGER: case F_BOW: case F_CROSSBOW: case F_SHOVEL: return K_STAB; // attack_spear/dagger/bow/crossbow
	case F_HAMMER: case F_TOOL_HAMMER: case F_NONE: return K_BLUNT;                         // attack_hammer, attack_unarmed
	default: return K_SLASH;                                                                 // walk_slash, attack_axe
	}
}
inline double impact_of(Kind k) { return k == K_SLASH ? 12.0 : (k == K_STAB ? 8.0 : 35.0); }
constexpr double UNARMED_IMPACT = 14.0; // SiteCombatRules.UNARMED_IMPACT: bare hands stun less than a hammer (2026-11-25)
inline double exchange_stun(const Equip &e) { return e.family == F_NONE ? UNARMED_IMPACT : impact_of(attack_kind(e.family)); }
inline int weapon_level(const Equip &e) { return e.family == F_NONE ? 0 : (int)e.material; }
inline int armor_level(const Equip &e) {
	switch (e.armor) {
	case A_MINGGUANG: case A_STEEL: return 4;
	case A_IRON: return 3;
	case A_LEATHER: return 2;
	case A_OUTFIT: return 1;
	default: return 0;
	}
}
struct ArmorProfile { double slash, stab, blunt, cushion; };
inline ArmorProfile armor_profile(const Equip &e) {
	switch (e.armor) {
	case A_MINGGUANG: case A_STEEL: return {35.0, 25.0, 15.0, 10.0};
	case A_IRON: return {25.0, 18.0, 10.0, 6.0};
	case A_LEATHER: return {12.0, 6.0, 4.0, 4.0};
	case A_OUTFIT: return {1.0, 0.0, 0.0, 2.0};
	default: return {0.0, 0.0, 0.0, 0.0};
	}
}
inline bool is_ranged(const Equip &e) { return e.family == F_BOW || e.family == F_CROSSBOW; }

struct RangedProfile { double range, cooldown, hold, speed; bool valid; };
inline RangedProfile ranged_profile(const Equip &e) {
	if (e.family == F_BOW) return {8.0, 2.0, 0.25, 10.0, true};
	if (e.family == F_CROSSBOW) return {RANGED_MAX_RANGE, 3.0, 0.4, 14.0, true};
	return {0, 0, 0, 0, false};
}

// ------------------------------------------------------------------ helpers (GDScript semantics)
inline double clampd(double v, double a, double b) { return v < a ? a : (v > b ? b : v); }
inline int64_t wrap_mul(int64_t a, int64_t b) { return (int64_t)((uint64_t)a * (uint64_t)b); }
inline int64_t posmod(int64_t a, int64_t b) { int64_t r = a % b; return r < 0 ? r + b : r; }
inline double diminishing(double value, double cap) { double v = std::max(0.0, value); return cap * v / (100.0 + v); }

// ------------------------------------------------------------------ exchange
struct ExStats {
	double ability = TROOP_COMBAT_ABILITY, training = 0, morale = 100, fatigue = 0, armorbonus = 0, facility = 0;
	uint8_t skill = SK_NONE;
	Equip equip;
};

// TerrainArmy.exchange_stats armorbonus
inline double armor_bonus(const Equip &e) { return armor_profile(e).slash * 0.25 + (e.shield ? 4.0 : 0.0); }

inline double exchange_score(const ExStats &p) {
	double skill_bonus = (p.skill == SK_BRACE || p.skill == SK_POWER) ? EXCHANGE_SKILL_BONUS : 0.0;
	return clampd(p.ability, 0.0, 100.0)
		+ clampd(p.training, 0.0, 100.0) * EXCHANGE_TRAINING_WEIGHT
		+ (clampd(p.morale, 0.0, 100.0) - 100.0) * EXCHANGE_MORALE_WEIGHT
		- clampd(p.fatigue, 0.0, 100.0) * EXCHANGE_FATIGUE_WEIGHT
		+ p.armorbonus + p.facility + skill_bonus;
}

inline double exchange_hp(const Equip &winner, const Equip &loser, bool big) {
	double value = std::pow(2.0, (double)(weapon_level(winner) - armor_level(loser)));
	return value * (big ? 2.0 : 1.0);
}

enum ExKind : uint8_t { EX_DRAW = 0, EX_SMALL = 1, EX_BIG = 2 };
struct ExResult {
	int winner = 0; // 1 = a, -1 = b, 0 = draw
	ExKind kind = EX_DRAW;
	double hp_a = 0, hp_b = 0, stun_a = 0, stun_b = 0, stagger = 0, hold = EXCHANGE_DRAW_HOLD;
	double fatigue_a = 0, fatigue_b = 0, score_a = 0, score_b = 0, margin = 0;
	bool knockback = false;
};

inline ExResult exchange_result(const ExStats &a, const ExStats &b, double roll) {
	ExResult r;
	r.score_a = exchange_score(a);
	r.score_b = exchange_score(b);
	r.margin = r.score_a - r.score_b + clampd(roll, -EXCHANGE_ROLL_LIMIT, EXCHANGE_ROLL_LIMIT);
	r.stun_a = exchange_stun(b.equip);
	r.stun_b = exchange_stun(a.equip);
	if (std::fabs(r.margin) <= EXCHANGE_DRAW_MARGIN) return r;
	bool a_wins = r.margin > 0.0;
	bool big = std::fabs(r.margin) >= EXCHANGE_BIG_MARGIN;
	const ExStats &w = a_wins ? a : b;
	const ExStats &l = a_wins ? b : a;
	r.winner = a_wins ? 1 : -1;
	r.kind = big ? EX_BIG : EX_SMALL;
	r.fatigue_a = EXCHANGE_FATIGUE;
	r.fatigue_b = EXCHANGE_FATIGUE;
	double hp = exchange_hp(w.equip, l.equip, big);
	double stun = exchange_stun(w.equip) + (w.skill == SK_POWER ? EXCHANGE_POWER_STUN : 0.0);
	r.hp_b = a_wins ? hp : 0.0;
	r.hp_a = a_wins ? 0.0 : hp;
	r.stun_b = a_wins ? stun : 0.0;
	r.stun_a = a_wins ? 0.0 : stun;
	r.stagger = big ? EXCHANGE_BIG_STAGGER : EXCHANGE_SMALL_STAGGER;
	r.hold = 0.0;
	r.knockback = big && l.skill != SK_BRACE;
	if (big) (a_wins ? r.fatigue_b : r.fatigue_a) += EXCHANGE_BIG_LOSER_FATIGUE;
	return r;
}

// TerrainLab._resolve_exchanges roll: (low*73856093) ^ (high*19349663) ^ (round*83492791) ^ seed,
// posmod 21 - 10, negated when A is the higher id.
inline double exchange_roll(int64_t id_a, int64_t id_b, int64_t round, int64_t seed) {
	int64_t low = std::min(id_a, id_b), high = std::max(id_a, id_b);
	int64_t noise = wrap_mul(low, 73856093) ^ wrap_mul(high, 19349663) ^ wrap_mul(round, 83492791) ^ seed;
	return (double)(posmod(noise, 21) - 10) * (id_a == low ? 1.0 : -1.0);
}

// ------------------------------------------------------------------ ranged
struct RangedShooter { double ability = TROOP_COMBAT_ABILITY, training = 0, fatigue = 0; uint8_t skill = SK_NONE; Equip equip; };
struct RangedDefense { bool moving = false, shield = false, facility = false; double armor_stab = 0; uint8_t skill = SK_NONE; Equip equip; };
enum RangedKind : uint8_t { R_MISS = 0, R_HIT = 1, R_GRAZE = 2, R_BLOCKED = 3, R_EMPTY = 4 };
struct RangedResult { RangedKind kind = R_MISS; double hp = 0, stun = 0, stagger = 0, chance = 0; };

inline RangedResult ranged_result(const RangedShooter &s, const RangedDefense &d, double distance, double roll) {
	RangedResult r;
	if (!is_ranged(s.equip) || !std::isfinite(distance) || distance <= 1.0 || distance > RANGED_MAX_RANGE
	    || !std::isfinite(roll) || roll < 0.0 || roll >= 100.0)
		return r;
	bool power = s.skill == SK_POWER;
	double chance = 65.0 + (clampd(s.ability, 0.0, 100.0) - 50.0) * 0.5
		+ clampd(s.training, 0.0, 100.0) * 0.1
		- clampd(s.fatigue, 0.0, 100.0) * 0.25
		- std::max(0.0, distance - 2.0) * 4.0 + (power ? EXCHANGE_SKILL_BONUS : 0.0)
		- (d.moving ? 20.0 : 0.0)
		- (d.shield ? 15.0 : 0.0)
		- std::max(0.0, d.armor_stab) * 0.2
		- (d.facility ? 20.0 : 0.0)
		- (d.skill == SK_BRACE ? EXCHANGE_SKILL_BONUS : 0.0);
	chance = clampd(chance, 5.0, 95.0);
	r.chance = chance;
	if (roll >= chance) return r;
	bool hit = roll < chance * 0.6;
	r.kind = hit ? R_HIT : R_GRAZE;
	double contact_scale = hit ? 1.0 : 0.5;
	r.hp = exchange_hp(s.equip, d.equip, false) * contact_scale;
	r.stun = exchange_stun(s.equip) * contact_scale + (power ? EXCHANGE_POWER_STUN : 0.0);
	r.stagger = hit ? 0.35 : 0.2;
	return r;
}

inline double ranged_roll(int64_t shooter_id, int64_t shot_id, int64_t target_id, int64_t seed) {
	int64_t noise = wrap_mul(shooter_id, 73856093) ^ wrap_mul(shot_id, 83492791) ^ wrap_mul(target_id, 19349663) ^ seed;
	return (double)posmod(noise, 10000) / 100.0;
}

struct Cell { int x, y; bool operator==(const Cell &o) const { return x == o.x && y == o.y; } };

// SiteCombatRules.ranged_cells: exact integer supercover; at a corner both side cells
// precede the diagonal cell.
inline void ranged_cells(Cell s, Cell g, std::vector<Cell> &out) {
	out.clear();
	int ox = g.x - s.x, oy = g.y - s.y;
	if ((ox == 0 && oy == 0) || (double)(ox * ox + oy * oy) > RANGED_MAX_RANGE * RANGED_MAX_RANGE) return;
	int nx = std::abs(ox), ny = std::abs(oy);
	int dx = ox > 0 ? 1 : (ox < 0 ? -1 : 0), dy = oy > 0 ? 1 : (oy < 0 ? -1 : 0);
	int ix = 0, iy = 0;
	Cell cur = s;
	while (ix < nx || iy < ny) {
		int xb = (2 * ix + 1) * ny, yb = (2 * iy + 1) * nx;
		if (xb == yb) {
			out.push_back({cur.x + dx, cur.y});
			out.push_back({cur.x, cur.y + dy});
			cur.x += dx; cur.y += dy; ++ix; ++iy;
		} else if (xb < yb) {
			cur.x += dx; ++ix;
		} else {
			cur.y += dy; ++iy;
		}
		out.push_back(cur);
	}
}

// ------------------------------------------------------------------ fatigue
inline double fatigue_slowdown(double v) {
	return FATIGUE_MAX_SLOWDOWN * clampd((v - FATIGUE_THRESHOLD) / (FATIGUE_LIMIT - FATIGUE_THRESHOLD), 0.0, 1.0);
}

} // namespace rules
} // namespace wg
