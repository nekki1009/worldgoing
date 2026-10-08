// Presentation flicker probe: the Godot P2 layout (50 formations x 100, three factions, 100 x 100 open
// ground), pack_rows every 30 Hz step, and per soldier count
//   - direction / visual-slot changes, and "flickers": a value that lasts <= 3 steps (0.1 s) and then
//     changes again (what reads as twitching on screen)
//   - ground-position reversals: the screen position steps back against its previous step (> 0.5 px)
// Only conscious, free soldiers are counted.
#include "../src/crowd_core.hpp"
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <string>
using namespace wg;

int main(int argc, char **argv) {
	int seconds = argc > 1 ? std::atoi(argv[1]) : 60;
	const bool filter = argc > 2 ? std::atoi(argv[2]) != 0 : true;
	const float rev_px = argc > 3 ? (float)std::atof(argv[3]) : 0.5f; // reversal threshold, pixels per 1/30 s
	World w(4);
	w.render_filter = filter;
	w.cfg.seed = 581;
	w.terrain.allocate(100, 100);
	const float zone_x[3][2] = {{0.09f, 0.20f}, {0.81f, 0.92f}, {0.45f, 0.56f}};
	const float facing[3] = {0.f, 3.14159265f, 1.5707963f};
	int64_t pid = 1000;
	for (int k = 0; k < 50; ++k) {
		int fac = k % 3, slot = k / 3;
		float cx = 100.f * zone_x[fac][slot % 2], cy = 100.f * (0.06f + 0.11f * (float)((slot / 2) % 9));
		int troop = slot % 5 == 4 ? 1 + (slot / 5) % 2 : 0;
		int f = w.add_formation(fac, cx, cy, facing[fac], 10, 1.f, (Troop)troop, 20.0 + 10.0 * fac);
		for (int s = 0; s < 100; ++s) {
			rules::Equip e; e.family = troop == 0 ? rules::F_LONGSWORD : (troop == 1 ? rules::F_BOW : rules::F_CROSSBOW);
			e.material = fac == 0 ? 3 : 2; e.armor = (uint8_t)(2 + s % 2); e.shield = troop == 0;
			w.add_soldier(f, e, s == 0 ? R_CAPTAIN : (s <= 2 ? R_OFFICER : R_REGULAR), pid++, troop ? 20 : 0);
		}
	}
	w.finalize();
	// one 8-frame track per (slot, direction), 1 s loops, anchor (0, 0)
	for (int t = 0; t < V_COUNT * 4; ++t) {
		RenderTrack tr; tr.sequence = t; tr.duration = 1.f; tr.loop = true;
		for (int f = 0; f < 8; ++f) { tr.times.push_back(f / 8.f); tr.ax.push_back(0); tr.ay.push_back(0); }
		w.render_tracks.push_back(tr);
	}
	RenderKit K; K.page = 0; K.palette = 0; K.scale = 1;
	for (int s = 0; s < V_COUNT; ++s) for (int d = 0; d < 4; ++d) K.track[s][d] = s * 4 + d;
	w.render_kits.push_back(K);
	for (int i = 0; i < w.soldier_count(); ++i) w.kit[i] = 0;
	w.render_trace = true;
	const int n = w.soldier_count();
	std::vector<int> dir_last(n, -1), dir_run(n, 0), slot_last(n, -1), slot_run(n, 0);
	std::vector<float> lx(n), ly(n), ldx(n, 0), ldy(n, 0);
	long dir_changes = 0, dir_flicker = 0, slot_changes = 0, slot_flicker = 0, reversals = 0, samples = 0;
	long slot_flicker_by[V_COUNT][V_COUNT] = {};
	std::vector<float> out, bounds; std::vector<int32_t> spans;
	const int steps = seconds * 30;
	long seg_df = 0, seg_sf = 0, seg_rev = 0, seg_samples = 0;
	std::printf("t,alive_free,dir_flicker_per_soldier_s,slot_flicker_per_soldier_s,reversals_per_soldier_s,fighting\n");
	for (int step = 0; step < steps; ++step) {
		w.step(1.f / 30.f);
		// the screen runs at 4x the 30 Hz simulation: pack four times per step, measure the last
		for (int f = 0; f < 4; ++f) { w.render_frame_dt = 1.f / 120.f; w.pack_rows(out, spans, bounds, 64.f); }
		for (int i = 0; i < n; ++i) {
			const uint16_t st = w.trace_state[i];
			const bool free_up = w.can_act(i);
			if (st == 0xFFFF || !free_up) { dir_last[i] = slot_last[i] = -1; continue; }
			const int d = st & 0xFF, sl = st >> 8;
			const float x = w.trace_xy[i * 2], y = w.trace_xy[i * 2 + 1];
			++samples; ++seg_samples;
			if (dir_last[i] >= 0) {
				if (d != dir_last[i]) { ++dir_changes; if (dir_run[i] <= 3) { ++dir_flicker; ++seg_df; } dir_run[i] = 1; } else ++dir_run[i];
				if (sl != slot_last[i]) {
					++slot_changes;
					if (slot_run[i] <= 3) { ++slot_flicker; ++seg_sf; ++slot_flicker_by[slot_last[i]][sl]; }
					slot_run[i] = 1;
				} else ++slot_run[i];
				const float dx = x - lx[i], dy = y - ly[i];
				if ((dx * ldx[i] + dy * ldy[i]) < 0.f && std::hypot(dx, dy) > rev_px && std::hypot(ldx[i], ldy[i]) > rev_px) { ++reversals; ++seg_rev; }
				ldx[i] = dx; ldy[i] = dy;
			} else { dir_run[i] = slot_run[i] = 1; ldx[i] = ldy[i] = 0; }
			dir_last[i] = d; slot_last[i] = sl; lx[i] = x; ly[i] = y;
		}
		if ((step + 1) % 150 == 0) {
			double ss = (double)seg_samples / 30.0; // soldier-seconds
			std::printf("%.0f,%ld,%.3f,%.3f,%.3f,%llu\n", (step + 1) / 30.0, seg_samples / 150, seg_df / ss, seg_sf / ss, seg_rev / ss,
				(unsigned long long)w.stats.pairs);
			seg_df = seg_sf = seg_rev = seg_samples = 0;
		}
	}
	double ss = (double)samples / 30.0;
	std::printf("\ntotal soldier-seconds %.0f\n", ss);
	std::printf("direction changes %.3f /soldier/s, flickers (<= 0.1 s) %.3f\n", dir_changes / ss, dir_flicker / ss);
	std::printf("slot changes %.3f /soldier/s, flickers %.3f\n", slot_changes / ss, slot_flicker / ss);
	std::printf("position reversals %.3f /soldier/s\n", reversals / ss);
	const char *names[V_COUNT] = {"idle", "walk", "run", "attack", "heavy", "guard", "hit", "knock", "shoot", "down", "uncon", "getup", "rescue"};
	std::printf("slot flickers from -> to (top):\n");
	for (int k = 0; k < 12; ++k) {
		long best = 0; int ba = 0, bb = 0;
		for (int a = 0; a < V_COUNT; ++a) for (int b = 0; b < V_COUNT; ++b) if (slot_flicker_by[a][b] > best) { best = slot_flicker_by[a][b]; ba = a; bb = b; }
		if (!best) break;
		std::printf("  %s -> %s: %ld\n", names[ba], names[bb], best);
		slot_flicker_by[ba][bb] = 0;
	}
}
