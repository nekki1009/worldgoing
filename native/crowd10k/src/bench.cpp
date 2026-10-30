// crowd10k v2 benchmark: two AI-driven armies of 100-soldier formations (melee / bow / crossbow, mixed
// equipment tiers, captain + 2 officers each) on a battlefield with a river, three bridges and a
// cliffed plateau with three ramps. Every rule layer runs: exchange rounds, ranged fire, stun / KO,
// rescue, command presence & succession, morale & rout, pursuit, encirclement, shared fatigue.
#include "crowd_core.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using namespace wg;
using Clock = std::chrono::steady_clock;

struct Args {
	int n = 10000, map = 256, threads = 1, seconds = 120, dump_every = 0, seed = 581;
	float spacing = 1.0f;
	std::string scenario = "battle", out = "out";
	double ranged_share = 0.2, ko_seconds = -1, aftermath = 0;
	bool ai = true;
	float push_clamp = 0.25f, rescue_seek = 8.f, capture_seek = 8.f;
	bool auto_capture = true;
};

static uint32_t rng_state = 1;
static uint32_t rnd() { rng_state ^= rng_state << 13; rng_state ^= rng_state >> 17; rng_state ^= rng_state << 5; return rng_state; }

static void build_terrain(Terrain &t, int W, int H, bool features, bool open_ground = false) {
	t.allocate(W, H);
	if (!features) return;
	int px0 = (int)(0.62f * W), px1 = (int)(0.92f * W), py0 = (int)(0.12f * H), py1 = (int)(0.88f * H);
	if (!open_ground) { // river with three bridges, and a plateau with three ramps
		int bridges[3][2] = {{(int)(0.25f * H), 6}, {(int)(0.5f * H), 8}, {(int)(0.75f * H), 5}};
		for (int y = 0; y < H; ++y) {
			int rx = (int)(0.45f * W + 3.0f * std::sin((float)y * 0.05f));
			bool bridge = false;
			for (auto &b : bridges) if (y >= b[0] - b[1] / 2 && y < b[0] - b[1] / 2 + b[1]) bridge = true;
			for (int x = rx; x < rx + 4; ++x)
				if (!bridge) t.flags[t.idx(x, y)] = 0;
		}
		for (int y = py0; y < py1; ++y)
			for (int x = px0; x < px1; ++x) t.height[t.idx(x, y)] = 1;
		int ramps[3][2] = {{(int)(0.3f * H), 8}, {(int)(0.5f * H), 10}, {(int)(0.7f * H), 8}};
		for (auto &r : ramps)
			for (int y = r[0] - r[1] / 2; y < r[0] - r[1] / 2 + r[1]; ++y) {
				t.ramp_edges[t.idx(px0, y)] |= 1 << wg::Dir::W;
				t.ramp_edges[t.idx(px0 - 1, y)] |= 1 << wg::Dir::E;
			}
	}
	// scattered rocks: the same random draws with or without the river and plateau, so the armies spawn alike
	for (int k = 0; k < (W * H) / 900; ++k) {
		int cx = (int)(rnd() % (uint32_t)W), cy = (int)(rnd() % (uint32_t)H), r = 1 + (int)(rnd() % 2);
		if (std::abs(cx - (int)(0.45f * W)) < 12 || std::abs(cx - px0) < 6) continue;
		for (int y = cy - r; y <= cy + r; ++y)
			for (int x = cx - r; x <= cx + r; ++x)
				if (t.contains(x, y) && (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) t.static_blocked[t.idx(x, y)] = 1;
	}
}

static rules::Equip melee_kit(int team) {
	using namespace rules;
	static const uint8_t fams[] = {F_LONGSWORD, F_SPEAR, F_AXE, F_HAMMER};
	Equip e;
	e.family = fams[rnd() % 4];
	e.material = team == 0 ? (uint8_t)(M_IRON + (rnd() % 3 == 0 ? 1 : 0)) : (uint8_t)(M_STONE + rnd() % 2);
	e.armor = team == 0 ? (uint8_t)(A_LEATHER + rnd() % 2) : (uint8_t)(A_LEATHER + rnd() % 3);
	e.shield = (e.family == F_LONGSWORD || e.family == F_AXE) && rnd() % 2;
	return e;
}

static void spawn_army(World &w, int team, int formations, float x0, float y0, float facing, float spacing, double ranged_share,
                       double training, int64_t &pid, float xsign = 0.f) {
	int fcols = 5;
	int frows = (formations + fcols - 1) / fcols;
	float block = 10 * spacing + 2.0f;
	int ranged_cols = std::min(fcols - 1, (int)(fcols * ranged_share + 1e-9));
	for (int k = 0; k < formations; ++k) {
		int c = k % fcols, r = k / fcols;
		float sgn = xsign != 0.f ? xsign : (team == 0 ? -1.f : 1.f);
		float cx = x0 + sgn * (float)c * block;
		float cy = y0 + ((float)r - (float)(frows - 1) * 0.5f) * block;
		// archers stand in the rear columns
		bool ranged = c >= fcols - ranged_cols; // rear columns
		Troop tr = ranged ? ((k / fcols) % 2 ? T_CROSSBOW : T_BOW) : T_MELEE;
		int f = w.add_formation(team, cx, cy, facing, 10, spacing, tr, training);
		rules::Equip kit = tr == T_MELEE ? melee_kit(team) : rules::Equip{};
		if (tr != T_MELEE) {
			kit.family = tr == T_BOW ? rules::F_BOW : rules::F_CROSSBOW;
			kit.material = team == 0 ? rules::M_IRON : rules::M_WOOD;
			kit.armor = rules::A_LEATHER;
		}
		for (int s = 0; s < 100; ++s) {
			Role role = s == 0 ? R_CAPTAIN : (s <= 2 ? R_OFFICER : R_REGULAR);
			w.add_soldier(f, kit, role, pid++, tr == T_MELEE ? 0 : 20); // 20 matching arrows / bolts each
		}
	}
}

struct Series {
	std::vector<double> v;
	void add(double x) { v.push_back(x); }
	double mean() const { double s = 0; for (double x : v) s += x; return v.empty() ? 0 : s / (double)v.size(); }
	double pct(double p) const {
		if (v.empty()) return 0;
		auto c = v; std::sort(c.begin(), c.end());
		size_t k = (size_t)std::ceil(p * (double)c.size()) - 1; return c[std::min(k, c.size() - 1)];
	}
	double max() const { return v.empty() ? 0 : *std::max_element(v.begin(), v.end()); }
};

int main(int argc, char **argv) {
	Args a;
	for (int i = 1; i < argc; ++i) {
		std::string k = argv[i];
		auto next = [&]() { return std::string(argv[++i]); };
		if (k == "--n") a.n = std::stoi(next());
		else if (k == "--map") a.map = std::stoi(next());
		else if (k == "--threads") a.threads = std::stoi(next());
		else if (k == "--seconds") a.seconds = std::stoi(next());
		else if (k == "--spacing") a.spacing = std::stof(next());
		else if (k == "--scenario") a.scenario = next();
		else if (k == "--dump") a.dump_every = std::stoi(next());
		else if (k == "--out") a.out = next();
		else if (k == "--seed") a.seed = std::stoi(next());
		else if (k == "--ranged") a.ranged_share = std::stod(next());
		else if (k == "--ko-seconds") a.ko_seconds = std::stod(next());
		else if (k == "--aftermath") a.aftermath = std::stod(next());
		else if (k == "--rescue-seek") a.rescue_seek = std::stof(next());
		else if (k == "--capture-seek") a.capture_seek = std::stof(next());
		else if (k == "--no-auto-capture") a.auto_capture = false;
		else if (k == "--no-ai") a.ai = false;
		else if (k == "--push-clamp") a.push_clamp = std::stof(next());
	}
	rng_state = (uint32_t)a.seed * 2654435761u | 1u;
	World w(a.threads);
	w.cfg.seed = a.seed;
	w.cfg.ai = a.ai;
	w.cfg.push_clamp = a.push_clamp;
	w.cfg.rescue_seek_cells = a.rescue_seek;
	w.cfg.capture_seek_cells = a.capture_seek;
	w.cfg.auto_capture = a.auto_capture;
	if (a.ko_seconds > 0) w.cfg.ko_seconds = a.ko_seconds;
	int W = a.map, H = a.map;
	// CAV-4a: the battle armies (same draws) on open ground (no river or plateau; the scattered rocks stay), 1,000 riders
	// wheel-charging a standing army
	const bool cavalry = a.scenario == "cavalry";
	bool battle = a.scenario == "battle" || cavalry, three = a.scenario == "three";
	build_terrain(w.terrain, W, H, battle, cavalry);
	int per_team = std::max(1, a.n / (three ? 300 : 200));
	int64_t pid = 1000;
	if (three) { // three factions with non-contiguous ids 0 / 2 / 5, all mutually hostile, open field
		spawn_army(w, 0, per_team, 0.28f * (float)W, 0.5f * (float)H, 0.f, a.spacing, a.ranged_share, 40.0, pid, -1.f);
		spawn_army(w, 2, per_team, 0.72f * (float)W, 0.5f * (float)H, wg::kPi, a.spacing, a.ranged_share, 30.0, pid, 1.f);
		spawn_army(w, 5, per_team, 0.5f * (float)W - 24.f, 0.82f * (float)H, -0.5f * wg::kPi, a.spacing, a.ranged_share, 20.0, pid, 1.f);
	} else if (battle) {
		spawn_army(w, 0, per_team, 0.30f * (float)W, 0.5f * (float)H, 0.f, a.spacing, a.ranged_share, 40.0, pid);
		spawn_army(w, 1, per_team, 0.78f * (float)W, 0.5f * (float)H, wg::kPi, a.spacing, a.ranged_share, 20.0, pid);
	} else { // open field, 30 cells apart
		spawn_army(w, 0, per_team, 0.5f * (float)W - 15.f, 0.5f * (float)H, 0.f, a.spacing, a.ranged_share, 40.0, pid);
		spawn_army(w, 1, per_team, 0.5f * (float)W + 15.f, 0.5f * (float)H, wg::kPi, a.spacing, a.ranged_share, 20.0, pid);
	}
	w.finalize();
	if (cavalry) { // CAV-4a bench: every infantry formation of both teams stands (HOLD, native AI off). Every fifth team-0
		// formation (ten, 100 men each: 1,000 riders) mounts and is moved round team 1's block (three north, three south,
		// four west, about 25 cells out), and charges the nearest standing team-1 formation not taken by another: its live
		// centre is followed (CHARGE to an enemy formation) and the formation layer cycles FORM / CHARGE / RALLY.
		int riders = 0, ordered = 0;
		for (int f = 0; f < (int)w.formations.size(); ++f) if (!(f < per_team && f % 5 == 0)) { w.formations[f].ai_enabled = false; w.host_order(f, 0, 0.f, 0.f, 0); } // everything but the riders stands (HOLD)
		std::vector<int> taken;
		for (int k = 0; k < 10; ++k) {
			const int f = 5 * k;
			if (f >= per_team || f >= (int)w.formations.size()) break;
			static const float ring[10][2] = {{200, 46}, {224, 46}, {248, 46}, {200, 210}, {224, 210}, {248, 210}, {172, 86}, {172, 110}, {172, 134}, {172, 158}};
			const float ncx = ring[k][0] * (float)W / 256.f, ncy = ring[k][1] * (float)H / 256.f; // round team 1 (x 195..253, y 69..187 on the 256 map)
			const float dx = ncx - w.formations[f].cx, dy = ncy - w.formations[f].cy;
			for (int i : w.formations[f].members) {
				w.px[i] += dx; w.py[i] += dy; w.nx[i] += dx; w.ny[i] += dy;
				// a shifted body on a random obstacle steps to the nearest walkable cell (bench set-up only)
				for (int r = 0; r <= 3 && !w.terrain.walkable((int)w.px[i], (int)w.py[i]); ++r)
					for (int ox = -r; ox <= r && !w.terrain.walkable((int)w.px[i], (int)w.py[i]); ++ox)
						for (int oy = -r; oy <= r; ++oy)
							if (w.terrain.walkable((int)(w.px[i] + ox), (int)(w.py[i] + oy))) { w.px[i] += ox; w.py[i] += oy; w.nx[i] = w.px[i]; w.ny[i] = w.py[i]; break; }
				riders += w.set_mounted(i, true) ? 1 : 0;
			}
			w.formations[f].cx += dx; w.formations[f].cy += dy; w.formations[f].goal_x += dx; w.formations[f].goal_y += dy;
			w.formations[f].ai_enabled = false;
			int enemy = -1; float best = 1e30f; // nearest standing team-1 formation not yet taken by another rider formation
			for (int e = per_team; e < (int)w.formations.size(); ++e) {
				const float ex = w.formations[e].cx - ncx, ey = w.formations[e].cy - ncy, d2 = ex * ex + ey * ey;
				if (d2 < best && std::find(taken.begin(), taken.end(), e) == taken.end()) { best = d2; enemy = e; }
			}
			if (enemy >= 0) taken.push_back(enemy); // each riding formation takes its own standing body
			ordered += (enemy >= 0 && w.host_order(f, 7, 0.f, 0.f, (double)enemy) == OK) ? 1 : 0;
		}
		std::printf("cavalry: riders=%d formations_ordered=%d (CHARGE to the nearest standing team-1 formation)\n", riders, ordered);
	}
	const float dt = 1.f / 30.f;
	const int steps = a.seconds * 30;
	Series total, impact, quiet; // CAV-4a: impact windows (a contact step and the 15 steps, 0.5 s, after it) and the other steps
	int impact_left = 0, peak_gallop = 0;
	double form_speed_sum = 0.0, charge_speed_sum = 0.0;
	uint64_t form_speed_n = 0, charge_speed_n = 0;
	PhaseTimes acc;
	std::vector<float> buf;
	FILE *dump = nullptr;
	int n = w.soldier_count();
	if (a.dump_every > 0) {
		std::string p = a.out + "/dump.bin";
		dump = std::fopen(p.c_str(), "wb");
		int32_t hdr[3] = {W, H, n};
		std::fwrite(hdr, 4, 3, dump);
		std::vector<uint8_t> tf((size_t)W * H), rr((size_t)W * H);
		for (int i = 0; i < W * H; ++i) {
			tf[i] = (uint8_t)((w.terrain.walkable(i % W, i / W) ? 1 : 0) | (w.terrain.height[i] << 1) | ((w.terrain.flags[i] & 1) ? 0 : 4));
			rr[i] = w.terrain.ramp_edges[i] ? 1 : 0;
		}
		std::fwrite(tf.data(), 1, tf.size(), dump);
		std::fwrite(rr.data(), 1, rr.size(), dump);
	}
	std::printf("scenario=%s n=%d formations=%zu map=%dx%d threads=%d ranged_share=%.2f ai=%d\n", a.scenario.c_str(), n,
	            w.formations.size(), W, H, a.threads, a.ranged_share, (int)a.ai);
	uint64_t max_overlap = 0;
	int peak_fight = 0;
	// per-5-second segments (Astra review 2026-09-29: keep the time course, not only the whole-run mean)
	std::string sp = a.out + "/series_" + a.scenario + "_n" + std::to_string(n) + "_t" + std::to_string(a.threads) + ".csv";
	FILE *series = std::fopen(sp.c_str(), "w");
	if (series) std::fprintf(series, "phase,t_end_s,step_mean_ms,step_p95_ms,step_max_ms,alive,down,captive,fighting,engaging,routed_now,deaths,bled,kos,pairs,shots,rescues,captures\n");
	Series seg;
	double seg_t = 0;
	auto seg_tick = [&](const char *phase, double ms, double sim_t) {
		seg.add(ms);
		if (seg.v.size() < 150) return;
		w.measure();
		int routed_now = 0;
		for (auto &f : w.formations) routed_now += f.routed ? 1 : 0;
		if (series)
			std::fprintf(series, "%s,%.0f,%.4f,%.4f,%.4f,%d,%d,%d,%d,%d,%d,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n", phase, sim_t, seg.mean(),
			             seg.pct(.95), seg.max(), w.stats.alive, w.stats.down, w.stats.captive, w.stats.fighting, w.stats.engaging,
			             routed_now, (unsigned long long)w.stats.deaths, (unsigned long long)w.stats.bled_deaths,
			             (unsigned long long)w.stats.kos, (unsigned long long)w.stats.pairs, (unsigned long long)w.stats.shots,
			             (unsigned long long)w.stats.rescues_done, (unsigned long long)w.stats.captures_done);
		seg.v.clear();
	};
	auto wall0 = Clock::now();
	for (int s = 0; s < steps; ++s) {
		const uint64_t c_before = w.stats.cav_contacts, pairs_before = w.stats.pairs;
		w.step(dt);
		auto t = Clock::now();
		w.pack_render(buf, 64.f);
		double pr = std::chrono::duration<double, std::milli>(Clock::now() - t).count();
		PhaseTimes p = w.last;
		p.present = pr;
		p.total += pr;
		if (s >= 30) { total.add(p.total); acc.add(p); }
		// impact window: a cavalry contact (cavalry) or a melee pair (battle) in this step or the 15 steps before it
		if (cavalry ? w.stats.cav_contacts > c_before : w.stats.pairs > pairs_before) impact_left = 16;
		if (s >= 30) (impact_left > 0 ? impact : quiet).add(p.total);
		if (impact_left > 0) --impact_left;
		if (cavalry) { // rider speeds: marching to the form-up point (CS_FORM, not yet there) and charging riders (CS_CHARGE)
			int gallop = 0;
			for (int f = 0; f < per_team && f < (int)w.formations.size(); f += 5) {
				const Formation &F = w.formations[f];
				for (int i : F.members) {
					if (!w.mounted[i] || !w.can_act(i)) continue;
					const double v = std::hypot(w.vx[i], w.vy[i]);
					gallop += v >= 7.9 ? 1 : 0;
					if (F.order == Order::CHARGE && F.charge_stage == CS_FORM && !F.arrived && w.state[i] == S_SLOT) { form_speed_sum += v; ++form_speed_n; }
					if (w.charge_rider(i)) { charge_speed_sum += v; ++charge_speed_n; }
				}
			}
			peak_gallop = std::max(peak_gallop, gallop);
		}
		seg_t = (double)(s + 1) / 30.0;
		seg_tick("battle", p.total, seg_t);
		if (std::getenv("WG_SPIKE") && p.total > 15.0) std::printf("spike s=%d total=%.2f hash=%.2f fields=%.2f cmd=%.2f ai=%.2f form=%.2f contact=%.2f soldier=%.2f timers=%.2f ex=%.2f ranged=%.2f act=%.2f fat=%.2f compact=%.2f\n", s, p.total, p.hash, p.fields, p.command, p.ai, p.formation, p.contact, p.soldier, p.timers, p.exchange, p.ranged, p.actions, p.fatigue, p.compact);
		if (cavalry && std::getenv("WG_CAV_DEBUG") && s % 60 == 59) {
			const Formation &F = w.formations[std::atoi(std::getenv("WG_CAV_DEBUG"))];
			std::printf("dbg lag=%.2f spacing=%.2f cols=%d ", F.lag, F.spacing, F.cols); std::printf("dbg t=%d order=%d stage=%d t_left=%.1f centre=(%.1f,%.1f) goal=(%.1f,%.1f) arrived=%d field=%d los=%d contact=%d fight=%d\n",
			            (s + 1) / 30, (int)F.order, (int)F.charge_stage, F.charge_t, F.cx, F.cy, F.goal_x, F.goal_y, (int)F.arrived,
			            F.field, (int)F.los_goal, (int)F.in_contact, w.stats.fighting);
			if (F.charge_target_form >= 0) { int able = 0; for (int i : w.formations[F.charge_target_form].members) able += w.can_act(i) ? 1 : 0; std::printf("  dbg target form=%d team=%d able=%d own_team=%d tx=%.1f ty=%.1f\n", F.charge_target_form, w.formations[F.charge_target_form].team, able, F.team, F.charge_tx, F.charge_ty); }
			{ int spent = 0, fight = 0, slot = 0, charging = 0; double sp = 0, along = 0; int nrid = 0;
			  for (int i : F.members) if (w.can_act(i) && w.mounted[i]) { ++nrid; spent += w.cav_spent[i]; fight += w.state[i] == S_FIGHT; slot += w.state[i] == S_SLOT; charging += w.charge_rider(i); sp += std::hypot(w.vx[i], w.vy[i]); }
			  std::printf("  dbg riders=%d spent=%d fight=%d slot=%d charge_rider=%d mean_speed=%.2f\n", nrid, spent, fight, slot, charging, nrid ? sp / nrid : 0.0); (void)along; }
		}
		if (s % 30 == 29) {
			w.measure();
			max_overlap = std::max<uint64_t>(max_overlap, w.stats.deep_overlap_pairs);
			peak_fight = std::max(peak_fight, w.stats.fighting);
			if (s % 300 == 299) {
				int alive_t[256] = {0}, routed_t[256] = {0};
				for (int i = 0; i < n; ++i) if (w.alive(i)) alive_t[w.team[i]]++;
				for (auto &f : w.formations) if (f.routed) routed_t[f.team]++;
				std::printf("t=%3ds alive=%d/%d/%d fight=%d engage=%d down=%d dead=%llu pairs=%llu shots=%llu routs=%d/%d succ=%llu step=%.2fms\n",
				            (s + 1) / 30, alive_t[0], alive_t[1] + alive_t[2], alive_t[5], w.stats.fighting, w.stats.engaging, w.stats.down,
				            (unsigned long long)w.stats.deaths, (unsigned long long)w.stats.pairs, (unsigned long long)w.stats.shots,
				            routed_t[0], routed_t[1], (unsigned long long)w.stats.successions, p.total);
			}
		}
		if (dump && s % a.dump_every == 0) {
			int32_t sn = s;
			std::fwrite(&sn, 4, 1, dump);
			std::vector<float> xy(2 * (size_t)n);
			std::vector<uint8_t> meta(n);
			for (int i = 0; i < n; ++i) {
				xy[2 * i] = w.px[i]; xy[2 * i + 1] = w.py[i];
				meta[i] = (uint8_t)(w.team[i] | (w.alive(i) << 1) | ((w.state[i] & 15) << 2) | (w.ko[i] > 0 ? 64 : 0) | (w.troop[i] ? 128 : 0));
			}
			std::fwrite(xy.data(), 4, xy.size(), dump);
			std::fwrite(meta.data(), 1, meta.size(), dump);
			int32_t nf = (int32_t)w.formations.size();
			std::fwrite(&nf, 4, 1, dump);
			for (auto &F : w.formations) { float c[3] = {F.cx, F.cy, (float)(F.team | (F.routed ? 2 : 0))}; std::fwrite(c, 4, 3, dump); }
			int32_t np = (int32_t)w.projectiles.size();
			std::fwrite(&np, 4, 1, dump);
			for (auto &p : w.projectiles) {
				float c[4] = {(float)p.source.x + 0.5f, (float)p.source.y + 0.5f, (float)p.target.x + 0.5f, (float)p.target.y + 0.5f};
				std::fwrite(c, 4, 4, dump);
			}
		}
	}
	double wall = std::chrono::duration<double>(Clock::now() - wall0).count();
	uint64_t bled_in_battle = w.stats.bled_deaths, deaths_in_battle = w.stats.deaths, rescued_in_battle = w.stats.bandaged,
	         captured_in_battle = w.stats.captures_done;
	int down_end_battle = 0, bleeding_end_battle = 0;
	for (int i = 0; i < n; ++i) if (w.alive(i) && w.ko[i] > 0) { ++down_end_battle; if (!w.bandaged[i] && !w.captive[i]) ++bleeding_end_battle; }
	// save / load cost at the end of the battle (same build); the original and the loaded copy then both
	// run 1 more second and must have the same full-state hash
	double save_ms = 0, load_ms = 0;
	size_t save_bytes = 0;
	bool save_same = false;
	{
		auto t0 = Clock::now();
		std::vector<uint8_t> blob = w.save();
		save_ms = std::chrono::duration<double, std::milli>(Clock::now() - t0).count();
		save_bytes = blob.size();
		World r(a.threads);
		t0 = Clock::now();
		bool ok = r.load(blob);
		load_ms = std::chrono::duration<double, std::milli>(Clock::now() - t0).count();
		for (int k = 0; k < 30; ++k) { w.step(dt); if (ok) r.step(dt); } // the loaded copy must continue exactly like the original
		save_same = ok && r.state_hash() == w.state_hash();
	}
	double aftermath_game_s = 0, aftermath_combat_s = 0;
	if (a.aftermath > 0) {
		// both sides hold, AI off; the Site clock runs on its own: 1:1 while combat events keep
		// combat_left up, then 1 action second = 1 game minute
		// every formation steps back 15 cells, away from the centre of all hostile formations (a retreat
		// keeps going without a commander) and then holds, so the lines separate and the Site can leave combat
		w.cfg.ai = false;
		std::vector<std::pair<float, float>> goals;
		for (size_t f = 0; f < w.formations.size(); ++f) {
			const auto &F = w.formations[f];
			double sx = 0, sy = 0, cnt = 0;
			for (const auto &o : w.formations) {
				if (!w.hostile(o.team, F.team) || o.members.empty()) continue;
				sx += o.cx; sy += o.cy; cnt += 1;
			}
			float dx = cnt > 0 ? F.cx - (float)(sx / cnt) : 0.f, dy = cnt > 0 ? F.cy - (float)(sy / cnt) : 0.f, d = std::sqrt(dx * dx + dy * dy);
			if (d < 1e-3f) { dx = -std::cos(F.facing); dy = -std::sin(F.facing); d = 1; }
			goals.push_back({std::clamp(F.cx + dx / d * 15.f, 2.f, (float)W - 3.f), std::clamp(F.cy + dy / d * 15.f, 2.f, (float)H - 3.f)});
		}
		for (size_t f = 0; f < w.formations.size(); ++f) w.order_retreat((int)f, goals[f].first, goals[f].second);
		int as = (int)(a.aftermath * 30);
		for (int s = 0; s < as; ++s) {
			auto t0 = Clock::now();
			if (w.combat_left > 0) aftermath_combat_s += dt;
			w.step(dt);
			aftermath_game_s += w.game_dt;
			seg_tick("aftermath", std::chrono::duration<double, std::milli>(Clock::now() - t0).count(), seg_t + (double)(s + 1) / 30.0);
		}
	}
	if (dump) std::fclose(dump);
	if (series) std::fclose(series);
	w.measure();
	if (std::getenv("WG_OVL")) {
		int hist[16][16] = {{0}};
		for (int i = 0; i < n; ++i) for (int j = i + 1; j < n; ++j) {
			if (!w.alive(i) || !w.alive(j) || w.ko[i] > 0 || w.ko[j] > 0) continue;
			float dx = w.px[i] - w.px[j], dy = w.py[i] - w.py[j];
			if (std::fabs(dx) > 0.35f || std::fabs(dy) > 0.35f || dx * dx + dy * dy >= 0.35f * 0.35f) continue;
			int a = w.state[i], b = w.state[j]; if (a > b) std::swap(a, b);
			if (a == 0 && b == 0 && hist[0][0] < 12) std::printf("pair %d %d at (%.2f,%.2f) (%.2f,%.2f) form %d %d slot %d %d fo=%d\n", i, j, w.px[i], w.py[i], w.px[j], w.py[j], w.form[i], w.form[j], w.slot[i], w.slot[j], (int)w.formations[w.form[i]].order);
			hist[a][b]++; if (w.team[i] != w.team[j]) hist[15][15]++;
		}
		for (int a = 0; a < 16; ++a) for (int b = 0; b < 16; ++b) if (hist[a][b]) std::printf("ovl %d-%d: %d\n", a, b, hist[a][b]);
	}
	int alive_t[256] = {0}, routed_t[256] = {0};
	for (int i = 0; i < n; ++i) if (w.alive(i)) alive_t[w.team[i]]++;
	for (auto &f : w.formations) if (f.routed) routed_t[f.team]++;
	int ammo_left = 0;
	for (int i = 0; i < n; ++i) ammo_left += w.ammo[i];
	double k = acc.steps ? 1.0 / acc.steps : 0;
	const Stats &st = w.stats;
	std::printf("\n== RESULT (first second excluded) ==\n");
	std::printf("step_total mean=%.3f p95=%.3f p99=%.3f max=%.3f ms -> %.3f us/soldier/step\n", total.mean(), total.pct(.95),
	            total.pct(.99), total.max(), total.mean() * 1000.0 / std::max(1, n));
	std::printf("  hash %.3f | fields %.3f | command %.3f | ai %.3f | formation %.3f | contact %.3f | soldier %.3f | timers %.3f\n"
	            "  exchange %.3f | ranged %.3f | actions %.3f | fatigue %.3f | compact %.3f | present %.3f\n",
	            acc.hash * k, acc.fields * k, acc.command * k, acc.ai * k, acc.formation * k, acc.contact * k, acc.soldier * k,
	            acc.timers * k, acc.exchange * k, acc.ranged * k, acc.actions * k, acc.fatigue * k, acc.compact * k, acc.present * k);
	std::printf("invariants: illegal_cell=%llu illegal_step=%llu cooldown_violations=%llu max_deep_overlap=%llu\n",
	            (unsigned long long)st.illegal_cell, (unsigned long long)st.illegal_step, (unsigned long long)st.cooldown_violations,
	            (unsigned long long)max_overlap);
	std::printf("exchange: rounds=%llu pairs=%llu draw=%llu small=%llu big=%llu knockback=%llu skills=%llu encircle=%llu\n",
	            (unsigned long long)st.rounds, (unsigned long long)st.pairs, (unsigned long long)st.draws, (unsigned long long)st.small,
	            (unsigned long long)st.big, (unsigned long long)st.knockbacks, (unsigned long long)st.skills_used,
	            (unsigned long long)st.encircle_assigned);
	std::printf("ranged: shots=%llu hit=%llu graze=%llu miss=%llu blocked=%llu empty=%llu friendly=%llu ammo_left=%d in_flight=%zu\n",
	            (unsigned long long)st.shots, (unsigned long long)st.hits, (unsigned long long)st.grazes, (unsigned long long)st.misses,
	            (unsigned long long)st.blocked, (unsigned long long)st.empty, (unsigned long long)st.friendly_hits, ammo_left,
	            w.projectiles.size());
	std::printf("wounded: battle end down=%d bleeding=%d | in battle: deaths=%llu (bled %llu) rescued=%llu | aftermath %.0fs x60: deaths=%llu (bled %llu) rescued=%llu\n",
	            down_end_battle, bleeding_end_battle, (unsigned long long)deaths_in_battle, (unsigned long long)bled_in_battle,
	            (unsigned long long)rescued_in_battle, a.aftermath, (unsigned long long)(w.stats.deaths - deaths_in_battle),
	            (unsigned long long)(w.stats.bled_deaths - bled_in_battle), (unsigned long long)(w.stats.bandaged - rescued_in_battle));
	std::printf("save: %.2f MB in %.1f ms, load %.1f ms (flow fields rebuilt), continuation identical=%d\n", save_bytes / 1048576.0, save_ms, load_ms, (int)save_same);
	if (a.aftermath > 0)
		std::printf("aftermath clock: %.0f action s, of which %.1f s still in combat time; %.2f game hours\n", a.aftermath, aftermath_combat_s,
		            aftermath_game_s / 3600.0);
	std::printf("captivity: rescue_seek=%.0f auto_capture=%d seek=%.0f | captured in battle=%llu aftermath=%llu (auto %llu, cancelled %llu) captive_now=%d escapes=%llu\n",
	            a.rescue_seek, (int)a.auto_capture, a.capture_seek, (unsigned long long)captured_in_battle,
	            (unsigned long long)(st.captures_done - captured_in_battle), (unsigned long long)st.captures_auto,
	            (unsigned long long)st.captures_cancelled, st.captive, (unsigned long long)st.escapes);
	std::printf("people: ko=%llu dead=%llu wakes=%llu rescue start/done/cancel=%llu/%llu/%llu down_now=%d alive(f0/f1/f2/f5)=%d/%d/%d/%d\n",
	            (unsigned long long)st.kos, (unsigned long long)st.deaths, (unsigned long long)st.wakes,
	            (unsigned long long)st.rescues_started, (unsigned long long)st.rescues_done, (unsigned long long)st.rescues_cancelled,
	            st.down, alive_t[0], alive_t[1], alive_t[2], alive_t[5]);
	std::printf("command: successions=%llu command_losses=%llu routs=%llu (now %d/%d) pursuits=%llu ends=%llu ai_orders=%llu\n",
	            (unsigned long long)st.successions, (unsigned long long)st.command_losses, (unsigned long long)st.routs, routed_t[0],
	            routed_t[1], (unsigned long long)st.pursuits, (unsigned long long)st.pursuit_ends, (unsigned long long)st.ai_orders);
	if (cavalry) for (int f = 0; f < per_team && f < (int)w.formations.size(); f += 5) {
		const Formation &F = w.formations[f];
		int riding = 0, alive_r = 0;
		for (int i : F.members) if (w.can_act(i)) { ++alive_r; riding += w.mounted[i] ? 1 : 0; }
		std::printf("cav_formation %d: order=%d stage=%d charge_t=%.2f centre=(%.1f,%.1f) goal=(%.1f,%.1f) arrived=%d able=%d mounted=%d cmd_ok=%d hits=%d\n",
		            f, (int)F.order, (int)F.charge_stage, F.charge_t, F.cx, F.cy, F.goal_x, F.goal_y, (int)F.arrived, alive_r, riding,
		            (int)w.charge_commander_ok(f), 0);
	}
	if (cavalry) { // cycles per cavalry formation (completed charge cycles = breaks through to RALLY) and the impact-window timing
		std::printf("cavalry_cycles:");
		for (int f = 0; f < per_team && f < (int)w.formations.size(); f += 5) std::printf(" %d", w.formations[f].charge_runs);
		std::printf("\n");
	}
	std::printf("impact_step_ms: n=%zu p50=%.3f p95=%.3f p99=%.3f max=%.3f mean=%.3f (window: a cavalry contact step (battle: a melee pair step) and 0.5 s after)\n",
	            impact.v.size(), impact.pct(.5), impact.pct(.95), impact.pct(.99), impact.max(), impact.mean());
	std::printf("quiet_step_ms: n=%zu p50=%.3f p95=%.3f p99=%.3f max=%.3f mean=%.3f (steps outside those windows)\n",
	            quiet.v.size(), quiet.pct(.5), quiet.pct(.95), quiet.pct(.99), quiet.max(), quiet.mean());
	if (cavalry)
		std::printf("cavalry_speed: form_march_mean=%.2f (riders following slots while the form-up walks) charge_mean=%.2f (charging riders, from a standing line) impact_mean=%.2f peak_gallop_riders=%d (>= 7.9 cells/s in one step)\n",
		            form_speed_n ? form_speed_sum / (double)form_speed_n : 0.0, charge_speed_n ? charge_speed_sum / (double)charge_speed_n : 0.0,
		            w.stats.cav_contacts ? w.stats.cav_impact_speed / (double)w.stats.cav_contacts : 0.0, peak_gallop);
	std::printf("step_ms: p50=%.3f p95=%.3f p99=%.3f max=%.3f mean=%.3f (steps %zu)\n", total.pct(.5), total.pct(.95), total.pct(.99), total.max(), total.mean(), total.v.size());
	std::printf("cavalry_stats: contacts=%llu penetrations=%llu falls=%llu stops=%llu dismounts=%llu shocks=%llu charge_forms=%llu charge_breaks=%llu charge_rallies=%llu\n",
	            (unsigned long long)w.stats.cav_contacts, (unsigned long long)w.stats.cav_penetrations, (unsigned long long)w.stats.cav_falls, (unsigned long long)w.stats.cav_stops,
	            (unsigned long long)w.stats.cav_dismounts, (unsigned long long)w.stats.cav_shocks, (unsigned long long)w.stats.charge_forms,
	            (unsigned long long)w.stats.charge_breaks, (unsigned long long)w.stats.charge_rallies);
	std::printf("wall=%.1fs sim=%ds peak_fighting=%d\nstate_hash=%016llx\n", wall, a.seconds, peak_fight, (unsigned long long)w.state_hash());
	std::string jp = a.out + "/result_" + a.scenario + "_n" + std::to_string(n) + "_t" + std::to_string(a.threads) + ".json";
	if (FILE *j = std::fopen(jp.c_str(), "w")) {
		std::fprintf(j,
		             "{\"scenario\":\"%s\",\"n\":%d,\"map\":%d,\"threads\":%d,\"seconds\":%d,\"ranged_share\":%.2f,"
		             "\"step_mean_ms\":%.4f,\"step_p95_ms\":%.4f,\"step_p99_ms\":%.4f,\"step_max_ms\":%.4f,\"us_per_soldier_step\":%.4f,"
		             "\"phases\":{\"hash\":%.4f,\"fields\":%.4f,\"command\":%.4f,\"ai\":%.4f,\"formation\":%.4f,\"contact\":%.4f,"
		             "\"soldier\":%.4f,\"timers\":%.4f,\"exchange\":%.4f,\"ranged\":%.4f,\"actions\":%.4f,\"fatigue\":%.4f,\"compact\":%.4f,\"present\":%.4f},"
		             "\"illegal_cell\":%llu,\"illegal_step\":%llu,\"cooldown_violations\":%llu,\"max_deep_overlap\":%llu,"
		             "\"pairs\":%llu,\"draws\":%llu,\"small\":%llu,\"big\":%llu,\"knockbacks\":%llu,\"skills\":%llu,\"encircle\":%llu,"
		             "\"shots\":%llu,\"hits\":%llu,\"grazes\":%llu,\"misses\":%llu,\"blocked\":%llu,\"friendly_hits\":%llu,"
		             "\"kos\":%llu,\"deaths\":%llu,\"bled_deaths\":%llu,\"battle_deaths\":%llu,\"battle_bled\":%llu,\"down_at_end\":%d,\"bleeding_at_end\":%d,\"save_mb\":%.3f,\"save_ms\":%.2f,\"load_ms\":%.2f,\"save_same\":%d,\"aftermath_s\":%.0f,\"aftermath_game_h\":%.3f,\"aftermath_combat_s\":%.1f,\"rescues_done\":%llu,\"bandaged\":%llu,\"wakes\":%llu,\"captures_done\":%llu,\"battle_captures\":%llu,\"captive_now\":%d,\"rescue_seek\":%.1f,\"auto_capture\":%d,\"successions\":%llu,\"command_losses\":%llu,\"routs\":%llu,"
		             "\"pursuits\":%llu,\"ai_orders\":%llu,\"alive\":[%d,%d],\"alive_f0_f2_f5\":[%d,%d,%d],\"peak_fighting\":%d,\"state_hash\":\"%016llx\"}\n",
		             a.scenario.c_str(), n, W, a.threads, a.seconds, a.ranged_share, total.mean(), total.pct(.95), total.pct(.99),
		             total.max(), total.mean() * 1000.0 / std::max(1, n), acc.hash * k, acc.fields * k, acc.command * k, acc.ai * k,
		             acc.formation * k, acc.contact * k, acc.soldier * k, acc.timers * k, acc.exchange * k, acc.ranged * k,
		             acc.actions * k, acc.fatigue * k, acc.compact * k, acc.present * k, (unsigned long long)st.illegal_cell,
		             (unsigned long long)st.illegal_step, (unsigned long long)st.cooldown_violations, (unsigned long long)max_overlap,
		             (unsigned long long)st.pairs, (unsigned long long)st.draws, (unsigned long long)st.small, (unsigned long long)st.big,
		             (unsigned long long)st.knockbacks, (unsigned long long)st.skills_used, (unsigned long long)st.encircle_assigned,
		             (unsigned long long)st.shots, (unsigned long long)st.hits, (unsigned long long)st.grazes,
		             (unsigned long long)st.misses, (unsigned long long)st.blocked, (unsigned long long)st.friendly_hits,
		             (unsigned long long)st.kos, (unsigned long long)st.deaths, (unsigned long long)st.bled_deaths, (unsigned long long)deaths_in_battle,
		             (unsigned long long)bled_in_battle, down_end_battle, bleeding_end_battle, save_bytes / 1048576.0, save_ms, load_ms, (int)save_same, a.aftermath, aftermath_game_s / 3600.0, aftermath_combat_s, (unsigned long long)st.rescues_done,
		             (unsigned long long)st.bandaged, (unsigned long long)st.wakes, (unsigned long long)st.captures_done, (unsigned long long)captured_in_battle,
		             st.captive, a.rescue_seek, (int)a.auto_capture,
		             (unsigned long long)st.successions, (unsigned long long)st.command_losses, (unsigned long long)st.routs,
		             (unsigned long long)st.pursuits, (unsigned long long)st.ai_orders, alive_t[0], alive_t[1], alive_t[0], alive_t[2], alive_t[5], peak_fight,
		             (unsigned long long)w.state_hash());
		std::fclose(j);
	}
	// release gate: invariant violations fail the run (non-zero exit code for the batch file)
	if (st.illegal_cell || st.illegal_step || st.cooldown_violations || !save_same) {
		std::printf("GATE FAIL: illegal_cell=%llu illegal_step=%llu cooldown_violations=%llu save_same=%d\n", (unsigned long long)st.illegal_cell,
		            (unsigned long long)st.illegal_step, (unsigned long long)st.cooldown_violations, (int)save_same);
		return 2;
	}
	return 0;
}
