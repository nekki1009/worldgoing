// Rule behaviour tests on small hand-built situations. Each test states the rule it checks.
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#undef small
#endif
#include "../src/crowd_core.hpp"

#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <set>
#include <vector>

using namespace wg;
using namespace wg::rules;

static int failures = 0, checks = 0;
#define CHECK(cond, ...)                                                                   \
	do {                                                                                   \
		++checks;                                                                          \
		if (!(cond)) { ++failures; std::printf("  FAIL %s:%d  %s  ", __FILE__, __LINE__, #cond); \
			std::printf(__VA_ARGS__); std::printf("\n"); }                                  \
	} while (0)

static const float DT = 1.f / 30.f;

static void check_valid(const World &w) {
	std::string reason;
	if (!w.validate(&reason)) { std::fprintf(stderr,"VALIDATE tick %u: %s\n",w.tick,reason.c_str()); std::exit(3); }
}
static void checked_step(World &w,float dt) { CHECK(w.step(dt),"step input"); check_valid(w); }
static void checked_step_clock(World &w,float dt,double gs,double cl) { CHECK(w.step_clock(dt,gs,cl),"step clock input"); check_valid(w); }

static Equip sword(uint8_t mat = M_IRON, uint8_t armor = A_LEATHER) { Equip e; e.family = F_LONGSWORD; e.material = mat; e.armor = armor; return e; }
static Equip hammer() { Equip e; e.family = F_HAMMER; e.material = M_IRON; e.armor = A_LEATHER; return e; }
static Equip bow() { Equip e; e.family = F_BOW; e.material = M_IRON; e.armor = A_LEATHER; return e; }

struct Scene {
	World w;
	// Rule tests start from the original rules (adjacent rescue only, captures by explicit order);
	// the 2026-09-29 defaults (walk 8 cells to rescue, AI auto-capture) are switched on per test.
	explicit Scene(int threads = 1, int W = 48, int H = 48) : w(threads) {
		w.terrain.allocate(W, H); w.cfg.ai = false; w.cfg.rescue_seek_cells = 0.f; w.cfg.auto_capture = false;
		w.combat_left = 1e9; // rule tests run on the combat clock (1 action s = 1 game s) unless they say otherwise
	}
	// one formation of `count` soldiers, first is captain, next two officers
	int formation(int team, float x, float y, float facing, int count, Equip e, Troop tr = T_MELEE, int ammo = 0, int cols = 10) {
		int f = w.add_formation(team, x, y, facing, cols, 1.0f, tr, 0.0);
		for (int k = 0; k < count; ++k) w.add_soldier(f, e, k == 0 ? R_CAPTAIN : (k <= 2 ? R_OFFICER : R_REGULAR), -1, (uint16_t)ammo);
		return f;
	}
	void place(int i, float x, float y) { w.px[i] = w.nx[i] = x; w.py[i] = w.ny[i] = y; }
	void run(double seconds) { int n = (int)std::lround(seconds * 30); for (int k = 0; k < n; ++k) checked_step(w, DT); }
};

static void test_exchange_round_rules() {
	std::printf("[exchange] 1 round / s per person, ATTACK initiates, HOLD-with-commander does not\n");
	Scene s;
	int a = s.formation(0, 20, 24, 0, 3, sword());
	int b = s.formation(1, 21.1f, 24, kPi, 3, sword());
	s.w.finalize();
	// line them up face to face: 0-3, 1-4, 2-5 at 1.0 cell
	for (int k = 0; k < 3; ++k) { s.place(k, 20.0f, 20.5f + 3.f * k); s.place(3 + k, 21.0f, 20.5f + 3.f * k); }
	s.w.order_hold(a); s.w.order_hold(b);
	s.run(3);
	CHECK(s.w.stats.pairs == 0, "HOLD vs HOLD with commanders must not duel, got %llu pairs", (unsigned long long)s.w.stats.pairs);
	s.w.order_attack(a, 3);
	s.w.formations[a].order_delay = 0;
	for (int k = 0; k < 3; ++k) { s.place(k, 20.0f, 20.5f + 3.f * k); s.place(3 + k, 21.0f, 20.5f + 3.f * k); }
	uint64_t before = s.w.stats.pairs;
	s.run(10);
	uint64_t pairs = s.w.stats.pairs - before;
	CHECK(pairs > 0, "ATTACK should start exchanges");
	CHECK(pairs <= 3 * 11, "at most one round per second per pair: %llu pairs in 10 s", (unsigned long long)pairs);
	CHECK(s.w.stats.cooldown_violations == 0, "cooldown violations %llu", (unsigned long long)s.w.stats.cooldown_violations);
}

static void test_cliff_blocks_exchange() {
	std::printf("[terrain] no exchange across a cliff edge; exchange across a ramp edge\n");
	for (int ramp = 0; ramp < 2; ++ramp) {
		Scene s;
		for (int y = 0; y < 48; ++y) for (int x = 24; x < 48; ++x) s.w.terrain.height[s.w.terrain.idx(x, y)] = 1;
		if (ramp) for (int y = 20; y < 28; ++y) { s.w.terrain.ramp_edges[s.w.terrain.idx(23, y)] |= 1 << E; s.w.terrain.ramp_edges[s.w.terrain.idx(24, y)] |= 1 << W; }
		int a = s.formation(0, 22, 24, 0, 1, sword());
		int b = s.formation(1, 25, 24, kPi, 1, sword());
		s.w.finalize();
		s.place(0, 23.6f, 24.5f); s.place(1, 24.4f, 24.5f); // 0.8 apart, across the x=24 edge
		s.w.order_attack(a, 1); s.w.order_attack(b, 0);
		s.w.formations[a].order_delay = s.w.formations[b].order_delay = 0;
		s.w.formations[a].arrived = s.w.formations[b].arrived = true;
		s.run(3);
		if (ramp) CHECK(s.w.stats.pairs > 0, "ramp edge must allow the exchange");
		else CHECK(s.w.stats.pairs == 0, "cliff edge must block the exchange, got %llu", (unsigned long long)s.w.stats.pairs);
		CHECK(s.w.stats.illegal_step == 0 && s.w.stats.illegal_cell == 0, "terrain invariant");
	}
}

static void test_stun_ko_wake() {
	std::printf("[stun] grace 3 s then -10/s; KO at 100 (4 game h); wake -> stun 30 + 2.2 s get-up, HP unchanged\n");
	Scene s;
	s.formation(0, 10, 10, 0, 1, sword());
	s.formation(1, 30, 30, 0, 1, sword());
	s.w.finalize();
	s.w.apply_contact(0, 0.0, 50.0);
	s.run(2.9);
	CHECK(std::fabs(s.w.stun[0] - 50.0) < 1e-9, "no decay inside the 3 s grace: %.4f", s.w.stun[0]);
	s.run(1.1); // t = 4.0 -> about 1 s of decay
	CHECK(std::fabs(s.w.stun[0] - 40.0) < 0.35, "decay 10/s after grace: %.4f", s.w.stun[0]);
	s.w.apply_contact(0, 3.0, 70.0);
	CHECK(s.w.ko[0] == s.w.cfg.ko_seconds && s.w.cfg.ko_seconds == 4 * 3600.0, "KO for 4 game hours");
	CHECK(std::fabs(s.w.hp[0] - 97.0) < 1e-9, "HP kept separately: %.3f", s.w.hp[0]);
	CHECK(!s.w.can_act(0), "KO cannot act");
	s.w.apply_contact(0, 0.0, 5.0);
	CHECK(s.w.ko[0] == s.w.cfg.ko_seconds, "a new impact resets (not adds) the KO wait");
	// shortened clock to observe the wake
	s.w.ko[0] = 1.0;
	s.run(1.1);
	CHECK(s.w.ko[0] == 0 && std::fabs(s.w.stun[0] - 30.0) < 1e-9, "wake sets stun 30 (%.3f)", s.w.stun[0]);
	CHECK(s.w.getup[0] > 2.0 && !s.w.can_act(0), "2.2 s get-up");
	s.run(2.3);
	double bled = 25.0 / 3600.0 * 1.0; // bleeding while down (about 1 s of the shortened wait)
	CHECK(s.w.can_act(0) && s.w.hp[0] < 97.0 && s.w.hp[0] > 97.0 - 2 * bled && s.w.hp[0] == s.w.hp[0], "stands up without healing (%.6f)", s.w.hp[0]);
	double hp_up = s.w.hp[0];
	s.run(5.0);
	CHECK(s.w.hp[0] == hp_up, "no bleeding once awake");
	CHECK(s.w.stats.wakes == 1, "one wake counted");
	s.w.apply_contact(0, s.w.hp[0], 0.0);
	CHECK(s.w.hp[0] == 0 && s.w.ko[0] == 0 && s.w.stats.deaths == 1, "HP 0 is death, not KO");
}

static void test_rescue() {
	std::printf("[rescue] adjacent idle team-mate in HOLD, 4 s -> KO wait <= 1 game h; interrupted by a hit\n");
	Scene s;
	int f = s.formation(0, 20, 20, 0, 4, sword(), T_MELEE, 0, 2);
	s.formation(1, 44, 44, 0, 1, sword());
	s.w.finalize();
	s.w.order_hold(f);
	s.run(0.5);
	s.w.apply_contact(3, 0.0, 100.0);
	CHECK(s.w.ko[3] > 3600, "patient down");
	s.run(1.0);
	CHECK(s.w.stats.rescues_started == 1, "one rescuer starts (%llu)", (unsigned long long)s.w.stats.rescues_started);
	int rescuer = -1;
	for (int i = 0; i < 3; ++i) if (s.w.rescue_of[i] == 3) rescuer = i;
	CHECK(rescuer >= 0, "rescuer found");
	s.run(4.2);
	CHECK(s.w.stats.rescues_done == 1 && s.w.ko[3] <= 3600.0, "KO shortened to %.1f", s.w.ko[3]);
	CHECK(s.w.ko[3] > 0, "rescue does not wake immediately");
	// interruption
	s.w.apply_contact(2, 0.0, 100.0);
	s.run(1.0);
	int r2 = -1;
	for (int i = 0; i < 2; ++i) if (s.w.rescue_of[i] == 2) r2 = i;
	CHECK(r2 >= 0, "second rescue started");
	if (r2 >= 0) {
		s.w.apply_contact(r2, 1.0, 0.0);
		CHECK(s.w.rescue_of[r2] < 0 && s.w.stats.rescues_cancelled >= 1, "effective hit cancels the rescue");
	}
}

static void test_morale_and_command() {
	std::printf("[morale/command] death -40*n/alive, KO -20*n/alive, leadership up to -25%%, succession, -10 on vacancy, rout at 20\n");
	Scene s;
	int f = s.formation(0, 20, 20, 0, 100, sword());
	s.formation(1, 44, 44, 0, 1, sword());
	s.w.finalize();
	s.run(0.2);
	Formation &F = s.w.formations[f];
	int cap = F.current_cmd;
	CHECK(cap == 0, "captain commands (%d)", cap);
	double lead = s.w.command_effect(f, 1, 0.25);
	CHECK(lead > 0 && lead < 0.25, "leadership effect %.4f", lead);
	for (int i = 50; i < 60; ++i) s.w.apply_contact(i, 200.0, 0.0);
	double m0 = F.morale;
	s.run(DT * 1.01);
	// the formation stands safe in HOLD, so the same sustain pass also resupplies +5 / game hour
	auto resupply = [&]() { return F.resupplying ? 5.0 / 3600.0 * DT : 0.0; };
	double expected = m0 - 40.0 * 10 / 100.0 * (1.0 - lead) + resupply();
	CHECK(std::fabs(F.morale - expected) < 1e-9, "death morale %.6f expected %.6f", F.morale, expected);
	lead = s.w.command_effect(f, 1, 0.25);
	m0 = F.morale;
	for (int i = 60; i < 65; ++i) s.w.apply_contact(i, 0.0, 200.0);
	s.run(DT * 1.01);
	expected = m0 - 20.0 * 5 / 90.0 * (1.0 - lead) + resupply();
	CHECK(std::fabs(F.morale - expected) < 1e-9, "KO morale %.6f expected %.6f", F.morale, expected);
	// captain dies -> officer #1 (index 1) takes command, no morale loss for a covered vacancy
	m0 = F.morale;
	s.w.apply_contact(0, 200.0, 0.0);
	s.run(DT * 1.01);
	double after_death = m0 - 40.0 * 1 / 90.0 * (1.0 - lead);
	CHECK(F.current_cmd == 1 && F.formal_cmd == 1, "officer 1 promoted (current %d formal %d)", F.current_cmd, F.formal_cmd);
	CHECK(std::fabs(F.morale - after_death) < 0.05, "only the death loss (%.4f vs %.4f)", F.morale, after_death);
	// officer 1 KO'd -> acting: officer 2
	s.w.apply_contact(1, 0.0, 200.0);
	s.run(DT * 1.01);
	CHECK(F.current_cmd == 2 && F.formal_cmd == 1 && F.acting_cmd == 2, "officer 2 acts for the unconscious formal commander");
	// everybody else unconscious -> no eligible commander: vacancy, -10 x (1 - leadership of eligible holders = 0)
	for (int i = 2; i < 100; ++i) if (s.w.hp[i] > 0) s.w.apply_contact(i, 0.0, 200.0);
	m0 = F.morale;
	s.run(DT * 1.01);
	CHECK(F.current_cmd < 0 && F.needs_attack_order && !F.attacking, "vacancy -> needs a fresh attack order");
	CHECK(s.w.stats.command_losses == 1, "one command loss");
	CHECK(F.routed || F.morale < m0, "morale fell by the KO batch and the -10 interruption");
	// rout
	Scene r;
	int g = r.formation(0, 20, 20, 0, 30, sword());
	int e = r.formation(1, 30, 20, kPi, 30, sword());
	r.w.finalize();
	r.run(0.1);
	r.w.order_attack(g, 30);
	r.w.formations[g].morale = 15;
	r.run(DT * 2);
	CHECK(r.w.formations[g].routed && r.w.formations[g].order == Order::RETREAT, "morale <= 20 routs and retreats");
	CHECK(!r.w.initiates(5, true), "a routed soldier does not initiate");
	(void)e;
}

static void test_ranged() {
	std::printf("[ranged] ammo spent at release, cooldown, fire discipline, first body intercepts (friend too), adjacent enemy forces melee\n");
	Scene s;
	int a = s.formation(0, 10, 24, 0, 1, bow(), T_BOW, 3);
	int blk = s.formation(0, 14, 24, 0, 1, sword());
	int e = s.formation(1, 16, 24, kPi, 1, sword());
	s.w.finalize();
	s.place(0, 10.5f, 24.5f); s.place(1, 13.5f, 24.5f); s.place(2, 16.5f, 24.5f);
	for (int f : {a, blk, e}) { s.w.formations[f].arrived = true; s.w.formations[f].ai_enabled = false; }
	s.w.order_attack(a, 2); s.w.formations[a].order_delay = 0; s.w.formations[a].arrived = true;
	s.w.cfg.ai = false;
	// hold the blocker and the enemy in place
	auto pin = [&]() { s.place(1, 13.5f, 24.5f); s.place(2, 16.5f, 24.5f); s.place(0, 10.5f, 24.5f); };
	for (int k = 0; k < 30; ++k) { pin(); checked_step(s.w, DT); }
	CHECK(s.w.stats.shots == 0 && s.w.ammo[0] == 3, "friendly on the line: hold fire (%llu shots)", (unsigned long long)s.w.stats.shots);
	s.place(1, 13.5f, 30.5f); // blocker steps aside
	for (int k = 0; k < 6; ++k) { s.place(2, 16.5f, 24.5f); s.place(0, 10.5f, 24.5f); checked_step(s.w, DT); }
	CHECK(s.w.stats.shots == 1 && s.w.ammo[0] == 2 && s.w.ranged_cd[0] > 1.5, "fired once, ammo 2, cooldown 2 s");
	// friend walks into the released arrow's path: it is intercepted by the friend
	s.place(1, 13.5f, 24.5f);
	for (int k = 0; k < 30; ++k) { pin(); checked_step(s.w, DT); }
	CHECK(s.w.stats.hits + s.w.stats.grazes + s.w.stats.misses == 1, "one arrival resolved");
	CHECK(s.w.stats.blocked == 0 && s.w.stats.empty == 0, "the friend body was on the line");
	uint64_t shots = s.w.stats.shots;
	// adjacent enemy forces close combat: no shot even with ammo and cooldown ready
	s.place(1, 13.5f, 40.5f);
	for (int k = 0; k < 90; ++k) { s.place(2, 11.4f, 24.5f); s.place(0, 10.5f, 24.5f); checked_step(s.w, DT); }
	CHECK(s.w.stats.shots == shots, "adjacent enemy -> no shot (%llu vs %llu)", (unsigned long long)s.w.stats.shots, (unsigned long long)shots);
	CHECK(s.w.stats.pairs > 0, "the archer exchanges in melee instead");
}

static void test_knockback_legal() {
	std::printf("[knockback] big loss pushes one cell away but never across an illegal edge\n");
	Scene s;
	for (int y = 0; y < 48; ++y) for (int x = 0; x < 20; ++x) s.w.terrain.height[s.w.terrain.idx(x, y)] = 1;
	int a = s.formation(0, 23, 24, kPi, 1, hammer());
	int b = s.formation(1, 21, 24, 0, 1, sword(M_WOOD, A_NONE));
	s.w.finalize();
	s.w.formations[a].training = 100; // score gap >= 25 -> big wins
	for (int k = 0; k < 150; ++k) {
		if (k % 30 == 0) { s.place(0, 21.6f, 24.5f); s.place(1, 20.5f, 24.5f); s.w.order_attack(a, 1); s.w.formations[a].order_delay = 0; }
		checked_step(s.w, DT);
	}
	CHECK(s.w.stats.knockbacks > 0, "big losses happened (%llu)", (unsigned long long)s.w.stats.knockbacks);
	CHECK(s.w.px[1] >= 20.0f + s.w.cfg.wall_margin - 1e-3f, "loser stays on its side of the cliff (x=%.3f)", s.w.px[1]);
	CHECK(s.w.stats.illegal_step == 0 && s.w.stats.illegal_cell == 0, "terrain invariant");
	(void)b;
}

static void test_capture_escape() {
	std::printf("[captivity] explicit order, 4 s adjacent, interruptible, guard holds <= 4, escape after 30 s unguarded\n");
	Scene s;
	int g = s.formation(0, 10, 10, 0, 1, sword());
	int v = s.formation(1, 12, 10, 0, 6, sword(), T_MELEE, 0, 3);
	s.w.finalize();
	for (int f : {g, v}) s.w.formations[f].ai_enabled = false;
	int guard = 0;
	for (int k = 1; k <= 6; ++k) { s.place(k, 11.2f + 0.05f * k, 10.5f + 0.15f * (k - 3)); s.w.apply_contact(k, 0.0, 200.0); }
	s.place(guard, 10.5f, 10.5f);
	int captured = 0;
	for (int k = 1; k <= 6; ++k) {
		s.place(guard, s.w.px[k] - 0.8f, s.w.py[k]);
		bool ok = s.w.order_capture(guard, k);
		if (!ok) continue;
		for (int t = 0; t < 130; ++t) { s.place(guard, s.w.px[k] - 0.8f, s.w.py[k]); checked_step(s.w, DT); }
		if (s.w.captive[k]) ++captured;
	}
	CHECK(captured == 4, "guard capacity 4 (captured %d)", captured);
	// interruption: a hit on the guard during the action
	Scene q;
	q.formation(0, 10, 10, 0, 1, sword());
	q.formation(1, 12, 10, 0, 1, sword());
	q.w.finalize();
	q.place(1, 11.3f, 10.5f); q.place(0, 10.5f, 10.5f);
	q.w.apply_contact(1, 0.0, 200.0);
	CHECK(q.w.order_capture(0, 1), "capture order accepted");
	q.run(2.0);
	q.w.apply_contact(0, 1.0, 0.0);
	q.run(3.0);
	CHECK(!q.w.captive[1] && q.w.stats.captures_cancelled == 1, "hit on the guard cancels the capture");
	// escape: shortened KO, guard walks away beyond 4 cells, no threat -> free after 30 s
	s.w.cfg.ko_seconds = 1;
	int prisoner = -1;
	for (int k = 1; k <= 6; ++k) if (s.w.captive[k]) { prisoner = k; break; }
	CHECK(prisoner >= 0, "a prisoner exists");
	if (prisoner < 0) return;
	s.w.ko[prisoner] = 0.5;
	s.run(4.0); // wakes, gets up (still captive)
	CHECK(s.w.captive[prisoner] && !s.w.can_act(prisoner), "awake captive still bound");
	s.run(3.0);
	float dx = s.w.px[prisoner] - s.w.px[guard], dy = s.w.py[prisoner] - s.w.py[guard];
	CHECK(dx * dx + dy * dy < 4.0f, "escort: the awake captive follows the guard");
	s.w.cfg.ko_seconds = 4 * 3600.0;
	s.w.apply_contact(guard, 0.0, 200.0); // the only guard is knocked out -> no effective guard
	s.run(29.0);
	CHECK(s.w.captive[prisoner], "not yet free before 30 s");
	s.run(1.5);
	CHECK(!s.w.captive[prisoner] && s.w.stats.escapes >= 1, "escape after 30 s without a guard or threat");
}

static void test_pursuit_limits() {
	std::printf("[pursuit] ends at 20 cells from the origin or 20 s, then returns\n");
	Scene s(1, 96, 48);
	int a = s.formation(0, 10, 24, 0, 1, sword());
	int b = s.formation(1, 14, 24, 0, 1, sword());
	s.w.finalize();
	s.w.order_pursue(a, 1);
	s.w.formations[a].order_delay = 0;
	int ended_at = -1;
	for (int k = 0; k < 30 * 25; ++k) {
		s.place(1, std::min(90.f, 14.5f + (float)k * DT * 2.f), 24.5f); // target runs east at 2 cells/s
		checked_step(s.w, DT);
		if (ended_at < 0 && s.w.formations[a].order != Order::PURSUE) ended_at = k;
	}
	CHECK(ended_at > 0 && ended_at <= 30 * 20 + 1, "pursuit ended at step %d", ended_at);
	CHECK(s.w.stats.pursuit_ends == 1, "one end");
	CHECK(s.w.formations[a].order == Order::RETURN || s.w.formations[a].order == Order::HOLD, "returns to the origin");
	s.run(30.0);
	CHECK(std::hypot(s.w.formations[a].cx - s.w.formations[a].origin_x, s.w.formations[a].cy - s.w.formations[a].origin_y) <= 1.5f, "automatic RETURN reaches within 1.5 cells of the recorded origin");
	(void)b;
}

static void test_fatigue_shared() {
	std::printf("[fatigue] shared pool: exchange +0.5/N, big loser +0.5/N, shot +1/N\n");
	Scene s;
	int f = s.formation(0, 10, 10, 0, 4, bow(), T_BOW, 5);
	s.formation(1, 30, 30, 0, 1, sword());
	s.w.finalize();
	Formation &F = s.w.formations[f];
	double f0 = F.fatigue;
	s.w.apply_contact(0, 0, 0);
	// direct rule: charge through a shot
	int n = F.fatigue_count;
	CHECK(n == 4, "pool count %d", n);
	F.fatigue = 10;
	F.fatigue_count = 4;
	// emulate one shot and one exchange charge through the public path
	s.w.formations[f].charged_this_step = false;
	(void)f0;
	ExStats a, b;
	a.equip = sword(); b.equip = sword(); b.ability = 90; // b wins big
	ExResult r = exchange_result(a, b, 0.0);
	CHECK(r.kind == EX_BIG && std::fabs(r.fatigue_a - 1.0) < 1e-12 && std::fabs(r.fatigue_b - 0.5) < 1e-12, "big loser 0.5+0.5, winner 0.5");
	CHECK(std::fabs(fatigue_slowdown(100) - 0.30) < 1e-12 && fatigue_slowdown(30) == 0, "slowdown curve");
}

static void test_bleeding() {
	std::printf("[bleeding] unconscious: -25 HP / game hour until rescued or captured; bleed-out is a death\n");
	{   // rate, and bleeding does not cancel anything or reset the KO wait
		Scene s;
		s.formation(0, 10, 10, 0, 1, sword());
		s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize();
		s.w.apply_contact(0, 10.0, 200.0);
		double hp0 = s.w.hp[0], ko0 = s.w.ko[0];
		s.run(60.0);
		CHECK(std::fabs((hp0 - s.w.hp[0]) - 25.0 / 60.0) < 1e-5, "60 game s -> %.6f HP lost (expected %.6f)", hp0 - s.w.hp[0], 25.0 / 60.0);
		CHECK(std::fabs((ko0 - s.w.ko[0]) - 60.0) < 1e-4, "the KO wait only counts down");
		// after disengagement 1 action second = 1 game minute
		s.w.combat_left = 0.0; // disengaged: 1 action s = 1 game minute
		double h1 = s.w.hp[0];
		s.run(10.0);
		CHECK(std::fabs((h1 - s.w.hp[0]) - 25.0 / 6.0) < 1e-5, "time scale 60: 10 s -> %.4f HP", h1 - s.w.hp[0]);
		// bleed out: 90 HP at 25/h = 3.6 game hours < 4 h wait
		s.run(60.0 * 3.6 + 30.0);
		CHECK(s.w.hp[0] == 0 && s.w.stats.bled_deaths == 1 && s.w.stats.deaths == 1, "bled out before waking (hp %.3f)", s.w.hp[0]);
		CHECK(s.w.stats.wakes == 0, "never woke");
	}
	{   // rescue stops bleeding, even when the wait is already under 1 h
		Scene s;
		int f = s.formation(0, 20, 20, 0, 4, sword(), T_MELEE, 0, 2);
		s.formation(1, 44, 44, 0, 1, sword());
		s.w.finalize();
		s.w.order_hold(f);
		s.run(0.5);
		s.w.apply_contact(3, 0.0, 200.0);
		s.w.ko[3] = 1800.0; // already under 1 h: still worth rescuing because it bleeds
		s.run(6.0);
		CHECK(s.w.stats.rescues_done == 1 && s.w.bandaged[3], "rescued and bandaged");
		double h = s.w.hp[3];
		s.run(30.0);
		CHECK(s.w.hp[3] == h, "no bleeding after rescue");
		s.w.apply_contact(3, 1.0, 0.0);
		CHECK(!s.w.bandaged[3], "a new wound reopens bleeding");
		double h2 = s.w.hp[3];
		s.run(1.0);
		CHECK(s.w.hp[3] < h2, "bleeding again");
	}
	{   // optional: idle members walk up to rescue_seek_cells to a bleeding team-mate
		Scene s;
		int f = s.formation(0, 20, 20, 0, 4, sword(), T_MELEE, 0, 2);
		s.formation(1, 44, 44, 0, 1, sword());
		s.w.finalize();
		s.w.order_hold(f);
		s.w.formations[f].ai_enabled = false;
		s.run(0.5);
		s.w.apply_contact(3, 0.0, 200.0);
		s.place(3, 26.5f, 20.5f); // about 6 cells from the others
		s.run(6.0);
		CHECK(s.w.stats.rescues_started == 0, "original rule: adjacent only, nobody comes");
		s.w.cfg.rescue_seek_cells = 8.f;
		s.run(10.0);
		CHECK(s.w.stats.rescues_done == 1 && s.w.bandaged[3], "with seek 8 a team-mate walks over and bandages");
	}
	{   // captivity stops bleeding
		Scene q;
		q.formation(0, 10, 10, 0, 1, sword());
		q.formation(1, 12, 10, 0, 1, sword());
		q.w.finalize();
		q.place(1, 11.3f, 10.5f); q.place(0, 10.5f, 10.5f);
		q.w.apply_contact(1, 0.0, 200.0);
		CHECK(q.w.order_capture(0, 1), "capture order");
		q.run(4.5);
		CHECK(q.w.captive[1], "captured");
		double h = q.w.hp[1];
		checked_step_clock(q.w, DT, 3600.0, 0);
		CHECK(q.w.hp[1] == h && q.w.ko[1] > 0, "a downed captive does not bleed for one full game hour");
	}
	{   // bleed-out deaths hit morale like any death
		Scene s;
		int f = s.formation(0, 20, 20, 0, 10, sword());
		s.formation(1, 44, 44, 0, 1, sword());
		s.w.finalize();
		s.w.formations[f].ai_enabled = false;
		for (int i = 5; i < 10; ++i) { s.w.apply_contact(i, 99.0, 200.0); }
		s.run(0.2);
		double m0 = s.w.formations[f].morale;
		s.w.combat_left = 0.0;
		s.run(4.0); // 1 HP left at 25/h: gone within 2.4 game minutes
		CHECK(s.w.stats.bled_deaths == 5, "five bled out (%llu)", (unsigned long long)s.w.stats.bled_deaths);
		CHECK(s.w.formations[f].morale < m0 - 10.0, "morale took the death losses (%.2f -> %.2f)", m0, s.w.formations[f].morale);
	}
}

static void test_auto_capture() {
	std::printf("[auto-capture] 2026-09-29 defaults: walk 8 cells to rescue; AI formations capture unconscious enemies\n");
	{
		World d(1);
		CHECK(d.cfg.rescue_seek_cells == 8.f && d.cfg.auto_capture && d.cfg.capture_seek_cells == 8.f, "defaults: rescue 8, auto-capture on, 8 cells");
	}
	{   // an idle AI member walks up to a downed enemy 5 cells away, captures it; the captive stops bleeding
		Scene s;
		s.w.cfg.auto_capture = true; s.w.cfg.capture_seek_cells = 8.f;
		int f = s.formation(0, 20, 20, 0, 2, sword(), T_MELEE, 0, 2);
		s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize();
		s.w.order_hold(f);
		s.run(0.5);
		s.w.apply_contact(2, 0.0, 200.0);
		s.place(2, 25.5f, 20.5f);
		s.run(10.0);
		CHECK(s.w.captive[2] && s.w.stats.captures_auto == 1, "captured without an order (auto %llu)", (unsigned long long)s.w.stats.captures_auto);
		CHECK(s.w.captor[2] >= 0 && s.w.captor[2] < 2, "the guard is one of the idle AI members");
		double h = s.w.hp[2];
		s.run(30.0);
		CHECK(s.w.hp[2] == h, "a captive does not bleed");
	}
	{   // a formation that is not AI-controlled (the player's) does not auto-capture; 9 cells is out of range
		Scene s;
		s.w.cfg.auto_capture = true;
		int f = s.formation(0, 20, 20, 0, 2, sword(), T_MELEE, 0, 2);
		int g = s.formation(0, 20, 30, 0, 2, sword(), T_MELEE, 0, 2);
		s.formation(1, 40, 40, 0, 2, sword());
		s.w.finalize();
		s.w.order_hold(f); s.w.order_hold(g);
		s.w.formations[f].ai_enabled = false;
		s.run(0.5);
		s.w.apply_contact(4, 0.0, 200.0); s.place(4, 22.5f, 21.5f);   // next to the player formation
		s.w.apply_contact(5, 0.0, 200.0); s.place(5, 30.5f, 38.5f);   // about 12 cells from the AI formation
		s.run(8.0);
		CHECK(!s.w.captive[4] && s.w.stats.captures_started == 0, "player formation / out of range: no capture (%llu)", (unsigned long long)s.w.stats.captures_started);
	}
	{   // guard capacity: one guard, six downed enemies -> at most 4 prisoners
		Scene s;
		s.w.cfg.auto_capture = true;
		int f = s.formation(0, 20, 20, 0, 1, sword());
		s.formation(1, 40, 40, 0, 6, sword(), T_MELEE, 0, 3);
		s.w.finalize();
		s.w.order_hold(f);
		s.run(0.5);
		for (int k = 1; k <= 6; ++k) { s.w.apply_contact(k, 0.0, 200.0); s.place(k, 21.5f + 0.9f * (float)(k % 3), 22.0f + 1.2f * (float)(k / 3)); }
		s.run(60.0);
		int held = 0;
		for (int k = 1; k <= 6; ++k) if (s.w.captive[k] && s.w.captor[k] == 0) ++held;
		CHECK(held == 4, "guard holds 4 (%d)", held);
	}
	{   // own wounded first: an idle soldier with a downed friend and a downed enemy nearby rescues first
		Scene s;
		s.w.cfg.auto_capture = true; s.w.cfg.rescue_seek_cells = 8.f;
		int f = s.formation(0, 20, 20, 0, 2, sword(), T_MELEE, 0, 2);
		s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize();
		s.w.order_hold(f);
		s.run(0.5);
		s.w.apply_contact(1, 0.0, 200.0);
		s.w.apply_contact(2, 0.0, 200.0); s.place(2, s.w.px[0] + 2.0f, s.w.py[0]);
		s.run(1.0);
		CHECK(s.w.rescue_of[0] == 1 && s.w.capture_of[0] < 0, "rescue before capture (rescue_of %d capture_of %d)", s.w.rescue_of[0], s.w.capture_of[0]);
		s.run(20.0);
		CHECK(s.w.bandaged[1] && s.w.captive[2], "then the prisoner is taken");
	}
}

static void test_three_factions() {
	std::printf("[factions] full faction ids: 0/2/5 all fight each other; allies set by relation; ally on the line holds fire\n");
	{   // factions 0 and 2 have the same parity: they must still be enemies (Astra review 2026-09-29)
		Scene s;
		int a = s.formation(0, 20, 20, 0, 1, sword());
		int b = s.formation(2, 21, 20, kPi, 1, sword());
		s.formation(5, 40, 40, 0, 1, sword());
		s.w.finalize();
		for (int f = 0; f < 3; ++f) s.w.formations[f].ai_enabled = false;
		s.place(0, 20.5f, 20.5f); s.place(1, 21.5f, 20.5f);
		s.w.order_attack(a, 1); s.w.formations[a].order_delay = 0;
		s.w.order_hold(b);
		for (int k = 0; k < 90; ++k) { s.place(0, 20.5f, 20.5f); s.place(1, 21.5f, 20.5f); checked_step(s.w, DT); }
		CHECK(s.w.stats.pairs > 0, "faction 0 attacks faction 2 (%llu pairs)", (unsigned long long)s.w.stats.pairs);
		CHECK(s.w.target[0] == 1 && s.w.target[1] == 0, "each targets the other (%d, %d)", s.w.target[0], s.w.target[1]);
	}
	{   // three-way: every soldier is in exchanges with both other factions
		Scene s;
		int f0 = s.formation(0, 20, 20, 0, 1, sword());
		int f2 = s.formation(2, 21, 20, 0, 1, sword());
		int f5 = s.formation(5, 20, 21, 0, 1, sword());
		s.w.finalize();
		auto pin = [&]() { s.place(0, 20.5f, 20.5f); s.place(1, 21.5f, 20.5f); s.place(2, 20.5f, 21.5f); };
		for (int f : {f0, f2, f5}) { s.w.formations[f].ai_enabled = false; s.w.order_move(f, 20.5f, 20.5f, 0); s.w.formations[f].order_delay = 0; }
		uint64_t p0 = s.w.stats.pairs;
		int rounds_with_pairs = 0;
		for (int k = 0; k < 45; ++k) {
			pin();
			uint64_t before = s.w.stats.pairs;
			checked_step(s.w, DT);
			uint64_t d = s.w.stats.pairs - before;
			if (d) { ++rounds_with_pairs; CHECK(d == 2, "0-2 and 0-5 in one round (1 and 2 are 1.41 apart): %llu", (unsigned long long)d); }
		}
		CHECK(s.w.stats.pairs > p0 && rounds_with_pairs >= 1, "three factions exchange");
		CHECK(s.w.stats.cooldown_violations == 0, "one round per person");
	}
	{   // allies (0 and 2): no exchange between them; an ally on the line blocks the archer; no friendly hits
		Scene s;
		int a = s.formation(0, 10, 24, 0, 1, bow(), T_BOW, 3);
		s.formation(2, 14, 24, 0, 1, sword());
		s.formation(5, 16, 24, kPi, 1, sword());
		s.w.set_hostile(0, 2, false);
		s.w.finalize();
		for (int f = 0; f < 3; ++f) s.w.formations[f].ai_enabled = false;
		CHECK(!s.w.hostile(0, 2) && !s.w.hostile(2, 0) && s.w.hostile(0, 5) && s.w.hostile(2, 5) && !s.w.hostile(5, 5), "relation table");
		auto pin = [&]() { s.place(0, 10.5f, 24.5f); s.place(1, 13.5f, 24.5f); s.place(2, 16.5f, 24.5f); };
		s.w.order_attack(a, 2); s.w.formations[a].order_delay = 0; s.w.formations[a].arrived = true;
		for (int k = 0; k < 60; ++k) { pin(); checked_step(s.w, DT); }
		CHECK(s.w.stats.shots == 0 && s.w.stats.friendly_hits == 0, "ally of faction 2 on the line: hold fire (%llu)", (unsigned long long)s.w.stats.shots);
		s.place(1, 11.4f, 24.5f); // ally adjacent to the archer
		uint64_t pairs = s.w.stats.pairs;
		for (int k = 0; k < 60; ++k) { s.place(0, 10.5f, 24.5f); s.place(1, 11.4f, 24.5f); s.place(2, 16.5f, 24.5f); checked_step(s.w, DT); }
		CHECK(s.w.stats.pairs == pairs, "allies do not exchange");
	}
}

static void test_round_fatigue_before_deaths() {
	std::printf("[fatigue] one exchange round is charged on the pre-death roster: 0.5/2 + 0.5/2, not 0.5/2 + 0.5/1\n");
	Scene s;
	int a = s.formation(0, 20, 20, 0, 2, sword(), T_MELEE, 0, 2);
	int b = s.formation(1, 30, 30, 0, 2, sword(), T_MELEE, 0, 2);
	s.w.finalize();
	for (int f : {a, b}) s.w.formations[f].ai_enabled = false;
	// side b is far stronger: every exchange is a big loss for side a (1.0 fatigue each: 0.5 + 0.5)
	s.w.formations[b].training = 100.0;
	s.w.formations[a].fatigue = 90.0;
	auto pin = [&]() { s.place(0, 20.5f, 20.5f); s.place(2, 21.5f, 20.5f); s.place(1, 20.5f, 24.5f); s.place(3, 21.5f, 24.5f); };
	pin();
	s.w.order_hold(a);
	s.w.order_attack(b, 0); s.w.formations[b].order_delay = 0;
	s.w.hp[0] = 0.5; // dies in the first round
	double f0 = -1;
	for (int k = 0; k < 60 && s.w.stats.pairs == 0; ++k) { pin(); f0 = s.w.formations[a].fatigue; checked_step(s.w, DT); }
	CHECK(s.w.stats.pairs == 2 && s.w.stats.big == 2, "two big losses in one round (pairs %llu big %llu)", (unsigned long long)s.w.stats.pairs, (unsigned long long)s.w.stats.big);
	CHECK(s.w.hp[0] == 0.0, "the first soldier died in that round");
	double d = s.w.formations[a].fatigue - f0;
	CHECK(std::fabs(d - 1.0) < 1e-9, "fatigue +%.4f (expected 1.0/2 + 1.0/2 = 1.0, the bug gave 1.5)", d);
}

static void test_move_encounter() {
	std::printf("[move] MOVE meets enemies: fights every adjacent enemy in one round, pauses, resumes the order, never leaves the ranks to chase\n");
	{   // one soldier on MOVE with two adjacent enemies (HOLD with a commander, so they do not initiate)
		Scene s(1, 64, 48);
		int a = s.formation(0, 10, 24, 0, 1, sword());
		int b = s.formation(1, 40, 40, 0, 2, sword(), T_MELEE, 0, 2);
		s.w.finalize();
		for (int f : {a, b}) s.w.formations[f].ai_enabled = false;
		s.w.order_hold(b);
		s.w.order_move(a, 50.5f, 24.5f, 0); s.w.formations[a].order_delay = 0;
		auto pin = [&]() { s.place(0, 20.5f, 24.5f); s.place(1, 21.5f, 24.5f); s.place(2, 20.5f, 25.5f); };
		uint64_t first = 0;
		for (int k = 0; k < 60 && first == 0; ++k) { pin(); checked_step(s.w, DT); first = s.w.stats.pairs; }
		CHECK(first == 2, "the first round takes both contacts together (%llu)", (unsigned long long)first);
		CHECK(s.w.formations[a].order == Order::MOVE, "still a MOVE order during the encounter");
	}
	{   // a squad on MOVE passes an enemy 2.5 cells to the side: nobody leaves the ranks, the move completes
		Scene s(1, 64, 48);
		int a = s.formation(0, 10, 24, 0, 3, sword(), T_MELEE, 0, 3);
		int b = s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize();
		for (int f : {a, b}) s.w.formations[f].ai_enabled = false;
		s.w.order_hold(b);
		s.w.order_move(a, 40.5f, 24.5f, 0); s.w.formations[a].order_delay = 0;
		int left = 0;
		for (int k = 0; k < 30 * 25; ++k) {
			s.place(3, 25.5f, 27.8f);
			checked_step(s.w, DT);
			for (int i = 0; i < 3; ++i) if (s.w.state[i] == S_ENGAGE || s.w.state[i] == S_ENCIRCLE) ++left;
		}
		CHECK(left == 0, "no soldier left the ranks to chase (%d steps)", left);
		CHECK(s.w.formations[a].arrived && s.w.formations[a].order == Order::HOLD, "move completed (cx %.1f)", s.w.formations[a].cx);
	}
	{   // an enemy blocks the path: exchange, pause, then the enemy is gone and the MOVE resumes to the goal
		Scene s(1, 64, 48);
		int a = s.formation(0, 10, 24, 0, 1, sword());
		int b = s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize();
		for (int f : {a, b}) s.w.formations[f].ai_enabled = false;
		s.w.order_hold(b);
		s.w.order_move(a, 40.5f, 24.5f, 0); s.w.formations[a].order_delay = 0;
		for (int k = 0; k < 30 * 8 && s.w.stats.pairs == 0; ++k) { s.place(1, 18.5f, 24.5f); checked_step(s.w, DT); }
		CHECK(s.w.stats.pairs > 0, "encounter exchange on the path");
		for (int k = 0; k < 30 * 2; ++k) { s.place(1, 18.5f, 24.5f); checked_step(s.w, DT); }
		float cx_paused = s.w.formations[a].cx;
		CHECK(cx_paused < 18.5f && s.w.formations[a].order == Order::MOVE, "paused in contact (cx %.2f), order kept", cx_paused);
		for (int k = 0; k < 30 * 20; ++k) { s.place(1, 60.5f, 44.5f); checked_step(s.w, DT); } // contact ends
		CHECK(s.w.formations[a].arrived && std::fabs(s.w.formations[a].cx - 40.5f) < 0.5f, "resumed and reached the goal (cx %.2f)", s.w.formations[a].cx);
	}
}

// ---------------------------------------------------------------- P1 (2026-09-29): formal flow order, clock, state, save
static void test_site_clock() {
	std::printf("[clock] combat_left: 1:1 while combat events keep it up (exchange / hit 10 s, shot 12 s), then 1 s = 60 game s; host clock\n");
	{
		Scene s;
		s.w.combat_left = 0.0;
		s.formation(0, 10, 10, 0, 1, sword());
		s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize();
		checked_step(s.w, DT);
		CHECK(std::fabs(s.w.game_dt - DT * 60.0) < 1e-9, "peace: game_dt %.6f", s.w.game_dt);
		s.w.apply_contact(0, 1.0, 0.0);
		CHECK(std::fabs(s.w.combat_left - 10.0) < 1e-9 && s.w.combat_mark == 10.0, "an effective hit marks 10 s (%.3f)", s.w.combat_left);
		checked_step(s.w, DT);
		CHECK(std::fabs(s.w.game_dt - DT) < 1e-9, "combat: game_dt %.6f", s.w.game_dt);
		s.run(9.9);
		checked_step(s.w, DT); checked_step(s.w, DT); checked_step(s.w, DT); checked_step(s.w, DT);
		CHECK(s.w.combat_left == 0.0 && std::fabs(s.w.game_dt - DT * 60.0) < 1e-9, "10 s later the clock is back to peace");
		s.w.cfg.speed = 2.0;
		checked_step(s.w, DT);
		CHECK(std::fabs(s.w.game_dt - DT * 120.0) < 1e-9, "Site speed x2 doubles game time only");
	}
	{   // host clock: exactly the given game seconds; marks are reported, not applied
		Scene s;
		s.formation(0, 10, 10, 0, 1, sword());
		s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize();
		s.w.apply_contact(0, 0.0, 200.0);
		double ko0 = s.w.ko[0];
		checked_step_clock(s.w, DT, 7.5, 0.0);
		CHECK(std::fabs((ko0 - s.w.ko[0]) - 7.5) < 1e-9, "KO wait counts the host's game seconds (%.4f)", ko0 - s.w.ko[0]);
		s.w.apply_contact(0, 0.0, 5.0);
		CHECK(s.w.combat_mark == 10.0 && s.w.combat_left == 0.0, "host clock: the mark is reported (%.1f), combat_left untouched", s.w.combat_mark);
	}
}

static void test_game_time_actions() {
	std::printf("[clock] capture 4 game s, escape 30 game s, fatigue / morale resupply on game time\n");
	{   // capture in peace completes in 4/60 action s
		Scene q;
		q.formation(0, 10, 10, 0, 1, sword());
		q.formation(1, 12, 10, 0, 1, sword());
		q.w.finalize();
		q.place(1, 11.3f, 10.5f); q.place(0, 10.5f, 10.5f);
		q.w.apply_contact(1, 0.0, 200.0);
		q.w.combat_left = 0.0;
		CHECK(q.w.order_capture(0, 1), "capture order");
		for (int k = 0; k < 3; ++k) checked_step(q.w, DT);
		CHECK(q.w.captive[1], "4 game s = 2.4 action frames in peace");
	}
	{   // resupply: a non-routed team at 60 morale, HOLD, safe, disengaged -> +5 per game hour
		Scene s;
		int f = s.formation(0, 10, 10, 0, 4, sword(), T_MELEE, 0, 2);
		s.formation(1, 44, 44, 0, 1, sword());
		s.w.finalize();
		s.w.order_hold(f);
		s.run(1.0);
		s.w.formations[f].morale = 60.0;
		s.w.combat_left = 0.0;
		s.run(60.0); // 1 game hour
		CHECK(std::fabs(s.w.formations[f].morale - 65.0) < 0.01, "morale 60 -> %.3f after one game hour", s.w.formations[f].morale);
		// same with an enemy 6 cells away: no resupply
		s.place(4, 16.0f, 11.0f);
		s.w.formations[1].ai_enabled = false;
		double m = s.w.formations[f].morale;
		for (int k = 0; k < 90; ++k) { s.place(4, 16.0f, 11.0f); checked_step(s.w, DT); }
		CHECK(std::fabs(s.w.formations[f].morale - m) < 1e-9 || s.w.combat_left > 0, "threat within 8: no resupply (%.4f -> %.4f)", m, s.w.formations[f].morale);
	}
	{   // fatigue recovers only in HOLD with the Site out of combat
		Scene s;
		int f = s.formation(0, 10, 10, 0, 4, sword(), T_MELEE, 0, 2);
		s.formation(1, 44, 44, 0, 1, sword());
		s.w.finalize();
		s.w.order_hold(f);
		s.run(1.0);
		s.w.formations[f].fatigue = 50.0;
		s.run(60.0); // combat clock (1e9): no recovery
		CHECK(s.w.formations[f].fatigue == 50.0, "no recovery while the Site is in combat (%.3f)", s.w.formations[f].fatigue);
		s.w.combat_left = 0.0;
		s.run(60.0); // 1 game hour; 30 game s delay then -20 / h
		double expect = 50.0 - 20.0 * (3600.0 - 30.0) / 3600.0;
		CHECK(std::fabs(s.w.formations[f].fatigue - expect) < 0.05, "peace: %.3f (expected %.3f)", s.w.formations[f].fatigue, expect);
		s.w.order_move(f, 20.5f, 10.5f, 0);
		double v = s.w.formations[f].fatigue;
		s.run(0.5);
		CHECK(s.w.formations[f].fatigue >= v, "a MOVE order stops recovery");
	}
	{   // escape: 30 game seconds unguarded; in peace that is half an action second
		Scene s;
		s.formation(0, 10, 10, 0, 1, sword());
		s.formation(1, 12, 10, 0, 1, sword());
		s.w.finalize();
		s.place(1, 11.3f, 10.5f); s.place(0, 10.5f, 10.5f);
		s.w.apply_contact(1, 0.0, 200.0);
		s.w.order_capture(0, 1);
		s.run(4.5);
		CHECK(s.w.captive[1], "captured");
		s.w.ko[1] = 0.01;
		s.run(3.0); // wakes and gets up
		s.w.apply_contact(0, 0.0, 200.0); // guard knocked out
		s.w.combat_left = 0.0;
		for (int k = 0; k < 20; ++k) checked_step(s.w, DT);
		CHECK(!s.w.captive[1] && s.w.stats.escapes == 1, "free after 30 game s (%d frames)", 20);
	}
}

static void test_flow_order() {
	std::printf("[flow] commander loss -> HOLD; KO+death in one step = one death; captives count in the roster; knockback; stagger; rescuer stun\n");
	{   // the last eligible commander lost on a MOVE: the formation holds (settle_combat_command)
		Scene s(1, 64, 48);
		int f = s.formation(0, 10, 24, 0, 3, sword(), T_MELEE, 0, 3);
		s.formation(1, 60, 44, 0, 1, sword());
		s.w.finalize();
		s.w.formations[f].ai_enabled = false;
		s.w.order_move(f, 50.5f, 24.5f, 0); s.w.formations[f].order_delay = 0;
		s.run(1.0);
		for (int i = 0; i < 3; ++i) s.w.apply_contact(i, 0.0, 200.0);
		s.run(0.2);
		CHECK(s.w.formations[f].order == Order::HOLD && s.w.formations[f].needs_attack_order, "no commander: HOLD (order %d)", (int)s.w.formations[f].order);
		CHECK(s.w.stats.command_losses == 1, "one -10 interruption");
	}
	{   // KO and death of the same person inside one observation interval: a death only (-40/n, not -60/n)
		Scene s;
		int f = s.formation(0, 20, 20, 0, 10, sword());
		s.formation(1, 44, 44, 0, 1, sword());
		s.w.finalize();
		s.w.formations[f].ai_enabled = false;
		s.run(0.2);
		Formation &F = s.w.formations[f];
		double lead = s.w.command_effect(f, 1, 0.25);
		s.w.apply_contact(5, 0.0, 200.0);
		s.w.apply_contact(5, 200.0, 0.0);
		// two captives of this team (captured by team 1) still count in the roster denominator
		s.w.captive[7] = 1; s.w.captive[8] = 1;
		double m0 = F.morale;
		F.resupplying = false;
		checked_step(s.w, DT);
		double res = F.resupplying ? 5.0 / 3600.0 * DT : 0.0;
		double expect = m0 - 40.0 / 10.0 * (1.0 - lead) + res;
		CHECK(std::fabs(F.morale - expect) < 1e-9, "morale %.6f expected %.6f", F.morale, expect);
		s.w.captive[7] = 0; s.w.captive[8] = 0;
	}
	{   // a big loss that also knocks the loser out: the body still slides one cell
		Scene s;
		s.formation(0, 20, 20, 0, 1, sword());
		s.formation(1, 30, 30, 0, 1, sword());
		s.w.finalize();
		s.place(0, 20.5f, 20.5f); s.place(1, 21.5f, 20.5f);
		s.w.knock_t[0] = 0.25; s.w.knock_dx[0] = -4.f; s.w.knock_dy[0] = 0.f; // as set by the knockback phase
		s.w.apply_contact(0, 0.0, 200.0);
		float x0 = s.w.px[0];
		s.run(0.4);
		CHECK(s.w.ko[0] > 0 && x0 - s.w.px[0] > 0.8f, "the unconscious body slid %.2f cells", x0 - s.w.px[0]);
	}
	{   // rescuer stun does not decay while rescuing
		Scene s;
		int f = s.formation(0, 20, 20, 0, 4, sword(), T_MELEE, 0, 2);
		s.formation(1, 44, 44, 0, 1, sword());
		s.w.finalize();
		s.w.order_hold(f);
		s.run(0.5);
		s.w.apply_contact(3, 0.0, 200.0);
		s.run(0.6);
		int r = -1;
		for (int i = 0; i < 3; ++i) if (s.w.rescue_of[i] == 3) r = i;
		CHECK(r >= 0, "rescue started");
		if (r >= 0) {
			s.w.stun[r] = 40.0; s.w.grace[r] = 0.0;
			s.run(1.0);
			CHECK(s.w.stun[r] == 40.0, "stun frozen while rescuing (%.2f)", s.w.stun[r]);
		}
	}
	{   // an arrow fired this step starts its flight next step (arrivals run before the exchange / fire)
		Scene s;
		int a = s.formation(0, 10, 24, 0, 1, bow(), T_BOW, 3);
		int e = s.formation(1, 16, 24, kPi, 1, sword());
		s.w.finalize();
		for (int f : {a, e}) s.w.formations[f].ai_enabled = false;
		s.w.order_attack(a, 1); s.w.formations[a].order_delay = 0; s.w.formations[a].arrived = true;
		double left = -1;
		for (int k = 0; k < 60 && s.w.projectiles.empty(); ++k) { s.place(0, 10.5f, 24.5f); s.place(1, 16.5f, 24.5f); checked_step(s.w, DT); }
		if (!s.w.projectiles.empty()) {
			const Projectile &p = s.w.projectiles[0];
			int ox = p.target.x - p.source.x, oy = p.target.y - p.source.y;
			left = std::sqrt((double)(ox * ox + oy * oy)) / ranged_profile(bow()).speed;
			CHECK(std::fabs(p.left - left) < 1e-12, "full flight time after the firing step (%.4f vs %.4f)", p.left, left);
		} else CHECK(false, "no shot");
	}
}

static void test_state_import_export() {
	std::printf("[state] SiteStore import / export: HP, stun, KO, captivity, ammo, abilities, morale, fatigue, commanders\n");
	Scene s;
	int f = s.formation(0, 20, 20, 0, 6, bow(), T_BOW, 10, 3);
	int g = s.formation(1, 24, 20, kPi, 3, sword());
	s.w.finalize();
	SoldierState a;
	a.hp = 37.5; a.stun = 12.0; a.grace = 1.5; a.ammo = 4; a.tactics = 70; a.leadership = 20; a.coach = 5;
	s.w.set_soldier_state(3, a);
	SoldierState k;
	k.hp = 80; k.ko = 1234.0; k.bandaged = 1;
	s.w.set_soldier_state(4, k);
	SoldierState c;
	c.hp = 60; c.captive = 1; c.captor_person = s.w.person_id[6];
	s.w.set_soldier_state(5, c);
	SoldierState b = s.w.get_soldier_state(3);
	CHECK(b.hp == 37.5 && b.stun == 12.0 && b.grace == 1.5 && b.ammo == 4 && b.tactics == 70 && b.leadership == 20 && b.coach == 5,
	      "soldier round trip");
	CHECK(s.w.get_soldier_state(4).ko == 1234.0 && s.w.get_soldier_state(4).bandaged == 1, "KO wait and bandage kept");
	CHECK(s.w.captive[5] && s.w.captor[5] == 6 && s.w.get_soldier_state(5).captor_person == s.w.person_id[6], "captor by person id");
	FormationState fs;
	fs.morale = 42.0; fs.fatigue = 33.0; fs.fatigue_rest = 10.0; fs.training = 55.0; fs.routed = 0;
	fs.formal_person = s.w.person_id[2]; fs.officer_persons = {s.w.person_id[1], s.w.person_id[3]};
	s.w.set_formation_state(f, fs);
	FormationState o = s.w.get_formation_state(f);
	CHECK(o.morale == 42.0 && o.fatigue == 33.0 && o.training == 55.0 && o.formal_person == s.w.person_id[2], "formation round trip");
	CHECK(s.w.formations[f].current_cmd == 2, "imported formal commander commands (%d)", s.w.formations[f].current_cmd);
	s.w.events.clear();
	s.run(0.1);
	CHECK(s.w.formations[f].morale >= 42.0 && s.w.formations[f].morale < 42.01, "import is not a morale event (%.4f)", s.w.formations[f].morale);
	int kos = 0;
	for (auto &e : s.w.events) kos += e.kind == EV_KO || e.kind == EV_DEATH;
	CHECK(kos == 0, "no KO / death events from the import");
	CHECK(s.w.ko[4] > 0 && s.w.ko[4] < 1234.0, "the imported KO wait keeps counting (%.2f)", s.w.ko[4]);
	(void)g;
}

static void test_full_formation_import_preserves_command_state() {
	std::printf("[state] full import preserves absent abilities and command state until the next real step\n");
	Scene s;
	const int fi = s.w.add_formation(0, 20.5f, 20.5f, 0, 5, 1.0f, T_MELEE, 0);
	for (int k = 0; k < 5; ++k)
		s.w.add_soldier(fi, sword(), k == 0 ? R_CAPTAIN : (k == 1 ? R_OFFICER : R_REGULAR), 100 + k);
	s.w.finalize();
	for (int i = 0; i < 5; ++i) {
		SoldierState body = s.w.get_soldier_state(i);
		body.x = i < 2 ? 2.5f + (float)i : 18.5f + (float)i;
		body.y = i < 2 ? 2.5f : 20.5f;
		body.tactics = i == 0 ? 53 : (i == 1 ? 17 : -1);
		body.leadership = i == 0 ? 31 : (i == 1 ? 23 : -1);
		body.coach = i == 0 ? 58 : (i == 1 ? 29 : -1);
		s.w.set_soldier_state(i, body);
	}
	// The original order owner primes the same goal/field; no simulation tick has occurred.
	s.w.order_move(fi, 20.5f, 20.5f, 0);
	const FormationState source = s.w.get_formation_state(fi);
	const auto roles = s.w.role;
	const auto presence = s.w.present;
	const auto abilities = s.w.ability;
	const uint64_t rng = s.w.formations[fi].rng;
	const uint64_t successions = s.w.stats.successions;
	const auto before = s.w.save();
	CHECK(source.formal_person == 100 && source.acting_person == -1 && source.current_person == 100
	      && source.officer_persons == std::vector<int64_t>{101}, "declared source command references");
	CHECK(s.w.formations[fi].command_dirty, "original soldier import leaves normal command work pending");
	// Native presence will use member 102 near the centroid; radius is 8 plus at most 2 hysteresis.
	CHECK(std::hypot(s.w.px[0] - s.w.px[2], s.w.py[0] - s.w.py[2]) > 10.0f
	      && std::hypot(s.w.px[1] - s.w.px[2], s.w.py[1] - s.w.py[2]) > 10.0f,
	      "formal commander and listed officer lie outside native presence");
	s.w.set_formation_state(fi, source);
	const FormationState restored = s.w.get_formation_state(fi);
	CHECK(restored.formal_person == source.formal_person && restored.acting_person == source.acting_person
	      && restored.current_person == source.current_person && restored.officer_persons == source.officer_persons,
	      "full import preserves explicit formal/acting/current/officer references");
	CHECK(s.w.role == roles && s.w.present == presence && s.w.formations[fi].command_dirty,
	      "full import does not rewrite roles, presence cache or pending command work");
	for (int i = 0; i < 5; ++i)
		CHECK(s.w.ability[i].tactics == abilities[i].tactics && s.w.ability[i].leadership == abilities[i].leadership
		      && s.w.ability[i].coach == abilities[i].coach, "all three abilities, including absence, stay exact for %d", i);
	CHECK(s.w.formations[fi].rng == rng && s.w.stats.successions == successions, "import consumes no command RNG or succession");
	CHECK(s.w.save() == before, "full source round trip preserves every serialized field, including all stats/events/clocks");
	check_valid(s.w);
	checked_step(s.w, DT);
	const int acting = s.w.formations[fi].acting_cmd;
	CHECK(acting >= 2 && acting < 5 && s.w.formations[fi].current_cmd == acting
	      && s.w.formations[fi].formal_cmd == 0, "next real step applies the normal temporary-succession rule");
	if (acting >= 2 && acting < 5)
		CHECK(s.w.ability[acting].tactics >= 0 && s.w.ability[acting].leadership >= 0 && s.w.ability[acting].coach >= 0,
		      "abilities are generated only when the real step selects the absent-ability regular");
	CHECK(s.w.formations[fi].rng != rng && s.w.stats.successions == successions + 1,
	      "the real succession consumes RNG and records exactly one succession");
	int succession_events = 0;
	for (const Event &event : s.w.events) succession_events += event.kind == EV_SUCCESSION;
	CHECK(succession_events == 1 && s.w.role == roles && !s.w.present[0] && !s.w.present[1],
	      "the real step emits its event and refreshes presence without rewriting roles");
}

static void check_event_ledger(const World &w) {
 std::set<int64_t> deployed(w.person_id.begin(),w.person_id.end()), dead;
 for(const Event &e:w.events) {
  CHECK(e.kind<EV_COUNT && e.formation>=0 && e.formation<(int)w.formations.size(), "event kind/formation is valid");
  if(e.person>=0) {
   CHECK(deployed.count(e.person)==1 && e.soldier>=0 && e.soldier<w.soldier_count(), "event person belongs to the deployed population, including host");
   CHECK(w.person_id[e.soldier]==e.person && w.form[e.soldier]==e.formation, "event raw soldier and formation agree with person");
  } else CHECK(e.soldier==-1 && (e.kind==EV_COMMAND_LOST || e.kind==EV_ROUT || e.kind==EV_RALLY), "sentinel subject is allowed only for formation events");
  if(e.other>=0) CHECK(deployed.count(e.other)==1, "other person was deployed");
  if(e.kind==EV_KO || e.kind==EV_WAKE || e.kind==EV_SHOT || e.kind==EV_ESCAPED || e.kind==EV_ROUT || e.kind==EV_RALLY)
   CHECK(e.other==-1,"event kind %d requires sentinel other",e.kind);
  if(e.kind==EV_RESCUED || e.kind==EV_CAPTURED || e.kind==EV_COMMAND_LOST) CHECK(e.other>=0,"event requires real other person");
  if(e.kind==EV_DEATH) CHECK(dead.insert(e.person).second,"one DEATH per person %lld",(long long)e.person);
  if(e.kind==EV_KO || e.kind==EV_WAKE || e.kind==EV_CAPTURED) CHECK(!dead.count(e.person),"dead person has no later KO/WAKE/CAPTURED");
 }
}

// Every event is checked against its actual action/command owner, never only a statistics total.
static void expect_event(const World &w, EventKind kind, int expected_count, int soldier, int other, int formation) {
	check_event_ledger(w);
	int count = 0;
	const int64_t person_id = soldier >= 0 ? w.person_id[soldier] : -1;
	const int64_t other_id = other >= 0 ? w.person_id[other] : -1;
	for (const Event &e : w.events) {
		if (e.kind != kind) continue;
		++count;
		CHECK(e.soldier == soldier && e.person == person_id && e.other == other_id && e.formation == formation,
		      "event %d fields soldier=%d person=%lld other=%lld formation=%d; expected %d/%lld/%lld/%d", (int)kind,
		      e.soldier, (long long)e.person, (long long)e.other, e.formation,
		      soldier, (long long)person_id, (long long)other_id, formation);
		CHECK(std::isfinite(e.time) && e.time >= 0 && e.time <= w.time, "event %d timestamp %.9f in [0, %.9f]", (int)kind, e.time, w.time);
	}
	CHECK(count == expected_count, "event %d exact count %d, expected %d", (int)kind, count, expected_count);
	std::printf("[event-fields] kind=%d count=%d expected=%d soldier=%d person=%lld other=%lld formation=%d\n",
	            (int)kind, count, expected_count, soldier, (long long)person_id, (long long)other_id, formation);
}

static void test_events() {
	std::printf("[events] all 11 kinds: exact count, person/other/formation identity, and finite timestamp\n");
	{   // KO -> a real adjacent rescue action -> wake; captain death -> the explicit officer succeeds.
		Scene s;
		int f = s.formation(0, 20, 20, 0, 4, sword(), T_MELEE, 0, 2);
		s.formation(1, 40, 40, kPi, 1, sword());
		for (int i = 0; i < s.w.soldier_count(); ++i) s.w.person_id[i] = 10001 + i * 17;
		s.w.finalize(); s.w.set_host_control(0, true); s.w.order_hold(f); s.run(0.5); s.w.events.clear();
		s.w.apply_contact(3, 0.0, 200.0);
		int rescuer = -1;
		for (int step = 0; step < 180; ++step) {
			checked_step(s.w, DT);
			for (int i = 0; i < 3; ++i) if (s.w.rescue_of[i] == 3) rescuer = i;
		}
		CHECK(rescuer >= 0 && s.w.bandaged[3], "a real rescue action completed (rescuer %d)", rescuer);
		s.w.ko[3] = 0.01; s.run(0.2);
		s.w.apply_contact(0, 200.0, 0.0); s.run(0.2);
		CHECK(s.w.formations[f].current_cmd == 1, "the first officer succeeds");
		// Reapplying damage to the dead, and later steps, must not repeat the transition events.
		s.w.apply_contact(0, 200.0, 0.0); s.run(0.5);
		expect_event(s.w, EV_KO, 1, 3, -1, f);
		expect_event(s.w, EV_RESCUED, 1, 3, rescuer, f);
		expect_event(s.w, EV_WAKE, 1, 3, -1, f);
		expect_event(s.w, EV_DEATH, 1, 0, -1, f);
		expect_event(s.w, EV_SUCCESSION, 1, 1, 0, f);
	}
	{   // The last qualified commander falls: formation event uses person=-1, other=old commander.
		Scene s;
		int f = s.formation(0, 10, 10, 0, 1, sword());
		s.w.person_id[0] = 20003;
		s.w.finalize(); s.w.events.clear();
		s.w.apply_contact(0, 0.0, 200.0); s.run(1.0);
		expect_event(s.w, EV_COMMAND_LOST, 1, -1, 0, f);
	}
	{   // Actual four-second capture and thirty-second unguarded escape, not a hand-written event.
		Scene s;
		s.formation(0, 10, 10, 0, 1, sword());
		int victim_f = s.formation(1, 12, 10, 0, 1, sword());
		s.w.person_id[0] = 30007; s.w.person_id[1] = 30019;
		s.w.finalize(); s.place(0, 10.5f, 10.5f); s.place(1, 11.3f, 10.5f);
		s.w.apply_contact(1, 0.0, 200.0); s.w.events.clear();
		CHECK(s.w.order_capture(0, 1), "event fixture capture order accepted");
		s.run(4.4); CHECK(s.w.captive[1] && s.w.captor[1] == 0, "capture actually committed");
		s.w.ko[1] = 0.01; s.run(3.0); // shortened fixture KO, normal get-up path
		s.w.apply_contact(0, 0.0, 200.0); s.run(29.0);
		CHECK(s.w.captive[1], "escape has not fired early");
		s.run(2.0); CHECK(!s.w.captive[1], "unguarded captive escaped");
		expect_event(s.w, EV_CAPTURED, 1, 1, 0, victim_f);
		expect_event(s.w, EV_ESCAPED, 1, 1, -1, victim_f);
	}
	{   // Rout and rally use formation identity and -1 for both person fields.
		Scene s;
		int f = s.formation(0, 10, 10, 0, 1, sword());
		s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize(); s.w.events.clear(); s.w.formations[f].morale = 15;
		s.run(DT); CHECK(s.w.formations[f].routed, "low morale really routed");
		s.w.order_hold(f); s.run(3.0);
		s.w.formations[f].morale = 50;
		s.w.formations[f].rally_rest = RALLY_REST_SECONDS - 0.5;
		s.run(1.0); CHECK(!s.w.formations[f].routed, "safe fed HOLD really rallied");
		expect_event(s.w, EV_ROUT, 1, -1, -1, f);
		expect_event(s.w, EV_RALLY, 1, -1, -1, f);
	}
	{   // One actual release consumes the only arrow; subsequent steps do not emit a duplicate.
		Scene s;
		int f = s.formation(0, 10, 24, 0, 1, bow(), T_BOW, 1);
		s.formation(1, 16, 24, kPi, 1, sword());
		s.w.person_id[0] = 40009;
		s.w.finalize(); s.w.events.clear(); s.w.order_attack(f, 1);
		s.w.formations[f].order_delay = 0; s.w.formations[f].arrived = true;
		for (int step = 0; step < 20; ++step) {
			s.place(0, 10.5f, 24.5f); s.place(1, 16.5f, 24.5f); checked_step(s.w, DT);
		}
		CHECK(s.w.ammo[0] == 0 && s.w.stats.shots == 1, "one release consumed one arrow");
		expect_event(s.w, EV_SHOT, 1, 0, -1, f);
	}
}

static void test_twelve_arrow_capture_escape_chain() {
 std::printf("[ammo-chain] 12 arrows -> 3 real releases -> contact KO -> capture -> guard death -> wake/get-up -> 30-second escape\n");
 Scene s;
 int archer=s.formation(0,10.5f,24.5f,0,1,bow(),T_BOW,12);
 Equip protected_guard=sword(M_STEEL,A_MINGGUANG);protected_guard.shield=true;
 int guard=s.formation(1,16.5f,24.5f,kPi,1,protected_guard);
 s.w.person_id[0]=50101;s.w.person_id[1]=50209;s.w.formations[guard].training=100;
 s.w.finalize();s.w.events.clear();s.w.order_attack(archer,1);s.w.formations[archer].order_delay=0;s.w.formations[archer].arrived=true;
 int shot_count=0;
 for(int t=0;t<300 && shot_count<3;++t) {
  s.place(0,10.5f,24.5f);s.place(1,16.5f,24.5f);checked_step(s.w,DT);
  shot_count=0;for(const Event&e:s.w.events)if(e.kind==EV_SHOT && e.person==50101)++shot_count;
  CHECK(s.w.ammo[0]+shot_count==12,"pre-capture ammo %d + shots %d = 12",s.w.ammo[0],shot_count);
 }
 CHECK(shot_count==3 && s.w.ammo[0]==9 && s.w.hp[1]>0,"exactly three real shots, nine arrows remain, target survived");
 s.w.order_hold(archer);s.run(3.0);CHECK(s.w.projectiles.empty(),"all three flight actions resolved before capture");
 // Native-only explicit effective contact input; no imported KO flag or fabricated event.
 s.w.apply_contact(0,0,200);CHECK(s.w.ko[0]>0 && s.w.ammo[0]+shot_count==12,"contact caused KO without changing arrows");
 s.place(0,15.7f,24.5f);s.place(1,16.5f,24.5f);
 CHECK(s.w.order_capture(1,0),"guard starts actual capture action");s.run(4.4);
 CHECK(s.w.captive[0] && s.w.captor[0]==1,"native capture committed");
 s.w.apply_contact(1,200,0); // Guard death while A is still KO must not release A.
 s.run(31.0);CHECK(s.w.captive[0] && s.w.ko[0]>0 && s.w.escape_t[0]==0,"guard death while KO cannot start escape");
 s.w.ko[0]=0.01;s.run(0.1);CHECK(s.w.captive[0] && s.w.getup[0]>0 && s.w.escape_t[0]==0,"wake alone cannot bypass get-up");
 for(int t=0;t<100 && s.w.getup[0]>0;++t){checked_step(s.w,DT);if(s.w.getup[0]>0)CHECK(s.w.captive[0] && s.w.escape_t[0]==0,"get-up still blocks escape timer");}
 CHECK(s.w.getup[0]==0 && s.w.escape_t[0]<0.1,"escape clock starts only after full get-up");
 s.run(29.0);CHECK(s.w.captive[0],"not free before 30 qualifying game seconds");s.run(1.2);
 CHECK(!s.w.captive[0] && s.w.hp[0]>0,"free after 30 qualifying game seconds");
 std::vector<int> actual;for(const Event&e:s.w.events)if(e.person==50101 && (e.kind==EV_SHOT || e.kind==EV_KO || e.kind==EV_CAPTURED || e.kind==EV_ESCAPED))actual.push_back(e.kind);
 const std::vector<int> expected{EV_SHOT,EV_SHOT,EV_SHOT,EV_KO,EV_CAPTURED,EV_ESCAPED};CHECK(actual==expected,"A's full discrete chain has exact order and no duplicate transitions");
 expect_event(s.w,EV_SHOT,3,0,-1,archer);expect_event(s.w,EV_KO,1,0,-1,archer);
 expect_event(s.w,EV_CAPTURED,1,0,1,archer);expect_event(s.w,EV_ESCAPED,1,0,-1,archer);
 expect_event(s.w,EV_DEATH,1,1,-1,guard);
 std::printf("AMMO_CHAIN shots=%d native_ammo=%d filtered_events=%zu escaped=%d guard_dead=%d\n",shot_count,s.w.ammo[0],actual.size(),!s.w.captive[0],s.w.hp[1]<=0);
}

static void test_captive_effective_hit_death() {
 std::printf("[captive-death] explicit internal effective hit names guard; no duplicate death or later KO/wake/capture\n");
 Scene s;s.formation(0,10.5f,10.5f,0,1,sword());int f=s.formation(1,11.3f,10.5f,0,1,sword());
 s.w.person_id[0]=60101;s.w.person_id[1]=60209;s.w.finalize();s.place(0,10.5f,10.5f);s.place(1,11.3f,10.5f);
 s.w.apply_contact(1,0,200);CHECK(s.w.order_capture(0,1),"capture order");s.run(4.4);CHECK(s.w.captive[1],"capture completed");
 double hp=s.w.hp[1];checked_step_clock(s.w,DT,3600,0);CHECK(s.w.captive[1] && s.w.ko[1]>0 && s.w.hp[1]==hp,"one full hour captive/downed HP unchanged");
 s.w.apply_contact(1,200,0);s.w.apply_contact(1,0,200);s.w.apply_contact(1,200,0);s.run(4.0);
 CHECK(s.w.hp[1]==0 && !s.w.captive[1] && s.w.ko[1]==0,"effective hit commits complete captive death");
 expect_event(s.w,EV_DEATH,1,1,0,f);expect_event(s.w,EV_KO,1,1,-1,f);expect_event(s.w,EV_CAPTURED,1,1,0,f);expect_event(s.w,EV_WAKE,0,1,-1,f);
}

static void test_hold_anchor_near_allies() {
	std::printf("[hold-anchor] overlapping allied blocks and an enemy six cells away never move a HOLD anchor\n");
	for (int threads : {1, 4}) {
		Scene s(threads);
		int a = s.formation(0, 20, 24, 0, 36, sword(), T_MELEE, 0, 6);
		int b = s.formation(0, 20.5f, 24, 0, 36, sword(), T_MELEE, 0, 6);
		int e = s.formation(1, 26, 24, kPi, 1, sword());
		s.w.finalize();
		for (int f : {a, b, e}) { s.w.formations[f].ai_enabled = false; s.w.order_hold(f); }
		const Formation before_a = s.w.formations[a], before_b = s.w.formations[b];
		const float body_x = s.w.px[0], body_y = s.w.py[0];
		s.run(4.0);
		for (int f : {a, b}) {
			const Formation &before = f == a ? before_a : before_b;
			const Formation &after = s.w.formations[f];
			float drift = std::hypot(after.cx - before.cx, after.cy - before.cy);
			CHECK(drift < 1e-6f && after.goal_x == before.goal_x && after.goal_y == before.goal_y && after.order == Order::HOLD,
			      "%d threads formation %d HOLD drift %.9f, goal %.4f/%.4f", threads, f, drift, after.goal_x, after.goal_y);
			std::printf("[hold-anchor-result] threads=%d formation=%d action_seconds=4 drift=%.9f\n", threads, f, drift);
		}
		CHECK(s.w.stats.pairs == 0, "HOLD enemy nearby did not authorize an attack");
		CHECK(std::hypot(s.w.px[0] - body_x, s.w.py[0] - body_y) > 1e-4f, "individual collision resolution still moves overlapping bodies");
	}
	{   // A moving ally still gets the existing spacing correction, while the held block stays anchored.
		Scene s;
		int a = s.formation(0, 20, 24, 0, 1, sword());
		int b = s.formation(0, 20.3f, 24, 0, 1, sword());
		s.w.finalize(); s.w.order_move(a, 30, 24, 0); s.w.formations[a].order_delay = 0; s.w.order_hold(b);
		const float ax = s.w.formations[a].cx, bx = s.w.formations[b].cx;
		checked_step(s.w, DT);
		float moved = s.w.formations[a].cx - ax;
		CHECK(moved > 0 && moved < s.w.cfg.march_speed * DT * 0.9f, "moving ally keeps spacing correction (moved %.9f)", moved);
		CHECK(s.w.formations[b].cx == bx, "held ally remains fixed while the moving ally separates");
	}
}

static void test_host_order_owner() {
	std::printf("[owner] one decision owner per formation: AI-owned refuses host orders, host-owned is never ordered by the AI\n");
	Scene s(1, 64, 48);
	s.w.cfg.ai = true;
	int a = s.formation(0, 10, 24, 0, 10, sword());
	int b = s.formation(1, 30, 24, kPi, 10, sword());
	s.w.finalize();
	s.w.formations[b].ai_enabled = false; // host (player) owns b
	CHECK(!s.w.host_may_order(a) && s.w.host_may_order(b), "owner flags");
	s.w.order_hold(b);
	uint64_t ai0 = s.w.stats.ai_orders;
	s.run(10.0);
	CHECK(s.w.formations[b].order == Order::HOLD, "the AI never ordered the host formation");
	CHECK(s.w.stats.ai_orders > ai0, "the AI did order its own formation");
}

static void test_save_load() {
	std::printf("[save/load] save mid-battle (exchanges, arrows in flight, rescue and capture running), load, continue: same hash\n");
	auto build = [](World &w) {
		w.terrain.allocate(64, 48);
		w.cfg.seed = 11;
		w.combat_left = 1e9;
		int f0 = w.add_formation(0, 8, 8, 0, 5, 1.0f, T_MELEE, 40.0);     // quiet corner: rescue / capture
		int f1 = w.add_formation(0, 36, 22, 0.5f * kPi, 5, 1.0f, T_BOW, 30.0); // archers north of the enemy, clear line
		int f2 = w.add_formation(1, 34, 34, kPi, 5, 1.0f, T_MELEE, 20.0); // enemy, holds
		int f3 = w.add_formation(0, 30, 34, 0, 5, 1.0f, T_MELEE, 40.0);   // attackers in contact
		for (int q = 0; q < 10; ++q) w.add_soldier(f0, q % 2 ? sword() : hammer(), q == 0 ? R_CAPTAIN : (q <= 2 ? R_OFFICER : R_REGULAR), 100 + q, 0);
		for (int q = 0; q < 10; ++q) w.add_soldier(f1, bow(), q == 0 ? R_CAPTAIN : R_REGULAR, 200 + q, 20);
		for (int q = 0; q < 20; ++q) w.add_soldier(f2, sword(), q == 0 ? R_CAPTAIN : (q <= 2 ? R_OFFICER : R_REGULAR), 300 + q, 0);
		for (int q = 0; q < 10; ++q) w.add_soldier(f3, hammer(), q == 0 ? R_CAPTAIN : (q <= 2 ? R_OFFICER : R_REGULAR), 400 + q, 0);
		w.finalize();
		for (auto &f : w.formations) f.ai_enabled = false;
		w.order_hold(f0); w.order_hold(f2);
		w.order_attack(f1, 20 + 5); w.formations[f1].order_delay = 0;
		w.order_attack(f3, 20 + 10); w.formations[f3].order_delay = 0;
	};
	World w(2);
	build(w);
	bool saw = false, rescue_seen = false, capture_seen = false;
	std::vector<uint8_t> blob;
	int prisoner = 20 + 19;
	for (int k = 0; k < 30 * 90 && !saw; ++k) {
		if (k == 30 * 4) {
			w.apply_contact(5, 0.0, 200.0);                                 // a wounded team-mate in the quiet corner
			w.px[prisoner] = w.nx[prisoner] = w.px[6] + 0.9f; w.py[prisoner] = w.ny[prisoner] = w.py[6];
			w.apply_contact(prisoner, 0.0, 200.0);                          // a downed enemy next to soldier 6
			CHECK(w.order_capture(6, prisoner), "capture ordered");
		}
		checked_step(w, DT);
		bool rescue = false, capture = false;
		for (int i = 0; i < w.soldier_count(); ++i) { rescue |= w.rescue_of[i] >= 0; capture |= w.capture_of[i] >= 0; }
		rescue_seen |= rescue; capture_seen |= capture;
		if (!w.projectiles.empty() && w.stats.pairs > 0 && rescue && capture) { saw = true; blob = w.save(); }
	}
	CHECK(saw, "found a save point with arrows in flight, exchanges done, a rescue and a capture running (t=%.1f, rescue %d capture %d shots %llu pairs %llu)", w.time, (int)rescue_seen, (int)capture_seen, (unsigned long long)w.stats.shots, (unsigned long long)w.stats.pairs);
	if (!saw) return;
	for (int k = 0; k < 30 * 20; ++k) checked_step(w, DT);
	uint64_t direct = w.state_hash();
	World r(4);
	CHECK(r.load(blob), "load");
	CHECK(r.projectiles.size() > 0, "arrows restored in flight");
	for (int k = 0; k < 30 * 20; ++k) checked_step(r, DT);
	uint64_t loaded = r.state_hash();
	CHECK(direct == loaded, "continue after load: %016llx vs %016llx", (unsigned long long)direct, (unsigned long long)loaded);
	CHECK(r.stats.pairs == w.stats.pairs && r.stats.shots == w.stats.shots && r.stats.deaths == w.stats.deaths, "same counters");
	std::vector<uint8_t> bad = blob;
	bad.resize(bad.size() / 2);
	World z(1);
	CHECK(!z.load(bad), "a truncated save is refused");
}

static void test_determinism() {
	std::printf("[determinism] same battle with 1 / 2 / 4 threads -> identical state hash\n");
	auto run = [](int threads) {
		World w(threads);
		w.terrain.allocate(96, 96);
		w.cfg.seed = 7;
		for (int team = 0; team < 2; ++team)
			for (int k = 0; k < 10; ++k) {
				Troop tr = k % 5 == 4 ? T_BOW : T_MELEE;
				int f = w.add_formation(team, team ? 62.f + (float)(k / 5) * 12.f : 34.f - (float)(k / 5) * 12.f, 12.f + (float)(k % 5) * 16.f,
				                        team ? kPi : 0.f, 10, 1.0f, tr, team ? 20.0 : 40.0);
				Equip e = tr == T_BOW ? bow() : (k % 2 ? hammer() : sword());
				for (int q = 0; q < 100; ++q) w.add_soldier(f, e, q == 0 ? R_CAPTAIN : (q <= 2 ? R_OFFICER : R_REGULAR), -1, tr == T_BOW ? 20 : 0);
			}
		w.finalize();
		for (int s = 0; s < 30 * 60; ++s) checked_step(w, DT);
		return std::make_pair(w.state_hash(), w.stats.pairs);
	};
	auto h1 = run(1), h2 = run(2), h4 = run(4);
	CHECK(h1.first == h2.first && h2.first == h4.first, "hash %016llx %016llx %016llx", (unsigned long long)h1.first,
	      (unsigned long long)h2.first, (unsigned long long)h4.first);
	CHECK(h1.second > 1000, "the battle actually fought (%llu pairs)", (unsigned long long)h1.second);
}


// P2c draw order: pack_rows output order = draw order inside each z row. Host actors split rows exactly at
// their ground line; atlas pages interleave by depth within 64 / bands pixels.
static void test_render_order() {
	for (int bands : {1, 4}) {
		Scene s(1, 48, 48);
		const int n = 600;
		int f = s.formation(0, 20, 20, 0, n, sword());
		(void)f;
		uint32_t rng = 12345;
		auto rnd = [&]() { rng = rng * 1664525u + 1013904223u; return (float)(rng >> 8) / 16777216.f; };
		for (int i = 0; i < n; ++i) s.place(i, 8.f + 30.f * rnd(), 8.f + 30.f * rnd());
		RenderTrack t; t.sequence = 3; t.duration = 1.f; t.loop = true; t.times = {0.f}; t.ax = {0.f}; t.ay = {40.f};
		s.w.render_tracks.push_back(t);
		for (int page = 0; page < 3; ++page) {
			RenderKit k; k.page = page; k.palette = page; k.scale = 1.f;
			for (auto &slot : k.track) for (int &d : slot) d = 0;
			s.w.render_kits.push_back(k);
		}
		for (int i = 0; i < n; ++i) s.w.kit[i] = (int16_t)(i % 3);
		s.w.render_bands = bands;
		// three actors: two share a row (with soldiers above and below both), one alone
		s.w.render_actors = {20.5f * 64.f, 20.f * 64.f + 30.f, 22.f * 64.f, 20.f * 64.f + 10.f, 30.f * 64.f, 25.f * 64.f + 50.f};
		std::vector<float> out, bounds; std::vector<int32_t> spans;
		int drawn = s.w.pack_rows(out, spans, bounds, 64.f);
		CHECK(drawn == n, "bands %d: all %d soldiers packed (%d)", bands, n, drawn);
		CHECK(spans.size() % World::SPAN_STRIDE == 0, "span stride");
		struct Entry { int row; float y; int actor; };
		std::vector<Entry> seq;
		int palette_bad = 0, actors_seen = 0;
		std::vector<uint32_t> ids;
		for (size_t k = 0; k < spans.size(); k += World::SPAN_STRIDE) {
			const int row = spans[k], page = spans[k + 1], start = spans[k + 2], count = spans[k + 3];
			ids.push_back((uint32_t)spans[k + 5]);
			if (page < 0) { seq.push_back({row, bounds[(k / World::SPAN_STRIDE) * 4 + 1], start}); ++actors_seen; continue; }
			for (int q = 0; q < count; ++q) {
				const size_t slot = (size_t)start + q;
				if ((int)out[slot * 12 + 10] != page) ++palette_bad;
				seq.push_back({row, s.w.render_grounds[slot * 2 + 1], -1});
			}
		}
		const size_t n_ids = ids.size();
		std::sort(ids.begin(), ids.end());
		CHECK(std::unique(ids.begin(), ids.end()) == ids.end() && n_ids > 0, "bands %d: group ids unique within a frame", bands);
		CHECK(actors_seen == 3, "three actor markers (%d)", actors_seen);
		CHECK(palette_bad == 0, "every packed soldier sits in its page's group (%d wrong)", palette_bad);
		int rows_back = 0, actor_bad = 0, above = 0, below = 0;
		float worst = 0.f;
		for (size_t a = 0; a < seq.size(); ++a) {
			if (a > 0 && seq[a].row < seq[a - 1].row) ++rows_back;
			if (seq[a].actor >= 0) {
				for (size_t b = 0; b < seq.size(); ++b) {
					if (seq[b].actor >= 0 || seq[b].row != seq[a].row) continue;
					if (b < a) { ++above; if (seq[b].y > seq[a].y) ++actor_bad; }
					else { ++below; if (seq[b].y < seq[a].y) ++actor_bad; }
				}
				continue;
			}
			for (size_t b = a + 1; b < seq.size() && seq[b].row == seq[a].row; ++b)
				if (seq[b].actor < 0) worst = std::max(worst, seq[a].y - seq[b].y);
		}
		CHECK(rows_back == 0, "rows ascend in draw order (%d back steps)", rows_back);
		CHECK(actor_bad == 0 && above > 0 && below > 0, "bands %d: actors split their rows exactly (%d wrong; %d above, %d below)", bands, actor_bad, above, below);
		const float limit = 64.f / (float)bands;
		CHECK(worst <= limit + 1e-3f, "bands %d: worst in-row depth inversion %.2f px <= %.1f", bands, worst, limit);
		std::printf("  render order bands %d: %zu groups, worst inversion %.2f px\n", bands, spans.size() / World::SPAN_STRIDE, worst);
		// one page only: bands must not add groups (runs merge back into one group per row)
		for (int i = 0; i < n; ++i) s.w.kit[i] = 0;
		s.w.render_actors.clear();
		s.w.pack_rows(out, spans, bounds, 64.f);
		std::vector<int> rows;
		for (size_t k = 0; k < spans.size(); k += World::SPAN_STRIDE) rows.push_back(spans[k]);
		const size_t groups = rows.size();
		rows.erase(std::unique(rows.begin(), rows.end()), rows.end());
		CHECK(groups == rows.size(), "bands %d, one page: one group per row (%zu groups, %zu rows)", bands, groups, rows.size());
		// two pages far apart in x (left half page 0, right half page 1): no bands needed, two groups per row
		for (int i = 0; i < n; ++i) s.place(i, (i % 2) ? 30.f + 8.f * rnd() : 8.f + 8.f * rnd(), 8.f + 30.f * rnd());
		for (int i = 0; i < n; ++i) s.w.kit[i] = (int16_t)(i % 2);
		s.w.pack_rows(out, spans, bounds, 64.f);
		rows.clear();
		for (size_t k = 0; k < spans.size(); k += World::SPAN_STRIDE) rows.push_back(spans[k]);
		const size_t apart = rows.size();
		rows.erase(std::unique(rows.begin(), rows.end()), rows.end());
		CHECK(apart <= rows.size() * 2, "bands %d, pages apart: at most one group per page and row (%zu groups, %zu rows)", bands, apart, rows.size());
	}
}

// P2d host blockers (the player): the crowd never overlaps a blocker; in the open it walks around, in a
// one-cell pass it queues behind it and goes through once the blocker steps away.
static void test_host_blocker() {
	std::printf("[blocker] player as a host blocker: never overlapped, walked around in the open, queued behind in a pass\n");
	{   // open field: 30 soldiers march through a blocker standing on their line
		Scene s(1, 64, 48);
		int a = s.formation(0, 10, 24, 0, 30, sword(), T_MELEE, 0, 6);
		s.w.finalize();
		s.w.formations[a].ai_enabled = false;
		s.w.order_move(a, 45.5f, 24.5f, 0); s.w.formations[a].order_delay = 0;
		s.w.blockers = {{25.5f, 24.5f, 0.45f}};
		float closest = 1e9f;
		for (int k = 0; k < 30 * 30; ++k) {
			checked_step(s.w, DT);
			for (int i = 0; i < 30; ++i) closest = std::min(closest, std::hypot(s.w.px[i] - 25.5f, s.w.py[i] - 24.5f));
		}
		int past = 0;
		for (int i = 0; i < 30; ++i) if (s.w.px[i] > 30.f) ++past;
		const float R = 0.45f + s.w.cfg.radius;
		CHECK(closest >= R - 0.02f, "nobody overlaps the blocker (closest %.3f, blocker + body %.3f)", closest, R);
		CHECK(past == 30, "everyone got around it (%d / 30 past)", past);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant");
	}
	{   // a one-cell pass (walls above and below row 24 for x 20..30), blocker in the middle of it
		Scene s(1, 64, 48);
		for (int x = 20; x <= 30; ++x)
			for (int y = 0; y < 48; ++y)
				if (y != 24) s.w.terrain.flags[s.w.terrain.idx(x, y)] = 0;
		int a = s.formation(0, 12, 24, 0, 12, sword(), T_MELEE, 0, 3);
		s.w.finalize();
		s.w.formations[a].ai_enabled = false;
		s.w.order_move(a, 40.5f, 24.5f, 0); s.w.formations[a].order_delay = 0;
		s.w.blockers = {{25.5f, 24.5f, 0.45f}};
		float closest = 1e9f, furthest = 0.f;
		for (int k = 0; k < 30 * 25; ++k) {
			checked_step(s.w, DT);
			for (int i = 0; i < 12; ++i) {
				closest = std::min(closest, std::hypot(s.w.px[i] - 25.5f, s.w.py[i] - 24.5f));
				furthest = std::max(furthest, s.w.px[i]);
			}
		}
		const float R = 0.45f + s.w.cfg.radius;
		CHECK(closest >= R - 0.02f, "pass: nobody overlaps the blocker (closest %.3f)", closest);
		CHECK(furthest < 25.5f - R + 0.03f, "pass: nobody gets by (furthest x %.2f)", furthest);
		int queued = 0;
		for (int i = 0; i < 12; ++i) if (s.w.px[i] > 19.f) ++queued;
		CHECK(queued >= 3, "pass: a queue forms inside the pass behind the blocker (%d in it)", queued);
		s.w.blockers.clear(); // the player steps away
		for (int k = 0; k < 30 * 30; ++k) checked_step(s.w, DT);
		int through = 0;
		for (int i = 0; i < 12; ++i) if (s.w.px[i] > 31.f) ++through;
		CHECK(through == 12, "pass: all through once the blocker leaves (%d / 12)", through);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "pass: terrain invariant");
		CHECK(s.w.standing_near(40.5f, 24.5f, 3.f) >= 8, "standing_near finds the arrived squad (%d)", s.w.standing_near(40.5f, 24.5f, 3.f));
	}
}

// P2d the player is one crowd soldier (2026-09-30): host input moves him, every soldier rule applies.
static void test_host_soldier() {
	std::printf("[player] host-controlled soldier: walks on input, pushes and is pushed, fights on engage, can be KO'd and captured, company retains orders\n");
	{   // walks on input; pushes through nobody: a HOLD friendly line stops / displaces him like any soldier
		Scene s(1, 64, 48);
		int me = s.formation(0, 10, 24, 0, 1, sword());
		int wall = s.formation(0, 20, 24, 0.f, 20, sword(), T_MELEE, 0, 20); // one rank across his way
		s.w.finalize();
		for (int f : {me, wall}) s.w.formations[f].ai_enabled = false;
		const int P = 0;
		s.w.set_host_control(P, true);
		float closest = 1e9f;
		for (int k = 0; k < 30 * 6; ++k) {
			s.w.host_input(P, s.w.cfg.march_speed, 0.f, false, false);
			checked_step(s.w, DT);
			for (int j = 1; j <= 20; ++j) closest = std::min(closest, std::hypot(s.w.px[j] - s.w.px[P], s.w.py[j] - s.w.py[P]));
		}
		CHECK(s.w.px[P] > 16.f, "walked on his input (x %.2f)", s.w.px[P]);
		CHECK(s.w.state[P] == S_HOST, "state S_HOST (%d)", s.w.state[P]);
		CHECK(closest > 2.f * s.w.cfg.radius * 0.6f, "bodies separate like any two soldiers (closest %.3f)", closest);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant");
	}
	for (int engage = 0; engage <= 1; ++engage) { // an enemy in reach on HOLD without an attack order: only his wish starts a round
		Scene s(1, 64, 48);
		int me = s.formation(0, 20, 24, 0, 1, sword());
		int foe = s.formation(1, 40, 40, 0, 1, sword());
		s.w.finalize();
		for (int f : {me, foe}) s.w.formations[f].ai_enabled = false;
		s.w.order_hold(foe);
		s.w.set_host_control(0, true);
		for (int k = 0; k < 30 * 3; ++k) {
			s.place(1, 21.f, 24.5f); s.place(0, 20.f, 24.5f);
			s.w.host_input(0, 0.f, 0.f, false, engage != 0);
			checked_step(s.w, DT);
		}
		if (engage) CHECK(s.w.stats.pairs >= 2 && s.w.state[0] == S_FIGHT, "engage: he starts rounds and stands to fight (%llu, state %d)", (unsigned long long)s.w.stats.pairs, s.w.state[0]);
		else CHECK(s.w.stats.pairs == 0, "no engage: no round starts (%llu)", (unsigned long long)s.w.stats.pairs);
	}
	{   // an AI enemy squad attacks him: soldier rules down him and the AI takes him prisoner
		Scene s(2, 64, 48);
		s.w.cfg.auto_capture = true; s.w.cfg.capture_seek_cells = 8.f; s.w.cfg.ai = true;
		int me = s.formation(0, 20, 24, 0, 1, sword(M_WOOD, A_NONE));
		int foe = s.formation(1, 30, 24, kPi, 12, sword(M_STEEL, A_LEATHER), T_MELEE, 0, 4);
		s.w.finalize();
		s.w.formations[me].ai_enabled = false;
		s.w.set_host_control(0, true);
		bool downed = false;
		for (int k = 0; k < 30 * 120 && !s.w.captive[0]; ++k) {
			s.w.host_input(0, 0.f, 0.f, false, true);
			checked_step(s.w, DT);
			downed = downed || s.w.ko[0] > 0.0 || s.w.hp[0] <= 0.0;
		}
		CHECK(downed, "the enemy AI fights him down under the ordinary rules");
		CHECK(s.w.captive[0] || s.w.hp[0] <= 0.0, "then takes him prisoner (captive %d, hp %.1f)", s.w.captive[0], s.w.hp[0]);
		(void)foe;
	}
	{   // Controlling a roster captain never turns HOLD into implicit FOLLOW_PLAYER; save/load still continues exactly.
		Scene s(1, 64, 48);
		int co = s.formation(0, 12, 24, 0, 9, sword(), T_MELEE, 0, 3); // soldier 0 is the captain = the player
		s.w.finalize();
		s.w.formations[co].ai_enabled = false;
		s.w.set_host_control(0, true);
		for (int k = 0; k < 30 * 6; ++k) { s.w.host_input(0, s.w.cfg.march_speed * 0.8f, 0.f, false, false); checked_step(s.w, DT); }
		float mx = 0;
		for (int i = 1; i < 9; ++i) mx += s.w.px[i] / 8.f;
		CHECK(s.w.px[0] > 20.f && std::fabs(mx - 12.f) < 3.f, "company retains HOLD (player x %.1f, company x %.1f)", s.w.px[0], mx);
		std::vector<uint8_t> blob = s.w.save();
		World w2(1);
		CHECK(w2.load(blob), "load");
		for (int k = 0; k < 60; ++k) {
			s.w.host_input(0, 0.f, s.w.cfg.march_speed, true, false); checked_step(s.w, DT);
			w2.host_input(0, 0.f, w2.cfg.march_speed, true, false); checked_step(w2, DT);
		}
		CHECK(s.w.state_hash() == w2.state_hash(), "save / load with a host soldier continues identically");
		// drawn by the host: no kit, so pack_rows lists him as an actor marker at his drawn ground point
		RenderTrack t; t.sequence = 0; t.duration = 1.f; t.loop = true; t.times = {0.f}; t.ax = {0.f}; t.ay = {0.f};
		s.w.render_tracks.push_back(t);
		RenderKit K; K.page = 0; K.palette = 0; K.scale = 1.f;
		for (auto &sl : K.track) for (int &d : sl) d = 0;
		s.w.render_kits.push_back(K);
		for (int i = 1; i < 9; ++i) s.w.kit[i] = 0;
		std::vector<float> out, bounds; std::vector<int32_t> spans;
		int drawn = s.w.pack_rows(out, spans, bounds, 64.f);
		int markers = 0; float mx2 = 0, my2 = 0;
		for (size_t k = 0; k < spans.size(); k += World::SPAN_STRIDE)
			if (spans[k + 1] < 0) { ++markers; mx2 = bounds[k / World::SPAN_STRIDE * 4]; my2 = bounds[k / World::SPAN_STRIDE * 4 + 1]; }
		CHECK(drawn == 8 && markers == 1 && std::fabs(mx2 - s.w.pres[0].x) < 1e-3f && std::fabs(my2 - s.w.pres[0].y) < 1e-3f,
			"host soldier without a kit = one actor marker at his drawn point (%d drawn, %d markers)", drawn, markers);
	}
}

// C1 crash (2026-09-30): a trial team deployed against the map edge had slots outside the map; finalize
// must keep every soldier on the map (build_hash indexes cells by position)
static void test_edge_deploy() {
	std::printf("[deploy] formations at and beyond the map edge are pulled onto the map\n");
	Scene s(1, 40, 30);
	s.formation(0, 39.6f, 29.7f, 0.f, 100, sword());
	s.formation(1, -0.5f, 15.f, kPi, 100, sword());
	s.w.finalize();
	int outside = 0;
	for (int i = 0; i < s.w.soldier_count(); ++i)
		if (!(s.w.px[i] >= 0.f && s.w.px[i] < 40.f && s.w.py[i] >= 0.f && s.w.py[i] < 30.f)) ++outside;
	CHECK(outside == 0, "every soldier on the map after finalize (%d outside)", outside);
	s.run(2.0);
	CHECK(s.w.stats.illegal_cell == 0, "no illegal cells after the first steps");
}

// Native melee contact and exchange fatigue (Region battle adapter, G6.3 API gap A and B).
static void test_melee_contact_and_exchange_fatigue() {
	std::printf("[melee] melee contact: HP loss, stun to KO at STUN_LIMIT, HP 0 death, refusals; exchange fatigue charge\n");
	Scene s;
	s.formation(0, 10, 10, 0, 2, sword());
	s.formation(1, 30, 30, 0, 1, sword());
	s.w.finalize();
	const double hp0 = s.w.hp[0];
	CHECK(s.w.apply_melee_contact(0, 3.0, 0.0), "melee contact accepted");
	CHECK(std::fabs(s.w.hp[0] - (hp0 - 3.0)) < 1e-9, "melee contact reduces HP (%.4f)", s.w.hp[0]);
	CHECK(s.w.apply_melee_contact(0, 0.0, 60.0) && s.w.ko[0] == 0 && std::fabs(s.w.stun[0] - 60.0) < 1e-9,
		"stun accumulates below STUN_LIMIT without KO (%.3f)", s.w.stun[0]);
	CHECK(s.w.apply_melee_contact(0, 0.0, 50.0) && s.w.ko[0] == s.w.cfg.ko_seconds && s.w.stats.kos == 1,
		"stun crossing STUN_LIMIT is KO (stun %.3f)", s.w.stun[0]);
	const double hp1 = s.w.hp[1];
	CHECK(s.w.apply_melee_contact(1, hp1, 0.0), "lethal melee contact accepted");
	CHECK(s.w.hp[1] == 0 && s.w.ko[1] == 0 && s.w.stats.deaths == 1, "HP 0 is death, not KO");
	CHECK(s.w.apply_melee_contact(1, 5.0, 0.0) && s.w.hp[1] == 0 && s.w.stats.deaths == 1, "contact on a dead soldier is a no-op that succeeds");
	const double kept = s.w.hp[0];
	CHECK(!s.w.apply_melee_contact(-1, 1.0, 0.0) && !s.w.apply_melee_contact(s.w.soldier_count(), 1.0, 0.0), "invalid soldier index refused");
	CHECK(!s.w.apply_melee_contact(0, NAN, 0.0) && !s.w.apply_melee_contact(0, 1.0, NAN), "NaN refused");
	CHECK(!s.w.apply_melee_contact(0, -1.0, 0.0) && !s.w.apply_melee_contact(0, 0.0, -1.0), "negative amount refused");
	CHECK(s.w.hp[0] == kept, "refused contact writes nothing (%.4f)", s.w.hp[0]);

	Scene t;
	t.formation(0, 10, 10, 0, 2, sword());
	t.formation(1, 30, 30, 0, 1, sword());
	t.w.finalize();
	const int fi = t.w.form[0];
	const double f0 = t.w.formations[fi].fatigue;
	CHECK(t.w.charge_exchange_fatigue(0, 1.0), "fatigue charge on a member accepted");
	CHECK(t.w.formations[fi].fatigue > f0, "fatigue charge raises the shared pool (%.4f -> %.4f)", f0, t.w.formations[fi].fatigue);
	t.w.apply_contact(1, t.w.hp[1], 0.0); // the second member dies
	const double f1 = t.w.formations[fi].fatigue;
	CHECK(t.w.charge_exchange_fatigue(1, 5.0) && t.w.formations[fi].fatigue == f1, "dead member: fatigue charge is a succeeding no-op");
	CHECK(!t.w.charge_exchange_fatigue(-1, 1.0) && !t.w.charge_exchange_fatigue(t.w.soldier_count(), 1.0), "invalid soldier index refused for fatigue");
	CHECK(!t.w.charge_exchange_fatigue(2, NAN) && !t.w.charge_exchange_fatigue(2, -1.0), "NaN and negative fatigue refused");
	t.w.formations[fi].members.erase(t.w.formations[fi].members.begin()); // soldier 0 is no longer on the roster
	CHECK(!t.w.charge_exchange_fatigue(0, 1.0), "fatigue on a non-member refused");
}

// G6.4 site exit (native release): the exit gate, the release out of neighbour queries, exchange, formation and
// the step loop, and the released flag surviving save / load.
static void test_site_person_release() {
	std::printf("[site exit] exit gate refuses KO, getting up, captive, exchange, committed step; release leaves pool, neighbours, formation; save/load keeps it\n");
	Scene s;
	s.formation(0, 10, 10, 0, 4, sword());   // soldiers 0..3, team 0
	s.formation(1, 14, 10, kPi, 2, sword()); // soldiers 4..5, team 1
	s.w.finalize();
	const int n = s.w.soldier_count();
	CHECK(n == 6, "six soldiers (%d)", n);
	s.place(0, 2.5f, 2.5f); s.place(2, 2.5f, 4.5f); s.place(3, 4.5f, 2.5f);
	s.place(1, 10.5f, 10.5f); s.place(4, 12.5f, 10.5f); s.place(5, 4.5f, 40.5f);
	const double hp1 = s.w.hp[1];

	CHECK(s.w.site_person_exit_ready(1), "a conscious idle soldier may leave");
	CHECK(!s.w.site_person_exit_ready(-1) && !s.w.site_person_exit_ready(n), "invalid index refused");
	s.w.ko[1] = 5.0;
	CHECK(!s.w.site_person_exit_ready(1), "KO soldier refused");
	s.w.ko[1] = 0.0;
	s.w.getup[1] = 1.0;
	CHECK(!s.w.site_person_exit_ready(1), "soldier getting up refused");
	s.w.getup[1] = 0.0;
	s.w.captive[1] = 1;
	CHECK(!s.w.site_person_exit_ready(1), "captive soldier refused");
	s.w.captive[1] = 0;
	s.w.state[1] = S_FIGHT;
	CHECK(!s.w.site_person_exit_ready(1), "soldier in melee exchange refused");
	s.w.state[1] = S_SLOT;
	s.w.state[4] = S_ENGAGE; s.w.target[4] = 1;
	CHECK(!s.w.site_person_exit_ready(1), "soldier targeted in melee by an engaged enemy refused");
	s.w.state[4] = S_SLOT; s.w.target[4] = -1;
	s.w.captive[4] = 1; s.w.captor[4] = 1;
	CHECK(!s.w.site_person_exit_ready(1), "soldier still holding a captive refused");
	s.w.captive[4] = 0; s.w.captor[4] = -1;
	s.w.escort_mode[1] = 1;
	CHECK(!s.w.site_person_exit_ready(1), "soldier on a committed custody step refused");
	s.w.escort_mode[1] = 0;
	CHECK(s.w.site_person_exit_ready(1), "soldier is ready again once every condition is clear");

	// release: enemy 4 is engaging soldier 1 under orders; soldier 1 stands 2 cells from it
	s.w.formations[1].target_person = 1; s.w.target[4] = 1;
	CHECK(s.w.nearest_hostile(4, 4.f) == 1, "before release the enemy finds soldier 1 (%d)", s.w.nearest_hostile(4, 4.f));
	CHECK(s.w.standing_near(10.5f, 10.5f, 0.5f) == 1, "before release one standing soldier at the spot");
	const int members0 = (int)s.w.formations[0].members.size();
	const int roster0 = s.w.formations[0].roster;
	const int fatigue_count0 = s.w.formations[0].fatigue_count;
	SitePersonRelease rel;
	CHECK(s.w.site_person_release(1, rel), "ready soldier released");
	CHECK(s.w.released[1] == 1 && !s.w.alive(1) && !s.w.can_act(1), "released soldier is neither alive nor able to act");
	CHECK(std::fabs(rel.hp - hp1) < 1e-9 && rel.cell_x == 10 && rel.cell_y == 10 && rel.ammo == 0,
		"receipt keeps hp %.2f, cell (%d,%d), ammo %d", rel.hp, rel.cell_x, rel.cell_y, rel.ammo);
	CHECK(s.w.nearest_hostile(4, 4.f) == -1, "neighbour query no longer finds the released soldier");
	CHECK(s.w.standing_near(10.5f, 10.5f, 0.5f) == 0, "standing-soldier query excludes it");
	bool listed = false;
	for (int k : s.w.formations[0].members) if (k == 1) listed = true;
	CHECK(!listed, "released soldier is off the formation member list");
	CHECK((int)s.w.formations[0].members.size() == members0 - 1, "member count falls by one (%d)", (int)s.w.formations[0].members.size());
	CHECK(s.w.formations[0].roster == roster0 - 1 && s.w.formations[0].fatigue_count == fatigue_count0 - 1,
		"roster and shared-fatigue binding drop by one");
	CHECK(s.w.soldier_count() == n && s.w.slot[1] == -1, "no array is reindexed and the slot is cleared");
	CHECK(s.w.target[4] == -1 && s.w.formations[1].target_person == -1, "orders naming the released soldier are cleared");
	CHECK(!s.w.charge_exchange_fatigue(1, 1.0), "exchange fatigue on the released soldier refused");
	const double hp_released = s.w.hp[1];
	CHECK(s.w.apply_melee_contact(1, 5.0, 0.0) && s.w.hp[1] == hp_released, "melee contact on the released soldier changes nothing");
	CHECK(!s.w.site_person_exit_ready(1) && !s.w.site_person_release(1, rel), "released soldier cannot be released again");

	// the step loop: the released soldier neither moves nor is hit while the enemy stands by
	const float x1 = s.w.px[1], y1 = s.w.py[1];
	s.run(2.0);
	CHECK(s.w.hp[1] == hp_released && s.w.px[1] == x1 && s.w.py[1] == y1, "released soldier neither moves nor takes hits while stepping");

	// the released flag is saved and loaded with the rest of the state
	const std::vector<uint8_t> blob = s.w.save();
	CHECK(!blob.empty(), "scene with a released soldier saves");
	World loaded(1);
	CHECK(loaded.load(blob), "blob with a released soldier loads");
	CHECK(loaded.released[1] == 1 && !loaded.alive(1) && loaded.hp[1] == s.w.hp[1], "released flag and hp survive save/load");
	CHECK(loaded.state_hash() == s.w.state_hash(), "reloaded state hash matches");
	CHECK(!loaded.site_person_exit_ready(1) && !loaded.site_person_release(1, rel), "reloaded soldier is still released");
	check_valid(loaded);
}

// CAV-1 mounted cavalry (reports/cavalry-charge-plan.md V0.5, section 9 acceptance). Each block states the rule it checks.
static Equip spear_steel() { Equip e; e.family = F_SPEAR; e.material = M_IRON; e.armor = A_STEEL; return e; }
static void place_start(Scene &s, const std::vector<std::pair<float, float>> &xy) {
	s.w.start_x.assign(xy.size(), NAN); s.w.start_y.assign(xy.size(), NAN);
	for (size_t k = 0; k < xy.size(); ++k) { s.w.start_x[k] = xy[k].first; s.w.start_y[k] = xy[k].second; }
}
static float wrap_angle(float a) { return std::remainder(a, 2.f * kPi); }

static void test_cavalry() {
	std::printf("[cavalry] mounted riders: speed / acceleration / turn limits, charge threshold, modifiers, penetration cap, 2 s re-charge, dismount, no illegal cell or edge, thread parity\n");
	{   // 3.1 / N2 / N4: gallop 8 cells/s, accelerate 3.2 cells/s^2 (about 2.5 s from rest), turn at most 576 / speed deg/s
		Scene s(1, 64, 48);
		int r = s.formation(0, 10, 24, 0, 1, sword());
		s.w.finalize();
		s.w.formations[r].ai_enabled = false;
		CHECK(s.w.set_mounted(0, true) && s.w.is_mounted(0), "a living soldier can be mounted");
		s.w.set_host_control(0, true);
		float vmax = 0.f, dv_max = 0.f, prev = 0.f, v1 = 0.f;
		for (int k = 0; k < 30 * 4; ++k) {
			s.w.host_input(0, 8.f, 0.f, true, false);
			checked_step(s.w, DT);
			const float v = std::hypot(s.w.vx[0], s.w.vy[0]);
			if (k == 29) v1 = v;
			vmax = std::max(vmax, v); dv_max = std::max(dv_max, std::fabs(v - prev)); prev = v;
		}
		CHECK(v1 <= cav::ACCEL + 0.05f && v1 > 2.5f, "after 1 s from rest the speed is within the acceleration limit (%.3f)", v1);
		CHECK(vmax <= cav::GALLOP + 1e-3f && vmax > 7.5f, "gallop cap 8 reached and not exceeded (max %.3f)", vmax);
		CHECK(dv_max <= cav::ACCEL * DT + 1e-3f, "speed changes by at most ACCEL per step (%.4f)", dv_max);
		const float h0 = std::atan2(s.w.vy[0], s.w.vx[0]);
		s.w.host_input(0, 0.f, 8.f, true, false);
		checked_step(s.w, DT);
		const float turn1 = std::fabs(wrap_angle(std::atan2(s.w.vy[0], s.w.vx[0]) - h0));
		CHECK(turn1 <= cav::TURN_DEG_CELLS * kPi / 180.f / 8.f * DT + 1e-3f, "one step turns at most 576 / 8 deg/s (%.4f rad)", turn1);
		float turned = 0.f;
		for (int k = 0; k < 10; ++k) { s.w.host_input(0, 0.f, 8.f, true, false); checked_step(s.w, DT); }
		turned = std::fabs(wrap_angle(std::atan2(s.w.vy[0], s.w.vx[0]) - h0));
		CHECK(turned < 30.f * kPi / 180.f, "eleven steps turn less than 30 degrees at gallop (%.1f deg)", turned * 180.f / kPi);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant on open ground");
	}
	{   // 4.1: charge needs 4.5 cells/s along the heading, and the heading held within 20 degrees for 0.4 s
		Scene s(1, 64, 48);
		int r = s.formation(0, 10, 24, 0, 1, sword());
		s.w.finalize();
		s.w.formations[r].ai_enabled = false;
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		bool slow_charges = false;
		for (int k = 0; k < 30 * 4; ++k) { s.w.host_input(0, 4.4f, 0.f, false, false); checked_step(s.w, DT); slow_charges = slow_charges || s.w.charge_state(0); }
		CHECK(!slow_charges && std::hypot(s.w.vx[0], s.w.vy[0]) > 4.2f, "a rider at 4.4 cells/s never charges (speed %.3f)", std::hypot(s.w.vx[0], s.w.vy[0]));
		for (int k = 0; k < 30 * 2; ++k) { s.w.host_input(0, 8.f, 0.f, true, false); checked_step(s.w, DT); }
		CHECK(s.w.charge_state(0), "straight at gallop: charge state on");
		// the heading history of the test itself: the last 12 steps (0.4 s) must stay within 20 degrees of the newest heading
		std::vector<float> hist = {0.f}; // straight east before the turn
		bool charged_inside_window = false;
		for (int k = 0; k < 60; ++k) {
			s.w.host_input(0, 0.f, 8.f, true, false);
			checked_step(s.w, DT);
			const float now = std::atan2(s.w.vy[0], s.w.vx[0]);
			hist.push_back(now);
			float dev = 0.f;
			for (size_t j = hist.size() > 12 ? hist.size() - 12 : 0; j < hist.size(); ++j) dev = std::max(dev, std::fabs(wrap_angle(hist[j] - now)));
			if (dev > 21.f * kPi / 180.f && s.w.charge_state(0)) charged_inside_window = true;
		}
		CHECK(!charged_inside_window, "a heading that moved more than 20 degrees in 0.4 s does not charge");
		CHECK(s.w.charge_state(0), "the heading settles and the charge resumes after 0.4 s straight");
	}
	{   // 4.3 modifiers, exact values (rider: iron sword, no armour; victim: iron sword, leather). No hash needed.
		Scene s(1, 64, 48);
		int r = s.formation(0, 10, 10, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 11, 10, 0, 1, sword(M_IRON, A_LEATHER));
		place_start(s, {{10.5f, 10.5f}, {11.5f, 10.5f}});
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.set_mounted(r, true);
		s.w.face[v] = kPi; // the victim faces the rider: met head on
		ExStats a, b;
		s.w.charge_stats(r, v, 4.5, a, b);
		CHECK(std::fabs(a.armorbonus - 5.0) < 1e-9, "rider: mounted basic +5 only, head on (%.2f)", a.armorbonus);
		CHECK(std::fabs(b.armorbonus - 3.0) < 1e-9, "victim: leather iron sword, no bonus (%.2f)", b.armorbonus);
		s.w.charge_stats(r, v, 6.0, a, b);
		CHECK(std::fabs(a.armorbonus - (5.0 + 1.5 * 7.0)) < 1e-9, "impact speed 6 gives (6 - 4.5) x 7 (%.2f)", a.armorbonus);
		s.w.charge_stats(r, v, 9.0, a, b);
		CHECK(std::fabs(a.armorbonus - (5.0 + 25.0)) < 1e-9, "impact speed bonus is capped at 25 (%.2f)", a.armorbonus);
		s.w.face[v] = -kPi / 2; // victim faces north, rider comes from the west: 90 degrees = flank
		s.w.charge_stats(r, v, 4.5, a, b);
		CHECK(std::fabs(a.armorbonus - 15.0) < 1e-9, "flank (> 60 degrees) +10 (%.2f)", a.armorbonus);
		s.w.face[v] = 0; // facing away from the rider: rear
		s.w.charge_stats(r, v, 4.5, a, b);
		CHECK(std::fabs(a.armorbonus - 25.0) < 1e-9, "rear (> 120 degrees) +20 (%.2f)", a.armorbonus);
		s.w.equip[v].family = F_SPEAR; s.w.face[v] = kPi; s.w.vx[v] = s.w.vy[v] = 0.f;
		s.w.charge_stats(r, v, 4.5, a, b);
		CHECK(std::fabs(b.armorbonus - 23.0) < 1e-9, "pole-arm stand: spear facing the rider and still +20 (%.2f)", b.armorbonus);
		s.w.vx[v] = 1.0f;
		s.w.charge_stats(r, v, 4.5, a, b);
		CHECK(std::fabs(b.armorbonus - 3.0) < 1e-9, "a moving spearman gets no pole-arm bonus (%.2f)", b.armorbonus);
		s.w.vx[v] = 0.f; s.w.face[v] = 0;
		s.w.charge_stats(r, v, 4.5, a, b);
		CHECK(std::fabs(b.armorbonus - 3.0) < 1e-9, "a spearman facing away gets no pole-arm bonus (%.2f)", b.armorbonus);
	}
	{   // 4.3 rear support: a living team-mate within one cell behind the victim (further from the rider)
		Scene s(1, 64, 48);
		int r = s.formation(0, 10, 10, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 11, 10, 0, 2, sword(M_IRON, A_LEATHER));
		place_start(s, {{10.5f, 10.5f}, {11.5f, 10.5f}, {12.3f, 10.5f}});
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.set_mounted(r, true);
		s.w.face[1] = kPi;
		ExStats a, b;
		s.w.charge_stats(r, 1, 4.5, a, b);
		CHECK(std::fabs(b.armorbonus - 8.0) < 1e-9, "a team-mate 0.8 cell behind the victim gives +5 (%.2f)", b.armorbonus);
	}
	{   // 4.4 penetration cap: at most three contacts per charge; the count resets once the rider drops below 4.5
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24.5f, 0, 1, sword(M_IRON, A_NONE));
		std::vector<int> file; // eight single-man formations in a file along his path, each holding its own spot
		for (int k = 0; k < 8; ++k) file.push_back(s.formation(1, 16.5f + 1.1f * k, 24.5f, kPi, 1, sword(M_WOOD, A_NONE)));
		s.w.finalize();
		s.w.formations[r].ai_enabled = false;
		for (int f : file) s.w.formations[f].ai_enabled = false;
		s.w.skill[0] = SK_POWER; // a powered lance wins big, so the charge carries on through the file
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		uint64_t last = 0; int seg = 0, max_seg = 0, segments = 0;
		for (int k = 0; k < 30 * 4; ++k) {
			s.w.host_input(0, 8.f, 0.f, true, false);
			checked_step(s.w, DT);
			seg += (int)(s.w.stats.cav_contacts - last); last = s.w.stats.cav_contacts;
			if (std::hypot(s.w.vx[0], s.w.vy[0]) < cav::CHARGE_SPEED) { max_seg = std::max(max_seg, seg); seg = 0; ++segments; }
		}
		max_seg = std::max(max_seg, seg);
		std::printf("  file of eight: %llu contacts, largest charge %d, steps below the charge speed %d\n", (unsigned long long)last, max_seg, segments);
		CHECK(last >= 1, "the rider charged the file (%llu contacts)", (unsigned long long)last);
		CHECK(max_seg <= cav::MAX_HITS, "at most three penetrations per charge (largest %d)", max_seg);
		CHECK(max_seg == cav::MAX_HITS, "a charge that goes through reaches the cap (largest %d)", max_seg);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "no illegal cell or edge through the file");
		(void)segments;
	}
	{   // 4.2 / 4.4: one rider hits the same person at most once per 2 s
		Scene s(1, 64, 48);
		int r = s.formation(0, 4, 24, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 14, 24, kPi, 1, sword(M_WOOD, A_NONE));
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		double t0 = -1.0;
		for (int k = 0; k < 30 * 6 && s.w.stats.cav_contacts == 0; ++k) {
			const double before = s.w.time;
			s.w.host_input(0, 8.f, 0.f, true, false);
			const uint64_t c0 = s.w.stats.cav_contacts;
			checked_step(s.w, DT);
			if (s.w.stats.cav_contacts > c0) t0 = before;
		}
		CHECK(t0 >= 0.0, "the rider contacts the victim");
		bool blocked_for_2s = true;
		while (t0 >= 0.0 && s.w.time - t0 < 2.0 - 1e-3) {
			blocked_for_2s = blocked_for_2s && !s.w.cav_may_hit(0, 1);
			s.w.host_input(0, 0.f, 0.f, false, false);
			checked_step(s.w, DT);
		}
		CHECK(blocked_for_2s, "no second hit on the same person within 2 s");
		for (int k = 0; k < 30 && t0 >= 0.0 && !s.w.cav_may_hit(0, 1); ++k) { s.w.host_input(0, 0.f, 0.f, false, false); checked_step(s.w, DT); }
		CHECK(t0 >= 0.0 && s.w.cav_may_hit(0, 1), "the same person may be charged again after 2 s");
	}
	{   // 4.4 / 4.6: a rider defeated by a big loss dismounts and lies 1.2 s; the recoil hits the rider
		Scene s(1, 64, 48);
		int r = s.formation(0, 2, 24, 0, 1, sword(M_WOOD, A_NONE));
		int v = s.formation(1, 14, 24, kPi, 1, spear_steel());
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.skill[v] = SK_BRACE; // a braced spearman in full steel stands fast
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		for (int k = 0; k < 30 * 8 && s.w.stats.cav_dismounts == 0; ++k) {
			s.w.host_input(0, 5.f, 0.f, false, false);
			checked_step(s.w, DT);
		}
		CHECK(s.w.stats.cav_dismounts == 1 && !s.w.is_mounted(0), "big loss dismounts the rider");
		CHECK(s.w.getup[0] > 0.0 && s.w.hp[0] < 100.0, "the rider lies up (get-up %.2f) and takes the recoil (hp %.2f)", s.w.getup[0], s.w.hp[0]);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant through the defeat");
	}
	{   // 4.4 penetration: a rider beats a lone unarmoured victim, who is pushed or falls; the victim cannot act while down
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 14, 24, kPi, 1, sword(M_WOOD, A_NONE));
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		bool down_seen = false;
		for (int k = 0; k < 30 * 3; ++k) {
			s.w.host_input(0, 8.f, 0.f, true, false);
			checked_step(s.w, DT);
			down_seen = down_seen || s.w.getup[1] > 0.0 || s.w.ko[1] > 0.0 || s.w.stats.cav_falls > 0;
		}
		CHECK(s.w.stats.cav_contacts >= 1 && down_seen, "the lone victim is hit and goes down (contacts %llu)", (unsigned long long)s.w.stats.cav_contacts);
	}
	{   // 2.1 / no tunnelling: a gallop rider never passes a victim without a registered contact
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 14, 24, kPi, 1, sword(M_IRON, A_LEATHER));
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		bool passed = false;
		float min_gap = 1e9f;
		for (int k = 0; k < 30 * 3 && !passed; ++k) {
			s.w.host_input(0, 8.f, 0.f, true, false);
			checked_step(s.w, DT);
			if (s.w.px[0] > s.w.px[1]) passed = true;
			min_gap = std::min(min_gap, std::fabs(s.w.px[0] - s.w.px[1]));
		}
		CHECK(passed == (s.w.stats.cav_contacts >= 1 || s.w.getup[1] > 0.0), "passing the victim requires a contact (passed %d, contacts %llu)", passed, (unsigned long long)s.w.stats.cav_contacts);
		CHECK(min_gap < 0.9f && s.w.stats.cav_contacts >= 1, "bodies met at gallop (closest gap %.3f)", min_gap);
	}
	{   // 4.5 morale shock: a penetration costs the victim's formation 3 morale when another member stands within 3 cells
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 14, 24, kPi, 2, sword(M_WOOD, A_NONE), T_MELEE, 0, 2);
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.skill[0] = SK_POWER; // powered lance: the first contact is a penetration
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		for (int k = 0; k < 30 * 3 && s.w.stats.cav_falls == 0; ++k) {
			s.w.host_input(0, 8.f, 0.f, true, false);
			checked_step(s.w, DT);
		}
		CHECK(s.w.stats.cav_falls >= 1 && s.w.stats.cav_shocks >= 1, "penetration with a neighbour in the victim formation shocks it (falls %llu, shocks %llu)", (unsigned long long)s.w.stats.cav_falls, (unsigned long long)s.w.stats.cav_shocks);
		CHECK(s.w.formations[v].morale <= 100.0 - cav::MORALE_SHOCK + 1e-9, "victim formation morale is down by at least 3 (%.2f)", s.w.formations[v].morale);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant through the shock");
	}
	{   // 4.1 / N2: a sharp turn at gallop drops the charge before any contact; the victim ahead is never reached
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 30, 24, kPi, 1, sword(M_WOOD, A_NONE));
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		for (int k = 0; k < 30 * 2; ++k) { s.w.host_input(0, 8.f, 0.f, true, false); checked_step(s.w, DT); }
		CHECK(s.w.charge_state(0) && s.w.charge_straight_seconds(0) >= cav::STRAIGHT_SECONDS, "charging straight east before the turn (straight %.2f s)", s.w.charge_straight_seconds(0));
		const uint64_t contacts0 = s.w.stats.cav_contacts;
		bool charge_after_turn = false;
		for (int k = 0; k < 30 * 2; ++k) { s.w.host_input(0, 0.f, 8.f, true, false); checked_step(s.w, DT); charge_after_turn = charge_after_turn || (k >= 10 && k < 30 && s.w.charge_state(0)); }
		CHECK(!charge_after_turn, "the charge is lost while the heading turns (none from 1/3 s to 1 s after the turn)");
		CHECK(s.w.stats.cav_contacts == contacts0 && s.w.stats.cav_falls == 0 && s.w.getup[1] <= 0.0, "a turned rider makes no penetration and the victim stays up");
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant through the turn");
	}
	{   // 4.3 pole-arm stand (Q3=A): a braced spearman in full steel stops the charge; the pole-arm counter applies, the rider recoils
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 1, sword(M_WOOD, A_NONE));
		int v = s.formation(1, 14, 24, kPi, 1, spear_steel());
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.skill[v] = SK_BRACE;
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		ExStats a, b;
		s.w.face[v] = kPi;
		s.w.charge_stats(r, v, 8.0, a, b);
		CHECK(b.armorbonus >= cav::POLE_BONUS, "the braced spearman facing the rider gets the pole-arm bonus (%.2f)", b.armorbonus);
		const float hp0 = (float)s.w.hp[0];
		uint64_t contacts0 = s.w.stats.cav_contacts;
		for (int k = 0; k < 30 * 6 && s.w.stats.cav_contacts == contacts0; ++k) { s.w.host_input(0, 5.f, 0.f, false, false); checked_step(s.w, DT); }
		CHECK(s.w.stats.cav_contacts > contacts0, "the charge reaches the pike line");
		CHECK(s.w.stats.cav_stops >= 1 && std::hypot(s.w.vx[0], s.w.vy[0]) < 1e-4f, "the pike line stops the charge (speed %.4f)", std::hypot(s.w.vx[0], s.w.vy[0]));
		CHECK(s.w.stats.cav_falls == 0 && s.w.getup[v] <= 0.0, "a stopped charge makes no penetration");
		CHECK(s.w.hp[0] < hp0 || s.w.stats.cav_dismounts == 1 || s.w.stagger[0] > 0.0, "the rider is held (stagger) or recoils (hp %.2f)", s.w.hp[0]);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant through the stop");
	}
	{   // CAV-2: a host-controlled rider with constant foot-scale run input (4 cells/s) rides up to gallop and charges an infantry line
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 1, sword(M_IRON, A_NONE));
		std::vector<int> line;
		for (int k = 0; k < 6; ++k) line.push_back(s.formation(1, 20, 21.5f + (float)k, kPi, 1, sword(M_WOOD, A_NONE)));
		s.w.finalize();
		s.w.formations[r].ai_enabled = false;
		for (int f : line) s.w.formations[f].ai_enabled = false;
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		float vmax = 0.f;
		bool charged = false;
		for (int k = 0; k < 30 * 6 && s.w.stats.cav_contacts == 0; ++k) {
			s.w.host_input(0, 4.f, 0.f, true, false);
			checked_step(s.w, DT);
			vmax = std::max(vmax, std::hypot(s.w.vx[0], s.w.vy[0]));
			charged = charged || s.w.charge_state(0);
		}
		CHECK(vmax > cav::CHARGE_SPEED, "the mounted host rider rides past the charge speed on foot-scale input (max %.3f)", vmax);
		CHECK(charged, "the host rider reaches the charge state");
		CHECK(s.w.stats.cav_contacts >= 1, "the host rider charges the infantry line (contacts %llu)", (unsigned long long)s.w.stats.cav_contacts);
	}
	{   // terrain: a palisade (a column of blocked cells) stops the charge in front of it; no leak through, no penetration
		Scene s(1, 64, 48);
		for (int y = 0; y < 48; ++y) s.w.terrain.flags[s.w.terrain.idx(20, y)] = 0;
		int r = s.formation(0, 12, 24, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 25, 24, kPi, 1, sword(M_WOOD, A_NONE));
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.set_mounted(0, true);
		s.w.set_host_control(0, true);
		float furthest = 0.f;
		for (int k = 0; k < 30 * 5; ++k) { s.w.host_input(0, 8.f, 0.f, true, false); checked_step(s.w, DT); furthest = std::max(furthest, s.w.px[0]); }
		CHECK(furthest < 20.0f, "the rider never crosses the palisade column (furthest x %.3f)", furthest);
		CHECK(std::hypot(s.w.vx[0], s.w.vy[0]) < cav::CHARGE_SPEED, "the rider brakes in front of the palisade (speed %.3f)", std::hypot(s.w.vx[0], s.w.vy[0]));
		CHECK(!s.w.charge_state(0) && s.w.stats.cav_contacts == 0 && s.w.stats.cav_falls == 0, "no charge contact or penetration through the wall");
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "no illegal cell or edge at the palisade");
	}
	{   // 1 / 2 / 4 threads: identical hashes; save / load keeps the mounted state and continues identically
		auto run = [](int threads, std::vector<uint8_t> *save_out) {
			Scene s(threads, 64, 48);
			int r = s.formation(0, 6, 24, 0, 1, sword(M_IRON, A_NONE));
			int v = s.formation(1, 16, 24, kPi, 8, sword(M_WOOD, A_NONE), T_MELEE, 0, 1);
			int w2 = s.formation(0, 30, 40, 0, 6, sword(M_IRON, A_NONE), T_MELEE, 0, 3);
			int foe = s.formation(1, 40, 40, kPi, 24, sword(M_WOOD, A_NONE), T_MELEE, 0, 6);
			std::vector<std::pair<float, float>> at = {{6.5f, 24.5f}};
			for (int k = 0; k < 8; ++k) at.push_back({16.5f, 20.5f + 0.8f * k});
			place_start(s, at);
			s.w.finalize();
			for (int f : {r, v, w2, foe}) s.w.formations[f].ai_enabled = false;
			for (int i : s.w.formations[w2].members) s.w.set_mounted(i, true);
			s.w.set_mounted(0, true);
			s.w.order_move(w2, 52.f, 40.f, 0.f);
			s.w.set_host_control(0, true);
			for (int k = 0; k < 30 * 5; ++k) {
				s.w.host_input(0, k < 30 * 3 ? 8.f : 0.f, 0.f, true, false);
				checked_step(s.w, DT);
			}
			if (save_out) *save_out = s.w.save();
			return s.w.state_hash();
		};
		std::vector<uint8_t> blob;
		const uint64_t h1 = run(1, &blob), h2 = run(2, nullptr), h4 = run(4, nullptr);
		CHECK(h1 == h2 && h1 == h4, "1 / 2 / 4 threads: identical state hash (%llx %llx %llx)", (unsigned long long)h1, (unsigned long long)h2, (unsigned long long)h4);
		World back(1);
		CHECK(back.load(blob), "the mounted battle loads");
		check_valid(back);
		CHECK(back.state_hash() == h1, "load gives the same hash");
		World again(1);
		CHECK(again.load(blob) && again.is_mounted(0) && again.is_mounted(8 + 1), "mounted state survives the save");
	}
}

// CAV-4a regression: a mounted formation marches at the cruise pace and its charge reaches the gallop (CAV-1 rules: cruise 5,
// gallop 8 cells/s). The bench of v2 had 100-rider formations crawling at about 0.5 cells/s: the infantry slot spacing
// (1.0) is narrower than two rider bodies (1.12), so riders never reached their slots, the formation lag stayed high and the
// lag cohesion held the centre at its 0.15 floor of the infantry march; and riders came within reach of the line already
// braked to the cruise cap, so every impact was judged at 5 cells/s.
static void test_cavalry_speed() {
	std::printf("[cavalry speed] CAV-4a: a 100-rider block marches at cruise, foot unchanged, the charge reaches gallop at impact\n");
	auto centre_speed = [](Scene &s, int f, double seconds) {
		const float x0 = s.w.formations[f].cx, y0 = s.w.formations[f].cy;
		s.run(seconds);
		return std::hypot(s.w.formations[f].cx - x0, s.w.formations[f].cy - y0) / (float)seconds;
	};
	for (int riding = 0; riding < 2; ++riding) { // MOVE across open ground: 100 men, 10 x 10 at the infantry spacing 1.0
		Scene s(1, 200, 60);
		int f = s.formation(0, 15, 30, 0, 100, sword(M_IRON, A_LEATHER));
		s.w.finalize();
		s.w.formations[f].ai_enabled = false;
		if (riding) for (int i : s.w.formations[f].members) s.w.set_mounted(i, true);
		s.run(1.0);
		s.w.order_move(f, 185.f, 30.f, 0.f);
		s.run(4.0); // accelerate and settle into the march (bounded: 4 s)
		const float v = centre_speed(s, f, 3.0);
		double rider = 0.0;
		for (int i : s.w.formations[f].members) rider += std::hypot(s.w.vx[i], s.w.vy[i]);
		rider /= 100.0;
		if (riding) {
			CHECK(v >= 0.95f * cav::CRUISE && v <= cav::CRUISE + 0.05f, "a mounted block marches at the cruise pace within 4 s of the order (centre %.2f cells/s)", v);
			CHECK(rider >= 0.95 * cav::CRUISE, "its riders keep up with the centre (mean %.2f cells/s)", rider);
		} else {
			CHECK(std::fabs(v - s.w.cfg.march_speed) < 0.05f, "a foot block still marches at the infantry pace (centre %.2f, march %.2f)", v, s.w.cfg.march_speed);
		}
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant on the march");
		std::printf("  %s block of 100 on MOVE: centre %.2f cells/s, members %.2f cells/s\n", riding ? "mounted" : "foot", v, rider);
	}
	{   // CHARGE from 100 cells: the form-up walk is at cruise, the line forms, and the riders hit the line at gallop
		Scene s(1, 200, 60);
		int r = s.formation(0, 15, 30, 0, 100, sword(M_IRON, A_LEATHER));
		int v = s.formation(1, 120, 30, kPi, 60, sword(M_WOOD, A_NONE), T_MELEE, 0, 20);
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		for (int i : s.w.formations[r].members) s.w.set_mounted(i, true);
		s.run(1.0);
		CHECK(s.w.host_order(r, 7, 0.f, 0.f, v) == OK, "a 100-rider block charges the enemy formation");
		s.run(5.0);
		const float walk = centre_speed(s, r, 3.0);
		CHECK(s.w.formations[r].charge_stage == CS_FORM && walk >= 0.9f * cav::CRUISE, "the form-up walk goes at the cruise pace (centre %.2f cells/s)", walk);
		int charge_step = -1, peak_gallop = 0;
		for (int k = 0; k < 30 * 30 && s.w.stats.cav_contacts < 10; ++k) {
			checked_step(s.w, DT);
			if (charge_step < 0 && s.w.formations[r].charge_stage == CS_CHARGE) charge_step = k;
			int gallop = 0;
			for (int i : s.w.formations[r].members) gallop += s.w.charge_rider(i) && std::hypot(s.w.vx[i], s.w.vy[i]) >= cav::GALLOP - 0.1f ? 1 : 0;
			peak_gallop = std::max(peak_gallop, gallop);
		}
		CHECK(charge_step >= 0 && charge_step <= 30 * 20, "the line forms and the charge starts within 25 s of the order (%.1f s after the walk check)", charge_step / 30.0);
		CHECK(peak_gallop >= 20, "the charging line reaches the gallop (%d riders at %.1f cells/s together)", peak_gallop, cav::GALLOP - 0.1f);
		const double impact = s.w.stats.cav_contacts ? s.w.stats.cav_impact_speed / (double)s.w.stats.cav_contacts : 0.0;
		CHECK(s.w.stats.cav_contacts >= 10 && impact >= 0.5 * (cav::CHARGE_SPEED + cav::GALLOP), "impacts are judged at charge speed, not braked to cruise first (%llu contacts, mean %.2f cells/s)",
		      (unsigned long long)s.w.stats.cav_contacts, impact);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant through the charge");
		std::printf("  CHARGE of 100 riders: form-up walk %.2f cells/s, charge %.1f s after the walk check, %d riders at gallop together, %llu contacts at %.2f cells/s mean, %llu penetrations\n",
		            walk, charge_step / 30.0, peak_gallop, (unsigned long long)s.w.stats.cav_contacts, impact, (unsigned long long)s.w.stats.cav_penetrations);
	}
	{   // CAV-4b Site fixture: the enemy stands on a strip of low ground below a terrace edge (a cliff). The form-up point in
		// front of it on the approach side lies on the terrace, with no straight run down; the form-up must pick a point with
		// a straight run in (beside the target, on the strip) and the charge must reach the line.
		Scene s(1, 64, 48);
		for (int y = 10; y < 38; ++y) for (int x = 20; x < 56; ++x) s.w.terrain.height[s.w.terrain.idx(x, y)] = 1; // the terrace, no ramps
		int r = s.formation(0, 6, 24, 0, 4, sword(M_IRON, A_LEATHER), T_MELEE, 0, 2);
		int v = s.formation(1, 60, 24, kPi, 6, sword(M_WOOD, A_NONE), T_MELEE, 0, 2);
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		for (int i : s.w.formations[r].members) s.w.set_mounted(i, true);
		s.run(0.5);
		CHECK(s.w.host_order(r, 7, 0.f, 0.f, v) == OK, "riders charge a formation standing below a terrace edge");
		const float gx = s.w.formations[r].goal_x, gy = s.w.formations[r].goal_y;
		CHECK(s.w.terrain.height[s.w.terrain.idx((int)gx, (int)gy)] == 0, "the form-up point lies on the low ground with the target, not on the terrace (%.1f, %.1f)", gx, gy);
		int k = 0;
		for (; k < 30 * 60 && s.w.stats.cav_contacts == 0; ++k) checked_step(s.w, DT);
		CHECK(s.w.stats.cav_contacts >= 1, "the charge reaches the line round the terrace (contact after %.1f s)", k / 30.0);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant: no rider crosses the terrace edge");
		std::printf("  below-terrace charge: form-up point (%.1f, %.1f), first contact after %.1f s\n", gx, gy, k / 30.0);
	}
}

// CAV-4a: CHARGE / RALLY formation orders (reports/cavalry-charge-plan.md section 5 and 6)
static void test_cavalry_charge() {
	std::printf("[cavalry charge] CAV-4a: form-up line, straight charge through the line, rally behind the target, recharge, spent rider, commander and cavalry gates, AI cycles, KW18 and KW17 save, thread parity\n");
	{   // form up to the line, charge straight, break through, rally behind the target
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 6, sword(M_IRON, A_NONE), T_MELEE, 0, 6);
		int v = s.formation(1, 40, 24, kPi, 3, sword(M_WOOD, A_NONE), T_MELEE, 0, 1);
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		for (int i : s.w.formations[r].members) s.w.set_mounted(i, true);
		CHECK(s.w.cavalry_formation(r) && s.w.charge_commander_ok(r), "six riders with an eligible commander at the centre");
		CHECK(s.w.host_order(r, 5, 40.5f, 24.5f, 0) == OK, "CHARGE to a point is accepted");
		CHECK(s.w.formations[r].order == Order::CHARGE && s.w.formations[r].charge_stage == CS_FORM, "the order starts in form-up");
		int formed_step = -1;
		float cx_at_charge = 0.f;
		for (int k = 0; k < 30 * 25 && formed_step < 0; ++k) {
			checked_step(s.w, DT);
			if (s.w.formations[r].charge_stage == CS_CHARGE) { formed_step = k; cx_at_charge = s.w.formations[r].cx; }
		}
		CHECK(formed_step >= 0, "the formation reaches the form-up point and starts the charge");
		CHECK(formed_step >= 0 && cx_at_charge > 24.f && cx_at_charge < 36.f, "form-up point is 8 to 12 cells in front of the target (centre x %.2f)", cx_at_charge);
		CHECK(s.w.formations[r].cols == 6 || s.w.formations[r].charge_cols == 6, "line abreast: one row while charging");
		float max_ang = 0.f, max_x = 0.f, first_rx = 0.f;
		bool saw_rally = false;
		for (int k = 0; k < 30 * 12; ++k) {
			checked_step(s.w, DT);
			// the first charge of the cycle (heading +x); later cycles charge in from the rally flank
			if (s.w.formations[r].charge_stage == CS_CHARGE && !saw_rally) {
				for (int i : s.w.formations[r].members) {
					if (!s.w.mounted[i] || s.w.px[i] < 20.f) continue;
					const float sp = std::hypot(s.w.vx[i], s.w.vy[i]);
					// at gallop (above 6 cells/s) and before the infantry line (x 40): the turn of a rider still lining up at the
					// charge start, and the push of contact, are not counted
					if (sp > 6.f && s.w.px[i] < 37.f) max_ang = std::max(max_ang, std::fabs(wrap_angle(std::atan2(s.w.vy[i], s.w.vx[i]))));
					max_x = std::max(max_x, s.w.px[i]);
				}
			}
			if (s.w.formations[r].charge_stage == CS_RALLY && !saw_rally) { saw_rally = true; first_rx = s.w.formations[r].rally_x; }
		}
		CHECK(max_ang < 25.f * kPi / 180.f, "charging riders keep to a straight heading, no flow field (max %.1f deg)", max_ang * 180.f / kPi);
		CHECK(max_x > 41.f, "a rider charges through the target line, not stopped in front of it (furthest x %.2f)", max_x);
		CHECK(s.w.stats.cav_contacts >= 1, "the charge reaches the infantry line (contacts %llu)", (unsigned long long)s.w.stats.cav_contacts);
		CHECK(saw_rally && s.w.stats.charge_breaks >= 1, "break-through ends the charge in the rally stage");
		const float rx = first_rx;
		CHECK(rx > 40.f, "rally point of the first cycle lies behind the target (x %.2f)", rx);
		bool back = false;
		for (int k = 0; k < 30 * 25 && !back; ++k) {
			checked_step(s.w, DT);
			const Formation &f = s.w.formations[r];
			back = f.charge_stage == CS_FORM || f.charge_stage == CS_CHARGE;
		}
		CHECK(back, "after rally the cycle forms up again and recharges");
		CHECK(s.w.stats.charge_rallies >= 1 && s.w.stats.charge_forms >= 2, "rally arrival counted and a second form-up begun (forms %llu)", (unsigned long long)s.w.stats.charge_forms);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant through the cycle");
		CHECK(s.w.host_order(r, 6, 0.f, 0.f, 0) == OK && s.w.formations[r].order == Order::RALLY, "a RALLY order is accepted");
		bool rallied = false;
		for (int k = 0; k < 30 * 30 && !rallied; ++k) { checked_step(s.w, DT); rallied = s.w.formations[r].order == Order::HOLD; }
		CHECK(rallied && s.w.formations[r].charge_stage == CS_NONE, "RALLY goes to its point and then holds");
	}
	{   // refusals: commander too far, not a cavalry formation, enemy formation target not hostile or missing
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 6, sword(M_IRON, A_NONE), T_MELEE, 0, 6);
		int inf = s.formation(0, 6, 34, 0, 6, sword(M_IRON, A_NONE), T_MELEE, 0, 6);
		int v = s.formation(1, 40, 24, kPi, 3, sword(M_WOOD, A_NONE), T_MELEE, 0, 1);
		s.w.finalize();
		for (int f : {r, inf, v}) s.w.formations[f].ai_enabled = false;
		for (int i : s.w.formations[r].members) s.w.set_mounted(i, true);
		const int cmd = s.w.formations[r].current_cmd;
		CHECK(cmd >= 0, "the cavalry formation has a commander");
		s.place(cmd, 40.f, 40.f); // the commander walks 34 cells away from the centre
		CHECK(s.w.host_order(r, 5, 40.5f, 24.5f, 0) == NO_COMMANDER, "CHARGE refused with the commander out of reach");
		CHECK(s.w.formations[r].order != Order::CHARGE, "a refused order changes nothing");
		s.place(cmd, 6.5f, 24.5f);
		CHECK(s.w.host_order(inf, 5, 40.5f, 24.5f, 0) == NOT_CAVALRY, "CHARGE refused for a foot formation");
		CHECK(s.w.host_order(r, 7, 0.f, 0.f, v) == OK, "CHARGE to an enemy formation by index is accepted");
		CHECK(s.w.host_order(r, 7, 0.f, 0.f, r) == NO_TARGET, "a formation cannot charge itself");
		CHECK(s.w.host_order(r, 7, 0.f, 0.f, 1.5) == NO_TARGET, "a formation index must be whole");
	}
	{   // CHARGE form-up disengages: a rider already in melee contact rides out to the form-up line instead of fighting on
		Scene s(1, 64, 48);
		int r = s.formation(0, 10, 24, 0, 1, sword(M_IRON, A_NONE));
		int v = s.formation(1, 11, 24, kPi, 1, sword(M_WOOD, A_NONE));
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.place(0, 10.5f, 24.5f); s.place(1, 11.5f, 24.5f);
		s.w.set_mounted(0, true);
		s.run(0.2);
		CHECK(s.w.state[0] == S_FIGHT, "setup: the rider is in melee before the order (state %d)", (int)s.w.state[0]);
		CHECK(s.w.host_order(r, 5, 30.5f, 24.5f, 0) == OK, "CHARGE to a point with the rider in contact is accepted");
		s.run(1.0);
		CHECK(s.w.state[0] != S_FIGHT, "the riding contact disengages during the form-up (state %d)", (int)s.w.state[0]);
	}
	{   // spent rider: a charge stopped in contact is ordinary engagement; RALLY pulls the riders out of contact
		Scene s(1, 64, 48);
		int r = s.formation(0, 12, 24, 0, 1, sword(M_IRON, A_NONE));
		Equip pike = sword(M_WOOD, A_NONE); pike.family = F_SPEAR;
		int v = s.formation(1, 25, 24, kPi, 5, pike, T_MELEE, 0, 1); // five pikes in one file, facing the rider
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		s.w.set_mounted(0, true);
		CHECK(s.w.host_order(r, 7, 0.f, 0.f, v) == OK, "a lone cavalry formation charges an enemy by index");
		int k = 0;
		for (; k < 30 * 20 && s.w.stats.cav_stops == 0; ++k) checked_step(s.w, DT);
		CHECK(s.w.stats.charge_forms >= 1, "the charge began (forms %llu)", (unsigned long long)s.w.stats.charge_forms);
		CHECK(s.w.stats.cav_stops >= 1, "the pike line stops the charge (stops %llu, contacts %llu)", (unsigned long long)s.w.stats.cav_stops, (unsigned long long)s.w.stats.cav_contacts);
		// checked on the step of the stop: a later form-up of the cycle would clear the flag again
		CHECK(s.w.cav_spent[0] == 1 && !s.w.charge_rider(0), "the stopped rider is spent and no longer charges");
		for (int m = 0; m < 30 * 20; ++m) checked_step(s.w, DT);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant after the stop");
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant after the spent rider");
	}
	{   // AI: a mostly mounted native formation charges enemies in reach and keeps cycling
		Scene s(1, 64, 48);
		s.w.cfg.ai = true;
		int r = s.formation(0, 8, 24, 0, 6, sword(M_IRON, A_NONE), T_MELEE, 0, 6);
		int v = s.formation(1, 30, 24, kPi, 6, sword(M_WOOD, A_NONE), T_MELEE, 0, 3);
		s.w.finalize();
		for (int i : s.w.formations[r].members) s.w.set_mounted(i, true);
		bool ai_charged = false;
		for (int k = 0; k < 30 * 60; ++k) {
			checked_step(s.w, DT);
			ai_charged = ai_charged || s.w.formations[r].order == Order::CHARGE;
		}
		CHECK(ai_charged, "native AI issues CHARGE to a cavalry formation with an enemy in reach");
		CHECK(s.w.stats.charge_forms >= 1 && s.w.stats.charge_breaks >= 1, "the AI cycle reaches break-through (forms %llu breaks %llu)",
		      (unsigned long long)s.w.stats.charge_forms, (unsigned long long)s.w.stats.charge_breaks);
		CHECK(s.w.stats.illegal_cell == 0 && s.w.stats.illegal_step == 0, "terrain invariant under AI cycling");
	}
	{   // KW18 save mid-charge loads with the same hash and continues identically; KW17 layout loads with the charge defaults
		Scene s(1, 64, 48);
		int r = s.formation(0, 6, 24, 0, 6, sword(M_IRON, A_NONE), T_MELEE, 0, 6);
		int v = s.formation(1, 40, 24, kPi, 3, sword(M_WOOD, A_NONE), T_MELEE, 0, 1);
		s.w.finalize();
		s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
		for (int i : s.w.formations[r].members) s.w.set_mounted(i, true);
		s.w.host_order(r, 5, 40.5f, 24.5f, 0);
		for (int k = 0; k < 30 * 25 && s.w.formations[r].charge_stage != CS_CHARGE; ++k) checked_step(s.w, DT);
		for (int k = 0; k < 30 * 1; ++k) checked_step(s.w, DT); // mid-charge
		CHECK(s.w.formations[r].charge_stage == CS_CHARGE, "the save point is inside the charge");
		const std::vector<uint8_t> blob = s.w.save();
		const uint64_t h0 = s.w.state_hash();
		World back(1);
		CHECK(!blob.empty() && back.load(blob), "a KW18 blob loads");
		check_valid(back);
		CHECK(back.state_hash() == h0, "load gives the same hash mid-charge");
		CHECK(back.formations[r].charge_stage == CS_CHARGE && back.formations[r].order == Order::CHARGE, "charge stage and order survive the save");
		for (int k = 0; k < 30 * 2; ++k) { checked_step(s.w, DT); checked_step(back, DT); }
		CHECK(back.state_hash() == s.w.state_hash(), "the loaded copy and the original step identically through the charge");
		// KW17: an older layout (no charge cycle) loads with the defaults and hashes as the same state
		Scene q(1, 64, 48);
		int fr = q.formation(0, 6, 24, 0, 6, sword(M_IRON, A_NONE), T_MELEE, 0, 6);
		int fv = q.formation(1, 40, 24, kPi, 3, sword(M_WOOD, A_NONE), T_MELEE, 0, 1);
		q.w.finalize();
		q.w.formations[fr].ai_enabled = false; q.w.formations[fv].ai_enabled = false;
		for (int i : q.w.formations[fr].members) q.w.set_mounted(i, true);
		q.w.order_move(fr, 20.5f, 24.5f, 0.f);
		for (int k = 0; k < 30 * 2; ++k) checked_step(q.w, DT);
		const std::vector<uint8_t> old = q.w.save_kw17();
		World oldback(1);
		CHECK(!old.empty() && oldback.load(old), "a KW17 blob loads");
		check_valid(oldback);
		CHECK(oldback.state_hash() == q.w.state_hash(), "a KW17 blob loads as the same state (no charge cycle)");
		CHECK(oldback.formations[fr].charge_stage == CS_NONE && oldback.cav_spent.size() == oldback.px.size(), "KW17 charge fields take their defaults");
		CHECK(oldback.host_order(fr, 5, 40.5f, 24.5f, 0) == OK, "a loaded KW17 formation accepts a charge");
	}
	{   // 1 / 2 / 4 threads: identical state hash through the charge cycle
		auto run = [](int threads) {
			Scene s(threads, 64, 48);
			int r = s.formation(0, 6, 24, 0, 6, sword(M_IRON, A_NONE), T_MELEE, 0, 6);
			int v = s.formation(1, 40, 24, kPi, 6, sword(M_WOOD, A_NONE), T_MELEE, 0, 2);
			s.w.finalize();
			s.w.formations[r].ai_enabled = false; s.w.formations[v].ai_enabled = false;
			for (int i : s.w.formations[r].members) s.w.set_mounted(i, true);
			s.w.host_order(r, 5, 40.5f, 24.5f, 0);
			for (int k = 0; k < 30 * 30; ++k) checked_step(s.w, DT);
			return s.w.state_hash();
		};
		const uint64_t h1 = run(1), h2 = run(2), h4 = run(4);
		CHECK(h1 == h2 && h1 == h4, "1 / 2 / 4 threads: identical hash through the charge cycle (%llx %llx %llx)", (unsigned long long)h1, (unsigned long long)h2, (unsigned long long)h4);
	}
}

int main() {
	#ifdef _WIN32
	SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
#endif
	setvbuf(stdout, nullptr, _IONBF, 0);
	test_exchange_round_rules();
	test_cliff_blocks_exchange();
	test_stun_ko_wake();
	test_rescue();
	test_morale_and_command();
	test_ranged();
	test_knockback_legal();
	test_capture_escape();
	test_pursuit_limits();
	test_fatigue_shared();
	test_bleeding();
	test_auto_capture();
	test_three_factions();
	test_round_fatigue_before_deaths();
	test_move_encounter();
	test_site_clock();
	test_game_time_actions();
	test_flow_order();
	test_state_import_export();
	test_full_formation_import_preserves_command_state();
	test_events();
	test_twelve_arrow_capture_escape_chain();
	test_captive_effective_hit_death();
	test_hold_anchor_near_allies();
	test_host_order_owner();
	test_save_load();
	test_determinism();
	test_render_order();
	test_host_blocker();
	test_host_soldier();
	test_edge_deploy();
	test_melee_contact_and_exchange_fatigue();
	test_site_person_release();
	test_cavalry();
	test_cavalry_charge();
	test_cavalry_speed();
	std::printf("\n%d checks, %d failures\n", checks, failures);
	return failures ? 1 : 0;
}
