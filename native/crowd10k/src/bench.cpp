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

static void build_terrain(Terrain &t, int W, int H, bool features) {
	t.allocate(W, H);
	if (!features) return;
	int bridges[3][2] = {{(int)(0.25f * H), 6}, {(int)(0.5f * H), 8}, {(int)(0.75f * H), 5}};
	for (int y = 0; y < H; ++y) {
		int rx = (int)(0.45f * W + 3.0f * std::sin((float)y * 0.05f));
		bool bridge = false;
		for (auto &b : bridges) if (y >= b[0] - b[1] / 2 && y < b[0] - b[1] / 2 + b[1]) bridge = true;
		for (int x = rx; x < rx + 4; ++x)
			if (!bridge) t.flags[t.idx(x, y)] = 0;
	}
	int px0 = (int)(0.62f * W), px1 = (int)(0.92f * W), py0 = (int)(0.12f * H), py1 = (int)(0.88f * H);
	for (int y = py0; y < py1; ++y)
		for (int x = px0; x < px1; ++x) t.height[t.idx(x, y)] = 1;
	int ramps[3][2] = {{(int)(0.3f * H), 8}, {(int)(0.5f * H), 10}, {(int)(0.7f * H), 8}};
	for (auto &r : ramps)
		for (int y = r[0] - r[1] / 2; y < r[0] - r[1] / 2 + r[1]; ++y) {
			t.ramp_edges[t.idx(px0, y)] |= 1 << wg::Dir::W;
			t.ramp_edges[t.idx(px0 - 1, y)] |= 1 << wg::Dir::E;
		}
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
	bool battle = a.scenario == "battle", three = a.scenario == "three";
	build_terrain(w.terrain, W, H, battle);
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
	const float dt = 1.f / 30.f;
	const int steps = a.seconds * 30;
	Series total;
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
		w.step(dt);
		auto t = Clock::now();
		w.pack_render(buf, 64.f);
		double pr = std::chrono::duration<double, std::milli>(Clock::now() - t).count();
		PhaseTimes p = w.last;
		p.present = pr;
		p.total += pr;
		if (s >= 30) { total.add(p.total); acc.add(p); }
		seg_t = (double)(s + 1) / 30.0;
		seg_tick("battle", p.total, seg_t);
		if (std::getenv("WG_SPIKE") && p.total > 15.0) std::printf("spike s=%d total=%.2f hash=%.2f fields=%.2f cmd=%.2f ai=%.2f form=%.2f contact=%.2f soldier=%.2f timers=%.2f ex=%.2f ranged=%.2f act=%.2f fat=%.2f compact=%.2f\n", s, p.total, p.hash, p.fields, p.command, p.ai, p.formation, p.contact, p.soldier, p.timers, p.exchange, p.ranged, p.actions, p.fatigue, p.compact);
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
