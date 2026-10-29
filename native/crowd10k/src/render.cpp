// Atlas presentation (P2b): per-soldier (page, sequence, frame, palette) and anchored position, packed
// into the 12-float 2D MultiMesh layout of terrain_army_batch_view's SHADER, in draw order: groups by
// (row, part, band, page), host actors (player, live captains) as markers between them.
// Presentation only: reads the simulation state, never writes it (its own filter state lives in `pres`).
#include "crowd_core.hpp"

#include <algorithm>
#include <array>
#include <cmath>

namespace wg {

namespace {
// terrain_army: dominant axis, ties go horizontal; screen +y is "down". Track direction order: up, right, down, left.
inline int direction_index(float face) {
	float dx = std::cos(face), dy = std::sin(face);
	if (std::fabs(dx) >= std::fabs(dy)) return dx >= 0 ? 1 : 3;
	return dy >= 0 ? 2 : 0;
}
// Keep the current direction until the facing is clearly (12 degrees) past the diagonal toward another one.
inline int direction_sticky(float face, int current) {
	const int raw = direction_index(face);
	if (raw == current || current < 0 || current > 3) return raw;
	static const float axis[4][2] = {{0.f, -1.f}, {1.f, 0.f}, {0.f, 1.f}, {-1.f, 0.f}};
	const float c = std::cos(face) * axis[current][0] + std::sin(face) * axis[current][1];
	return c > std::cos(0.7854f + 0.2094f) ? current : raw; // still within 57 degrees of the current axis
}
// terrain_army_batch_view / army_idle render: loop -> fposmod, one-shot -> clamp; last sample <= t
inline int frame_at(const RenderTrack &t, float age) {
	float src;
	if (!t.map.empty() && t.map_step > 0) {
		float k = age / t.map_step;
		if (k >= (float)(t.map.size() - 1)) src = t.map.back();
		else {
			int a = (int)k;
			float f = k - (float)a;
			src = t.map[a] + (t.map[a + 1] - t.map[a]) * f;
		}
	} else if (t.loop && t.duration > 0) {
		src = std::fmod(std::max(0.f, age), t.duration);
	} else {
		src = std::min(std::max(0.f, age), t.duration);
	}
	auto it = std::upper_bound(t.times.begin(), t.times.end(), src + 1e-6f);
	int f = (int)(it - t.times.begin()) - 1;
	return std::clamp(f, 0, (int)t.times.size() - 1);
}
} // namespace


void World::contact_pose(int i, int movement, int &slot, double &age) const {
	slot = V_IDLE; age = time + double(i % 97) * 0.37;
	const double since = time - vis_t0[i];
	if (hp[i] <= 0.0) { slot = V_DOWN; age = since; }
	else if (ko[i] > 0.0) {
		slot = V_DOWN; age = since;
		if (since >= vis_window[V_DOWN]) { slot = V_UNCONSCIOUS; age = since - vis_window[V_DOWN]; }
	} else if (getup[i] > 0.0) { slot = V_GET_UP; age = rules::GETUP_SECONDS - getup[i]; }
	else if (rescue_of[i] >= 0 && movement == 0) slot = V_RESCUE;
	else if (vis_kind[i] >= V_ATTACK && vis_kind[i] <= V_SHOOT && since < vis_window[vis_kind[i]]) { slot = vis_kind[i]; age = since; }
	else if (movement == 2) slot = V_RUN;
	else if (movement == 1) slot = V_WALK;
}

int World::pack_rows(std::vector<float> &out, std::vector<int32_t> &spans, std::vector<float> &bounds, float cell_pixels) {
	const int n = soldier_count();
	// key: row 16 | part 4 | band 4 | page 8 | in-row ground y 16 | index 16. group = key >> 32.
	struct Item { uint64_t key; int32_t i, track, frame; float x, y, gx, gy; };
	static thread_local std::vector<Item> items;
	items.clear();
	items.reserve((size_t)n + render_actors.size() / 2);
	const int bands = std::clamp(render_bands, 1, 15);
	const float band_px = 64.f / (float)bands;
	auto row_of = [](float gy) { return std::clamp(10 + (int)std::floor(gy / 64.f), 0, 65535); };
	auto in_row = [](float gy, int row) { return std::clamp(gy - (float)(row - 10) * 64.f, 0.f, 63.99f); };
	const float march = cfg.march_speed;
	if (render_trace) { trace_state.assign((size_t)n, 0xFFFF); trace_xy.assign((size_t)n * 2, 0.f); }
	// presentation clock: host frame time when given, else the simulated time since the last pack
	float h = render_frame_dt >= 0.f ? render_frame_dt : (pres_time < 0.0 ? 0.f : (float)(time - pres_time));
	h = std::clamp(h, 0.f, 0.25f);
	pres_time = time;
	render_frame_dt = -1.f;
	if (pres.size() != (size_t)n) pres.assign((size_t)n, Presentation{});
	// actors: the host's (render_actors) first, then host-controlled soldiers without a kit in soldier order
	static thread_local std::vector<float> auto_actors;
	auto_actors.clear();
	for (int i = 0; i < n; ++i) {
		if (released[i] || absent[i]) continue; // departed with a travelling person, or off the field (G5 S1): not drawn
		int k = kit[i];
		const bool has_kit = k >= 0 && k < (int)render_kits.size();
		if (!has_kit && !host_ctl[i]) continue; // a host soldier without a kit is drawn by the host (soldier_view)
		VisualSlot slot = V_IDLE;
		float age = (float)(time + (double)(i % 97) * 0.37); // desynchronised loops
		const double since = time - vis_t0[i];
		const bool lying = hp[i] <= 0.0 || ko[i] > 0.0;
		// ---- presentation filter: drawn ground position, travel state, direction
		Presentation &P = pres[(size_t)i];
		const float tx = px[i] * cell_pixels, ty = py[i] * cell_pixels;
		const float sim_speed = std::sqrt(vx[i] * vx[i] + vy[i] * vy[i]); // cells / s
		const bool event_start = vis_kind[i] >= V_ATTACK && vis_kind[i] <= V_SHOOT && since >= 0.0 && since < (double)h + 0.034;
		if (!render_filter || !P.ok || std::hypot(tx - P.x, ty - P.y) > 3.f * cell_pixels) {
			P.x = tx; P.y = ty; P.speed = sim_speed;
			P.move = sim_speed > 0.3f ? (sim_speed > march * 1.2f ? 2 : 1) : 0;
			P.dir = (uint8_t)direction_index(face[i]); P.dir_hold = P.move_hold = 0.f; P.ok = 1;
		} else if (h > 0.f) {
			P.speed += (sim_speed - P.speed) * (1.f - std::exp(-h / 0.25f));
			P.move_hold += h; P.dir_hold += h;
			if (P.move_hold >= 0.2f) {
				uint8_t m = P.move;
				if (m == 0 && P.speed > 0.35f) m = 1;
				else if (m >= 1 && P.speed < 0.15f) m = 0;
				if (m >= 1) m = (m == 2 ? P.speed > march * 1.1f : P.speed > march * 1.25f) ? 2 : 1;
				if (m != P.move) { P.move = m; P.move_hold = 0.f; }
			}
			// travelling: follow closely; standing: ignore jitter under 3 px and ease the rest in slowly
			const float ex = tx - P.x, ey = ty - P.y, e = std::hypot(ex, ey);
			const bool moving = P.move > 0 || lying || getup[i] > 0.0;
			if (moving || e > 3.f) {
				const float k = 1.f - std::exp(-h / (moving ? 0.08f : 0.30f));
				P.x += ex * k; P.y += ey * k;
			}
			if (!lying) {
				const int want = direction_sticky(face[i], P.dir);
				if (want != P.dir && (P.dir_hold >= 0.15f || event_start)) { P.dir = (uint8_t)want; P.dir_hold = 0.f; }
			}
		}
		int selected_slot; double selected_age;
		contact_pose(i, P.move, selected_slot, selected_age);
		slot = (VisualSlot)selected_slot; age = (float)selected_age;
		int d = render_filter ? (int)P.dir : direction_index(face[i]);
		P.slot = (uint8_t)slot; P.age = age; P.shown_dir = (uint8_t)d;
		if (!has_kit) { // the host draws him; he joins the draw order as an actor at his drawn ground point
			auto_actors.push_back(render_filter ? P.x : tx);
			auto_actors.push_back(render_filter ? P.y : ty);
			continue;
		}
		const RenderKit &K = render_kits[k];
		int tr = K.track[slot][d];
		if (tr < 0 && slot == V_RUN) tr = K.track[V_WALK][d];
		if (tr < 0) tr = K.track[V_IDLE][d];
		if (tr < 0) continue;
		const RenderTrack &T = render_tracks[tr];
		if (T.times.empty()) continue;
		int fr = frame_at(T, age);
		float gx = render_filter ? P.x : tx, gy = render_filter ? P.y : ty;
		if (render_trace) {
			trace_state[(size_t)i] = (uint16_t)((int)slot << 8 | d);
			trace_xy[(size_t)i * 2] = gx; trace_xy[(size_t)i * 2 + 1] = gy;
		}
		const int row = row_of(gy);
		const float local = in_row(gy, row);
		// part (actors above this soldier in its row) and band are filled in below
		uint64_t key = ((uint64_t)row << 48) | ((uint64_t)(K.page & 0xFF) << 32)
			| ((uint64_t)(local * 1024.f) << 16) | (uint64_t)(i & 0xFFFF);
		items.push_back({key, i, tr, fr, gx - T.ax[fr], gy - T.ay[fr] - terrain.visual_lift(gx / cell_pixels, gy / cell_pixels), gx, gy});
	}
	// actors sorted by (row, ground y, index); rank inside the row = its part
	struct Actor { int row; float y; int index; };
	static thread_local std::vector<Actor> actors;
	actors.clear();
	static thread_local std::vector<float> all_actors;
	all_actors.assign(render_actors.begin(), render_actors.end());
	all_actors.insert(all_actors.end(), auto_actors.begin(), auto_actors.end());
	for (size_t a = 0; a + 1 < all_actors.size(); a += 2) {
		const float ax = all_actors[a], ay = all_actors[a + 1];
		if (!std::isfinite(ax) || !std::isfinite(ay)) continue;
		actors.push_back({row_of(ay), ay, (int)(a / 2)});
	}
	std::sort(actors.begin(), actors.end(), [](const Actor &p, const Actor &q) {
		return p.row != q.row ? p.row < q.row : (p.y != q.y ? p.y < q.y : p.index < q.index);
	});
	for (size_t a = 0; a < actors.size(); ++a) {
		const Actor &A = actors[a];
		size_t first = a;
		while (first > 0 && actors[first - 1].row == A.row) --first;
		const uint64_t part = (uint64_t)std::min<size_t>(a - first, 15);
		const float ax = all_actors[(size_t)A.index * 2];
		uint64_t key = ((uint64_t)A.row << 48) | (part << 44) | (15ull << 40) | (0xFFull << 32)
			| ((uint64_t)(in_row(A.y, A.row) * 1024.f) << 16) | (uint64_t)(A.index & 0xFFFF);
		items.push_back({key, A.index, -1, 0, ax, A.y, ax, A.y});
	}
	// part = actors of a soldier's row standing at or above its ground line (they are drawn first)
	if (!actors.empty())
		for (Item &it : items) {
			if (it.track < 0) continue;
			const int row = (int)(it.key >> 48);
			auto at = std::lower_bound(actors.begin(), actors.end(), row, [](const Actor &p, int r) { return p.row < r; });
			uint64_t part = 0;
			for (; at != actors.end() && at->row == row && at->y <= it.gy; ++at) ++part;
			it.key |= std::min<uint64_t>(part, 15) << 44;
		}
	// Depth bands matter only where sprites of different pages can overlap. Mark, per (row, page), the
	// 64-px columns its soldiers cover (widened by one column each side for the sprite width); a row gets
	// bands only if two of its pages share a column. Rows where the pages stay apart (a bow company at
	// one end of the row, swordsmen at the other) keep a single group per page.
	if (bands > 1) {
		static thread_local std::vector<std::array<uint64_t, 4>> cover;
		static thread_local std::vector<uint8_t> banded;
		int row_lo = 65535, row_hi = -1, pages = 1;
		for (const Item &it : items) {
			if (it.track < 0) continue;
			const int r = (int)(it.key >> 48);
			row_lo = std::min(row_lo, r); row_hi = std::max(row_hi, r);
			pages = std::max(pages, (int)((it.key >> 32) & 0xFF) + 1);
		}
		if (row_hi >= row_lo && pages > 1) {
			const size_t rows_n = (size_t)(row_hi - row_lo + 1);
			cover.assign(rows_n * (size_t)pages, std::array<uint64_t, 4>{0, 0, 0, 0});
			banded.assign(rows_n, 0);
			for (const Item &it : items) {
				if (it.track < 0) continue;
				const size_t r = (size_t)((int)(it.key >> 48) - row_lo);
				auto &mask = cover[r * (size_t)pages + (size_t)((it.key >> 32) & 0xFF)];
				const int col = std::clamp((int)std::floor(it.gx / 64.f), 0, 255);
				for (int c = std::max(0, col - 1); c <= std::min(255, col + 1); ++c) mask[(size_t)c >> 6] |= 1ull << (c & 63);
			}
			for (size_t r = 0; r < rows_n; ++r) {
				std::array<uint64_t, 4> seen{0, 0, 0, 0};
				for (int p = 0; p < pages && !banded[r]; ++p) {
					const auto &mask = cover[r * (size_t)pages + (size_t)p];
					for (int w = 0; w < 4; ++w) {
						if (seen[w] & mask[w]) banded[r] = 1;
						seen[w] |= mask[w];
					}
				}
			}
			for (Item &it : items) {
				if (it.track < 0 || !banded[(size_t)((int)(it.key >> 48) - row_lo)]) continue;
				const float local = (float)((it.key >> 16) & 0xFFFF) / 1024.f;
				const uint64_t band = std::min<uint64_t>((uint64_t)(local / band_px), (uint64_t)bands - 1);
				it.key |= band << 40;
			}
		}
	}
	std::sort(items.begin(), items.end(), [](const Item &a, const Item &b) { return a.key != b.key ? a.key < b.key : a.i < b.i; });
	spans.clear();
	bounds.clear();
	out.clear();
	render_grounds.clear();
	// Sorted order is (row, part, band, page, y). Consecutive runs of the same page inside a row are merged
	// (band order is ground-y order, so the merged run stays sorted): bands only cost extra groups where
	// two pages really interleave, or where an actor splits the row.
	// Output group id: row 16 | run number of this page inside the row 8 | page 8 (actor: page 255), so a
	// row with a single page keeps one stable group (node) however its soldiers move between bands.
	static thread_local std::vector<uint8_t> page_runs;
	static thread_local std::vector<int> touched;
	page_runs.assign(256, 0);
	touched.clear();
	size_t a = 0;
	int drawn = 0, current_row = -1;
	while (a < items.size()) {
		const int row = (int)(items[a].key >> 48);
		if (row != current_row) {
			for (int p : touched) page_runs[(size_t)p] = 0;
			touched.clear();
			current_row = row;
		}
		if (items[a].track < 0) { // host actor: a marker in the draw order, nothing packed
			const Item &it = items[a];
			const uint32_t group = ((uint32_t)row << 16) | ((uint32_t)(it.i & 0xFF) << 8) | 0xFFu;
			spans.insert(spans.end(), {row, -1, it.i, 1, 0, (int32_t)group});
			bounds.insert(bounds.end(), {it.x, it.y, it.x, it.y});
			++a;
			continue;
		}
		const int page = (int)((items[a].key >> 32) & 0xFF);
		size_t b = a;
		while (b < items.size() && items[b].track >= 0 && (int)(items[b].key >> 48) == row && (int)((items[b].key >> 32) & 0xFF) == page) ++b;
		if (page_runs[(size_t)page] == 0) touched.push_back(page);
		const uint32_t run = std::min<uint32_t>(page_runs[(size_t)page], 254);
		page_runs[(size_t)page] = (uint8_t)std::min<uint32_t>(run + 1, 255);
		const uint32_t group = ((uint32_t)row << 16) | (run << 8) | (uint32_t)(page & 0xFF);
		const int count = (int)(b - a);
		int cap = 8;
		while (cap < count) cap <<= 1;
		const int start = (int)(out.size() / 12);
		out.resize(out.size() + (size_t)cap * 12, 0.f);
		render_grounds.resize(render_grounds.size() + (size_t)cap * 2, 0.f);
		float minx = 1e30f, miny = 1e30f, maxx = -1e30f, maxy = -1e30f;
		const RenderKit &K0 = render_kits[kit[items[a].i]];
		for (size_t q = a; q < b; ++q) {
			const Item &it = items[q];
			const RenderKit &K = render_kits[kit[it.i]];
			const size_t slot = (size_t)start + (q - a);
			float *o = &out[slot * 12];
			o[0] = K.scale; o[3] = it.x; o[5] = K.scale; o[7] = it.y;
			o[8] = (float)render_tracks[it.track].sequence;
			o[9] = (float)it.frame;
			o[10] = (float)K.palette;
			o[11] = fire_visual.size()==size_t(n) ? float(fire_visual[it.i]) : 0.f;
			render_grounds[slot * 2] = it.gx;
			render_grounds[slot * 2 + 1] = it.gy;
			minx = std::min(minx, it.x); maxx = std::max(maxx, it.x);
			miny = std::min(miny, it.y); maxy = std::max(maxy, it.y);
		}
		spans.insert(spans.end(), {row, K0.page, start, count, cap, (int32_t)group});
		bounds.insert(bounds.end(), {minx, miny, maxx, maxy});
		drawn += count;
		a = b;
	}
	return drawn;
}

} // namespace wg
