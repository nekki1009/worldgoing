// worldgoing crowd10k - Godot-agnostic battle core (v2: movement + full exchange-mode rules).
//
// Layers (all per 30 Hz action step):
//   command   (serial, per formation)  presence (D46/D56), succession (D18/D35-D48), morale (inst. sec.4), rout
//   ai        (serial, every 0.5 s)     SiteArmyAI._decide port: hold / approach / attack / pursue
//   formation (serial, per formation)  centre movement per order over shared flow fields
//   contact   (parallel, 10 Hz stagger) nearest able enemy + threat bit per soldier
//   soldier   (parallel)               continuous movement: slot / engage / encircle / ranged spacing / flee /
//                                      stagger / knockback / escort; PBD separation; terrain edge solve
//   timers    (parallel)               stun decay, KO countdown & wake, get-up, cooldowns
//   exchange  (10 Hz global round)     parallel pair collection, fixed-order merged commit (2026-09-25 rounds)
//   ranged    (10 Hz)                  parallel target choice, ordered fire commit; flight; arrival intercept
//   actions   (serial)                 rescue (D72), capture/escort/escape (inst. sec.6)
//   fatigue   (serial, per formation)  shared pool (2026-09-15), running / exchange / shot charges, safe rest
//
// Determinism: parallel stages read the previous state and write only their own soldier or their own
// chunk buffer; chunk boundaries are fixed; serial commits run in index / shot order. Same seed + same
// inputs => same state for any thread count.
#pragma once
#include "rules.hpp"

#include <atomic>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <thread>
#include <string>
#include <unordered_map>
#include <vector>

namespace wg {

constexpr float kPi = 3.14159265358979323846f; // (MSVC has no M_PI without _USE_MATH_DEFINES)

// CAV-1 mounted cavalry (reports/cavalry-charge-plan.md V0.5, sections 3, 4 and 6). Values are cells and seconds.
namespace cav {
constexpr float RADIUS = 0.56f;          // mounted body (N1=A: about 1.6 x the 0.35 infantry radius)
constexpr float CRUISE = 5.f, GALLOP = 8.f; // speed caps; the gallop cap applies to riders the host runs
constexpr float ACCEL = 3.2f, BRAKE = 6.4f; // cells / s^2
constexpr float TURN_DEG_CELLS = 576.f;  // max heading change in degrees = 576 / speed (360 x 1.6 / speed), N2=A
constexpr float MASS = 3.f;              // push weight of a rider against an infantry body (1)
constexpr float CHARGE_SPEED = 4.5f;     // 4.1 charge: speed along the heading
constexpr double STRAIGHT_SECONDS = 0.4; // 4.1 charge: heading change within HEADING_TOL over this window (30 Hz steps)
constexpr float HEADING_TOL = 20.f * kPi / 180.f;
constexpr int HEADING_WINDOW = 12;       // 0.4 s of 30 Hz action steps
constexpr int MAX_HITS = 3;              // 4.4 penetration cap per charge
constexpr double RECHARGE_SECONDS = 2.0; // 4.2 one rider hits the same person at most once per 2 s
constexpr int RECENT_VICTIMS = 8;        // recent victims remembered per soldier for the re-charge limit
constexpr double FALL_SECONDS = 1.2;     // 4.4 penetrated (and 4.6 dismounted) bodies lie this long
constexpr double SMALL_FALL_SECONDS = 0.8; // 4.4 small win pinned against a crowd
constexpr double DRAW_STOP_SECONDS = 0.5;  // 4.4 draw: the horse is held up
constexpr double PUSHBACK_CELLS = 1.0;   // 4.4 small win push
constexpr double SIDE_LATERAL_CELLS = 1.0, SIDE_FORWARD_CELLS = 0.3; // 4.4 lateral impulse of a penetrated body
constexpr float SPEED_BONUS = 7.f, SPEED_BONUS_CAP = 25.f; // 4.3 impact speed bonus: (speed - 4.5) x 7, capped at 25
constexpr double LOSS_SPEED = 1.2;       // 4.4 rider speed lost by a penetration (cells / s)
constexpr double RECOIL = 1.5;           // 4.4 defeated rider: extra recoil damage = 1.5 x the exchange loss
constexpr double MOUNTED_BASIC = 5.0;    // 4.3 / 4.7 mounted basic bonus
constexpr double SIDE_BONUS = 10.0, BACK_BONUS = 20.0; // 4.3 flank (> 60 deg) and rear (> 120 deg)
constexpr double POLE_BONUS = 20.0;      // 4.3 pole-arm stand (Q3=A): spear, facing within 60 deg, speed < 0.5
constexpr double REAR_BONUS = 5.0;       // 4.3 a living team-mate stands within 1 cell behind the defender
constexpr float POLE_SPEED = 0.5f;
constexpr double MORALE_SHOCK = 3.0;    // 4.5 morale shock per penetration on the victim's formation (Q5=A)
constexpr float SHOCK_RADIUS = 3.f;     // 4.5 a formation member within 3 cells of the impact takes the shock
constexpr double SHOCK_SECONDS = 1.0;   // 4.5 one shock per rider and victim formation per second
constexpr float SLOPE_UP = 0.55f, SLOPE_DOWN = 0.8f; // terrain speed targets (old Actor values)
// CAV-4a formation charge (section 5). Seconds are formation-layer timers; cells are distances from the target point.
constexpr double FORM_SECONDS = 25.0, CHARGE_SECONDS = 6.0, RALLY_SECONDS = 25.0; // timeouts of each stage
constexpr float FORM_CELLS = 10.f;       // form-up point: 8 to 12 cells in front of the target (10, then nearby cells)
constexpr float PAST_CELLS = 8.f;        // straight charge goal beyond the target point
constexpr float BREAK_CELLS = 5.f;       // break-through: the formation centre passes the target by this much, the charge ends
constexpr float RALLY_CELLS = 10.f;      // rally point: behind the target (or behind-flank), this far from it
constexpr float COMMAND_CELLS = 8.f;     // the commander must stand within this distance of the formation centre
constexpr float CHARGE_RANGE = 30.f;     // native AI starts a charge against an enemy formation this close
constexpr float COMMAND_TARGET_CELLS = 2.f; // the live target point moves the form-up goal only past this shift
// CAV-4a mounted formation layout and pace (a formation whose able members all ride: Formation::cav_layout).
// Slots sit a mounted body diameter plus a margin apart, so the riders' bodies (2 x RADIUS = 1.12) fit their slots; at the
// infantry slot spacing of 1.0 neighbouring riders push each other out of their slots for ever, the formation lag grows and
// the lag cohesion slows the whole formation to a crawl. The centre marches at CRUISE (riders follow at up to 1.25 x CRUISE,
// as foot soldiers follow at 1.25 x march) and rides at GALLOP with the riders while a CHARGE runs.
constexpr float SLOT_SPACING = 2.f * RADIUS + 0.2f;
constexpr float FOLLOW_GAIN = 3.f;       // slot followers aim at sdist x 3 (the S_SLOT rule): steady lag = pace / 3
// lag cohesion floor of a mounted layout: the centre keeps at least half of CRUISE, so a rider following at up to
// 1.25 x CRUISE still closes on its slot at 0.75 x CRUISE (the foot floor of 0.15 x march left mounted form-up and rally
// walks crawling at 0.75 cells/s behind a few riders working free of the press or of a neighbouring formation)
constexpr float COHESION_FLOOR = 0.5f;
constexpr float FORM_READY_LAG = SLOT_SPACING; // the charge line is formed once its riders stand within a slot spacing of their slots on average
// CAV-4a charge line: line abreast at most LINE_RANKS deep (and at least ten wide, or one rank when fewer ride). The form-up
// distance FORM_CELLS is the run-up of the FRONT rank: the centre stands that far plus the half depth of the line from the
// target, so every rank has room to accelerate (from CRUISE to GALLOP takes (8^2 - 5^2) / (2 x ACCEL) = 6.1 cells).
constexpr int LINE_RANKS = 4;
// an angle difference wrapped into [-pi, pi]
inline float wrap_angle(float a) { return std::remainder(a, 2.f * kPi); }
}

// ---------------------------------------------------------------- terrain
// Mirrors scripts/terrain_lab/terrain_data.gd: 4-dir legality, height diff 0 or
// diff 1 with reciprocal ramp bits, static_blocked. can_attack_across == 4-dir edge.
enum Dir : int { N = 0, E = 1, S = 2, W = 3, NE = 4, SE = 5, SW = 6, NW = 7 };
static const int DX[8] = {0, 1, 0, -1, 1, 1, -1, -1};
static const int DY[8] = {-1, 0, 1, 0, -1, 1, 1, -1};

struct Terrain {
	enum Flag : uint8_t { WALKABLE = 1, CLIFF = 2, RAMP = 4, SHORE = 8, WET = 16, BLOCKED = 32 };
	int w = 0, h = 0;
	std::vector<uint8_t> height, flags, ramp_edges, static_blocked, facility, base_height;
	std::vector<uint8_t> edge_ok; // derived: bit d set => legal step to neighbour d (8 dirs)

	void allocate(int W, int H);
	inline bool contains(int x, int y) const { return x >= 0 && y >= 0 && x < w && y < h; }
	inline int idx(int x, int y) const { return y * w + x; }
	bool walkable(int x, int y) const;
	bool can_step4(int x, int y, int d) const;
	void build_edges();
	inline bool edge(int x, int y, int d) const { return (edge_ok[idx(x, y)] >> d) & 1; }
	// TerrainData.can_attack_across for 4-neighbours (from -> to)
	bool attack_across(int ax, int ay, int bx, int by) const;
	float visual_lift(float x, float y) const;
	double shot_height(int source, int goal, int sample, double source_eye = -1, double goal_eye = -1) const;
	bool shot_cell_clear(int source, int goal, int sample, double source_eye = -1, double goal_eye = -1) const;
	inline bool walkable_f(float fx, float fy) const {
		int x = (int)std::floor(fx), y = (int)std::floor(fy);
		return contains(x, y) && walkable(x, y);
	}
};

struct FlowField {
	int goal = -1;
	uint32_t last_used = 0;
	std::vector<uint32_t> cost; // integrated cost to goal, 10 orth / 14 diag
	std::vector<uint8_t> dir;   // best next direction, 255 = goal or unreachable
	// true: convoy bodies are impassable in this field (ordinary people route around them). false: built over
	// terrain and siege cells only, used by convoy anchors so their own body never blocks their own route.
	bool body_aware = true;
};

class Pool {
public:
	explicit Pool(int threads);
	~Pool();
	void run(int tasks, const std::function<void(int)> &fn); // caller participates
	int threads() const { return (int)workers_.size() + 1; }

private:
	void worker();
	std::vector<std::thread> workers_;
	std::mutex m_;
	std::condition_variable cv_, done_cv_;
	const std::function<void(int)> *fn_ = nullptr;
	std::atomic<int> next_{0};
	int tasks_ = 0, pending_ = 0;
	uint64_t gen_ = 0;
	bool stop_ = false;
};

// ---------------------------------------------------------------- enums
// CHARGE (6) and RALLY (7) are CAV-4a formation orders (reports/cavalry-charge-plan.md section 5); see cav_charge in crowd_core.cpp.
enum class Order : uint8_t { HOLD = 0, MOVE = 1, ATTACK = 2, PURSUE = 3, RETREAT = 4, RETURN = 5, CHARGE = 6, RALLY = 7 };
enum OrderResult : int { OK = 0, NOT_OWNER, BAD_FORMATION, BAD_ARGS, NO_TARGET, BLOCKED, NOT_ROUTED, ROUTED, NO_ORDERS,
	NO_COMMANDER, NOT_CAVALRY }; // CAV-4a: commander ineligible (not present, not eligible or more than 8 cells away); formation not mostly mounted
// CAV-4a charge stage of a formation (Formation::charge_stage)
enum ChargeStage : uint8_t { CS_NONE = 0, CS_FORM = 1, CS_CHARGE = 2, CS_RALLY = 3 };
enum Troop : uint8_t { T_MELEE = 0, T_BOW = 1, T_CROSSBOW = 2 };
enum Role : uint8_t { R_REGULAR = 0, R_CAPTAIN = 1, R_OFFICER = 2 };
// presentation / diagnostic state (derived every step, never read back as authority)
enum SState : uint8_t { S_SLOT = 0, S_ENGAGE, S_FIGHT, S_ENCIRCLE, S_RANGED, S_RESCUE, S_CAPTURE, S_DOWN, S_DEAD, S_CAPTIVE,
	S_GETUP, S_STAGGER, S_FLEE, S_KNOCK, S_HOST };
enum AIStatus : uint8_t { AI_NONE = 0, AI_NO_COMMAND, AI_ROUTED, AI_RETURNING, AI_IDLE, AI_RECOVER, AI_OUTMATCHED, AI_PURSUE,
	AI_ENGAGE, AI_APPROACH, AI_WAIT_PATH, AI_CHARGE };

struct CommandAbility { int16_t tactics = -1, leadership = -1, coach = -1; bool has() const { return tactics >= 0; } };

struct Formation {
	int team = 0;
	Troop troop = T_MELEE;
	Order order = Order::HOLD;
	float cx = 0, cy = 0, facing = 0;
	float goal_x = 0, goal_y = 0, goal_facing = 0;
	int cols = 10;
	// G7b formation preset (saved from KW20, hashed): slot offsets as (lateral, back) pairs in spacing units, slot s at
	// pair s (the first n pairs for n able members). Empty, or fewer pairs than members, or a charge in progress: rows
	// of `cols` as before.
	std::vector<float> shape;
	float spacing = 1.0f;
	int field = -1;
	bool arrived = true, los_goal = false;
	float lag = 0;
	// CAV-4a derived each step at the start of the formation layer (not saved or hashed; a function of `mounted`):
	// every able member rides, so the layout and pace are the mounted ones (cav::SLOT_SPACING, cav::CRUISE)
	bool cav_layout = false;
	// CAV-4a derived each step by the formation layer (not saved or hashed): the target formation's body as a circle the
	// riders of a CHARGE form-up or rally ride round (avoid_r 0: none)
	float avoid_x = 0.f, avoid_y = 0.f, avoid_r = 0.f;
	std::vector<int> members;   // every member ever enrolled (dead included; rules skip hp <= 0); slots only for able ones
	int roster = 0;             // formal roster size incl. the dead (ready_fraction denominator)
	int slot_count = 0;
	double compact_t = 0;

	// orders
	int target_person = -1;          // ATTACK / PURSUE target soldier index
	float origin_x = 0, origin_y = 0; // PURSUE origin (D56 reference at issue)
	double pursuit_left = 0;
	double order_delay = 0;          // D77 tactics: order execution preparation
	bool attacking = false;          // TerrainArmy.combat_attacking
	bool needs_attack_order = false; // D50

	// command (TerrainArmy formal/acting/current)
	int formal_cmd = -1, acting_cmd = -1, current_cmd = -1;
	std::vector<int> officer_order;
	bool command_dirty = true;
	float ref_x = 0, ref_y = 0;
	bool ref_valid = false;
	uint64_t rng = 0;

	// shared state
	double training = 0;
	double morale = 100, rally_rest = 0;
	bool routed = false;
	double fatigue = 0, fatigue_rest = 0;
	int fatigue_count = 0;
	bool charged_this_step = false;
	double recovery_multiplier = 1.0; // One-step host input; rebuilt from the original Site, never serialized.
	double housing_recovery_multiplier = 1.0; // Same phase, separate Site attendance permission; never serialized.
	bool host_fire_rest_safe = false; // One-step host proof: every live member is clear of fire/work; never serialized.

	// contact / ai
	double contact_age = 1e9;  // seconds since any member was in a melee pair
	bool in_contact = false;   // some member stood in melee reach of an enemy last step (S_FIGHT)
	bool threat = false;       // any able member has an able enemy near (block test)
	bool ai_enabled = true, ai_recovering = false;
	bool no_orders = false, host_center = false, fully_fed = true;
	bool garrisoned = false; // Original roster retained in a barracks; no appointed command.
	double sustain_morale_delta = 0;
	double ai_order_cd = 0, ai_chase_cd = 0;
	int ai_target = -1;
	AIStatus ai_status = AI_NONE;
	double encircle_t = 0;

	// morale bookkeeping (site_controller._observe_team_life): was a qualified commander present at the
	// last observation; the per-member life checkpoint lives in World::life_ck
	bool commander_present = true;
	bool resupplying = false; // safe + stopped at the last sustain pass (reported)
	// G4: a formation carrying vehicles re-assigns its soldier slots once, by least total distance, when it arrives after a
	// layout change, so a turned block does not have to push members through each other to reach old slot numbers. Saved.
	bool reslot_pending = false;
	float rest_gx = 0, rest_gy = 0, rest_gf = 0; // layout the members' rest holds belong to (goal pose, slot count)
	int rest_slots = -1;
	// CAV-4a charge cycle (saved from KW18, hashed). charge_stage: ChargeStage. charge_dx/dy: unit heading of the charge,
	// fixed from the start of CS_CHARGE. charge_tx/ty: target point last used; charge_target_form: enemy formation followed
	// live (-1: fixed point). rally_x/y: rally point of CS_RALLY. charge_t: seconds left in the current stage.
	// charge_cols: layout columns before the line-abreast form-up (0: unchanged). charge_runs: completed charge cycles.
	uint8_t charge_stage = CS_NONE;
	float charge_dx = 1.f, charge_dy = 0.f, charge_tx = 0.f, charge_ty = 0.f, rally_x = 0.f, rally_y = 0.f;
	int charge_target_form = -1;
	double charge_t = 0.0;
	int charge_cols = 0, charge_runs = 0;
	// ORDSERIAL (saved from KW19, hashed): order_serial counts the issued orders, starting at 1 like TerrainArmy; it grows by
	// one on every accepted host_order and every native AI order (World::bump_order_serial), so a host holding an older value
	// knows a newer order was issued (G6 Region nation command, COMMAND_SUPERSEDED). ranged_order_serial is the original
	// ranged-order counter the host keeps with the formation (CrowdPersonOwner.ranged_order_serial); native never changes it.
	int64_t order_serial = 1, ranged_order_serial = 0;
};

struct Config {
	float radius = 0.35f, wall_margin = 0.30f;
	float march_speed = 2.63f;   // cells/s  (1 cell / 0.38 s, CharacterCombatTimings.MOVE_DURATION)
	float run_speed = 4.0f;      // engage / encircle / flee (RUN_DURATION 0.18 s is 5.6 cells/s; capped for PBD)
	float max_turn_rate = 1.2f;
	float engage_radius = 4.0f;
	float reach = 1.15f;         // continuous stand-in for "four-neighbour adjacent"
	float leash = 1.0f;          // D73: ordinary engage within 1 cell of the assigned slot
	float encircle_cells = 8.0f; // exchange v1: nearby targets within 8 of contact
	int encircle_budget = 32;    // new encircle moves per formation per review
	float ranged_keep = 3.0f;    // 2026-09-18: keep at least 3 cells
	float ranged_leash = 6.0f;
	float ally_push = 1.0f, enemy_push = 1.0f, push_clamp = 0.25f;
	int los_period = 4, contact_period = 3, los_max_cells = 24, chunk = 256, max_fields_per_step = 2;
	double ko_seconds = rules::KNOCKOUT_GAME_SECONDS;          // tests may shorten
	double rescued_ko_seconds = rules::RESCUED_KNOCKOUT_GAME_SECONDS;
	double bleed_per_game_hour = rules::KO_BLEED_PER_GAME_HOUR; // 2026-09-29 user decision
	float rescue_seek_cells = 8.f;  // 2026-09-29 default: idle members walk up to 8 cells to a bleeding team-mate (0 = original, adjacent only)
	bool auto_capture = true;       // 2026-09-29: AI formations (ai_enabled) capture unconscious enemies without an explicit order
	float capture_seek_cells = 8.f; // how far an idle AI member walks to capture
	double speed = 1.0;          // Site simulation speed (0.5 / 1 / 2 / 4): multiplies game time only
	double combat_grace = 10.0;  // SiteRuntime.COMBAT_GRACE: exchange / effective hit keep the combat clock
	double shot_grace = 12.0;    // TerrainArmy.ranged_fire: combat_event.emit(12.0)
	int64_t seed = 581;
	bool ai = true;
};

struct PhaseTimes {
	double bleed = 0, hash = 0, command = 0, ai = 0, formation = 0, fields = 0, contact = 0, soldier = 0, timers = 0, exchange = 0,
	       ranged = 0, actions = 0, fatigue = 0, compact = 0, present = 0, total = 0;
	int steps = 0;
	void add(const PhaseTimes &o);
};

struct Stats {
	uint64_t illegal_cell = 0, illegal_step = 0, deep_overlap_pairs = 0;
	uint64_t rounds = 0, pairs = 0, draws = 0, small = 0, big = 0, knockbacks = 0;
	uint64_t shots = 0, hits = 0, grazes = 0, misses = 0, blocked = 0, empty = 0, friendly_hits = 0;
	uint64_t kos = 0, deaths = 0, bled_deaths = 0, bandaged = 0, wakes = 0, rescues_started = 0, rescues_done = 0, rescues_cancelled = 0;
	uint64_t captures_started = 0, captures_done = 0, captures_cancelled = 0, escapes = 0, captures_auto = 0;
	uint64_t successions = 0, command_losses = 0, routs = 0, pursuits = 0, pursuit_ends = 0, ai_orders = 0,
	         skills_used = 0, encircle_assigned = 0, fields_built = 0, cooldown_violations = 0;
	int fighting = 0, engaging = 0, alive = 0, down = 0, captive = 0;
	uint64_t cav_contacts = 0, cav_falls = 0, cav_dismounts = 0, cav_stops = 0, cav_shocks = 0; // CAV-1 charge outcomes (reporting); cav_shocks: 4.5
	uint64_t charge_forms = 0, charge_breaks = 0, charge_rallies = 0, cav_penetrations = 0; // CAV-4a: form-ups begun, charges broken through (to RALLY), rally arrivals
	double cav_impact_speed = 0.0; // CAV-4a reporting: sum of the impact speeds of the cavalry contacts
};

// Events for the Godot side (SiteStore owner commits). `time` is the World action time of the step.
enum EventKind : uint8_t {
	EV_DEATH = 0, EV_KO, EV_WAKE, EV_RESCUED, EV_CAPTURED, EV_ESCAPED, EV_SUCCESSION, EV_COMMAND_LOST,
	EV_ROUT, EV_RALLY, EV_SHOT, EV_COUNT
};
struct Event {
	uint8_t kind = 0;
	int32_t soldier = -1;   // index (DEATH / KO / WAKE / RESCUED / CAPTURED / ESCAPED / SHOT) or new commander
	int32_t formation = -1;
	int64_t person = -1;    // person_id of `soldier`
	int64_t other = -1;     // rescuer / captor / previous commander / -1
	double time = 0;
	// Original formation values at DEATH; the Site commits them into that original body.
	double fatigue = 0, fatigue_rest = 0;
};

// Person / formation state exchanged with SiteStore at battle start, battle end and on demand.
struct SoldierState {
	double hp = 100, stun = 0, grace = 0, ko = 0, getup = 0, stagger = 0;
	int captive = 0;
	int64_t captor_person = -1;
	int64_t prison_id = 0; // Site captivity relation mirror; zero is outdoor custody.
	int bandaged = 0;
	int ammo = 0;
	int tactics = -1, leadership = -1, coach = -1; // -1: no command ability generated yet
	double escape_t = 0, exch_cd = 0, ranged_cd = 0, skill_cd = 0, knock_t = 0, act_t = 0;
	int role = -1;
	float x = NAN, y = NAN, facing = NAN;
};
struct FormationState {
	double morale = 100, rally_rest = 0, fatigue = 0, fatigue_rest = 0, training = 0;
	int routed = 0, needs_attack_order = 0, commander_present = 1;
	int64_t formal_person = -1, acting_person = -1;
	std::vector<int64_t> officer_persons; // succession order
	int64_t current_person = -1, target_person = -1;
	int fatigue_count = -1, order = -1, ai_enabled = -1, no_orders = -1, host_center = -1;
	float goal_x = NAN, goal_y = NAN, goal_facing = NAN, cx = NAN, cy = NAN, facing = NAN, origin_x = NAN, origin_y = NAN, ref_x = NAN, ref_y = NAN;
	double pursuit_left = 0, order_delay = 0;
	int attacking = 0, ref_valid = 0, resupplying = 0;
	int64_t order_serial = -1, ranged_order_serial = -1; // ORDSERIAL: read back by get; an import with -1 leaves the counter as it is
};

// ---------------------------------------------------------------- presentation (atlas rendering, P2b)
// Visual slots the host maps to the game's atlas clips (terrain_army._combat_clip / exchange visuals).
enum VisualSlot : uint8_t { V_IDLE = 0, V_WALK, V_RUN, V_ATTACK, V_ATTACK_HEAVY, V_GUARD, V_HIT, V_KNOCKBACK, V_SHOOT, V_DOWN,
	V_UNCONSCIOUS, V_GET_UP, V_RESCUE, V_COUNT };
// One (clip, direction) sequence of one atlas page, as terrain_army_batch_view builds it: frame sample
// times, anchors pre-scaled by the page map_scale, and an optional visual-age -> source-time table
// (character_exchange_timings.sample_time) for the exchange / shot visuals.
struct RenderTrack {
	int sequence = 0;
	float duration = 0;
	bool loop = true;
	std::vector<float> times, ax, ay, map;
	float map_step = 0;
};
struct RenderKit { int page = 0, palette = 0; float scale = 1; int track[V_COUNT][4]; };

struct Projectile {
	int shooter = -1, faction = 0;
	int64_t shooter_id = 0, shot_id = 0;
	rules::Cell source{0, 0}, target{0, 0};
	double left = 0, source_eye = 1, goal_eye = 1;
	rules::RangedShooter stats;
};
struct MotionSegment { float from_x = 0, from_y = 0, to_x = 0, to_y = 0; };
// Receipt of World::site_person_release: the travelling person's values at departure. fatigue values are the
// formation's shared pool (the native World keeps no per-person fatigue).
struct SitePersonRelease { double hp = 0, fatigue = 0, fatigue_rest = 0, x = 0, y = 0; int ammo = 0, cell_x = 0, cell_y = 0; };
// G4 logistics convoy (one wagon or cart). Crew member k stands at anchor + (ox, oy) rotated by the anchor facing.
struct ConvoyCrew { int soldier = -1; int ox = 0, oy = 0; };
struct ConvoyOffset { int ox = 0, oy = 0; };
struct Convoy {
	int id = 0;
	float x = 0, y = 0, facing = 0;    // anchor (cell coordinates) and facing in radians (0 = +x)
	bool has_goal = false;
	float gx = 0, gy = 0, gfacing = 0; // goal anchor (cell centre) and goal facing
	int goal_cell = -1;
	int field = -1;                    // flow field index for goal_cell; re-requested when evicted or stale
	std::vector<ConvoyCrew> crew;
	// Body footprint in convoy-local offsets (rotated by facing exactly like crew). Saved and hashed. The absolute
	// cells are floor(anchor + rotate(offset)) and are re-derived every time the anchor or facing changes.
	std::vector<ConvoyOffset> body;
	std::vector<int> body_cells;       // sorted absolute footprint at the current pose. Derived: not saved, rebuilt on load.
	bool body_stalled = false;         // the last step refused to advance or turn into another body or occupied cells. Saved.
	int stall_reason = 0;              // CONVOY_* code from the last convoy_stage. Saved so the reported pose matches after load.
	// G4 formation following (OPUS). formation >= 0: the convoy is attached to that formation; its goal is its vehicle
	// slot in the formation layout (convoy_plan_formation) and it steers by its own route field. Saved and hashed.
	int formation = -1;
	float key_gx = 0, key_gy = 0;      // layout key the current slot goal was computed from: formation goal, quarter and
	int key_q = -1, key_slots = -1, key_count = -1; // soldier slot count (key_count: vehicles in that layout); key_q < 0 = replan
	int slot_index = -1;               // assigned rank position, -1 none
	int blocked = 0;                   // consecutive stages without progress (replan trigger)
	bool no_slot = false;              // the layout found no feasible slot for this convoy
	int turn_to = -1;                  // quarter of the turn under way about the pivot cell, -1 none
	int move_to = -1;                  // pivot cell of the translation step under way, -1 none
	int plan_x0 = 0, plan_y0 = 0, plan_w = 0, plan_h = 0; // route region (cells)
	std::vector<uint32_t> plan_cost;   // route cost to the slot per (region cell of the pivot, quarter); UINT32_MAX = none
	std::vector<int> claim;            // cells this convoy claimed (own-team soldiers step out, nobody else enters). Saved.
};
// Why a convoy with a goal is not advancing (ConvoyState::reason). CONVOY_OK means advancing, turning or complete.
// YIELDING (own-team soldiers are stepping out of the claimed cells) and CREW_OFF_SLOT are waits, not stalls.
enum ConvoyReason : int {
	CONVOY_OK = 0, CONVOY_NO_GOAL = 1, CONVOY_CREW_CANNOT_ACT = 2, CONVOY_CREW_OFF_SLOT = 3, CONVOY_NO_ROUTE = 4,
	CONVOY_BLOCKED_TERRAIN = 5, CONVOY_BLOCKED_BODY = 6, CONVOY_BLOCKED_SOLDIER = 7, CONVOY_YIELDING = 8, CONVOY_NO_SLOT = 9
};
struct ConvoyState { double x = 0, y = 0, facing = 0; int moving = 0, complete = 0, stalled = 0, reason = 0; };

class World {
public:
	Config cfg;
	Terrain terrain;
	std::vector<Formation> formations;

	// ---- soldier SoA (hot)
	std::vector<float> px, py, nx, ny, vx, vy, face, anim_t;
	std::vector<double> hp, stun, grace, ko, getup, stagger, exch_cd, ranged_cd, skill_cd, knock_t, act_t, escape_t;
	std::vector<float> knock_dx, knock_dy;
	// Rest rule (formation at rest in HOLD): a member whose target is contested (clipped by a wall or a step, or another
	// member's clipped target within 0.6) and who makes no progress toward it for kRestSeconds within 2.5 of it stops
	// pushing and holds: it stands where it is pushed, until pushed out a cell beyond its own slot's distance from the centre.
	// Cleared when the formation moves or its layout changes. Saved.
	std::vector<uint8_t> rest_hold;
	std::vector<float> rest_x, rest_y, rest_best, rest_t; // held spot, best distance to the target, seconds without progress
	std::vector<uint8_t> team, state, los_ok, skill, role, captive, present, troop, running, near_enemy, fire_blocked, bandaged;
	// Host-controlled soldiers (the player, 2026-09-30 user decision: the player is one soldier of the crowd
	// under every soldier rule; only the wish to move and to fight comes from the host's input instead of
	// orders / AI). host_vx / host_vy: wished velocity in cells / s; host_run: run speed cap; host_engage:
	// initiate exchanges and stand to fight when an enemy is in reach, like a soldier under ATTACK.
	std::vector<uint8_t> host_ctl, host_run, host_engage;
	std::vector<float> host_vx, host_vy;
	void set_host_control(int i, bool on);
	void host_input(int i, float wish_vx, float wish_vy, bool run, bool engage);
	std::vector<int32_t> form, slot, target, cell, enc_target, rescue_of, capture_of, captor;
	std::vector<int64_t> prison_id;
	std::vector<int64_t> contact_revision; // Original native body's effective-hit revision.
	std::vector<int32_t> escort_goal; // One original, adjacent step; -1 waits at the current place.
	std::vector<uint8_t> escort_mode; // 0 ordinary, 1/2 custody; 3/4 housing; 5/6 siege. Even means finish then cancel.
	std::vector<int32_t> housing_attendance_cell; // One-step host reference input only; -1 absent, never serialized.
	std::vector<uint16_t> ammo;
	std::vector<rules::Equip> equip;
	std::vector<CommandAbility> ability;
	std::vector<uint8_t> military_role; // 0 soldier, 1 qualified officer, 2 civilian.
	// 1 = holds a non-head post (文官 or 武官) in the original team (v2 plan R1b,
	// amended 2026-10-07 "文官也可以帶兵"). Command needs officer rank and either
	// this post or the formal captaincy; standalone callers default to 1 (legacy).
	std::vector<uint8_t> post_holder;
	// 1 = departed the Site with a travelling person (site_person_release). Such a soldier is not alive, not
	// able to act, not in its formation, and is not drawn; its hp and position are kept for the receipt. Saved.
	std::vector<uint8_t> released;
	// G1 S1: 1 = aboard a ship / vehicle (site_person_board). Such a soldier stays alive, on the roster, fatigue-bound and
	// in its formation's member list (as convoy crew are), but holds no soldier slot, is not moved, pushed, hashed or
	// targeted; its position is the deck position the host sets. aboard_vehicle: vehicle id, -1 when not aboard. Saved.
	std::vector<uint8_t> aboard;
	std::vector<int32_t> aboard_vehicle;
	// G5 S1 absent: 1 = off the field but still in the formation roster (site_person_absent). An absent soldier is not
	// alive (alive() is false), holds no slot and is not in members, but keeps its roster count, fatigue binding and hp;
	// it can return (site_person_return) or change formation (move_member). absent_kind: 0 when present, else 1 detached,
	// 2 off-map, 3 captive hold, 4 garrison reserve. Both saved and hashed.
	std::vector<uint8_t> absent, absent_kind;
	// G5 S4 surrender (NEKKI 2026-10-30 A): 1 = routed and terrain-trapped (World::retreat_trapped). A surrendered soldier
	// stands in place, is not a target, does not act (can_act is false) and leaves command. It is settled at once by
	// World::settle_surrender (a captive of the nearest hostile formation's able member) or, when no captor exists, retried
	// every 15 steps; death also clears it. Saved and hashed.
	std::vector<uint8_t> surrendered;
	// CAV-1 mounted cavalry (saved, hashed, validated). mounted: 1 = riding (cav::RADIUS body, speed caps and
	// acceleration / turn limits, two sub-steps); set by set_mounted, cleared on death. cav_hist: the last
	// cav::HEADING_WINDOW headings of the rider, one ring slot per step (slot = tick % window); cav_hold: seconds the rider has
	// been moving (the charge's 0.4 s straight run, see cav_straight). cav_hits: penetrations in the current charge
	// (MAX_HITS, reset when the speed falls below CHARGE_SPEED). cav_hit_who / cav_hit_t: the eight most recent victims per
	// soldier with the action time of each hit (2 s re-charge limit). cav_down: seconds left on the fall of a trampled
	// body; a fallen body exerts no push on riders.
	std::vector<uint8_t> mounted, cav_hits;
	std::vector<float> cav_hist;
	std::vector<double> cav_hold, cav_down, cav_hit_t;
	std::vector<int32_t> cav_hit_who;
	// CAV-4a: 1 once this rider's charge in the current cycle is over (stopped, or engaged in contact while charging).
	// A spent rider follows the ordinary engagement and slot rules until the next form-up clears it. Saved from KW18, hashed.
	std::vector<uint8_t> cav_spent;
	// Combat records (NEKKI 2026-11-05): the person who last landed an effective blow on each soldier, read by the host
	// with last_striker(i) when it handles that soldier's DEATH / KO event (events keep their sentinel `other`).
	// Transient: not saved or hashed; a loaded World starts unknown (-1). Sized lazily to the soldier count.
	std::vector<int64_t> last_striker_person;
	int64_t striker_person_ = -1; // set around apply_contact by the exchange, ranged and cavalry resolvers
	// derived each step (never saved or hashed): the charge candidate of each rider and the impact velocity of it
	std::vector<int32_t> cav_cand;
	std::vector<float> cav_cand_vx, cav_cand_vy;
	// NEKKI 2026-10-31 captive follow: the wish of each field captive walking behind its captor, planned serially before
	// the soldier stage from start-of-step state (never saved or hashed; re-planned every step).
	std::vector<uint8_t> follow_on_;
	std::vector<float> follow_wx_, follow_wy_;
	std::vector<int64_t> person_id;
	std::vector<uint8_t> life_ck; // morale checkpoint: 0 conscious, 1 unconscious, 2 dead
	// presentation only (never read by the rules, not hashed, not saved)
	std::vector<uint8_t> vis_kind;
	std::vector<double> vis_t0;
	std::vector<int16_t> kit;
	std::vector<Event> events;    // drained by the host
	std::vector<Projectile> projectiles;
	bool host_ranged_delegate=false;
	int64_t host_last_release_id=0; // Receipt watermark, not a flight owner.
	std::vector<uint8_t> fire_visual; // Derived presentation only.
	std::vector<MotionSegment> action_motion; // Original last-step path; derived and never saved/hashed.

	uint32_t tick = 0;
	int64_t exchange_round = 0, shot_serial = 0;
	double time = 0;
	// Time (single time source): action seconds drive movement, cooldowns, stagger, rescue pose, exchange rounds;
	// game seconds drive KO wait, bleeding, fatigue, morale resupply / rally, capture and escape.
	// step(dt) runs the Site clock itself (SiteRuntime.game_seconds with combat_left); step_clock(...)
	// takes both values from the host, which then forwards `combat_mark` to SiteRuntime.mark_combat.
	double combat_left = 0;   // seconds of combat clock left (1:1); 0 = disengaged (1 s = 1 game min)
	double game_dt = 0;       // game seconds of the current step
	double combat_mark = 0;   // largest combat_event duration raised during the last step
	bool external_clock = false;
	Stats stats;
	PhaseTimes last;

	explicit World(int threads);
	int add_formation(int team, float cx, float cy, float facing, int cols, float spacing, Troop troop, double training);
	int add_soldier(int formation, const rules::Equip &e, Role role, int64_t person = -1, uint16_t ammo_count = 0);
	void finalize(); // builds edges, places soldiers, sets captains / officers / abilities
	void order_move(int f, float gx, float gy, float gfacing);
	void order_attack(int f, int target_person);
	void order_hold(int f);
	void order_pursue(int f, int target_person);
	void order_retreat(int f, float gx, float gy);
	// CAV-4a (crowd_core.cpp, orders section). order_charge: target point (gx, gy), or the enemy formation `form` followed
	// live (gx, gy then only seed the point). Returns false (no change) when no form-up point is walkable.
	bool order_charge(int f, float gx, float gy, int form);
	void order_rally(int f);             // RALLY: pick the rally point behind the target, go there, then HOLD
	void clear_charge(Formation &f);     // any order other than CHARGE / RALLY drops the charge cycle
	void charge_stage_step(int fi, float dt); // one step of the charge cycle of formation fi (before its movement)
	bool cavalry_formation(int fi) const;     // at least half of the able members are mounted
	bool charge_commander_ok(int fi) const;   // commander eligible (command_eligible) and within COMMAND_CELLS of the centre
	bool charge_rider(int i) const;           // mounted, able, not spent, in the CS_CHARGE stage of a CHARGE order
	bool order_capture(int guard, int target); // explicit order (inst. sec.6)
	bool order_escort_step(int person, int guard, int destination_cell);
	void cancel_escort(int person);
	enum class ControlledStepKind : uint8_t { Housing = 3, Siege = 5 };
	bool order_controlled_step(int person, int destination_cell, ControlledStepKind kind);
	void cancel_controlled_step(int person, ControlledStepKind kind);
	bool order_housing_step(int person, int destination_cell) { return order_controlled_step(person, destination_cell, ControlledStepKind::Housing); }
	bool order_siege_step(int person, int destination_cell) { return order_controlled_step(person, destination_cell, ControlledStepKind::Siege); }
	void cancel_housing_step(int person) { cancel_controlled_step(person, ControlledStepKind::Housing); }
	void cancel_siege_step(int person) { cancel_controlled_step(person, ControlledStepKind::Siege); }
	bool controlled_step_pending(int person) const { return person >= 0 && person < soldier_count() && escort_mode[person] >= 3 && escort_mode[person] <= 6 && escort_goal[person] >= 0; }
	// Transient commitments reference original people and cells. No second person,
	// vehicle, item, HP, clock or save authority is created here.
	struct SiegeMember { int soldier = -1; int64_t person = -1; int from = -1, to = -1; };
	struct SiegeCompound {
		int64_t token = 0;
		std::vector<SiegeMember> members;
		std::vector<int> claims;
		std::vector<uint8_t> heights;
		std::vector<int> source_body; // SIEGE-YIELD: the vehicle's current body cells (subset of claims); transient like the compound
		double elapsed = 0, duration = 0;
		bool cancelled = false, complete = false, aborted = false;
	};
	std::vector<SiegeCompound> siege_compounds;
	std::vector<uint8_t> siege_crew; // Rebuilt from original Site crew references; never serialized.
	std::vector<int32_t> siege_member_group; // Transient index, -1 outside a compound.
	std::vector<int32_t> siege_step_source; // Original source of a single siege approach commitment.
	std::vector<uint8_t> siege_person_blocked; // Derived original Site physical bodies, never terrain authority.
	std::vector<std::vector<int>> siege_wreck_exit; // Current original occupants may leave only their own wreck.
	int64_t siege_serial = 0;
	bool set_siege_crew(int person, bool assigned);
	int64_t begin_siege_compound(const std::vector<SiegeMember> &members,
		const std::vector<int> &source_body, const std::vector<int> &target_body,
		const std::vector<int> &sweep, double duration);
	const SiegeCompound *siege_compound_state(int64_t token) const;
	bool cancel_siege_compound(int64_t token);
	bool settle_siege_compound(int64_t token);
	bool siege_claims_cell(int cell, int ignore_person = -1) const;
	// SIEGE-YIELD (decision 2026-10-30 A): own-team non-crew people standing in a compound's claimed cells step out
	// (convoy_evacuation rules) and their slot targets avoid the claims. Derived from the saved claims: no new state.
	int siege_claim_team(int cell) const;                       // team of the compound claiming cell, -1 none
	bool siege_yields(int person, int cell) const;              // person may stand in / pass through cell's siege claim
	void siege_slot_clear(int person, float &x, float &y) const; // slot target inside a yielded claim -> nearest free cell
	bool siege_turn_hold(int person) const; // v6: yielder whose own formation's crew are turning: stays with the formation
	// Site also blocks a rotating sweep in the person mask (build_siege_navigation); a yielder may still stand on and step
	// through the sweep cells it yields to (the future target body included: it is still empty), never the vehicle's
	// current (source) body.
	bool siege_yield_passable(int person, int cell) const;
	bool siege_compound_valid(const SiegeCompound &group, const Terrain &ground) const;
	void abort_siege_compound(int index);
	void advance_siege_compounds(float dt);
	bool move_siege_member(int person, float dt);
	bool set_siege_navigation(const std::vector<int> &blocked, const std::vector<int64_t> &exits);
	// siege_nav_cell: terrain plus siege bodies. siege_route_cell additionally excludes convoy body cells; people and
	// flow fields (body_aware) use it. Convoy anchors use siege_nav_cell and check bodies in convoy_cells_clear.
	bool siege_nav_cell(int cell) const { return cell >= 0 && cell < (int)terrain.height.size() && (siege_person_blocked.empty() || !siege_person_blocked[cell]); }
	bool convoy_body_cell(int cell) const { return cell >= 0 && cell < (int)convoy_body_owner.size() && convoy_body_owner[cell] != 0; }
	bool siege_route_cell(int cell) const { return siege_nav_cell(cell) && !convoy_body_cell(cell); }
	bool siege_person_cell(int person, int from, int to) const;
	void resolve_siege_person(int person, float old_x, float old_y, float &x, float &y) const;
	bool is_siege_crew(int person) const { return person >= 0 && person < (int)siege_crew.size() && siege_crew[person] != 0; }
	// G4 logistics convoys. Ids start at 1; 0 / false = refused with no state change. Saved (KW11) and hashed.
	// Crew are steered by their convoy (not by ordinary orders, slots or AI), like siege crew.
	static constexpr float convoy_tolerance = 0.5f; // crew distance from its slot before the anchor may advance
	std::vector<Convoy> convoys;
	std::vector<int32_t> convoy_of; // per soldier: owning convoy id, 0 when not convoy crew
	// Derived per cell: id of the convoy whose body covers it, 0 when none. Empty when no convoy has a body cell.
	std::vector<int32_t> convoy_body_owner;
	int convoy_serial = 0;
	int add_convoy(float ax, float ay, float facing);
	bool convoy_set_crew(int id, int soldier, int ox, int oy, bool assigned);
	bool convoy_order_goal(int id, float gx, float gy, float gfacing);
	bool convoy_set_body(int id, const std::vector<int> &cells);
	bool convoy_state(int id, ConvoyState &out) const;
	// Soldier indices of a convoy's crew, in crew order. Empty when the convoy is unknown.
	std::vector<int> convoy_crew_soldiers(int id) const;
	bool convoy_remove(int id);
	// Absolute footprint of a convoy at its current pose (sorted); false if unknown.
	bool convoy_body_at(int id, std::vector<int> &cells) const;
	// G4 formation following. attach: every crew member must be a member of the formation; refusals change nothing.
	// An explicit convoy_order_goal detaches. convoy_formation: -2 unknown convoy, -1 detached, else the formation.
	bool convoy_attach_formation(int id, int formation);
	bool convoy_detach_formation(int id);
	int convoy_formation(int id) const;
	// Diagnostics (read-only): a member's current slot target (slot index, world x / y, clip fraction); false if none.
	bool slot_target(int i, int &slot_index, float &x, float &y, float &clip) const {
		if (i < 0 || i >= soldier_count() || i >= (int)slot_tx_.size()) return false;
		slot_index = slot[i]; x = slot_tx_[i]; y = slot_ty_[i]; clip = slot_clip_[i];
		return true;
	}
	bool formation_has_convoys(int formation) const;
	// Convoy occupancy in its own frame: body and crew offsets, their bounds and the body's middle (the turning pivot).
	struct ConvoyShape { int min_ox = 0, max_ox = 0, min_oy = 0, max_oy = 0, mid_ox = 0, mid_oy = 0; std::vector<ConvoyOffset> occupancy; };
	ConvoyShape convoy_shape(const Convoy &c) const;
	// Derived per cell from the convoys' saved claims: id of the claiming convoy (own-team soldiers step out), 0 none.
	std::vector<int32_t> convoy_claim_owner;
	bool is_convoy_crew(int person) const { return person >= 0 && person < (int)convoy_of.size() && convoy_of[person] != 0; }
	// acting exclusions shared by siege crew and convoy crew (AI, exchange, rescue, capture, work)
	bool is_crewed(int person) const { return is_siege_crew(person) || is_convoy_crew(person) || is_aboard(person); }
	// G10: an arrived housing (3) or siege (5) step that holds its worker in place: no goal, no compound, no source.
	bool held_site_step(int i) const { return (escort_mode[i] == 3 || escort_mode[i] == 5) && escort_goal[i] < 0 && siege_group(i) < 0 && (i >= (int)siege_step_source.size() || siege_step_source[i] < 0); }
	int siege_group(int person) const { return person >= 0 && person < (int)siege_member_group.size() ? siege_member_group[person] : -1; }

	bool admit_prison(int person, int guard, int64_t prison, int slot_cell, int contact_cell);
	bool release_prison(int person, int executor, int64_t prison, int contact_cell, int exit_cell);
	bool step(float dt);                                              // internal Site clock
	bool step_clock(float dt, double game_seconds, double combat_left_now); // host-provided clock
	// Merge into the ORIGINAL wg::World declaration, public section.
	// Call-local values only; no new Formation field, saved owner or pending clock.
	struct WorkFatigueState {
		int formation = -1, before_count = 0;
		double before_fatigue = 0, before_rest = 0;
		double work_seconds = 0, run_seconds = 0; // Aggregate ORIGINAL person seconds.
		double fatigue = 0, rest = 0;             // Pure planner's admitted result.
	};
	std::vector<double> work_fatigue_state(int formation) const;
	std::vector<int64_t> work_fatigue_runners(int formation) const; // [unit, original person ID] pairs.
	double work_fatigue_rest_limit(int formation, double target, double maximum, double combat_left_now) const;
	bool validate_step_clock_work_plan(float dt, double game_seconds, double combat_left_now,
		uint32_t expected_tick, const std::vector<WorkFatigueState> &plan) const;
	// Pure original BEGIN pulse + its same future body scalar gate. No pending
	// state, cost, clock, person or formation mutation is created by this read.
	bool validate_step_clock_work_plan_after_host_ranged(float dt, double game_seconds,
		double combat_left_now, uint32_t expected_tick, const std::vector<WorkFatigueState> &plan,
		const std::vector<int64_t> &releases, const std::vector<double> &preview) const;
	bool validate_step_clock_work_plan_source(float dt, double game_seconds, double combat_left_now,
		uint32_t expected_tick, const std::vector<WorkFatigueState> &plan,
		const std::vector<double> *ranged_preview) const;
	bool step_clock_work_plan(float dt, double game_seconds, double combat_left_now,
		uint32_t expected_tick, const std::vector<WorkFatigueState> &plan);

	// ORIGINAL World transient completion of one already-integrated step.
	// P5 keeps its original post-contact classification. No new clock/save owner.
	bool step_clock_work_point(float dt, double game_seconds, double combat_left_now,
		uint32_t expected_tick, const std::vector<WorkFatigueState> &precontact_plan);
	bool validate_work_point_finish(uint32_t expected_begin_tick, const std::vector<WorkFatigueState> &final_plan) const;
	bool prepare_work_point_finish(uint32_t expected_begin_tick, const std::vector<WorkFatigueState> &final_plan);
	void publish_work_point_finish(); // Approved immutable values; no fallible work/callbacks in tail.
	std::vector<double> work_point_state() const;
	std::vector<int64_t> work_fatigue_run_upper() const; // Pure true start refs; clipping ONLY.
	std::vector<int64_t> work_point_runners() const; // True old-metered + actual new-motion union.
	struct WorkTrainingState { int formation = -1; double before_training = 0, training = 0, effort_seconds = 0, productive_seconds = 0; };
	bool work_training_start_ready(int formation, double combat_left_now) const;
	bool validate_work_point_training_plan(uint32_t begin_tick, const std::vector<WorkTrainingState> &targets) const;
	bool prepare_work_point_training_plan(uint32_t begin_tick, const std::vector<WorkTrainingState> &targets);
	// person / formation state (SiteStore import at battle start, export at end)
	void set_soldier_state(int i, const SoldierState &s);
	SoldierState get_soldier_state(int i) const;
	void set_formation_state(int f, const FormationState &s);
	bool set_garrisoned(int f, bool enabled);
	// G7b: set (or clear, with no offsets) a formation's preset slot offsets; refuses a garrisoned formation, an odd
	// count, more than MAX_SHAPE_SLOTS pairs, or a value that is not finite or beyond 64 slots. The able members reslot.
	static constexpr int MAX_SHAPE_SLOTS = 400;
	bool set_formation_shape(int f, const std::vector<float> &offsets);
	bool set_military_role(int i, int value);
	bool set_post_holder(int i, int value);
	bool apply_training_state(int f, double before_training, double before_fatigue, double before_rest,
	                          double training, double fatigue, double rest, bool worked);
	FormationState get_formation_state(int f) const;
	// single decision owner: an AI-owned formation (ai_enabled) refuses host orders and vice versa
	int host_order(int f, int kind, float gx, float gy, double x);
	int host_order_impl(int f, int kind, float gx, float gy, double x); // admission and order of host_order, without ORDSERIAL
	// ORDSERIAL: the issued-order counters of formation f (see Formation::order_serial). set_order_serials is the host import
	// (an original team's serials when the crowd takes it over, and the host's ranged order counter): false, and nothing
	// written, unless 1 <= order_serial <= ORDER_SERIAL_MAX and 0 <= ranged_order_serial <= ORDER_SERIAL_MAX.
	static constexpr int64_t ORDER_SERIAL_MAX = 2147483647;
	bool set_order_serials(int f, int64_t order_serial, int64_t ranged_order_serial);
	void bump_order_serial(int f) { if (f >= 0 && f < (int)formations.size() && formations[f].order_serial < ORDER_SERIAL_MAX) ++formations[f].order_serial; }
	bool set_sustain_input(int f, bool fully_fed, double delta);
	bool set_recovery_input(int f, double multiplier);
	bool set_housing_recovery_input(int f, double multiplier);
	bool set_fire_safe_rest_input(int f, bool safe);
	bool set_housing_attendance_input(int person, int cell);
	bool set_soldier_equip(int i, const rules::Equip &equipment);
	bool apply_environment_damage(int i, double amount);
	bool set_host_ranged_delegate(bool enabled);
	// Pure current-BEGIN facts only. Six int64 values per original release:
	// [unit, expected_ammo, mode, release_id, target_x, target_y].
	// No reservations, input projection, skill, charge, event or clock writes.
	std::vector<double> preview_host_ranged_batch(const std::vector<int64_t> &releases) const;
	bool commit_host_ranged(int i,int expected_ammo,int mode,int64_t release_id,int target_x,int target_y,bool auto_power,rules::RangedShooter &receipt);
	bool apply_host_projectile_contact(int i,double hp_loss,double stun_add,double stagger_seconds);
	bool apply_fire_exposure_damage(int i,double hp_loss);
	bool set_fire_visual_rows(const std::vector<int> &indices,const std::vector<uint8_t> &flags);
	MotionSegment motion_segment(int i) const { return i >= 0 && i < (int)action_motion.size() ? action_motion[i] : MotionSegment{}; }
	bool set_contact_revision(int index, int64_t value);
	bool apply_siege_contact(int i, double hp_loss, double stun_add, double stagger_seconds);
	bool apply_melee_contact(int i, double hp_loss, double stun_add);
	bool charge_exchange_fatigue(int i, double amount);
	// G6.4 site exit. Ready: a conscious, free soldier of a formation, not held, not in a melee exchange, with no
	// committed step. Release refuses (returns false, writes nothing) unless ready.
	bool site_person_exit_ready(int i) const;
	bool site_person_release(int i, SitePersonRelease &out);
	// SHIPSEA sea departure: the same gate and release for a soldier aboard `vehicle` (aboard accepted, siege / convoy
	// crew refused). The release clears aboard / aboard_vehicle; the receipt position is the deck point.
	bool site_person_exit_ready_aboard(int i, int vehicle) const;
	bool site_person_release_aboard(int i, int vehicle, SitePersonRelease &out);
	bool exit_ready_checks(int i, bool aboard_ok) const;
	void release_ready(int i, SitePersonRelease &out); // the release body; callers have passed the exit gate
	// G1 S1 aboard. Board: a ready soldier (the site_person_exit_ready guards) goes aboard vehicle >= 0; it keeps roster,
	// fatigue binding, hp, ammo and team, and loses its slot. Land: an aboard living soldier steps onto a free walkable
	// cell (no living non-aboard soldier, no convoy body) and rejoins its formation. set_deck: aboard only; moves the
	// position (presentation and ranged origin). retarget_aboard: aboard only; changes the vehicle. Refusals change nothing.
	bool is_aboard(int i) const { return i >= 0 && i < (int)aboard.size() && aboard[i] != 0; }
	bool site_person_board(int i, int vehicle);
	bool site_person_land(int i, double x, double y);
	bool site_person_set_deck(int i, double x, double y);
	bool site_person_retarget_aboard(int i, int vehicle);
	// G5 S1 absent. Absent: an exit-ready soldier (site_person_exit_ready, not aboard) leaves the field for kind 1..4;
	// it keeps roster, fatigue binding and hp, and loses its slot and member entry. Return: an absent living soldier
	// lands on a free walkable cell of formation `formation` (same team, not garrisoned) and rejoins it. Move: an
	// on-field or absent living soldier changes formation atomically. Refusals change nothing.
	bool site_person_absent(int i, int kind);
	bool site_person_return(int i, int formation, double x, double y);
	bool move_member(int i, int to_formation);
	// NEKKI 2026-10-30 persuasion: an awake captive of another team joins to_formation as a normal member (command.cpp).
	bool transfer_member(int i, int to_formation);
	// NEKKI 2026-11-04 joining in person: an awake member on the field leaves for another team's formation (command.cpp).
	bool leave_member(int i, int to_formation);
	bool landing_cell(int i, double x, double y, float &fx, float &fy, int &cell_index) const;
	void reassign_formation(int i, int to_formation);
	bool charge_siege_round(const std::vector<int> &members, double per_person);
	bool charge_siege_work(int person, double game_seconds);
	void contact_pose(int i, int movement, int &slot, double &age) const;
	bool charge_custody_work(int i, double seconds);
	bool begin_structure_strike(int i, int target_cell);
	bool host_may_order(int f) const { return f >= 0 && f < (int)formations.size() && !formations[f].ai_enabled; }
	// complete save / load (same build): everything that feeds the next step
	std::vector<uint8_t> save() const;
	// CAV-4a test hook: the same state in the KW17 layout (no charge cycle, no cav_spent); loads with the defaults.
	std::vector<uint8_t> save_kw17() const;
	mutable bool kw17_write_ = false;
	// ORDSERIAL test hook: the same state in the KW18 layout (no order serials); loads with order_serial 1, ranged 0.
	std::vector<uint8_t> save_kw18() const;
	mutable bool kw18_write_ = false;
	bool load(const std::vector<uint8_t> &blob);
	bool load(const std::vector<uint8_t> &blob, const std::vector<int> &blocked, const std::vector<int64_t> &wreck_exit);
	bool validate(std::string *error = nullptr, bool allow_site_jobs = true) const;
	int soldier_index(int64_t person) const;
	// Host blockers (the player, live captains, carts...): discs in cells the crowd cannot enter. Soldiers
	// steer around a blocker in their way and are projected out of it; where walls leave no way around
	// (a narrow pass) they stop and queue behind it. Host input, like orders: set before a step, not saved.
	struct Blocker { float x = 0, y = 0, r = 0.5f; };
	std::vector<Blocker> blockers;
	// standing (conscious, free) soldiers whose centre lies within r of (x, y): the host's cell_blocker query
	int standing_near(float x, float y, float r) const;
	// optional start positions (cells) set before finalize; soldiers without one start on their slot
	std::vector<float> start_x, start_y;
	// nearest able enemy of soldier i within r cells (-1: none); a host query, e.g. the player's auto-target
	int nearest_hostile(int i, float r) const;
	int pack_render(std::vector<float> &out, float cell_pixels);
	// atlas presentation: tracks / kits registered by the host, one kit per soldier. Output is in draw
	// order, grouped by (row, part, band, page); row = 10 + ground.y / 64 (terrain_army z_index).
	// Inside a row: 'band' splits the 64-px row into render_bands ground-y slices so different pages
	// interleave by depth; 'part' splits at every host actor (player / live captain Sprite) standing in
	// that row, so the actor is drawn after exactly the soldiers whose ground y is <= its own.
	// Consecutive same-page runs in a row are merged, so bands only add groups where pages interleave.
	// Each soldier group is padded to a power-of-two capacity.
	// spans (stride SPAN_STRIDE): row, page (-1 = actor), start (actor: actor index), count, capacity,
	// group id (row 16 | run number of that page in the row 8 | page 8; actor: row | index 8 | 255)
	// bounds: min x, min y, max x, max y; grounds: ground x, y per packed slot (verification)
	static constexpr int SPAN_STRIDE = 6;
	std::vector<RenderTrack> render_tracks;
	std::vector<RenderKit> render_kits;
	std::vector<float> render_actors;  // host actor ground positions in pixels, x, y pairs
	std::vector<float> render_grounds;
	int render_bands = 4;
	// Presentation filter (not simulation state: not saved, not hashed, cleared by load). The crowd's
	// positions carry push / contact jitter and its facings and speeds cross the pose thresholds many times a
	// second; drawn raw that reads as twitching. Per soldier the drawn ground position follows the simulated
	// one through a low-pass (short while travelling, long and with a dead zone while standing), and the
	// idle / walk / run choice and the 4-way direction change only with hysteresis and a minimum hold.
	struct Presentation { float x = 0, y = 0, speed = 0, dir_hold = 0, move_hold = 0, age = 0; uint8_t dir = 2, move = 0, ok = 0, slot = 0, shown_dir = 2; };
	std::vector<Presentation> pres;
	double pres_time = -1.0;
	float render_frame_dt = -1.f; // host frame seconds for the next pack_rows; < 0: use the simulated-time delta
	bool render_filter = true;
	// diagnostics: when render_trace is set, pack_rows records per soldier the chosen slot << 8 | direction
	// (0xFFFF = not drawn) and the ground position in pixels
	bool render_trace = false;
	std::vector<uint16_t> trace_state;
	std::vector<float> trace_xy;
	float vis_window[V_COUNT] = {0, 0, 0, 0.85f, 0.85f, 0.3f, 0.45f, 0.75f, 0.85f, 2.875f, 0, 2.2f, 0};
	int pack_rows(std::vector<float> &out, std::vector<int32_t> &spans, std::vector<float> &bounds, float cell_pixels);
	void set_visual(int i, VisualSlot v) { vis_kind[i] = (uint8_t)v; vis_t0[i] = time; }
	uint64_t state_hash(std::vector<int64_t> *marks = nullptr) const; // marks: the running hash at each section end (diagnostics)
	bool update_terrain(Terrain ground);
	std::vector<uint8_t> terrain_state() const;
	std::vector<uint8_t> occupancy_mask(const std::vector<int64_t> &ignored) const;
	void measure();
	int soldier_count() const { return (int)px.size(); }

	// rule queries (public for tests)
	// a released or absent soldier is out of every system. G5 S1: absent is in alive() exactly as released is, so every
	// rule path that skips released also skips absent. Death accounting (hp, fatigue_count) reads hp directly and is unchanged.
	bool alive(int i) const { return hp[i] > 0.0 && !released[i] && !absent[i]; }
	bool is_absent(int i) const { return i >= 0 && i < (int)absent.size() && absent[i] != 0; }
	bool is_surrendered(int i) const { return i >= 0 && i < (int)surrendered.size() && surrendered[i] != 0; }
	bool can_act(int i) const { return alive(i) && ko[i] <= 0.0 && getup[i] <= 0.0 && !captive[i] && !is_surrendered(i); }
	// G5 S4: an unconscious or surrendered living enemy can be captured (order_capture, auto-capture, progress).
	bool capture_target(int t) const { return alive(t) && !captive[t] && (ko[t] > 0.0 || is_surrendered(t)); }
	// G5 S4 native setter: on refuses a soldier that cannot surrender (dead, captive, KO, escorting, crewed); off clears it.
	bool set_surrendered(int i, bool on);
	// CAV-1. set_mounted(i, true) refuses a dead, aboard or captive soldier (no change); false clears the riding state.
	bool is_mounted(int i) const { return i >= 0 && i < (int)mounted.size() && mounted[i] != 0; }
	bool set_mounted(int i, bool on);
	bool cav_may_hit(int rider, int victim) const; // false while the rider's last hit on this victim is under 2 s old
	// Charge state of a rider (4.1) from its current velocity and heading history; the candidate test is the same one the step uses.
	bool charge_state(int i) const;
	// CAV-2 read accessors: seconds the rider has been moving straight (cav_hold) and the penetrations of the current charge.
	double charge_straight_seconds(int i) const { return i >= 0 && i < (int)cav_hold.size() ? cav_hold[i] : 0.0; }
	int64_t last_striker(int i) const { return i >= 0 && i < (int)last_striker_person.size() ? last_striker_person[i] : -1; }
	int charge_hits(int i) const { return i >= 0 && i < (int)cav_hits.size() ? (int)cav_hits[i] : 0; }
	int cav_distinct_victims(int i) const; // distinct victims in the rider's recent-victim ring (ids >= 0)
	// Modifiers of a rider charging a victim at `speed` (4.3): ability, speed bonus, flank / rear bonus, basic mount bonus
	// for the rider; pole-arm stand and rear support for the victim. Positions and facing are the current ones.
	void charge_stats(int rider, int victim, double speed, rules::ExStats &a, rules::ExStats &b) const;
	rules::ExResult charge_result(int rider, int victim, double speed) const; // the exchange result with those modifiers
	bool can_receive(int i) const { return can_act(i) && !is_aboard(i) && exch_cd[i] <= 0.000000001; }
	bool exchange_ready(int i) const;
	bool host_ranged_ready(int i,int expected_ammo,int mode,int64_t release_id,int target_x,int target_y) const;
	bool initiates(int i, bool melee) const;
	bool command_eligible(int i) const { return i >= 0 && can_act(i) && present[i] && military_role[i] == 1 && (post_holder[i] || formations[form[i]].formal_cmd == i) && !formations[form[i]].garrisoned; }
	double command_effect(int f, int kind, double cap) const; // 0 tactics, 1 leadership, 2 coach
	void apply_contact(int i, double hp_loss, double stun_add, bool environmental = false);
	void slot_world(const Formation &f, int s, int n, float &x, float &y) const;
	// CAV-4a: slot spacing and march pace of a formation (infantry: f.spacing and cfg.march_speed, unchanged)
	float slot_spacing(const Formation &f) const { return f.cav_layout ? std::max(f.spacing, cav::SLOT_SPACING) : f.spacing; }
	float march_pace(const Formation &f) const { return f.cav_layout ? cav::CRUISE : cfg.march_speed; }
	void refresh_cav_layout(Formation &f) const;
	// Faction relations (full faction id 0..255; default: every other faction is hostile). Astra review
	// 2026-09-29: never compare team parity; three or more factions and non-contiguous ids are legal.
	bool hostile(int a, int b) const { return hostile_[((size_t)(a & 255) << 8) | (size_t)(b & 255)] != 0; }
	void set_hostile(int a, int b, bool h);

private:

	struct WorkPointPool {
		WorkFatigueState source;
		double native_base_fatigue = 0, native_base_rest = 0, native_charge = 0;
		bool base_captured = false, training_start_eligible = false;
		double before_training = 0;
	};
	bool work_point_active_ = false, work_point_finish_ready_ = false;
	uint32_t work_point_begin_tick_ = 0;
	double work_point_seconds_ = 0;
	std::vector<WorkPointPool> work_point_pools_;
	std::vector<WorkFatigueState> work_point_finish_;
	std::vector<WorkTrainingState> work_point_training_;
	bool training_start_ready(int formation, double combat_left_now, bool fresh_inputs) const;
	struct WorkPointDeath {
		size_t event_index = 0;
		int formation = -1;
		int64_t person = -1;
		double native_charge = 0, before_fatigue = 0, before_rest = 0;
		double fatigue = 0, rest = 0;
	};
	std::vector<WorkPointDeath> work_point_deaths_;
	std::vector<int64_t> work_point_runners_;
	std::vector<uint8_t> work_point_run_seen_;
	void capture_work_point_runners();
	Pool pool_;
	bool finalized_ = false;
	void rebuild_buffers();
	void swap_state(World &other);
	bool load_impl(const std::vector<uint8_t> &blob, const std::vector<int> *blocked, const std::vector<int64_t> *wreck_exit);
	bool install_siege_navigation(const std::vector<int> &blocked, const std::vector<int64_t> &wreck_exit, bool invalidate_fields);
	std::vector<FlowField> fields_;
	std::vector<int> field_queue_;
	std::vector<int32_t> hash_start_, hash_items_;
	int bw_ = 0, bh_ = 0;
	std::vector<uint8_t> hostile_ = default_relations();
	static std::vector<uint8_t> default_relations();
	int faction_slot_[256];                              // faction id -> dense slot, -1 absent
	std::vector<int> slot_faction_;                      // dense slot -> faction id
	std::vector<std::vector<uint16_t>> block_count_;     // per slot: able soldiers per 8x8 block
	std::vector<std::vector<uint16_t>> enemy_block_;     // per slot: able soldiers of factions hostile to it
	void build_faction_slots();
	const uint16_t *enemy_blocks(int faction) const { return enemy_block_[faction_slot_[faction & 255]].data(); }
	std::vector<float> slot_tx_, slot_ty_, slot_clip_;
	std::vector<double> lag_acc_;
	std::vector<int> lag_cnt_;
	std::vector<uint32_t> sort_a_, sort_b_;
	int chunks_ = 0;

	struct PairOut { int a, b; rules::ExResult r; };
	struct FireReq { int shooter, target; };
	std::vector<std::vector<PairOut>> pair_buf_;
	std::vector<std::vector<FireReq>> fire_buf_;
	std::vector<uint64_t> illegal_buf_;   // per chunk: illegal cell, illegal step, wakes
	// merged outcome + the single "reaction" (terrain_lab._exchange_reaction_better): knockback first,
	// then loser > draw > winner, then larger HP loss, larger |margin|, lowest opponent person id
	struct ExAcc { double hp = 0, stun = 0, fat = 0, stag = 0; bool knock = false; bool in = false;
		int r_other = -1; bool r_knock = false; int r_rank = -1; double r_hp = 0, r_margin = 0;
		int count = 0, losses = 0, draws = 0, big_wins = 0, big_losses = 0; };
	std::vector<std::vector<int>> wake_buf_, getup_buf_; // per chunk: woke / finished get-up this step
	std::vector<ExAcc> ex_acc_;
	std::vector<int> ex_participants_;
	std::vector<int32_t> rescued_by_, capturing_by_;
	std::vector<int> rescuers_, capturers_, captives_;
	std::vector<uint8_t> held_; // captives per guard (scratch, rebuilt when auto-capture looks for guards)
	std::vector<uint8_t> flight_cells_; // cells crossed by arrows in flight (rest threat), empty when none
	void build_flight_cells();
	std::vector<std::vector<uint16_t>> idle_block_, idle_ai_block_; // per faction slot: idle HOLD members per block (rescue / capture prefilter)
	void build_idle_blocks();
	bool idle_near(const std::vector<uint16_t> &blocks, float x, float y, float r) const;
	mutable std::unordered_map<int64_t, int> person_index_;
	bool quiet_contact_ = false;
	std::vector<uint16_t> attackers_;
	uint32_t attackers_tick_ = UINT32_MAX;
	std::vector<uint8_t> touch_;

	// movement
	int request_field(int goal_cell, bool body_aware = true);
	void build_field(FlowField &f);
	void build_hash();
	void formation_stage(float dt);
	void contact_stage(int ch);
	void soldier_stage(float dt, int ch);
	void plan_captive_follow(float dt);
	void compact_slots(Formation &f);
	bool in_melee_exchange(int i) const; // G6.4: i fights in melee, is the melee target of one, or has an encircle target
	// body_blind: judge only terrain and siege bodies (convoy anchors pass true so their own body does not block them)
	bool los(float ax, float ay, float bx, float by, const std::vector<int> *rescue_domain = nullptr, bool body_blind = false) const;
	float ray_clip(float ax, float ay, float bx, float by) const;
	void resolve(float ox, float oy, float &x, float &y, float margin) const;
	int nearest_walkable(int goal_cell) const;
	void set_goal(Formation &f, float gx, float gy);

	// combat (combat.cpp)
	void timers_stage(float dt, double gdt, int ch);
	void exchange_round_run();
	void exchange_collect(int ch);
	rules::ExStats ex_stats(int i) const;
	void ranged_decide(int ch);
	void ranged_commit();
	void projectiles_advance(float dt);
	bool ranged_line_clear(rules::Cell s, rules::Cell g, std::vector<rules::Cell> &tmp) const;
	bool friendly_clear(rules::Cell s, rules::Cell g, int faction, std::vector<rules::Cell> &tmp) const;
	void rescue_stage(float dt);            // prepare_combat: rescue progress (action time) and HOLD auto-rescue
	void person_actions_stage(double gdt);  // capture start / progress and escape (game time)
	void bleed_stage(double gdt);
	void mark_combat(double d) { combat_mark = std::max(combat_mark, d); if (!external_clock) combat_left = std::max(combat_left, d); }
	void push_event(EventKind k, int soldier, int other_soldier);
	template <class Ar> void serialize(Ar &ar);
	void cancel_actions_involving(int i);
	void activate_skill(int i, uint8_t s);
	int enemy_sectors(int i) const;
	// CAV-1 (combat.cpp). cav_push / cav_detect run in the parallel soldier stage and write only their own rider's slots;
	// cav_settle runs serially after the motion and applies the outcomes in rider index order.
	void cav_push(int i, float x, float y, float &kx, float &ky) const;
	void cav_detect(int i, float x, float y, float vx_now, float vy_now);
	bool cav_hit_free(int rider, int victim) const;
	bool cav_rear_support(int victim, int rider) const;
	bool cav_clear_cell(int victim, float x, float y) const; // no other living body within reach of (x, y)
	void cav_record(int rider, int victim);
	void cav_fall(int i, double seconds);
	void cav_morale_shock(int rider, int victim); // 4.5: -3 morale on the victim's formation when a member stands within 3 cells
	bool cav_straight(int i) const; // 4.1: moving for 0.4 s and every heading of that window within HEADING_TOL of the current one
	void cav_resolve(int rider, int victim, double speed, float ux, float uy);
	void cav_settle();
	// CAV-4a helpers (crowd_core.cpp). charge_target: live target point of formation fi (followed formation centre, else the
	// fixed point). form_point: the walkable point 10 cells in front of target from the formation centre, or false.
	bool charge_target(int fi, float &tx, float &ty) const;
	bool form_point(int fi, float tx, float ty, float &fx, float &fy) const;
	bool rally_point(int fi, float tx, float ty, float &rx, float &ry) const;
	float layout_half_extent(const Formation &f) const;  // half diagonal of the slot layout (CAV-4a)
	// CAV-4a: (x, y) with a body of radius own_r stays clear of every hostile formation's body but the charge target's
	bool clear_of_enemy_bodies(int fi, float x, float y, float own_r) const;
	static int charge_line_cols(int n);                  // columns of the charge line of n riders (cav::LINE_RANKS)
	float charge_line_depth(const Formation &f) const;   // half depth of that line (centre to front rank)
	bool begin_form(int fi, float tx, float ty);  // enter CS_FORM toward the target: line abreast, spent riders cleared; false if no form-up point
	void enter_rally(int fi);                     // enter CS_RALLY: break-through layout restored, rally point, charge_runs counted

	// command / morale / fatigue (command.cpp)
	void command_stage(float dt);
	void settle_command(Formation &f, int fi);
	void refresh_presence(Formation &f);
	int select_commander(Formation &f);
	void ensure_ability(int i, Formation &f);
	void observe_life(Formation &f, int fi);   // site_controller._observe_team_life + Sustain.combat_event
	void sustain_stage(double gdt);           // morale observe, resupply, rout / rally (game time)
	bool team_threat(const Formation &f) const; // _fatigue_threat for any living, uncaptured member
	bool team_stopped(const Formation &f) const;
	void step_body(float dt, const std::vector<WorkFatigueState> *work_plan = nullptr);
	void begin_rout(Formation &f, int fi);
	void retreat_away(int fi);
	bool retreat_trapped(int i) const;          // G5 S4 terrain-trap test (command.cpp)
	void surrender_trapped(int fi);              // G5 S4: trapped members of a routed formation surrender; surrendered members are settled
	bool settle_surrender(int t, std::vector<uint8_t> &held);  // G5 S4: surrendered member becomes a captive now (command.cpp)
	int surrender_captor(int t, const std::vector<uint8_t> &held) const;  // G5 S4: nearest hostile formation's nearest able member
	bool surrender_captor_able(int g, int t) const;               // G5 S4: may take t as prisoner
	void fatigue_stage(double gdt, const std::vector<WorkFatigueState> *work_plan = nullptr);
	double fatigue_recovery_multiplier(int formation, double garrison, double housing) const;
	bool safe_fatigue_rest(int formation, bool busy, bool threat, bool fire_safe, double combat_left_now) const;
	void charge(int i, double amount);

	// G4 convoys (crowd_core.cpp)
	Convoy *convoy_at(int id);
	const Convoy *convoy_at(int id) const;
	bool convoy_reachable(int start, int goal) const;
	bool convoy_crew_aligned(const Convoy &c) const;
	void convoy_slot(const Convoy &c, const ConvoyCrew &k, float &x, float &y) const;
	void convoy_stage(float dt);
	bool convoy_steer(int i, float dt);
	// G4 S2 bodies. footprint: sorted absolute cells of c's body for an anchor and facing; false if any is off-map.
	// cells_clear: every cell walkable, not another convoy's body, and no living non-crew soldier standing on it.
	// set_cells: installs c's derived footprint into convoy_body_owner and refreshes body-aware fields when it changed.
	bool convoy_footprint(const Convoy &c, float ax, float ay, float facing, std::vector<int> &cells) const;
	bool convoy_cells_clear(const Convoy &c, const std::vector<int> &cells) const;
	bool convoy_soldier_in(const Convoy &c, const std::vector<int> &cells) const; // a living non-crew soldier stands on one of cells
	bool convoy_greedy_direction(const Convoy &c, float &dx, float &dy) const; // forward-edge fallback when no field direction exists
	void set_convoy_cells(Convoy &c, std::vector<int> cells);
	bool rebuild_convoy_bodies();   // load: re-derive every footprint and the owner map; false if they do not fit
	void refresh_body_fields();     // body-aware fields are cleared and re-queued; LOS observations are reset
	// G4 formation following (OPUS)
	enum FollowCheck : int { FOLLOW_CLEAR = 0, FOLLOW_YIELD, FOLLOW_BODY, FOLLOW_TERRAIN, FOLLOW_SOLDIER };
	void convoy_plan_formation(int formation);
	bool convoy_build_route(Convoy &c, const std::vector<uint8_t> &walls, int formation);
	bool convoy_route_valid(const Convoy &c, int q, int cell, const std::vector<uint8_t> &walls) const;
	std::vector<uint8_t> convoy_route_walls(const Convoy &c) const;
	int convoy_team(const Convoy &c) const;
	bool convoy_person_yields(int i, int my_team) const;
	void convoy_mark_fixed_people(int my_team, std::vector<uint8_t> &walls) const;
	int convoy_follow_check(const Convoy &c, float ax, float ay, float facing, std::vector<int> &cells, std::vector<int> &claim) const;
	int convoy_follow_cells(const Convoy &c, const std::vector<int> &cells, const std::vector<int> &crew, std::vector<int> &claim) const;
	bool convoy_pose_cells(const Convoy &c, float ax, float ay, float facing, std::vector<int> &cells, std::vector<int> &crew) const;
	void convoy_post_claim(Convoy &c, const std::vector<int> &cells);
	void convoy_release_claim(Convoy &c);
	void convoy_follow_stage(Convoy &c, float dt);
	void convoy_invalidate_plans();
	void reslot_formation(Formation &f);
	bool convoy_evacuation(int i, float &dvx, float &dvy) const;

	// ai (ai.cpp)
	void ai_review();
	void encircle_review(Formation &f, int fi);
	void refresh_attackers();
	void issue(Formation &f, int fi, Order o, float gx, float gy, int target);
	friend struct AIContext;
	friend struct WorldTestAccess;
};

} // namespace wg
