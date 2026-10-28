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
enum class Order : uint8_t { HOLD = 0, MOVE = 1, ATTACK = 2, PURSUE = 3, RETREAT = 4, RETURN = 5 };
enum OrderResult : int { OK = 0, NOT_OWNER, BAD_FORMATION, BAD_ARGS, NO_TARGET, BLOCKED, NOT_ROUTED, ROUTED, NO_ORDERS };
enum Troop : uint8_t { T_MELEE = 0, T_BOW = 1, T_CROSSBOW = 2 };
enum Role : uint8_t { R_REGULAR = 0, R_CAPTAIN = 1, R_OFFICER = 2 };
// presentation / diagnostic state (derived every step, never read back as authority)
enum SState : uint8_t { S_SLOT = 0, S_ENGAGE, S_FIGHT, S_ENCIRCLE, S_RANGED, S_RESCUE, S_CAPTURE, S_DOWN, S_DEAD, S_CAPTIVE,
	S_GETUP, S_STAGGER, S_FLEE, S_KNOCK, S_HOST };
enum AIStatus : uint8_t { AI_NONE = 0, AI_NO_COMMAND, AI_ROUTED, AI_RETURNING, AI_IDLE, AI_RECOVER, AI_OUTMATCHED, AI_PURSUE,
	AI_ENGAGE, AI_APPROACH, AI_WAIT_PATH };

struct CommandAbility { int16_t tactics = -1, leadership = -1, coach = -1; bool has() const { return tactics >= 0; } };

struct Formation {
	int team = 0;
	Troop troop = T_MELEE;
	Order order = Order::HOLD;
	float cx = 0, cy = 0, facing = 0;
	float goal_x = 0, goal_y = 0, goal_facing = 0;
	int cols = 10;
	float spacing = 1.0f;
	int field = -1;
	bool arrived = true, los_goal = false;
	float lag = 0;
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

class World {
public:
	Config cfg;
	Terrain terrain;
	std::vector<Formation> formations;

	// ---- soldier SoA (hot)
	std::vector<float> px, py, nx, ny, vx, vy, face, anim_t;
	std::vector<double> hp, stun, grace, ko, getup, stagger, exch_cd, ranged_cd, skill_cd, knock_t, act_t, escape_t;
	std::vector<float> knock_dx, knock_dy;
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
	bool siege_compound_valid(const SiegeCompound &group, const Terrain &ground) const;
	void abort_siege_compound(int index);
	void advance_siege_compounds(float dt);
	bool move_siege_member(int person, float dt);
	bool set_siege_navigation(const std::vector<int> &blocked, const std::vector<int64_t> &exits);
	bool siege_route_cell(int cell) const { return cell >= 0 && cell < (int)terrain.height.size() && (siege_person_blocked.empty() || !siege_person_blocked[cell]); }
	bool siege_person_cell(int person, int from, int to) const;
	void resolve_siege_person(int person, float old_x, float old_y, float &x, float &y) const;
	bool is_siege_crew(int person) const { return person >= 0 && person < (int)siege_crew.size() && siege_crew[person] != 0; }
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
	bool set_military_role(int i, int value);
	bool set_post_holder(int i, int value);
	bool apply_training_state(int f, double before_training, double before_fatigue, double before_rest,
	                          double training, double fatigue, double rest, bool worked);
	FormationState get_formation_state(int f) const;
	// single decision owner: an AI-owned formation (ai_enabled) refuses host orders and vice versa
	int host_order(int f, int kind, float gx, float gy, double x);
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
	bool charge_siege_round(const std::vector<int> &members, double per_person);
	bool charge_siege_work(int person, double game_seconds);
	void contact_pose(int i, int movement, int &slot, double &age) const;
	bool charge_custody_work(int i, double seconds);
	bool begin_structure_strike(int i, int target_cell);
	bool host_may_order(int f) const { return f >= 0 && f < (int)formations.size() && !formations[f].ai_enabled; }
	// complete save / load (same build): everything that feeds the next step
	std::vector<uint8_t> save() const;
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
	uint64_t state_hash() const;
	bool update_terrain(Terrain ground);
	std::vector<uint8_t> terrain_state() const;
	std::vector<uint8_t> occupancy_mask(const std::vector<int64_t> &ignored) const;
	void measure();
	int soldier_count() const { return (int)px.size(); }

	// rule queries (public for tests)
	bool alive(int i) const { return hp[i] > 0.0 && !released[i]; } // a released soldier is out of every system
	bool can_act(int i) const { return alive(i) && ko[i] <= 0.0 && getup[i] <= 0.0 && !captive[i]; }
	bool can_receive(int i) const { return can_act(i) && exch_cd[i] <= 0.000000001; }
	bool exchange_ready(int i) const;
	bool host_ranged_ready(int i,int expected_ammo,int mode,int64_t release_id,int target_x,int target_y) const;
	bool initiates(int i, bool melee) const;
	bool command_eligible(int i) const { return i >= 0 && can_act(i) && present[i] && military_role[i] == 1 && (post_holder[i] || formations[form[i]].formal_cmd == i) && !formations[form[i]].garrisoned; }
	double command_effect(int f, int kind, double cap) const; // 0 tactics, 1 leadership, 2 coach
	void apply_contact(int i, double hp_loss, double stun_add, bool environmental = false);
	void slot_world(const Formation &f, int s, int n, float &x, float &y) const;
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
	int request_field(int goal_cell);
	void build_field(FlowField &f);
	void build_hash();
	void formation_stage(float dt);
	void contact_stage(int ch);
	void soldier_stage(float dt, int ch);
	void compact_slots(Formation &f);
	bool in_melee_exchange(int i) const; // G6.4: i fights in melee, is the melee target of one, or has an encircle target
	bool los(float ax, float ay, float bx, float by, const std::vector<int> *rescue_domain = nullptr) const;
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
	void fatigue_stage(double gdt, const std::vector<WorkFatigueState> *work_plan = nullptr);
	double fatigue_recovery_multiplier(int formation, double garrison, double housing) const;
	bool safe_fatigue_rest(int formation, bool busy, bool threat, bool fire_safe, double combat_left_now) const;
	void charge(int i, double amount);

	// ai (ai.cpp)
	void ai_review();
	void encircle_review(Formation &f, int fi);
	void refresh_attackers();
	void issue(Formation &f, int fi, Order o, float gx, float gy, int target);
	friend struct AIContext;
	friend struct WorldTestAccess;
};

} // namespace wg
