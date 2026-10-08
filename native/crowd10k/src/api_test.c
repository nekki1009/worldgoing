/* C-only smoke test of the v2 ABI: flat 64x64 map with a wall gap, two formations, a fight. */
#include "crowd_c_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
	enum { W = 64, H = 64 };
	static uint8_t height[W * H], flags[W * H], ramps[W * H], blocked[W * H];
	memset(flags, 1, sizeof flags);
	for (int y = 10; y < 54; ++y) blocked[y * W + 40] = 1; /* a wall with a gap */
	blocked[30 * W + 40] = blocked[31 * W + 40] = 0;
	wg_crowd *c = wg_crowd_create(2, 581);
	wg_crowd_set_terrain(c, W, H, height, flags, ramps, blocked, NULL);
	int a = wg_crowd_add_formation(c, 0, 20.f, 32.f, 0.f, 10, 1.f, 0, 40.0);
	int b = wg_crowd_add_formation(c, 1, 50.f, 32.f, 3.14159f, 10, 1.f, 0, 0.0);
	for (int i = 0; i < 100; ++i) wg_crowd_add_soldier(c, a, 1000 + i, 1 /*longsword*/, 4 /*steel*/, 3 /*iron armor*/, 1, i == 0 ? 1 : (i <= 2 ? 2 : 0), 0);
	for (int i = 0; i < 100; ++i) wg_crowd_add_soldier(c, b, 2000 + i, 2 /*spear*/, 1 /*wood*/, 1 /*cloth*/, 0, i == 0 ? 1 : (i <= 2 ? 2 : 0), 0);
	wg_crowd_finalize(c);
	float *buf = malloc(sizeof(float) * 12 * 200);
	int deaths = 0;
	int64_t ids[256];
	for (int s = 0; s < 30 * 120; ++s) {
		if (!wg_crowd_step(c, 1.f / 30.f) || !wg_crowd_validate(c)) { fprintf(stderr,"invalid C API step\n"); return 2; }
		{ int kinds[256]; int m = wg_crowd_drain_events(c, kinds, ids, NULL, NULL, NULL, 256); for (int k = 0; k < m; ++k) deaths += kinds[k] == 0; }
	}
	int visible = wg_crowd_pack_render(c, buf, 200, 64.f);
	int bad = 0, down = 0;
	for (int i = 0; i < wg_crowd_soldier_count(c); ++i) {
		float x, y; double hp, stun, ko; int captive, st, tg;
		wg_crowd_get_soldier(c, i, &x, &y, &hp, &stun, &ko, &captive, &st, &tg);
		if (hp > 0 && (int)x == 40 && blocked[(int)y * W + 40]) ++bad;
		if (hp > 0 && ko > 0) ++down;
	}
	/* one decision owner: b is AI-owned (default) and refuses host orders; a is handed to the host */
	int refused = wg_crowd_order_hold(c, b) == WG_NOT_OWNER;
	wg_crowd_set_order_owner(c, a, 0);
	int accepted = wg_crowd_order_hold(c, a) == WG_OK;
	/* SiteStore boundary round trip */
	wg_soldier_state st0; wg_crowd_get_soldier_state(c, 5, &st0);
	wg_crowd_set_soldier_state(c, 5, &st0);
	wg_soldier_state st1; wg_crowd_get_soldier_state(c, 5, &st1);
	int state_ok = st0.hp == st1.hp && st0.ko == st1.ko && st0.stun == st1.stun;
	/* save, continue 10 s, load into a new instance, continue 10 s: same hash */
	int64_t size = wg_crowd_save(c, NULL, 0);
	uint8_t *blob = malloc((size_t)size);
	wg_crowd_save(c, blob, size);
	for (int s = 0; s < 300; ++s) if (!wg_crowd_step(c, 1.f / 30.f) || !wg_crowd_validate(c)) { fprintf(stderr,"invalid C API step\n"); return 2; }
	wg_crowd *r = wg_crowd_create(1, 0);
	int loaded = wg_crowd_load(r, blob, size);
	for (int s = 0; s < 300; ++s) if (!wg_crowd_step(r, 1.f / 30.f) || !wg_crowd_validate(r)) { fprintf(stderr,"invalid restored C API step\n"); return 2; }
	int same = loaded && wg_crowd_state_hash(r) == wg_crowd_state_hash(c);
	printf("owner refused=%d accepted=%d state_ok=%d save=%lld bytes load=%d same_after_load=%d\n", refused, accepted, state_ok, (long long)size, loaded, same);
	wg_crowd_destroy(r);
	free(blob);
	double morale_b; int routed_b, cmd_b, order_b;
	wg_crowd_get_formation(c, b, &morale_b, NULL, &routed_b, &cmd_b, &order_b);
	printf("deaths=%d down=%d visible=%d inside_wall=%d morale_b=%.1f routed_b=%d hash=%016llx\n", deaths, down, visible, bad,
	       morale_b, routed_b, (unsigned long long)wg_crowd_state_hash(c));
	free(buf);
	wg_crowd_destroy(c);
	return (bad == 0 && down + deaths > 0 && visible == 200 - deaths && refused && accepted && state_ok && same) ? 0 : 1;
}
