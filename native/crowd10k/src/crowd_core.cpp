// Movement core: terrain edges, flow fields, formations, soldiers, hash, render packing.
#include "crowd_core.hpp"
#include <queue>
#include <cassert>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>

namespace wg {

using Clock = std::chrono::steady_clock;
static inline double ms_since(Clock::time_point t) {
	return std::chrono::duration<double, std::milli>(Clock::now() - t).count();
}
static inline int opp(int d) { return d < 4 ? (d + 2) % 4 : 4 + ((d - 4 + 2) % 4); }
// G4 quarter facings: 0 = +x, 1 = +y, 2 = -x, 3 = -y (radians 0, pi/2, pi, -pi/2).
static inline int quarter_of(float angle) {
	const float q = std::round(std::remainder(angle, 2.f * kPi) / (0.5f * kPi));
	return (((int)q) % 4 + 4) % 4;
}
static inline float quarter_angle(int q) { return q == 0 ? 0.f : q == 1 ? 0.5f * kPi : q == 2 ? kPi : -0.5f * kPi; }
static const int QX[4] = {1, 0, -1, 0}, QY[4] = {0, 1, 0, -1};
// integer offset (x forward, y lateral) rotated by quarter q; same convention as convoy_slot
static inline void quarter_rotate(int q, int x, int y, int &ox, int &oy) { ox = x * QX[q] - y * QY[q]; oy = x * QY[q] + y * QX[q]; }
static inline int floor_div(int a, int b) { return (a >= 0) ? a / b : -((-a + b - 1) / b); }

// ================================================================ terrain
void Terrain::allocate(int W, int H) {
	w = W; h = H;
	size_t n = (size_t)W * H;
	height.assign(n, 0); flags.assign(n, WALKABLE); ramp_edges.assign(n, 0);
	base_height.clear(); // Native-only callers without buildings retain their flat presentation.
	static_blocked.assign(n, 0); facility.assign(n, 0); edge_ok.assign(n, 0);
}

bool Terrain::walkable(int x, int y) const {
	int i = idx(x, y);
	return (flags[i] & WALKABLE) && static_blocked[i] == 0;
}

bool Terrain::can_step4(int x, int y, int d) const {
	int bx = x + DX[d], by = y + DY[d];
	if (!contains(x, y) || !contains(bx, by) || !walkable(x, y) || !walkable(bx, by)) return false;
	int a = idx(x, y), b = idx(bx, by);
	if ((ramp_edges[a] & (1 << (d + 4))) || (ramp_edges[b] & (1 << (((d + 2) % 4) + 4)))) return false;
	int diff = std::abs((int)height[a] - (int)height[b]);
	if (diff == 0) return true;
	return diff == 1 && (ramp_edges[a] & (1 << d)) && (ramp_edges[b] & (1 << ((d + 2) % 4)));
}

bool Terrain::attack_across(int ax, int ay, int bx, int by) const {
	for (int d = 0; d < 4; ++d)
		if (ax + DX[d] == bx && ay + DY[d] == by) return contains(ax, ay) && edge(ax, ay, d);
	return false;
}

float Terrain::visual_lift(float x, float y) const {
	if (base_height.empty()) return 0.f;
	const int cx = (int)std::floor(x), cy = (int)std::floor(y);
	if (!contains(cx, cy)) return 0.f;
	const int at = idx(cx, cy);
	const float here = 48.f * (int(height[at]) - int(base_height[at]));
	float result = here;
	const float rx = x - cx - .5f, ry = y - cy - .5f;
	for (int d : {rx < 0 ? W : E, ry < 0 ? N : S}) {
		if (!can_step4(cx, cy, d)) continue;
		const int next = idx(cx + DX[d], cy + DY[d]);
		const float weight = d == W || d == E ? std::fabs(rx) : std::fabs(ry);
		result += (48.f * (int(height[next]) - int(base_height[next])) - here) * weight;
	}
	return result;
}

double Terrain::shot_height(int source, int goal, int sample, double source_eye, double goal_eye) const {
	if (source_eye < 0) source_eye = height[source] + 1.;
	if (goal_eye < 0) goal_eye = height[goal] + 1.;
	const double dx = goal % w - source % w, dy = goal / w - source / w;
	const double length2 = dx * dx + dy * dy;
	const double along = length2 > 0 ? std::clamp(((sample % w - source % w) * dx + (sample / w - source / w) * dy) / length2, 0., 1.) : 0.;
	return source_eye + (goal_eye - source_eye) * along;
}

bool Terrain::shot_cell_clear(int source, int goal, int sample, double source_eye, double goal_eye) const {
	const int count = w * h;
	if (source < 0 || source >= count || goal < 0 || goal >= count || sample < 0 || sample >= count) return false;
	if (sample == source) return true;
	const double solid_top = double(height[sample]) + (static_blocked[sample] ? 2. : 0.);
	return solid_top < shot_height(source, goal, sample, source_eye, goal_eye) - 1e-6;
}

void Terrain::build_edges() {
	for (int y = 0; y < h; ++y)
		for (int x = 0; x < w; ++x) {
			uint8_t m = 0;
			for (int d = 0; d < 4; ++d)
				if (can_step4(x, y, d)) m |= (uint8_t)(1 << d);
			edge_ok[idx(x, y)] = m;
		}
	for (int y = 0; y < h; ++y)
		for (int x = 0; x < w; ++x) {
			uint8_t m = edge_ok[idx(x, y)];
			for (int d = 4; d < 8; ++d) {
				int dx = DX[d], dy = DY[d];
				int hx = dx > 0 ? E : W, vy = dy > 0 ? S : N;
				bool p1 = (m >> hx & 1) && contains(x + dx, y) && (edge_ok[idx(x + dx, y)] >> vy & 1);
				bool p2 = (m >> vy & 1) && contains(x, y + dy) && (edge_ok[idx(x, y + dy)] >> hx & 1);
				if (p1 && p2) m |= (uint8_t)(1 << d);
			}
			edge_ok[idx(x, y)] = m;
		}
}

// ================================================================ pool
Pool::Pool(int threads) {
	for (int i = 1; i < std::max(1, threads); ++i) workers_.emplace_back(&Pool::worker, this);
}
Pool::~Pool() {
	{ std::lock_guard<std::mutex> l(m_); stop_ = true; }
	cv_.notify_all();
	for (auto &t : workers_) t.join();
}
void Pool::run(int tasks, const std::function<void(int)> &fn) {
	if (workers_.empty() || tasks <= 1) {
		for (int t = 0; t < tasks; ++t) fn(t);
		return;
	}
	{
		std::lock_guard<std::mutex> l(m_);
		fn_ = &fn; tasks_ = tasks; next_.store(0); pending_ = (int)workers_.size(); ++gen_;
	}
	cv_.notify_all();
	for (;;) {
		int t = next_.fetch_add(1);
		if (t >= tasks) break;
		fn(t);
	}
	std::unique_lock<std::mutex> l(m_);
	done_cv_.wait(l, [&] { return pending_ == 0; });
}
void Pool::worker() {
	uint64_t seen = 0;
	for (;;) {
		const std::function<void(int)> *fn;
		int tasks;
		{
			std::unique_lock<std::mutex> l(m_);
			cv_.wait(l, [&] { return stop_ || gen_ != seen; });
			if (stop_) return;
			seen = gen_; fn = fn_; tasks = tasks_;
		}
		for (;;) {
			int t = next_.fetch_add(1);
			if (t >= tasks) break;
			(*fn)(t);
		}
		std::lock_guard<std::mutex> l(m_);
		if (--pending_ == 0) done_cv_.notify_one();
	}
}

void PhaseTimes::add(const PhaseTimes &o) {
	bleed += o.bleed; hash += o.hash; command += o.command; ai += o.ai; formation += o.formation; fields += o.fields; contact += o.contact;
	soldier += o.soldier; timers += o.timers; exchange += o.exchange; ranged += o.ranged; actions += o.actions;
	fatigue += o.fatigue; compact += o.compact; present += o.present; total += o.total; steps += o.steps;
}

// ================================================================ world setup
World::World(int threads) : pool_(threads) {}

bool World::set_contact_revision(int index, int64_t value) {
	if (index < 0 || index >= soldier_count() || value < 0) return false;
	contact_revision[(size_t)index] = value;
	return true;
}


bool World::set_siege_crew(int i, bool assigned) {
	if (i < 0 || i >= soldier_count()) return false;
	if (siege_crew.size() != px.size()) siege_crew.assign(px.size(), 0);
	if (siege_member_group.size() != px.size()) siege_member_group.assign(px.size(), -1);
	if (!assigned && (siege_group(i) >= 0 || (escort_mode[i] >= 5 && escort_goal[i] >= 0))) return false;
	if (assigned && (!can_act(i) || (escort_mode[i] != 0 && escort_mode[i] != 5) || rescue_of[i] >= 0 || capture_of[i] >= 0 || prison_id[i] != 0 || is_convoy_crew(i))) return false;
	siege_crew[i] = assigned ? 1 : 0;
	if (!assigned && escort_mode[i] == 5 && escort_goal[i] < 0) escort_mode[i] = 0;
	return true;
}

const World::SiegeCompound *World::siege_compound_state(int64_t token) const {
	for (const auto &g : siege_compounds) if (g.token == token) return &g;
	return nullptr;
}

bool World::siege_claims_cell(int c, int ignore) const {
	for (size_t k = 0; k < siege_compounds.size(); ++k) {
		if (siege_group(ignore) == (int)k) continue;
		const auto &g = siege_compounds[k];
		if (std::find(g.claims.begin(), g.claims.end(), c) != g.claims.end()) return true;
	}
	return false;
}

int64_t World::begin_siege_compound(const std::vector<SiegeMember> &members,
	const std::vector<int> &source_body, const std::vector<int> &target_body,
	const std::vector<int> &sweep, double duration) {
	const int count = soldier_count(), cells = terrain.w * terrain.h;
	if (members.empty() || members.size() > 16 || source_body.empty() || source_body.size() > 64 || source_body.size() != target_body.size() || sweep.empty() || sweep.size() > 256 || !std::isfinite(duration) || duration <= 0 || duration > 3600 || siege_serial == INT64_MAX) return 0;
	std::vector<uint8_t> participants(count, 0), claims(cells, 0), destinations(cells, 0), swept(cells, 0), body_phase(cells, 0);
	SiegeCompound g;
	g.members = members; g.duration = duration;
	for (int c : sweep) { if (c < 0 || c >= cells || swept[c]) return 0; swept[c] = 1; }
	int minx = terrain.w, miny = terrain.h, maxx = -1, maxy = -1;
	uint8_t phase = 1;
	for (const auto *body : {&source_body, &target_body}) {
		std::vector<uint8_t> unique(cells, 0);
		for (int c : *body) {
			if (c < 0 || c >= cells || unique[c] || !swept[c]) return 0;
			unique[c] = 1; body_phase[c] |= phase;
			minx = std::min(minx,c%terrain.w); miny = std::min(miny,c/terrain.w); maxx = std::max(maxx,c%terrain.w); maxy = std::max(maxy,c/terrain.w);
		}
		phase = 2;
	}
	// The original rotation caller holds every crew stationary outside its sweep.
	// Moving crew are legal only for one rigid cardinal translation of the body.
	const bool translating = std::any_of(members.begin(), members.end(), [](const SiegeMember &m) { return m.from != m.to; });
	int body_dx = 0, body_dy = 0;
	if (translating) {
		const int source_min = *std::min_element(source_body.begin(), source_body.end());
		const int target_min = *std::min_element(target_body.begin(), target_body.end());
		body_dx = target_min % terrain.w - source_min % terrain.w;
		body_dy = target_min / terrain.w - source_min / terrain.w;
		if (std::abs(body_dx) + std::abs(body_dy) != 1) return 0;
		for (int c : source_body) {
			const int x = c % terrain.w + body_dx, y = c / terrain.w + body_dy;
			if (!terrain.contains(x,y) || !(body_phase[terrain.idx(x,y)] & 2)) return 0;
		}
	}
	// Sweeps must conservatively include the complete body bounding rectangle.
	for (int y=miny;y<=maxy;++y) for (int x=minx;x<=maxx;++x) if (!swept[terrain.idx(x,y)]) return 0;
	for (int c : sweep) {
		if (!terrain.walkable(c%terrain.w,c/terrain.w) || terrain.height[c] != terrain.height[source_body[0]]) return 0;
		claims[c] = 1;
	}
	for (const auto &m : members) {
		const int i=m.soldier;
		if (i<0 || i>=count || participants[i] || person_id[i]!=m.person || !is_siege_crew(i) || !can_act(i) || siege_group(i)>=0 || m.from<0 || m.from>=cells || m.to<0 || m.to>=cells || destinations[m.to]) return 0;
		const Formation &f=formations[form[i]];
		if (f.garrisoned || f.routed || f.order==Order::RETREAT || prison_id[i]!=0 || stagger[i]>0 || knock_t[i]>0 || rescue_of[i]>=0 || capture_of[i]>=0 || escort_goal[i]>=0 || (escort_mode[i]!=0 && escort_mode[i]!=5)) return 0;
		const int x=m.from%terrain.w,y=m.from/terrain.w,gx=m.to%terrain.w,gy=m.to/terrain.w,dx=gx-x,dy=gy-y;
		if (std::abs(px[i]-(x+.5f))>1e-5f || std::abs(py[i]-(y+.5f))>1e-5f || vx[i]*vx[i]+vy[i]*vy[i]>1e-6f || std::abs(dx)+std::abs(dy)>1 || !terrain.walkable(gx,gy)) return 0;
		if ((dx||dy) && !terrain.edge(x,y,dx>0?E:dx<0?W:dy>0?S:N)) return 0;
		if (translating) {
			if (dx != body_dx || dy != body_dy || (body_phase[m.from] & 1) || (body_phase[m.to] & 2)) return 0;
			// Same-progress interpolation keeps the crew outside the same body. Only
			// vacated source/future target cells may cross the opposite endpoint;
			// unrelated historical sweep cells remain blocked and every claim stays.
			if ((swept[m.from] && !(body_phase[m.from] & 2)) || (swept[m.to] && !(body_phase[m.to] & 1))) return 0;
		} else if (swept[m.to] || swept[m.from]) return 0;
		participants[i]=1; destinations[m.to]=1; claims[m.from]=claims[m.to]=1;
	}
	for (int c=0;c<cells;++c) if (claims[c]) {
		if (siege_claims_cell(c)) return 0;
		g.claims.push_back(c); g.heights.push_back(terrain.height[c]);
	}
	// Include every original body (KO and dead included), plus committed goals.
	for (int i=0;i<count;++i) if (!participants[i]) {
		const int here=terrain.idx((int)std::floor(px[i]),(int)std::floor(py[i]));
		if (claims[here] || (escort_goal[i]>=0 && claims[escort_goal[i]])) return 0;
	}
	if (siege_member_group.size()!=px.size()) siege_member_group.assign(px.size(),-1);
	g.token=++siege_serial;
	const int group=(int)siege_compounds.size();
	siege_compounds.push_back(std::move(g));
	for (const auto &m:members) { siege_member_group[m.soldier]=group; escort_mode[m.soldier]=5; escort_goal[m.soldier]=m.to; target[m.soldier]=enc_target[m.soldier]=-1; }
	return siege_serial;
}

bool World::cancel_siege_compound(int64_t token) {
	for (auto &g:siege_compounds) if (g.token==token) {
		g.cancelled=true;
		for (const auto &m:g.members) escort_mode[m.soldier]=6;
		return true;
	}
	return false;
}

bool World::settle_siege_compound(int64_t token) {
	for (size_t at=0;at<siege_compounds.size();++at) if (siege_compounds[at].token==token) {
		if (!siege_compounds[at].complete) return false;
		for (const auto &m:siege_compounds[at].members) { siege_member_group[m.soldier]=-1; escort_goal[m.soldier]=-1; escort_mode[m.soldier]=0; }
		siege_compounds.erase(siege_compounds.begin()+at);
		for (auto &index:siege_member_group) if (index>(int)at) --index;
		return true;
	}
	return false;
}

bool World::siege_compound_valid(const SiegeCompound &g,const Terrain &ground) const {
	for (size_t k=0;k<g.claims.size();++k) { const int c=g.claims[k]; if (!ground.walkable(c%ground.w,c/ground.w) || ground.height[c]!=g.heights[k]) return false; }
	for (const auto &m:g.members) {
		const int x=m.from%ground.w,y=m.from/ground.w,dx=m.to%ground.w-x,dy=m.to/ground.w-y;
		if ((dx||dy) && !ground.edge(x,y,dx>0?E:dx<0?W:dy>0?S:N)) return false;
	}
	return true;
}

void World::abort_siege_compound(int index) {
	auto &g=siege_compounds[index]; g.cancelled=g.complete=g.aborted=true; g.elapsed=0;
	for (const auto &m:g.members) {
		const int i=m.soldier;
		px[i]=nx[i]=float(m.from%terrain.w)+.5f; py[i]=ny[i]=float(m.from/terrain.w)+.5f; cell[i]=m.from; vx[i]=vy[i]=0; knock_t[i]=0;
		escort_goal[i]=-1; escort_mode[i]=6;
	}
}

void World::advance_siege_compounds(float dt) {
	for (auto &g:siege_compounds) if (!g.complete) {
		for (const auto &m:g.members) if (!can_act(m.soldier) || escort_mode[m.soldier]==6 || stagger[m.soldier]>0 || knock_t[m.soldier]>0) g.cancelled=true;
		g.elapsed=std::min(g.duration,g.elapsed+(double)dt);
		if (g.elapsed+1e-7>=g.duration) { g.elapsed=g.duration; g.complete=true; }
	}
}

bool World::move_siege_member(int i,float dt) {
	const int at=siege_group(i); if (at<0) return false;
	const auto &g=siege_compounds[at];
	for (const auto &m:g.members) if (m.soldier==i) {
		const float p=g.aborted?0.f:(float)(g.elapsed/g.duration);
		nx[i]=float(m.from%terrain.w)+.5f+float(m.to%terrain.w-m.from%terrain.w)*p;
		ny[i]=float(m.from/terrain.w)+.5f+float(m.to/terrain.w-m.from/terrain.w)*p;
		vx[i]=(nx[i]-px[i])/dt; vy[i]=(ny[i]-py[i])/dt;
		if (vx[i]*vx[i]+vy[i]*vy[i]>1e-6f) face[i]=std::atan2(vy[i],vx[i]);
		state[i]=!alive(i)?S_DEAD:ko[i]>0?S_DOWN:getup[i]>0?S_GETUP:stagger[i]>0?S_STAGGER:S_SLOT;
		running[i]=0; anim_t[i]+=dt;
		if(g.complete)cell[i]=g.aborted?m.from:m.to;
		return true;
	}
	return false;
}

bool World::set_siege_navigation(const std::vector<int> &blocked,const std::vector<int64_t> &exits) {
	return install_siege_navigation(blocked,exits,true);
}

bool World::install_siege_navigation(const std::vector<int> &blocked,const std::vector<int64_t> &exits,bool invalidate_fields) {
	const int cells=terrain.w*terrain.h,n=soldier_count();
	if (blocked.size()>(size_t)cells || exits.size()%3 || exits.size()>(size_t)n*64*3) return false;
	std::vector<uint8_t> mask(cells,0);
	std::vector<std::vector<int>> allowed(n);
	for (int c:blocked) { if (c<0 || c>=cells || mask[c]) return false; mask[c]=1; }
	for (size_t k=0;k<exits.size();k+=3) {
		const int64_t i=exits[k],id=exits[k+1],c=exits[k+2];
		if (i<0 || i>=n || person_id[(size_t)i]!=id || c<0 || c>=cells || !mask[(size_t)c]) return false;
		auto &entry=allowed[(size_t)i];
		if (entry.size()>=64 || std::find(entry.begin(),entry.end(),(int)c)!=entry.end()) return false;
		entry.push_back((int)c);
	}
	for (int i=0;i<n;++i) if (!allowed[i].empty()) {
		const int here=terrain.idx((int)px[i],(int)py[i]);
		if (std::find(allowed[i].begin(),allowed[i].end(),here)==allowed[i].end()) return false;
		std::vector<int> seen{here};
		for(size_t k=0;k<seen.size();++k)for(int d=0;d<4;++d) {
			const int x=seen[k]%terrain.w+DX[d],y=seen[k]/terrain.w+DY[d];
			if(!terrain.contains(x,y))continue;const int c=terrain.idx(x,y);
			if(std::find(allowed[i].begin(),allowed[i].end(),c)!=allowed[i].end() && std::find(seen.begin(),seen.end(),c)==seen.end())seen.push_back(c);
		}
		if(seen.size()!=allowed[i].size())return false;
	}
	const bool changed=mask!=siege_person_blocked;
	siege_person_blocked=std::move(mask);siege_wreck_exit=std::move(allowed);
	if(changed && invalidate_fields)convoy_invalidate_plans(); // live change only (load restores the saved plans as they were)
	if(changed && invalidate_fields) {
		fields_.clear();field_queue_.clear();
		for(auto &f:formations){f.field=-1;f.los_goal=false;}
		for(auto &f:formations)if(!f.arrived && f.order!=Order::HOLD)f.field=request_field(nearest_walkable(terrain.idx(int(f.goal_x),int(f.goal_y))));
		std::fill(los_ok.begin(),los_ok.end(),0);
	}
	return true;
}

bool World::siege_person_cell(int i,int from,int to) const {
	// G4 claims: nobody but the claiming convoy's crew enters a cell a convoy claimed this stage; a person already
	// inside a claimed cell may leave (and move) freely.
	if(!convoy_claim_owner.empty() && to>=0 && to<(int)convoy_claim_owner.size() && convoy_claim_owner[to]!=0 &&
	   !(i>=0 && i<(int)convoy_of.size() && convoy_claim_owner[to]==convoy_of[i]) &&
	   !(from>=0 && from<(int)convoy_claim_owner.size() && convoy_claim_owner[from]!=0))return false;
	if(siege_route_cell(to))return true;
	// A convoy's crew stand and step on their own convoy's body (G4 S2); other bodies stay blocking.
	if(is_convoy_crew(i) && convoy_body_cell(to) && convoy_body_owner[to]==convoy_of[i] && siege_nav_cell(to))return true;
	if(i<0 || i>=(int)siege_wreck_exit.size())return false;
	const auto &allowed=siege_wreck_exit[i];
	return std::find(allowed.begin(),allowed.end(),from)!=allowed.end() && std::find(allowed.begin(),allowed.end(),to)!=allowed.end();
}

void World::resolve_siege_person(int i,float ox,float oy,float &x,float &y) const {
	if(siege_person_blocked.empty() && convoy_body_owner.empty())return;
	int cx=(int)std::floor(ox),cy=(int)std::floor(oy);const int source=terrain.idx(cx,cy);
	int nx=(int)std::floor(x),ny=(int)std::floor(y);
	if(nx!=cx){if(!terrain.contains(nx,cy) || !siege_person_cell(i,source,terrain.idx(nx,cy)))x=ox;else cx=nx;}
	if(ny!=cy){if(!terrain.contains(cx,ny) || !siege_person_cell(i,source,terrain.idx(cx,ny)))y=oy;else cy=ny;}
	for(int d=0;d<4;++d) {
		const int tx=cx+DX[d],ty=cy+DY[d];
		if(!terrain.contains(tx,ty) || siege_person_cell(i,source,terrain.idx(tx,ty)))continue;
		if(d==E)x=std::min(x,cx+1.f-cfg.wall_margin);if(d==W)x=std::max(x,cx+cfg.wall_margin);
		if(d==S)y=std::min(y,cy+1.f-cfg.wall_margin);if(d==N)y=std::max(y,cy+cfg.wall_margin);
	}
}


bool World::update_terrain(Terrain ground) {
	const size_t n = size_t(ground.w) * ground.h;
	if (ground.w <= 0 || ground.h <= 0 || ground.w > 1024 || ground.h > 1024) return false;
	for (const auto *v : {&ground.height, &ground.flags, &ground.ramp_edges, &ground.static_blocked, &ground.facility, &ground.base_height}) if (v->size() != n) return false;
	for (uint8_t value : ground.static_blocked) if (value > 1) return false;
	for (uint8_t value : ground.facility) if (value > 1) return false;
	if (!formations.empty() && (ground.w != terrain.w || ground.h != terrain.h)) return false;
	ground.build_edges();
	std::vector<uint8_t> abort(siege_compounds.size(),0);
	for (size_t k=0;k<siege_compounds.size();++k) if (!siege_compounds[k].complete && !siege_compound_valid(siege_compounds[k],ground)) abort[k]=1;
	std::vector<uint8_t> abort_single(soldier_count(),0);
	for(int i=0;i<soldier_count();++i) if(siege_group(i)<0 && i<(int)siege_step_source.size() && siege_step_source[i]>=0 && escort_goal[i]>=0) {
		const int from=siege_step_source[i],to=escort_goal[i],x=from%terrain.w,y=from/terrain.w,dx=to%terrain.w-x,dy=to/terrain.w-y;
		abort_single[i]=ground.height[from]!=terrain.height[from] || !ground.walkable(to%terrain.w,to/terrain.w) || ((dx||dy) && !ground.edge(x,y,dx>0?E:dx<0?W:dy>0?S:N));
	}
	for (int i = 0; i < soldier_count(); ++i) {
		int source=terrain.idx(int(px[i]),int(py[i]));
		const int group=siege_group(i);
		if (group>=0 && abort[group]) for (const auto &m:siege_compounds[group].members) if (m.soldier==i) source=m.from;
		if(abort_single[i])source=siege_step_source[i];
		const int x=source%terrain.w,y=source/terrain.w;
		if (!ground.contains(x, y) || !ground.walkable(x, y)) return false;
		if (ground.height[ground.idx(x, y)] > terrain.height[source]) return false;
	}
	// A convoy anchor must stay on walkable ground; a terrain change that strands one is refused before any commitment is cancelled.
	for (const auto &cv : convoys) if (!ground.contains((int)cv.x, (int)cv.y) || !ground.walkable((int)cv.x, (int)cv.y)) return false;
	// A convoy body must stay on walkable ground of the same grid (its cells are indices into it).
	for (const auto &cv : convoys) for (int v : cv.body_cells) if (ground.w != terrain.w || ground.h != terrain.h || !ground.walkable(v % ground.w, v / ground.w)) return false;
	// Validate the entire new terrain before cancelling any original commitment.
	for (size_t k=0;k<abort.size();++k) if (abort[k]) abort_siege_compound((int)k);
	for(int i=0;i<soldier_count();++i)if(abort_single[i]) {
		const int source=siege_step_source[i];px[i]=nx[i]=float(source%terrain.w)+.5f;py[i]=ny[i]=float(source/terrain.w)+.5f;cell[i]=source;vx[i]=vy[i]=0;knock_t[i]=0;escort_goal[i]=-1;escort_mode[i]=0;siege_step_source[i]=-1;
	}
	const auto old_heights = terrain.height;
	terrain = std::move(ground);
	convoy_invalidate_plans(); // routes and slots are recomputed on the new ground
	fields_.clear(); field_queue_.clear();
	for (auto &f : formations) { f.field = -1; f.los_goal = false; }
	for (auto &f : formations) if (!f.arrived && f.order != Order::HOLD) f.field = request_field(terrain.idx(int(f.goal_x), int(f.goal_y)));
	std::fill(los_ok.begin(), los_ok.end(), 0);
	std::fill(enc_target.begin(), enc_target.end(), -1);
	// A destroyed support drops the original body at the same XY. No actor is
	// recreated and no nearest-cell search moves people or their belongings.
	if (old_heights.size() == n) {
		std::vector<int> falling;
		for (int i = 0; i < soldier_count(); ++i) if (old_heights[cell[i]] > terrain.height[cell[i]]) falling.push_back(i);
		std::sort(falling.begin(), falling.end(), [&](int a, int b) { return person_id[a] < person_id[b]; });
		for (int i : falling) {
			const int drop = int(old_heights[cell[i]]) - int(terrain.height[cell[i]]);
			nx[i] = px[i]; ny[i] = py[i]; vx[i] = vy[i] = 0;
			knock_t[i] = 0;
			apply_contact(i, 15. * drop, 100.);
		}
	}
	return true;
}

std::vector<uint8_t> World::terrain_state() const {
	std::vector<uint8_t> result(8);
	const int32_t dimensions[] = {terrain.w, terrain.h};
	std::memcpy(result.data(), dimensions, 8);
	for (const auto *v : {&terrain.height, &terrain.flags, &terrain.ramp_edges, &terrain.static_blocked, &terrain.facility, &terrain.base_height}) result.insert(result.end(), v->begin(), v->end());
	return result;
}

std::vector<uint8_t> World::occupancy_mask(const std::vector<int64_t> &ignored) const {
	std::vector<uint8_t> result(size_t(terrain.w) * terrain.h, 0);
	const float radius = cfg.radius + cfg.wall_margin;
	for (int i = 0; i < soldier_count(); ++i) {
		if (is_aboard(i) || std::find(ignored.begin(), ignored.end(), person_id[i]) != ignored.end()) continue; // aboard: on a deck, not on the ground
		const float end_x = px[i] + vx[i] / 30.f, end_y = py[i] + vy[i] / 30.f;
		for (int y = std::max(0, int(std::floor(std::min(py[i], end_y) - radius))); y <= std::min(terrain.h - 1, int(std::floor(std::max(py[i], end_y) + radius))); ++y)
			for (int x = std::max(0, int(std::floor(std::min(px[i], end_x) - radius))); x <= std::min(terrain.w - 1, int(std::floor(std::max(px[i], end_x) + radius))); ++x) result[terrain.idx(x, y)] = 1;
		if (escort_mode[i] && escort_goal[i] >= 0) result[escort_goal[i]] = 1;
	}
	for (const auto &g:siege_compounds) {
		bool ignored_group=true;
		for (const auto &m:g.members) if (std::find(ignored.begin(),ignored.end(),m.person)==ignored.end()) { ignored_group=false; break; }
		if (!ignored_group) for (int c:g.claims) result[c]=1;
	}
	return result;
}

int World::add_formation(int t, float cx, float cy, float facing, int cols, float spacing, Troop tr, double training) {
	Formation f;
	f.team = t; f.cx = f.goal_x = f.origin_x = cx; f.cy = f.goal_y = f.origin_y = cy;
	f.facing = f.goal_facing = facing; f.cols = cols; f.spacing = spacing; f.troop = tr; f.training = training;
	f.rng = 0x9E3779B97F4A7C15ull ^ ((uint64_t)formations.size() * 0xBF58476D1CE4E5B9ull) ^ (uint64_t)cfg.seed;
	const size_t old = formations.size();
	formations.push_back(std::move(f));
	if (finalized_) {
		std::vector<uint8_t> touch((old + 1) * (old + 1), 0);
		for (size_t a = 0; a < old; ++a) for (size_t b = 0; b < old; ++b) touch[a * (old + 1) + b] = touch_[a * old + b];
		touch_.swap(touch); lag_acc_.resize(old + 1, 0); lag_cnt_.resize(old + 1, 0);
		build_faction_slots();
	}
	return (int)formations.size() - 1;
}

int World::add_soldier(int fi, const rules::Equip &e, Role r, int64_t person, uint16_t ammo_count) {
	int i = (int)px.size();
	Formation &f = formations[fi];
	f.members.push_back(i);
	auto push = [](auto &v, auto x) { v.push_back(x); };
	push(px, f.cx); push(py, f.cy); push(nx, f.cx); push(ny, f.cy); push(vx, 0.f); push(vy, 0.f); push(face, f.facing);
	push(anim_t, 0.f);
	for (auto *v : {&hp}) push(*v, 100.0);
	for (auto *v : {&stun, &grace, &ko, &getup, &stagger, &exch_cd, &ranged_cd, &skill_cd, &knock_t, &act_t, &escape_t}) push(*v, 0.0);
	push(knock_dx, 0.f); push(knock_dy, 0.f);
	push(rest_hold, (uint8_t)0); push(rest_x, 0.f); push(rest_y, 0.f); push(rest_best, 1e9f); push(rest_t, 0.f);
	push(team, (uint8_t)f.team); push(state, (uint8_t)S_SLOT); push(los_ok, (uint8_t)1); push(skill, (uint8_t)rules::SK_NONE);
	push(role, (uint8_t)r); push(captive, (uint8_t)0); push(present, (uint8_t)1); push(troop, (uint8_t)(e.family == rules::F_BOW ? T_BOW : e.family == rules::F_CROSSBOW ? T_CROSSBOW : T_MELEE));
	push(running, (uint8_t)0); push(near_enemy, (uint8_t)0); push(fire_blocked, (uint8_t)0); push(bandaged, (uint8_t)0);
	push(form, fi); push(slot, (int)f.members.size() - 1); push(target, -1); push(cell, -1); push(enc_target, -1);
	push(rescue_of, -1); push(capture_of, -1); push(captor, -1); push(life_ck, (uint8_t)0);
	push(prison_id, int64_t(0)); push(escort_goal, -1); push(escort_mode, (uint8_t)0); push(housing_attendance_cell, -1);
	push(contact_revision, int64_t(0));
	push(siege_crew, (uint8_t)0); push(siege_member_group, -1); push(siege_step_source,-1);
	push(convoy_of, (int32_t)0);
	push(start_x, NAN); push(start_y, NAN);
	push(host_ctl, (uint8_t)0); push(host_run, (uint8_t)0); push(host_engage, (uint8_t)0); push(host_vx, 0.f); push(host_vy, 0.f);
	push(vis_kind, (uint8_t)V_IDLE); push(vis_t0, -1e9); push(kit, (int16_t)-1);
	push(fire_visual, (uint8_t)0);
	push(ammo, ammo_count); push(equip, e); push(ability, CommandAbility{});
	// Standalone prototype callers keep their legacy qualification; formal D5
	// writes every original person's explicit role before finalizing the World.
	push(military_role, (uint8_t)1);
	push(post_holder, (uint8_t)1);
	push(released, (uint8_t)0);
	push(aboard, (uint8_t)0); push(aboard_vehicle, (int32_t)-1);
	push(absent, (uint8_t)0); push(absent_kind, (uint8_t)0); push(surrendered, (uint8_t)0);
	push(person_id, person >= 0 ? person : (int64_t)i);
	if (finalized_) {
		f.slot_count++; f.roster++; f.fatigue_count++;
		slot[i] = f.slot_count - 1;
		if (r == R_CAPTAIN && f.formal_cmd < 0) f.formal_cmd = i;
		if (r == R_OFFICER) f.officer_order.push_back(i);
		if (r != R_REGULAR) ensure_ability(i, f);
		rescued_by_.resize(i + 1, -1); capturing_by_.resize(i + 1, -1);
		attackers_.resize(i + 1, 0); slot_tx_.resize(i + 1, f.cx); slot_ty_.resize(i + 1, f.cy); slot_clip_.resize(i + 1, 1.f);
		rebuild_buffers(); build_faction_slots(); build_hash();
		const size_t ev = events.size(); settle_command(f, fi); events.resize(ev);
		f.commander_present = f.current_cmd >= 0 && command_eligible(f.current_cmd);
	}
	return i;
}

void World::slot_world(const Formation &f, int s, int n, float &x, float &y) const {
	n = std::max(1, n);
	int cols = std::max(1, std::min(f.cols, n));
	int rows = (n + cols - 1) / cols;
	int row = s / cols, col = s % cols;
	int in_row = (row == rows - 1) ? n - row * cols : cols;
	float lat = ((float)col - (float)(in_row - 1) * 0.5f) * f.spacing;
	float back = ((float)row - (float)(rows - 1) * 0.5f) * f.spacing;
	float fx = std::cos(f.facing), fy = std::sin(f.facing);
	float rx = -fy, ry = fx;
	x = f.cx + rx * lat - fx * back;
	y = f.cy + ry * lat - fy * back;
}

void World::finalize() {
	terrain.build_edges();
	int n = soldier_count();
	slot_tx_.assign(n, 0); slot_ty_.assign(n, 0); slot_clip_.assign(n, 1.f);
	auto snap = [&](float &x, float &y) {
		// slots of a formation deployed at the map edge (a trial entry side) can fall outside the map
		if (!std::isfinite(x) || !std::isfinite(y)) { x = 0.5f; y = 0.5f; }
		x = std::clamp(x, 0.05f, (float)terrain.w - 0.05f);
		y = std::clamp(y, 0.05f, (float)terrain.h - 0.05f);
		int cx = std::clamp((int)x, 0, terrain.w - 1), cy = std::clamp((int)y, 0, terrain.h - 1);
		if (terrain.walkable(cx, cy)) return;
		int c = nearest_walkable(terrain.idx(cx, cy));
		x = (float)(c % terrain.w) + 0.5f; y = (float)(c / terrain.w) + 0.5f;
	};
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		Formation &f = formations[fi];
		snap(f.cx, f.cy);
		f.goal_x = f.origin_x = f.cx; f.goal_y = f.origin_y = f.cy;
		int m = (int)f.members.size();
		f.slot_count = m;
		for (int k = 0; k < m; ++k) {
			int i = f.members[k];
			float x, y;
			slot_world(f, k, m, x, y);
			if ((size_t)i < start_x.size() && std::isfinite(start_x[i]) && std::isfinite(start_y[i])) { x = start_x[i]; y = start_y[i]; }
			snap(x, y);
			px[i] = nx[i] = x; py[i] = ny[i] = y;
			if (role[i] == R_CAPTAIN && f.formal_cmd < 0) f.formal_cmd = i;
			if (role[i] == R_OFFICER) f.officer_order.push_back(i);
			if (role[i] != R_REGULAR) ensure_ability(i, f); // captain / officers hold command abilities (D19)
		}
		f.fatigue_count = m;
		f.roster = m;
		f.command_dirty = true;
	}
	chunks_ = (n + cfg.chunk - 1) / cfg.chunk;
	pair_buf_.assign(chunks_, {});
	fire_buf_.assign(chunks_, {});
	illegal_buf_.assign((size_t)chunks_ * 3, 0);
	ex_acc_.assign(n, ExAcc{});
	rescued_by_.assign(n, -1); capturing_by_.assign(n, -1);
	attackers_.assign(n, 0);
	touch_.assign(formations.size() * formations.size(), 0);
	lag_acc_.assign(formations.size(), 0.0);
	lag_cnt_.assign(formations.size(), 0);
	bw_ = (terrain.w + 7) / 8; bh_ = (terrain.h + 7) / 8;
	build_faction_slots();
	build_hash();
	for (size_t fi = 0; fi < formations.size(); ++fi) settle_command(formations[fi], (int)fi);
	for (auto &f : formations) f.commander_present = f.current_cmd >= 0 && command_eligible(f.current_cmd);
	for (int i = 0; i < n; ++i) life_ck[i] = hp[i] <= 0.0 ? 2 : (ko[i] > 0.0 ? 1 : 0);
	events.clear();
	finalized_ = true;
}

int World::nearest_walkable(int goal) const {
	if (terrain.walkable(goal % terrain.w, goal / terrain.w) && siege_route_cell(goal)) return goal;
	std::vector<uint8_t> seen(terrain.edge_ok.size(), 0);
	std::vector<int> q{goal};
	seen[goal] = 1;
	for (size_t h = 0; h < q.size(); ++h) {
		int c = q[h], x = c % terrain.w, y = c / terrain.w;
		if (terrain.walkable(x, y) && siege_route_cell(c)) return c;
		for (int d = 0; d < 4; ++d) {
			int ax = x + DX[d], ay = y + DY[d];
			if (!terrain.contains(ax, ay)) continue;
			int a = terrain.idx(ax, ay);
			if (!seen[a]) { seen[a] = 1; q.push_back(a); }
		}
	}
	return goal;
}

int World::request_field(int goal_cell, bool body_aware) {
	if (body_aware) goal_cell = nearest_walkable(goal_cell);
	for (size_t k = 0; k < fields_.size(); ++k)
		if (fields_[k].goal == goal_cell && fields_[k].body_aware == body_aware) { fields_[k].last_used = tick; return (int)k; }
	int slot_index = -1;
	const size_t cap = 256;
	if (fields_.size() < cap) {
		fields_.emplace_back();
		slot_index = (int)fields_.size() - 1;
	} else {
		uint32_t oldest = UINT32_MAX;
		for (size_t k = 0; k < fields_.size(); ++k)
			if (fields_[k].last_used < oldest) { oldest = fields_[k].last_used; slot_index = (int)k; }
		for (auto &f : formations) if (f.field == slot_index) f.field = -1;
	}
	FlowField &f = fields_[slot_index];
	f.goal = goal_cell; f.body_aware = body_aware; f.last_used = tick; f.dir.clear(); f.cost.clear();
	field_queue_.push_back(slot_index);
	return slot_index;
}

void World::build_field(FlowField &f) {
	const int n = terrain.w * terrain.h;
	const uint32_t INF = std::numeric_limits<uint32_t>::max();
	f.cost.assign(n, INF);
	f.dir.assign(n, 255);
	std::vector<int> buckets[16];
	// body-aware fields treat convoy bodies as walls; convoy-anchor fields (body_aware false) ignore them
	const bool body_aware = f.body_aware;
	const auto open = [this, body_aware](int q) { return body_aware ? siege_route_cell(q) : siege_nav_cell(q); };
	f.cost[f.goal] = 0;
	buckets[0].push_back(f.goal);
	size_t remaining = 1;
	for (uint32_t cur = 0; remaining > 0; ++cur) {
		auto &b = buckets[cur & 15];
		for (size_t k = 0; k < b.size(); ++k) {
			int c = b[k];
			if (f.cost[c] != cur) continue;
			uint8_t m = terrain.edge_ok[c];
			for (int d = 0; d < 8; ++d) {
				if (!(m >> d & 1)) continue;
				int nb = c + DY[d] * terrain.w + DX[d];
				if (!open(nb) || (d>=4 && (!open(c+DX[d]) || !open(c+DY[d]*terrain.w)))) continue;
				uint32_t ncost = cur + (d < 4 ? 10u : 14u);
				if (ncost < f.cost[nb]) {
					f.cost[nb] = ncost;
					f.dir[nb] = (uint8_t)opp(d);
					buckets[ncost & 15].push_back(nb);
					++remaining;
				}
			}
		}
		remaining -= b.size();
		b.clear();
	}
	stats.fields_built++;
}

void World::set_goal(Formation &f, float gx, float gy) {
	gx = std::clamp(gx, 0.5f, (float)terrain.w - 0.5f);
	gy = std::clamp(gy, 0.5f, (float)terrain.h - 0.5f);
	int c = nearest_walkable(terrain.idx((int)gx, (int)gy));
	if (!terrain.walkable((int)gx, (int)gy) || !siege_route_cell(terrain.idx((int)gx,(int)gy))) { gx = (float)(c % terrain.w) + 0.5f; gy = (float)(c / terrain.w) + 0.5f; }
	f.goal_x = gx; f.goal_y = gy;
	f.arrived = false;
	f.los_goal = false;
	f.field = request_field(c);
}

// ---------------------------------------------------------------- orders
static void clear_encircle(World &w, Formation &f) {
	for (int i : f.members) w.enc_target[i] = -1;
}

void World::order_move(int fi, float gx, float gy, float gfacing) {
	Formation &f = formations[fi];
	if (f.garrisoned) return;
	if (formation_has_convoys(fi)) gfacing = quarter_angle(quarter_of(gfacing)); // G4: a formation with vehicles rests on a quarter facing
	f.order = Order::MOVE; f.attacking = false; f.target_person = -1; f.goal_facing = gfacing;
	f.order_delay = 0.5 * (1.0 - command_effect(fi, 0, 0.20));
	set_goal(f, gx, gy);
	clear_encircle(*this, f);
}
void World::order_attack(int fi, int tp) {
	Formation &f = formations[fi];
	if (f.garrisoned) return;
	f.order = Order::ATTACK; f.attacking = true; f.needs_attack_order = false; f.target_person = tp;
	f.order_delay = 0.5 * (1.0 - command_effect(fi, 0, 0.20));
	if (tp >= 0) set_goal(f, px[tp], py[tp]);
}
void World::order_hold(int fi) {
	Formation &f = formations[fi];
	const bool was_arrived = f.arrived;
	const float arrival_facing = f.goal_facing;
	f.order = Order::HOLD; f.attacking = false; f.target_person = -1;
	f.goal_x = f.cx; f.goal_y = f.cy; f.arrived = true; f.goal_facing = f.facing;
	// G4: a formation with vehicles keeps the facing it arrived with, on a quarter, so its vehicle layout does not change
	if (formation_has_convoys(fi)) f.goal_facing = quarter_angle(quarter_of(was_arrived ? arrival_facing : f.facing));
	clear_encircle(*this, f);
}
void World::order_pursue(int fi, int tp) {
	Formation &f = formations[fi];
	if (f.garrisoned) return;
	f.order = Order::PURSUE; f.attacking = true; f.needs_attack_order = false; f.target_person = tp;
	f.origin_x = f.ref_valid ? f.ref_x : f.cx; f.origin_y = f.ref_valid ? f.ref_y : f.cy;
	f.pursuit_left = rules::PURSUIT_SECONDS;
	f.order_delay = 0.5 * (1.0 - command_effect(fi, 0, 0.20));
	if (tp >= 0) set_goal(f, px[tp], py[tp]);
	stats.pursuits++;
}
void World::order_retreat(int fi, float gx, float gy) {
	Formation &f = formations[fi];
	if (f.garrisoned) return;
	f.order = Order::RETREAT; f.attacking = false; f.target_person = -1;
	float dx = gx - f.cx, dy = gy - f.cy;
	if (dx * dx + dy * dy > 1e-4f) f.goal_facing = std::atan2(dy, dx);
	if (formation_has_convoys(fi)) f.goal_facing = quarter_angle(quarter_of(f.goal_facing));
	set_goal(f, gx, gy);
	clear_encircle(*this, f);
}

// ---------------------------------------------------------------- geometry
bool World::los(float ax, float ay, float bx, float by, const std::vector<int> *rescue_domain, bool body_blind) const {
	int x = (int)std::floor(ax), y = (int)std::floor(ay);
	int tx = (int)std::floor(bx), ty = (int)std::floor(by);
	if (x == tx && y == ty) return true;
	if (std::max(std::abs(tx - x), std::abs(ty - y)) > cfg.los_max_cells) return false;
	float dx = bx - ax, dy = by - ay;
	int sx = dx > 0 ? 1 : (dx < 0 ? -1 : 0), sy = dy > 0 ? 1 : (dy < 0 ? -1 : 0);
	const float INF = 1e30f;
	float tmx = sx ? (sx > 0 ? ((float)x + 1.f - ax) : (ax - (float)x)) / std::fabs(dx) : INF;
	float tmy = sy ? (sy > 0 ? ((float)y + 1.f - ay) : (ay - (float)y)) / std::fabs(dy) : INF;
	float tdx = sx ? 1.f / std::fabs(dx) : INF, tdy = sy ? 1.f / std::fabs(dy) : INF;
	// convoy bodies block sight like siege bodies unless the caller is a convoy anchor judging its own route
	const auto open = [this, body_blind](int q) { return body_blind ? siege_nav_cell(q) : siege_route_cell(q); };
	bool ending = false;
	for (int guard = 0; guard < 4 * cfg.los_max_cells + 4; ++guard) {
		const int crossed = terrain.idx(x, y);
		// Only rescue_stage supplies the original patient's invalid-surface
		// domain. Terrain edges and every unrelated siege body stay blocking.
		if (!open(crossed) && (rescue_domain == nullptr ||
		    std::find(rescue_domain->begin(), rescue_domain->end(), crossed) == rescue_domain->end())) return false;
		if (x == tx && y == ty) return true;
		// An end point on a cell boundary or corner (slots of an even grid lie on cell corners): rounding can step past the
		// end cell, and the walk would run on to the map edge. The last crossing is checked as usual, then the ray ends.
		if (ending) return true;
		ending = std::min(tmx, tmy) >= 1.f - 1e-5f;
		if (std::fabs(tmx - tmy) < 1e-6f) {
			int d = sx > 0 ? (sy > 0 ? SE : NE) : (sy > 0 ? SW : NW);
			if (!terrain.edge(x, y, d)) return false;
			if (rescue_domain != nullptr) {
				// This exceptional rescue ray may cross only its own wreck,
				// including the two side cells of a diagonal corner.
				for (int side : {terrain.idx(x + sx, y), terrain.idx(x, y + sy)})
					if (!open(side) && std::find(rescue_domain->begin(), rescue_domain->end(), side) == rescue_domain->end()) return false;
			}
			x += sx; y += sy; tmx += tdx; tmy += tdy;
		} else if (tmx < tmy) {
			if (!terrain.edge(x, y, sx > 0 ? E : W)) return false;
			x += sx; tmx += tdx;
		} else {
			if (!terrain.edge(x, y, sy > 0 ? S : N)) return false;
			y += sy; tmy += tdy;
		}
	}
	return false;
}

float World::ray_clip(float ax, float ay, float bx, float by) const {
	int x = (int)std::floor(ax), y = (int)std::floor(ay);
	int tx = (int)std::floor(bx), ty = (int)std::floor(by);
	if (x == tx && y == ty) return 1.f;
	float dx = bx - ax, dy = by - ay;
	float len = std::sqrt(dx * dx + dy * dy);
	int sx = dx > 0 ? 1 : (dx < 0 ? -1 : 0), sy = dy > 0 ? 1 : (dy < 0 ? -1 : 0);
	const float INF = 1e30f;
	float tmx = sx ? (sx > 0 ? ((float)x + 1.f - ax) : (ax - (float)x)) / std::fabs(dx) : INF;
	float tmy = sy ? (sy > 0 ? ((float)y + 1.f - ay) : (ay - (float)y)) / std::fabs(dy) : INF;
	float tdx = sx ? 1.f / std::fabs(dx) : INF, tdy = sy ? 1.f / std::fabs(dy) : INF;
	float back = (cfg.wall_margin + cfg.radius) / std::max(len, 1e-4f);
	for (int guard = 0; guard < 4 * cfg.los_max_cells + 4; ++guard) {
		if (x == tx && y == ty) return 1.f;
		float tc = std::min(tmx, tmy);
		// the end point lies on this cell's boundary (see los): a blocked boundary still clips, an open one ends the ray
		const bool ending = tc >= 1.f - 1e-5f;
		if (std::fabs(tmx - tmy) < 1e-6f) {
			int d = sx > 0 ? (sy > 0 ? SE : NE) : (sy > 0 ? SW : NW);
			if (!terrain.edge(x, y, d)) return std::max(0.f, tc - back);
			if (ending) return 1.f;
			x += sx; y += sy; tmx += tdx; tmy += tdy;
		} else if (tmx < tmy) {
			if (!terrain.edge(x, y, sx > 0 ? E : W)) return std::max(0.f, tc - back);
			if (ending) return 1.f;
			x += sx; tmx += tdx;
		} else {
			if (!terrain.edge(x, y, sy > 0 ? S : N)) return std::max(0.f, tc - back);
			if (ending) return 1.f;
			y += sy; tmy += tdy;
		}
	}
	return 0.f;
}

void World::resolve(float ox, float oy, float &x, float &y, float m) const {
	int cx = (int)std::floor(ox), cy = (int)std::floor(oy);
	float tx = x, ty = y;
	int ncx = (int)std::floor(tx);
	if (ncx != cx) {
		int d = ncx > cx ? E : W;
		if (std::abs(ncx - cx) != 1 || !terrain.edge(cx, cy, d)) tx = d == E ? (float)cx + 1.f - 1e-3f : (float)cx + 1e-3f;
		else cx = ncx;
	}
	int ncy = (int)std::floor(ty);
	if (ncy != cy) {
		int d = ncy > cy ? S : N;
		if (std::abs(ncy - cy) != 1 || !terrain.edge(cx, cy, d)) ty = d == S ? (float)cy + 1.f - 1e-3f : (float)cy + 1e-3f;
		else cy = ncy;
	}
	uint8_t e = terrain.edge_ok[terrain.idx(cx, cy)];
	if (!(e >> E & 1)) tx = std::min(tx, (float)cx + 1.f - m);
	if (!(e >> W & 1)) tx = std::max(tx, (float)cx + m);
	if (!(e >> S & 1)) ty = std::min(ty, (float)cy + 1.f - m);
	if (!(e >> N & 1)) ty = std::max(ty, (float)cy + m);
	x = tx; y = ty;
}

// ---------------------------------------------------------------- factions
std::vector<uint8_t> World::default_relations() {
	std::vector<uint8_t> h(256 * 256, 1);
	for (int a = 0; a < 256; ++a) h[(size_t)a * 256 + a] = 0;
	return h;
}

void World::set_hostile(int a, int b, bool h) {
	hostile_[((size_t)(a & 255) << 8) | (size_t)(b & 255)] = h ? 1 : 0;
	hostile_[((size_t)(b & 255) << 8) | (size_t)(a & 255)] = h ? 1 : 0;
	if ((a & 255) == (b & 255)) hostile_[((size_t)(a & 255) << 8) | (size_t)(a & 255)] = 0; // a faction is never its own enemy
}

void World::build_faction_slots() {
	for (int &s : faction_slot_) s = -1;
	slot_faction_.clear();
	for (uint8_t t : team)
		if (faction_slot_[t] < 0) { faction_slot_[t] = (int)slot_faction_.size(); slot_faction_.push_back(t); }
	const size_t B = (size_t)bw_ * bh_;
	block_count_.assign(slot_faction_.size(), std::vector<uint16_t>(B, 0));
	idle_block_.assign(slot_faction_.size(), std::vector<uint16_t>(B, 0));
	idle_ai_block_.assign(slot_faction_.size(), std::vector<uint16_t>(B, 0));
	enemy_block_.assign(slot_faction_.size(), std::vector<uint16_t>(B, 0));
}

// ---------------------------------------------------------------- hash
void World::build_hash() {
	const int cells = terrain.w * terrain.h;
	const int n = soldier_count();
	hash_start_.assign(cells + 1, 0);
	hash_items_.resize(n);
	for (auto &b : block_count_) std::fill(b.begin(), b.end(), 0);
	for (int i = 0; i < n; ++i) {
		if (!alive(i)) continue;
		int x = (int)px[i], y = (int)py[i];
		int c = terrain.idx(x, y);
		cell[i] = c;
		if (is_aboard(i)) continue; // G1 S1: aboard soldiers are not in the spatial grid or the block counts
		hash_start_[c + 1]++;
		if (can_act(i)) block_count_[faction_slot_[team[i]]][(y >> 3) * bw_ + (x >> 3)]++;
	}
	for (int c = 0; c < cells; ++c) hash_start_[c + 1] += hash_start_[c];
	std::vector<int32_t> fill(hash_start_.begin(), hash_start_.end() - 1);
	for (int i = 0; i < n; ++i)
		if (alive(i) && !is_aboard(i)) hash_items_[fill[cell[i]]++] = i;
	// enemy presence per block for each faction: sum of the factions hostile to it
	const size_t K = slot_faction_.size(), B = (size_t)bw_ * bh_;
	for (size_t a = 0; a < K; ++a) {
		auto &e = enemy_block_[a];
		std::fill(e.begin(), e.end(), 0);
		for (size_t b = 0; b < K; ++b) {
			if (!hostile(slot_faction_[a], slot_faction_[b])) continue;
			const auto &c = block_count_[b];
			for (size_t k = 0; k < B; ++k) e[k] = (uint16_t)(e[k] + c[k]);
		}
	}
}

// ---------------------------------------------------------------- formation layer
static constexpr float kRestSeconds = 4.f; // rest rule: seconds without progress before a member holds where it stands
void World::formation_stage(float dt) {
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		Formation &f = formations[fi];
		f.lag = lag_cnt_[fi] ? (float)(lag_acc_[fi] / lag_cnt_[fi]) : 0.f;
		lag_acc_[fi] = 0; lag_cnt_[fi] = 0;
		if (f.members.empty()) continue;
		if (f.garrisoned) {
			for (int i : f.members) { slot_tx_[i] = px[i]; slot_ty_[i] = py[i]; }
			continue;
		}
		// a formation led by a host-controlled soldier (the player and his company) is centred on him: the
		// other members keep their slots around him (the original FOLLOW_PLAYER), no goal of its own
		int lead = -1;
		for (int m : f.members) if (f.host_center && host_ctl[m] && can_act(m)) { lead = m; break; }
		if (lead >= 0) {
			f.cx = f.goal_x = px[lead]; f.cy = f.goal_y = py[lead]; f.arrived = true;
			f.facing = f.goal_facing = face[lead];
			if (f.order_delay > 0) f.order_delay -= dt;
			for (int i : f.members) {
				if (slot[i] < 0) continue;
				float x, y;
				slot_world(f, slot[i], f.slot_count, x, y);
				if ((tick + (uint32_t)i) % 4 == 0) slot_clip_[i] = ray_clip(f.cx, f.cy, x, y);
				float c = slot_clip_[i];
				if (c < 1.f) { x = f.cx + (x - f.cx) * c; y = f.cy + (y - f.cy) * c; }
				slot_tx_[i] = x; slot_ty_[i] = y;
			}
			continue;
		}
		if (f.reslot_pending && f.arrived) { reslot_formation(f); f.reslot_pending = false; } // G4 layout settle (vehicle formations only)
		// encounter: hold while any member is in melee reach, not only in the 0.4 s after an exchange pair
		bool contact = f.contact_age < 0.4 || f.in_contact;
		// PURSUE limits (D74): 20 cells from the issue reference, 20 seconds, valid target
		if (f.order == Order::PURSUE) {
			f.pursuit_left -= dt;
			int t = f.target_person;
			bool valid = t >= 0 && can_act(t);
			float odx = valid ? px[t] - f.origin_x : 0, ody = valid ? py[t] - f.origin_y : 0;
			float rdx = f.cx - f.origin_x, rdy = f.cy - f.origin_y;
			if (!valid || f.pursuit_left <= 0 || odx * odx + ody * ody > rules::PURSUIT_CELLS * rules::PURSUIT_CELLS ||
			    rdx * rdx + rdy * rdy > rules::PURSUIT_CELLS * rules::PURSUIT_CELLS) {
				f.order = Order::RETURN; f.attacking = false; f.target_person = -1;
				set_goal(f, f.origin_x, f.origin_y);
				clear_encircle(*this, f);
				stats.pursuit_ends++;
			}
		}
		// ATTACK / PURSUE re-target: follow the target person, quantised (1 s, > 3 cells)
		if ((f.order == Order::ATTACK || f.order == Order::PURSUE) && (tick + fi) % 30 == 0) {
			int t = f.target_person;
			if (t >= 0 && can_act(t)) {
				float ddx = px[t] - f.goal_x, ddy = py[t] - f.goal_y;
				if (std::fabs(ddx) + std::fabs(ddy) > 3.f) set_goal(f, px[t], py[t]);
			}
		}
		if (f.order_delay > 0) f.order_delay -= dt;
		bool may_move = f.order_delay <= 0 && !f.arrived && f.order != Order::HOLD;
		if (may_move && (f.order == Order::MOVE || f.order == Order::ATTACK) && contact) may_move = false; // encounter pause
		if (may_move && f.order == Order::ATTACK) {
			int t = f.target_person;
			if (t < 0 || !can_act(t)) may_move = false;
			else {
				float ddx = px[t] - f.cx, ddy = py[t] - f.cy;
				float stop = 2.5f; // melee closes in; archers stop inside their range (range - 1)
				if (f.troop != T_MELEE) stop = f.troop == T_BOW ? 7.0f : 9.0f;
				if (ddx * ddx + ddy * ddy < stop * stop) may_move = false;
			}
		}
		float desired_facing = f.facing;
		if (may_move) {
			float dx = f.goal_x - f.cx, dy = f.goal_y - f.cy;
			float dist = std::sqrt(dx * dx + dy * dy);
			if (dist < 0.4f) {
				f.cx = f.goal_x; f.cy = f.goal_y; f.arrived = true;
				if (f.order == Order::MOVE || f.order == Order::RETREAT || f.order == Order::RETURN) {
					bool routed_retreat = f.order == Order::RETREAT && f.routed;
					f.order = Order::HOLD; f.attacking = false;
					(void)routed_retreat;
				}
			} else {
				// The centre is a virtual point: convoy bodies never block its sight line, and inside a body cell (where a
				// body-aware field has no direction) it goes straight, so a vehicle can never hold the centre (G4).
				if ((tick + fi) % 8 == 0) f.los_goal = los(f.cx, f.cy, f.goal_x, f.goal_y, nullptr, true);
				float dirx = dx / dist, diry = dy / dist;
				const bool in_body = convoy_body_cell(terrain.idx((int)f.cx, (int)f.cy));
				if (!f.los_goal && !in_body && f.field >= 0 && !fields_[f.field].dir.empty()) {
					const FlowField &ff = fields_[f.field];
					int x = (int)f.cx, y = (int)f.cy, bx = -1, by = -1;
					for (int k = 0; k < 6; ++k) {
						uint8_t d = ff.dir[terrain.idx(x, y)];
						if (d == 255) break;
						x += DX[d]; y += DY[d];
						if (k == 0 || los(f.cx, f.cy, (float)x + 0.5f, (float)y + 0.5f)) { bx = x; by = y; }
						else break;
					}
					if (bx < 0) { bx = (int)f.cx; by = (int)f.cy; }
					float ax = (float)bx + 0.5f - f.cx, ay = (float)by + 0.5f - f.cy;
					float al = std::sqrt(ax * ax + ay * ay);
					if (al > 1e-4f) { dirx = ax / al; diry = ay / al; }
				} else if (!f.los_goal && !in_body) {
					dirx = diry = 0;
				}
				float cohesion = std::clamp((3.5f - f.lag) / 2.0f, 0.15f, 1.0f);
				float speed = (f.order == Order::RETREAT && f.routed) || f.order == Order::PURSUE ? cfg.run_speed * 0.8f : cfg.march_speed;
				float stepl = std::min(speed * cohesion * dt, dist);
				float tx = f.cx + dirx * stepl, ty = f.cy + diry * stepl;
				resolve(f.cx, f.cy, tx, ty, cfg.wall_margin);
				f.cx = tx; f.cy = ty;
				desired_facing = std::atan2(dy, dx);
			}
		}
		// Moving allied blocks separate their slot grids. HOLD keeps the issued anchor fixed;
		// individual collision resolution still separates bodies inside and around that block.
		if (f.order != Order::HOLD) {
			int m0 = std::max(1, f.slot_count);
			int c0 = std::max(1, std::min(f.cols, m0)), r0 = (m0 + c0 - 1) / c0;
			float ra = 0.5f * std::sqrt((float)(c0 * c0 + r0 * r0)) * f.spacing;
			float pxs = 0, pys = 0;
			for (size_t o = 0; o < formations.size(); ++o) {
				const Formation &g = formations[o];
				if (o == fi || g.team != f.team || g.slot_count == 0) continue;
				int m1 = g.slot_count, c1 = std::max(1, std::min(g.cols, m1)), r1 = (m1 + c1 - 1) / c1;
				float rb = 0.5f * std::sqrt((float)(c1 * c1 + r1 * r1)) * g.spacing;
				float dx = f.cx - g.cx, dy = f.cy - g.cy, d2 = dx * dx + dy * dy, rs = (ra + rb) * 0.85f;
				if (d2 >= rs * rs) continue;
				float d = std::sqrt(d2);
				if (d < 1e-3f) { dx = (float)((int)fi - (int)o); dy = 0; d = std::fabs(dx); }
				pxs += dx / d * (rs - d); pys += dy / d * (rs - d);
			}
			if (pxs != 0 || pys != 0) {
				float pl = std::sqrt(pxs * pxs + pys * pys), lim = cfg.march_speed * 0.5f * dt;
				if (pl > lim) { pxs *= lim / pl; pys *= lim / pl; }
				float tx = f.cx + pxs, ty = f.cy + pys;
				resolve(f.cx, f.cy, tx, ty, cfg.wall_margin);
				f.cx = tx; f.cy = ty;
			}
		}
		if (f.arrived) desired_facing = f.goal_facing;
		if (f.order == Order::ATTACK && f.target_person >= 0 && can_act(f.target_person)) {
			float ddx = px[f.target_person] - f.cx, ddy = py[f.target_person] - f.cy;
			if (ddx * ddx + ddy * ddy > 1e-4f) desired_facing = std::atan2(ddy, ddx);
		}
		float df = std::remainder(desired_facing - f.facing, 2.f * kPi);
		float mt = cfg.max_turn_rate * dt;
		f.facing += std::clamp(df, -mt, mt);
		int m = f.slot_count;
		// Rest rule: a formation at rest in HOLD keeps its members' rest holds only for the layout they were made in
		const bool resting = f.arrived && f.order == Order::HOLD;
		if (!resting || f.rest_slots != m || f.rest_gx != f.goal_x || f.rest_gy != f.goal_y || f.rest_gf != f.goal_facing) {
			for (int i : f.members) { rest_hold[i] = 0; rest_best[i] = 1e9f; rest_t[i] = 0.f; }
			f.rest_slots = resting ? m : -1; f.rest_gx = f.goal_x; f.rest_gy = f.goal_y; f.rest_gf = f.goal_facing;
		}
		// targets first (clipped toward the centre where a wall or a step cuts the ray), then the rest rule
		std::vector<float> clipped_x, clipped_y;
		for (int i : f.members) {
			if (slot[i] < 0) continue;
			float x, y;
			slot_world(f, slot[i], m, x, y);
			if ((tick + (uint32_t)i) % 4 == 0) slot_clip_[i] = ray_clip(f.cx, f.cy, x, y);
			float c = slot_clip_[i];
			if (c < 1.f) { x = f.cx + (x - f.cx) * c; y = f.cy + (y - f.cy) * c; if (resting) { clipped_x.push_back(x); clipped_y.push_back(y); } }
			slot_tx_[i] = x; slot_ty_[i] = y;
		}
		if (resting) for (int i : f.members) {
			if (slot[i] < 0) continue;
			if (!can_act(i) || state[i] != S_SLOT) { rest_hold[i] = 0; rest_best[i] = 1e9f; rest_t[i] = 0.f; continue; }
			if (rest_hold[i]) {
				// passive: it stands where it is pushed (it yields to anyone passing). Pushed out beyond its own slot's distance
				// from the centre plus a cell (outside the formation), it pushes for its place again
				float sx, sy;
				slot_world(f, slot[i], m, sx, sy);
				const float so = std::sqrt((sx - f.cx) * (sx - f.cx) + (sy - f.cy) * (sy - f.cy));
				const float po = std::sqrt((px[i] - f.cx) * (px[i] - f.cx) + (py[i] - f.cy) * (py[i] - f.cy));
				if (po > so + 1.f) { rest_hold[i] = 0; rest_best[i] = 1e9f; rest_t[i] = 0.f; continue; }
				rest_x[i] = px[i]; rest_y[i] = py[i]; slot_tx_[i] = px[i]; slot_ty_[i] = py[i];
				continue;
			}
			// only a contested place can be given up: the target is clipped (a wall or a step cuts it off), or a clipped
			// target of another member lies within 0.6 of it (several rows clipped onto one spot)
			const float x = slot_tx_[i], y = slot_ty_[i];
			bool contested = slot_clip_[i] < 1.f;
			for (size_t k = 0; k < clipped_x.size() && !contested; ++k) {
				const float ex = clipped_x[k] - x, ey = clipped_y[k] - y;
				if (ex * ex + ey * ey < 0.36f) contested = true;
			}
			if (!contested) { rest_best[i] = 1e9f; rest_t[i] = 0.f; continue; }
			// no progress (0.1) toward it for kRestSeconds while within 2.5 of it: the member stands where it is instead of
			// pushing for ever
			const float d = std::sqrt((px[i] - x) * (px[i] - x) + (py[i] - y) * (py[i] - y));
			if (d < rest_best[i] - 0.1f) { rest_best[i] = d; rest_t[i] = 0.f; }
			else rest_t[i] += dt;
			if (rest_t[i] >= kRestSeconds && d > 0.3f && d < 2.5f) { rest_hold[i] = 1; rest_best[i] = d; rest_x[i] = px[i]; rest_y[i] = py[i]; slot_tx_[i] = px[i]; slot_ty_[i] = py[i]; }
		} else for (int i : f.members) { rest_hold[i] = 0; rest_best[i] = 1e9f; rest_t[i] = 0.f; }
	}
}

// ---------------------------------------------------------------- contact (nearest able enemy, threat bit)
void World::contact_stage(int ch) {
	const int n = soldier_count();
	const int a = ch * cfg.chunk, b = std::min(n, a + cfg.chunk);
	for (int i = a; i < b; ++i) {
		if (!can_act(i) || is_aboard(i)) { target[i] = -1; near_enemy[i] = 0; continue; }
		if ((tick + (uint32_t)i) % (uint32_t)cfg.contact_period) continue;
		const uint16_t *eb = enemy_blocks(team[i]);
		int x = (int)px[i], y = (int)py[i];
		int bx = x >> 3, by = y >> 3, any = 0;
		for (int yy = std::max(0, by - 1); yy <= std::min(bh_ - 1, by + 1) && !any; ++yy)
			for (int xx = std::max(0, bx - 1); xx <= std::min(bw_ - 1, bx + 1); ++xx)
				if (eb[yy * bw_ + xx]) { any = 1; break; }
		near_enemy[i] = (uint8_t)any;
		if (!any) { target[i] = -1; continue; }
		float R = troop[i] == T_MELEE ? cfg.engage_radius : (float)rules::ranged_profile(equip[i]).range + 1.f;
		const float R2 = R * R;
		const int ri = (int)std::ceil(R);
		int best = -1;
		float bd = R2 + 1;
		for (int yy = std::max(0, y - ri); yy <= std::min(terrain.h - 1, y + ri); ++yy)
			for (int xx = std::max(0, x - ri); xx <= std::min(terrain.w - 1, x + ri); ++xx) {
				int c = terrain.idx(xx, yy);
				for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
					int j = hash_items_[k];
					if (!hostile(team[i], team[j]) || !can_act(j)) continue; // D73: do not select downed / captives
					float dx = px[j] - px[i], dy = py[j] - py[i], d2 = dx * dx + dy * dy;
					if ((d2 < bd || (d2 == bd && j < best)) && los(px[i], py[i], px[j], py[j])) { bd = d2; best = j; }
				}
			}
		int cur = target[i];
		if (cur >= 0 && can_act(cur) && hostile(team[i], team[cur])) {
			float dx = px[cur] - px[i], dy = py[cur] - py[i], d2 = dx * dx + dy * dy;
			if (d2 <= R2 && d2 <= bd * 1.44f && los(px[i], py[i], px[cur], py[cur])) best = cur, bd = d2; // keep target (D73)
		}
		target[i] = bd <= R2 ? best : -1;
	}
}

// ---------------------------------------------------------------- soldier layer
void World::soldier_stage(float dt, int ch) {
	const int n = soldier_count();
	const int a = ch * cfg.chunk, b = std::min(n, a + cfg.chunk);
	const float D = 2 * cfg.radius, D2 = D * D;
	const float reach2 = cfg.reach * cfg.reach;
	uint64_t bad_cell = 0, bad_step = 0;
	for (int i = a; i < b; ++i) {
		running[i] = 0;
		if (is_aboard(i)) { // G1 S1: aboard soldiers ride the vehicle; they neither move, push, nor take a step
			nx[i] = px[i]; ny[i] = py[i]; vx[i] = vy[i] = 0;
			state[i] = !alive(i) ? S_DEAD : ko[i] > 0 ? S_DOWN : S_SLOT;
			anim_t[i] += dt; continue;
		}
		if (move_siege_member(i,dt)) continue;
		if (convoy_steer(i, dt)) continue; // convoy crew: steered to their convoy slot, never by ordinary motion
		if (is_siege_crew(i) && !controlled_step_pending(i)) {
			nx[i]=px[i]; ny[i]=py[i]; vx[i]=vy[i]=0;
			state[i]=!alive(i)?S_DEAD:ko[i]>0?S_DOWN:getup[i]>0?S_GETUP:stagger[i]>0?S_STAGGER:S_SLOT;
			anim_t[i]+=dt; continue;
		}
		const bool committed = controlled_step_pending(i);
		if (!alive(i) && !committed) { nx[i] = px[i]; ny[i] = py[i]; vx[i] = vy[i] = 0; state[i] = S_DEAD; continue; }
		if (is_surrendered(i) && !committed) { // G5 S4: stands in place; host input and formation slots do not move it
			nx[i] = px[i]; ny[i] = py[i]; vx[i] = vy[i] = 0;
			state[i] = ko[i] > 0 ? S_DOWN : S_SLOT; running[i] = 0;
			anim_t[i] += dt; continue;
		}
		if (captive[i] && prison_id[i] > 0 && !committed) {
			// A confined original body is a stationary collision participant. Do not
			// let guard-follow, old velocity or separation move it outside its slot.
			nx[i] = px[i]; ny[i] = py[i]; vx[i] = vy[i] = 0;
			state[i] = ko[i] > 0 ? S_DOWN : S_CAPTIVE; running[i] = 0;
			anim_t[i] += dt;
			continue;
		}
		const Formation &f = formations[form[i]];
		const float p_x = px[i], p_y = py[i];
		float dvx = 0, dvy = 0;
		float speed_cap = cfg.march_speed * 1.25f;
		SState st = S_SLOT;
		bool lying = ko[i] > 0 || !alive(i);
		int tg = target[i];
		float ex = 0, ey = 0, ed = 1e9f;
		if (tg >= 0) { ex = px[tg] - p_x; ey = py[tg] - p_y; ed = std::sqrt(ex * ex + ey * ey); }
		bool in_reach = tg >= 0 && ed * ed <= reach2;
		const bool controlled = escort_mode[i] >= 3 && escort_mode[i] <= 6;
		const bool escorting = controlled || (escort_mode[i] != 0 && !lying && getup[i] <= 0 && stagger[i] <= 0);
		if (escorting) {
			st = !alive(i) ? S_DEAD : lying ? S_DOWN : getup[i] > 0 ? S_GETUP : stagger[i] > 0 ? S_STAGGER : captive[i] ? S_CAPTIVE : S_SLOT;
			bool permitted = controlled || !captive[i] || (captor[i] >= 0 && can_act(captor[i]));
			if (permitted && escort_goal[i] >= 0) {
				const int goal = escort_goal[i];
				const float gx = float(goal % terrain.w) + .5f, gy = float(goal / terrain.w) + .5f;
				float sx = gx - p_x, sy = gy - p_y, sd = std::sqrt(sx * sx + sy * sy);
				if (captive[i] && !controlled) {
					const float dx = gx - px[captor[i]], dy = gy - py[captor[i]];
					permitted = dx * dx + dy * dy <= 16.f;
				}
				const float arrival = escort_mode[i] >= 5 ? 1e-5f : .015f;
				if (permitted && sd > arrival) { const float sp = std::min(cfg.march_speed, sd / dt); dvx = sx / sd * sp; dvy = sy / sd * sp; }
				else if (permitted) { escort_goal[i] = -1; siege_step_source[i]=-1; if ((escort_mode[i] & 1u) == 0 || (escort_mode[i] == 5 && is_siege_crew(i))) escort_mode[i] = 0; }
			}
		} else if (captive[i]) {
			st = S_CAPTIVE;
			int g = captor[i];
			if (!lying && g >= 0 && can_act(g)) { // escort: follow one cell behind the guard
				float gx = px[g] - std::cos(face[g]) * 0.8f, gy = py[g] - std::sin(face[g]) * 0.8f;
				float sx = gx - p_x, sy = gy - p_y, sd = std::sqrt(sx * sx + sy * sy);
				if (sd > 0.2f) { float sp = std::min(cfg.march_speed * 1.2f, sd * 3.f); dvx = sx / sd * sp; dvy = sy / sd * sp; }
			}
		} else if (lying) {
			st = S_DOWN;
			if (knock_t[i] > 0) { dvx = knock_dx[i]; dvy = knock_dy[i]; speed_cap = 1e9f; } // a knockback still carries the falling body
		} else if (getup[i] > 0) {
			st = S_GETUP;
		} else if (knock_t[i] > 0) {
			st = S_KNOCK;
			dvx = knock_dx[i]; dvy = knock_dy[i]; speed_cap = 1e9f;
		} else if (stagger[i] > 0) {
			st = S_STAGGER;
		} else if (is_siege_crew(i)) {
			st = S_SLOT;
		} else if (f.garrisoned) {
			// Timers, damage, capture and knockback above remain authoritative.
			// A reserve roster does not march or choose offensive targets.
			st = in_reach ? S_FIGHT : S_SLOT;
		} else if (housing_attendance_cell[i] >= 0 && f.order == Order::HOLD && !f.routed && !in_reach && !near_enemy[i] && (!host_ctl[i] || (host_vx[i] == 0 && host_vy[i] == 0 && !host_engage[i]))) {
			// A current original Site reference holds this person at home for this
			// one phase. Commands, contacts, injury and host wishes keep their owners.
			st = S_SLOT;
		} else if (host_ctl[i]) {
			if (host_engage[i] && in_reach) st = S_FIGHT; // stand and exchange, as under ATTACK
			else {
				st = S_HOST;
				dvx = host_vx[i]; dvy = host_vy[i];
				speed_cap = host_run[i] ? cfg.run_speed : cfg.march_speed * 1.25f;
			}
		} else if (rescue_of[i] >= 0) {
			st = S_RESCUE;
			int p = rescue_of[i];
			float qx = px[p] - p_x, qy = py[p] - p_y, qd = std::sqrt(qx * qx + qy * qy);
			if (qd > 1.1f) { dvx = qx / qd * cfg.march_speed; dvy = qy / qd * cfg.march_speed; } // walk to the wounded
		} else if (capture_of[i] >= 0) {
			st = S_CAPTURE;
			int t = capture_of[i];
			float qx = px[t] - p_x, qy = py[t] - p_y, qd = std::sqrt(qx * qx + qy * qy);
			if (qd > 1.1f) { dvx = qx / qd * cfg.march_speed; dvy = qy / qd * cfg.march_speed; } // walk to the prisoner
		} else if (f.routed && f.order == Order::RETREAT) {
			st = S_FLEE; // follow the fleeing formation's slot at run speed
		} else if (in_reach && (f.order != Order::RETREAT && f.order != Order::RETURN)) {
			st = S_FIGHT; // stand and exchange (initiating or receiving)
		} else {
			bool melee = troop[i] == T_MELEE;
			bool can_init = initiates(i, melee) && f.order_delay <= 0;
			float sdx = slot_tx_[i] - p_x, sdy = slot_ty_[i] - p_y, sdist = std::sqrt(sdx * sdx + sdy * sdy);
			int et = enc_target[i];
			if (melee && et >= 0 && can_act(et) && can_init) {
				st = S_ENCIRCLE;
				float qx = px[et] - p_x, qy = py[et] - p_y, qd = std::sqrt(qx * qx + qy * qy);
				float sp = cfg.run_speed * std::clamp((qd - cfg.reach * 0.85f) / 0.5f, 0.f, 1.f);
				if (qd > 1e-4f && (tick + (uint32_t)i) % 4 == 0) los_ok[i] = los(p_x, p_y, px[et], py[et]) ? 1 : 0;
				if (qd > 1e-4f) {
					float dirx = qx / qd, diry = qy / qd;
					if (!los_ok[i]) { // go around: follow the formation field toward the enemy block
						int fld = f.field;
						if (fld >= 0 && !fields_[fld].dir.empty()) {
							uint8_t d = fields_[fld].dir[cell[i]];
							if (d != 255) { float l = d < 4 ? 1.f : 0.70710678f; dirx = (float)DX[d] * l; diry = (float)DY[d] * l; }
						}
					}
					dvx = dirx * sp; dvy = diry * sp;
				}
				speed_cap = cfg.run_speed;
			} else if (!melee && can_init && tg >= 0 && ed < cfg.ranged_keep && sdist < cfg.ranged_leash) {
				st = S_RANGED; // too close: step back to keep 3 cells
				dvx = -ex / ed * cfg.march_speed; dvy = -ey / ed * cfg.march_speed;
			} else if (!melee && can_init && tg >= 0 && ed > (float)rules::ranged_profile(equip[i]).range - 0.5f && sdist < cfg.ranged_leash) {
				st = S_RANGED; // out of range: close in, bounded by the leash
				dvx = ex / ed * cfg.march_speed; dvy = ey / ed * cfg.march_speed;
			} else if (!melee && can_init && tg >= 0 && fire_blocked[i] && sdist < cfg.ranged_leash) {
				st = S_RANGED; // friends on the line: side-step (safe firing position search, 2026-09-18)
				float side = (((tick / 60u) + (uint32_t)i) & 1u) ? 1.f : -1.f;
				dvx = -ey / ed * side * cfg.march_speed; dvy = ex / ed * side * cfg.march_speed;
			} else if (!melee && can_init && tg >= 0) {
				st = S_RANGED; // in range: stand and shoot
			} else if (melee && can_init && tg >= 0 && (f.order == Order::ATTACK || f.order == Order::PURSUE) && sdist <= cfg.leash + 0.5f) {
				st = S_ENGAGE;
				float sp = cfg.run_speed * std::clamp((ed - cfg.reach * 0.85f) / 0.5f, 0.f, 1.f);
				dvx = ex / ed * sp; dvy = ey / ed * sp;
				speed_cap = cfg.run_speed;
			}
			if (st == S_SLOT && sdist > 1e-3f && slot[i] >= 0) {
				if ((tick + (uint32_t)i) % (uint32_t)cfg.los_period == 0) los_ok[i] = los(p_x, p_y, slot_tx_[i], slot_ty_[i]) ? 1 : 0;
				float dirx = sdx / sdist, diry = sdy / sdist;
				if (!los_ok[i] && f.field >= 0 && !fields_[f.field].dir.empty()) {
					uint8_t d = fields_[f.field].dir[cell[i]];
					if (d != 255) { float l = d < 4 ? 1.f : 0.70710678f; dirx = (float)DX[d] * l; diry = (float)DY[d] * l; }
				}
				float sp = std::min(cfg.march_speed * 1.25f, sdist * 3.0f);
				dvx = dirx * sp; dvy = diry * sp;
			}
		}
		if (st == S_FLEE) {
			float sdx = slot_tx_[i] - p_x, sdy = slot_ty_[i] - p_y, sdist = std::sqrt(sdx * sdx + sdy * sdy);
			if (sdist > 1e-3f) {
				if ((tick + (uint32_t)i) % (uint32_t)cfg.los_period == 0) los_ok[i] = los(p_x, p_y, slot_tx_[i], slot_ty_[i]) ? 1 : 0;
				float dirx = sdx / sdist, diry = sdy / sdist;
				if (!los_ok[i] && f.field >= 0 && !fields_[f.field].dir.empty()) {
					uint8_t d = fields_[f.field].dir[cell[i]];
					if (d != 255) { float l = d < 4 ? 1.f : 0.70710678f; dirx = (float)DX[d] * l; diry = (float)DY[d] * l; }
				}
				float sp = std::min(cfg.run_speed, sdist * 3.0f);
				dvx = dirx * sp; dvy = diry * sp;
			}
			speed_cap = cfg.run_speed;
		}
		// G4: a standing person in a cell a convoy claimed steps out at run speed toward the free neighbour nearest its slot
		bool evacuating = false;
		if (!lying && !committed && !escorting && !captive[i] && !host_ctl[i] && st != S_FIGHT && can_act(i) && convoy_evacuation(i, dvx, dvy)) {
			evacuating = true;
			speed_cap = cfg.run_speed;
		}
		// host blockers in the way: turn the wish toward the blocker's nearer side, fading in over 1.5 cells
		if (!blockers.empty() && (!lying || committed) && (dvx != 0.f || dvy != 0.f)) {
			for (const Blocker &B : blockers) {
				const float bx = B.x - p_x, by = B.y - p_y, bd = std::sqrt(bx * bx + by * by), R = B.r + cfg.radius;
				if (bd > R + 1.5f || bd < 1e-5f) continue;
				const float dl = std::sqrt(dvx * dvx + dvy * dvy);
				const float ux = dvx / dl, uy = dvy / dl, nxb = bx / bd, nyb = by / bd;
				const float toward = ux * nxb + uy * nyb;
				if (toward <= 0.2f) continue;
				float tx = -nyb, ty = nxb; // the tangent on the side the wish already leans to (ties: by index)
				const float lean = ux * tx + uy * ty;
				if (lean < 0.f || (lean == 0.f && (i & 1))) { tx = -tx; ty = -ty; }
				const float w = std::clamp((R + 1.5f - bd) / 1.5f, 0.f, 1.f) * toward;
				float ox = ux * (1.f - w) + tx * w, oy = uy * (1.f - w) + ty * w;
				const float inward = ox * nxb + oy * nyb;
				if (bd < R + 0.3f && inward > 0.f) { ox -= inward * nxb; oy -= inward * nyb; } // no pushing into it
				const float ol = std::sqrt(ox * ox + oy * oy);
				if (ol > 1e-5f) { dvx = ox / ol * dl; dvy = oy / ol * dl; } else { dvx = dvy = 0.f; }
			}
		}
		const bool sliding = st == S_KNOCK || (st == S_DOWN && knock_t[i] > 0);
		float blend = sliding || escorting || evacuating ? 1.f : 0.4f;
		float cvx = vx[i] + (dvx - vx[i]) * blend, cvy = vy[i] + (dvy - vy[i]) * blend;
		if ((!committed && ((st == S_DOWN && !sliding) || st == S_GETUP || st == S_STAGGER)) || ((st == S_RESCUE || st == S_CAPTURE || escorting) && dvx == 0 && dvy == 0) || st == S_FIGHT) cvx = cvy = 0; // Only an existing Site step carries an incapacitated original body.
		float cl = std::sqrt(cvx * cvx + cvy * cvy);
		if (cl > speed_cap) { cvx *= speed_cap / cl; cvy *= speed_cap / cl; }
		float qx = p_x + cvx * dt, qy = p_y + cvy * dt;
		// separation against standing bodies only (D72: downed / dead no longer hold a standing place)
		float kx = 0, ky = 0;
		if (!lying) {
			int cx = (int)p_x, cy = (int)p_y;
			uint8_t my_team = team[i];
			float ally_w = cfg.ally_push;
			for (int yy = std::max(0, cy - 1); yy <= std::min(terrain.h - 1, cy + 1); ++yy)
				for (int xx = std::max(0, cx - 1); xx <= std::min(terrain.w - 1, cx + 1); ++xx) {
					int c = terrain.idx(xx, yy);
					for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
						int j = hash_items_[k];
						if (j == i || ko[j] > 0) continue;
						float dx = p_x - px[j], dy = p_y - py[j], d2 = dx * dx + dy * dy;
						if (d2 >= D2) continue;
						float w = !hostile(my_team, team[j]) ? ally_w : cfg.enemy_push;
						if (d2 < 1e-10f) { kx += (i < j ? 0.02f : -0.02f); continue; }
						float d = std::sqrt(d2), pen = D - d;
						kx += dx / d * pen * w * 0.5f; ky += dy / d * pen * w * 0.5f;
					}
				}
			float kl = std::sqrt(kx * kx + ky * ky);
			if (kl > cfg.push_clamp) { kx *= cfg.push_clamp / kl; ky *= cfg.push_clamp / kl; }
		}
		qx += kx; qy += ky;
		if (escorting && escort_goal[i] < 0) { qx = p_x; qy = p_y; }
		if (!lying || committed) // Original committed bodies also retain host-blocker collision.
			for (const Blocker &B : blockers) {
				float dx = qx - B.x, dy = qy - B.y, d = std::sqrt(dx * dx + dy * dy);
				const float R = B.r + cfg.radius;
				if (d >= R) continue;
				if (d < 1e-5f) { dx = (i & 1) ? 1.f : -1.f; dy = 0.f; d = 1.f; }
				qx = B.x + dx / d * R; qy = B.y + dy / d * R;
			}
		resolve(p_x, p_y, qx, qy, cfg.wall_margin);
		resolve_siege_person(i,p_x,p_y,qx,qy);
		if ((!lying || committed) && !blockers.empty()) {
			// a wall can undo the projection (a pass too narrow to step aside): then stay where it was,
			// unless the blocker itself walked onto this soldier
			for (const Blocker &B : blockers) {
				const float R = B.r + cfg.radius - 1e-3f;
				const float qd2 = (qx - B.x) * (qx - B.x) + (qy - B.y) * (qy - B.y);
				const float pd2 = (p_x - B.x) * (p_x - B.x) + (p_y - B.y) * (p_y - B.y);
				if (qd2 < R * R && pd2 >= qd2) { qx = p_x; qy = p_y; break; }
			}
		}
		if (terrain.contains(int(qx),int(qy)) && siege_claims_cell(terrain.idx(int(qx),int(qy)),i)) { qx=p_x; qy=p_y; }
		nx[i] = qx; ny[i] = qy;
		vx[i] = (qx - p_x) / dt; vy[i] = (qy - p_y) / dt;
		if (st == S_FIGHT || st == S_ENGAGE || st == S_RANGED) { if (tg >= 0) face[i] = std::atan2(ey, ex); }
		else if (st == S_ENCIRCLE && enc_target[i] >= 0) face[i] = std::atan2(py[enc_target[i]] - p_y, px[enc_target[i]] - p_x);
		else if (cvx * cvx + cvy * cvy > 0.04f) face[i] = std::atan2(cvy, cvx);
		else if (st == S_SLOT) face[i] = f.facing;
		state[i] = (uint8_t)st;
		running[i] = (uint8_t)((st == S_ENGAGE || st == S_ENCIRCLE || st == S_FLEE || (st == S_HOST && host_run[i])) && cl > cfg.march_speed * 1.05f);
		anim_t[i] += dt;
		// invariants
		int cx = (int)std::floor(p_x), cy = (int)std::floor(p_y);
		int ncx = (int)std::floor(qx), ncy = (int)std::floor(qy);
		if (!terrain.contains(ncx, ncy) || !terrain.walkable(ncx, ncy)) ++bad_cell;
		else if (ncx != cx || ncy != cy) {
			int ddx = ncx - cx, ddy = ncy - cy;
			bool ok = false;
			if (std::abs(ddx) + std::abs(ddy) == 1) {
				int d = ddx > 0 ? E : ddx < 0 ? W : ddy > 0 ? S : N;
				ok = terrain.edge(cx, cy, d);
			} else if (std::abs(ddx) == 1 && std::abs(ddy) == 1) {
				int hx = ddx > 0 ? E : W, vyd = ddy > 0 ? S : N;
				ok = (terrain.edge(cx, cy, hx) && terrain.edge(cx + ddx, cy, vyd)) ||
				     (terrain.edge(cx, cy, vyd) && terrain.edge(cx, cy + ddy, hx));
			}
			if (!ok) ++bad_step;
		}
	}
	illegal_buf_[(size_t)ch * 3] += bad_cell;
	illegal_buf_[(size_t)ch * 3 + 1] += bad_step;
}

// ---------------------------------------------------------------- slots (vacancy refill, D73)
int World::nearest_hostile(int i, float r) const {
	if (i < 0 || i >= soldier_count()) return -1;
	int best = -1;
	float bd = r * r;
	for (int j = 0; j < soldier_count(); ++j) {
		if (j == i || !can_act(j) || is_aboard(j) || !hostile(team[i], team[j])) continue;
		const float dx = px[j] - px[i], dy = py[j] - py[i], d2 = dx * dx + dy * dy;
		if (d2 < bd) { bd = d2; best = j; }
	}
	return best;
}

void World::set_host_control(int i, bool on) {
	if (i < 0 || i >= soldier_count()) return;
	if (on) for (int k = 0; k < soldier_count(); ++k) if (k != i && host_ctl[k]) set_host_control(k, false);
	host_ctl[i] = on ? 1 : 0;
	host_vx[i] = host_vy[i] = 0.f; host_run[i] = host_engage[i] = 0;
	if (on) { rescue_of[i] = -1; capture_of[i] = -1; enc_target[i] = -1; }
}

void World::host_input(int i, float wish_vx, float wish_vy, bool run, bool engage) {
	if (i < 0 || i >= soldier_count() || !host_ctl[i]) return;
	if (formations[form[i]].garrisoned) { host_vx[i] = host_vy[i] = 0; host_run[i] = host_engage[i] = 0; return; }
	if (!std::isfinite(wish_vx) || !std::isfinite(wish_vy)) wish_vx = wish_vy = 0.f;
	host_vx[i] = wish_vx; host_vy[i] = wish_vy; host_run[i] = run ? 1 : 0; host_engage[i] = engage ? 1 : 0;
}

int World::standing_near(float x, float y, float r) const {
	int count = 0;
	const int x0 = std::max(0, (int)std::floor(x - r)), x1 = std::min(terrain.w - 1, (int)std::floor(x + r));
	const int y0 = std::max(0, (int)std::floor(y - r)), y1 = std::min(terrain.h - 1, (int)std::floor(y + r));
	for (int i = 0; i < soldier_count(); ++i) { // host query, not per step: a plain scan keeps it independent of the hash
		if (!can_act(i) || is_aboard(i)) continue;
		if (px[i] < (float)x0 || px[i] >= (float)x1 + 1.f || py[i] < (float)y0 || py[i] >= (float)y1 + 1.f) continue;
		const float dx = px[i] - x, dy = py[i] - y;
		if (dx * dx + dy * dy <= r * r) ++count;
	}
	return count;
}

void World::compact_slots(Formation &f) {
	// members: all non-dead; slots only for able, free members, kept in current slot order
	size_t w = 0;
	for (size_t k = 0; k < f.members.size(); ++k)
		if (alive(f.members[k])) f.members[w++] = f.members[k];
	f.members.resize(w);
	std::vector<int> able;
	for (int i : f.members)
		if ((can_act(i) || getup[i] > 0) && !is_convoy_crew(i) && !is_aboard(i)) able.push_back(i); // convoy crew and aboard soldiers hold vehicle slots, not soldier slots
		else slot[i] = -1;
	std::stable_sort(able.begin(), able.end(), [&](int x, int y) {
		int sx = slot[x] < 0 ? 1 << 30 : slot[x], sy = slot[y] < 0 ? 1 << 30 : slot[y];
		return sx < sy;
	});
	for (size_t k = 0; k < able.size(); ++k) slot[able[k]] = (int)k;
	f.slot_count = (int)able.size();
}

// External command boundary. Internal AI/rout/return callers retain clipped order_* semantics.
int World::host_order(int fi, int kind, float gx, float gy, double x) {
	if (fi < 0 || fi >= (int)formations.size()) return BAD_FORMATION;
	const Formation &f = formations[fi];
	if (f.no_orders || f.garrisoned) return NO_ORDERS;
	if (f.ai_enabled) return NOT_OWNER;
	if (!finalized_ || kind < 0 || kind > 4 || !std::isfinite(gx) || !std::isfinite(gy) || !std::isfinite(x) || (kind == 1 && !std::isfinite((float)x))) return BAD_ARGS;
	if (kind == 3 && !f.routed) return NOT_ROUTED;
	if (f.routed && (kind == 1 || kind == 2 || kind == 4)) return ROUTED;
	int target_index = -1;
	if (kind == 2 || kind == 4) {
		if (x < 0 || x >= soldier_count() || x != std::floor(x)) return NO_TARGET;
		target_index = (int)x;
		if (!can_act(target_index) || !hostile(f.team, team[target_index])) return NO_TARGET;
		if (kind == 4) {
			const float rx = f.ref_valid ? f.ref_x : f.cx, ry = f.ref_valid ? f.ref_y : f.cy;
			const double dx = px[target_index] - rx, dy = py[target_index] - ry;
			if (dx * dx + dy * dy > rules::PURSUIT_CELLS * rules::PURSUIT_CELLS) return NO_TARGET;
		}
		gx = px[target_index]; gy = py[target_index];
	}
	if (kind != 0 && kind != 3) {
		if (!(gx >= 0 && gy >= 0 && gx < terrain.w && gy < terrain.h) || !terrain.walkable_f(gx, gy) || !siege_route_cell(terrain.idx((int)gx,(int)gy))) return BLOCKED;
		const int goal = terrain.idx((int)gx, (int)gy), start = terrain.idx((int)f.cx, (int)f.cy);
		std::vector<uint8_t> seen(terrain.edge_ok.size(), 0);
		std::vector<int> queue{start}; seen[start] = 1;
		for (size_t k = 0; k < queue.size() && !seen[goal]; ++k) {
			const int c = queue[k];
			for (int d = 0; d < 8; ++d) if ((terrain.edge_ok[c] >> d) & 1) {
				const int q = c + DY[d] * terrain.w + DX[d];
				if (!seen[q] && siege_route_cell(q) && (d<4 || (siege_route_cell(c+DX[d]) && siege_route_cell(c+DY[d]*terrain.w)))) { seen[q] = 1; queue.push_back(q); }
			}
		}
		if (!seen[goal]) return BLOCKED;
	}
	switch (kind) {
	case 0: order_hold(fi); break;
	case 1: order_move(fi, gx, gy, (float)x); break;
	case 2: order_attack(fi, target_index); break;
	case 3: retreat_away(fi); break;
	case 4: order_pursue(fi, target_index); break;
	}
	return OK;
}

bool World::set_soldier_equip(int i, const rules::Equip &equipment) {
	if (i < 0 || i >= soldier_count() || equipment.family > rules::F_SHOVEL || equipment.material > rules::M_STEEL || equipment.armor > rules::A_MINGGUANG) return false;
	equip[i] = equipment;
	troop[i] = (uint8_t)(equipment.family == rules::F_BOW ? T_BOW : equipment.family == rules::F_CROSSBOW ? T_CROSSBOW : T_MELEE);
	return true;
}

bool World::set_sustain_input(int fi, bool fed, double delta) {
	if (fi < 0 || fi >= (int)formations.size() || !std::isfinite(delta) || !std::isfinite(formations[fi].sustain_morale_delta + delta)) return false;
	formations[fi].fully_fed = fed; formations[fi].sustain_morale_delta += delta;
	return true;
}

void World::rebuild_buffers() {
	siege_crew.resize(soldier_count(),0); siege_member_group.resize(soldier_count(),-1); siege_step_source.resize(soldier_count(),-1);
	housing_attendance_cell.assign(soldier_count(), -1);
	const int n = soldier_count(); chunks_ = (n + cfg.chunk - 1) / cfg.chunk;
	pair_buf_.resize(chunks_); fire_buf_.resize(chunks_); illegal_buf_.resize((size_t)chunks_ * 3, 0);
	wake_buf_.resize(chunks_); getup_buf_.resize(chunks_); ex_acc_.resize(n);
}

// ---------------------------------------------------------------- step
// Site clock (SiteRuntime.game_seconds): the combat clock runs 1:1, the rest of the slice at 60x;
// the Site speed multiplies game time only.
static bool valid_action_dt(float dt) {
	const bool valid = std::isfinite(dt) && dt > 0 && dt < 1;
#ifdef _DEBUG
	assert(valid && "crowd action dt must be finite and in (0, 1)");
#endif
	return valid;
}

// These are additions to ORIGINAL crowd_core.cpp inside namespace wg, after
// valid_action_dt. Includes already present: algorithm / cmath / crowd_core.hpp.
std::vector<double> World::work_fatigue_state(int fi) const {
	if (fi < 0 || fi >= (int)formations.size()) return {};
	const Formation &f = formations[fi];
	return {double(tick), double(fi), f.fatigue, f.fatigue_rest, double(f.fatigue_count)};
}

std::vector<int64_t> World::work_fatigue_runners(int fi) const {
	if (fi < 0 || fi >= (int)formations.size()) return {};
	std::vector<int64_t> out;
	for (int i : formations[fi].members) if (can_act(i) && running[i]) {
		out.push_back(i);
		out.push_back(person_id[i]);
	}
	return out;
}

bool World::validate_step_clock_work_plan(float dt, double seconds, double combat_now,
	uint32_t expected_tick, const std::vector<WorkFatigueState> &plan) const {
	return validate_step_clock_work_plan_source(dt,seconds,combat_now,expected_tick,plan,nullptr);
}

bool World::validate_step_clock_work_plan_after_host_ranged(float dt, double seconds, double combat_now,
	uint32_t expected_tick, const std::vector<WorkFatigueState> &plan,
	const std::vector<int64_t> &releases, const std::vector<double> &preview) const {
	if(releases.empty()) return preview.empty() && validate_step_clock_work_plan_source(dt,seconds,combat_now,expected_tick,plan,nullptr);
	const auto current=preview_host_ranged_batch(releases);
	if(current.empty() || current!=preview) return false;
	// Preserve the true original BEGIN combat mark in the same body clock.
	for(size_t k=0;k<preview.size();k+=10)
		if(combat_now+1e-8<std::max(0.0,preview[k+9]-double(dt))) return false;
	return validate_step_clock_work_plan_source(dt,seconds,combat_now,expected_tick,plan,&preview);
}

bool World::validate_step_clock_work_plan_source(float dt, double seconds, double combat_now,
	uint32_t expected_tick, const std::vector<WorkFatigueState> &plan,
	const std::vector<double> *ranged_preview) const {
	// Validate ALL pools before any clock, sustain, work fatigue or movement is
	// published. A rejected packet leaves the actual World byte-for-byte intact.
	if (work_point_active_ || !valid_action_dt(dt) || !std::isfinite(seconds) || seconds < 0 ||
		!std::isfinite(combat_now) || combat_now < 0 || expected_tick != tick ||
		plan.size() > formations.size()) return false;
	int previous = -1;
	for (const auto &p : plan) {
		if (p.formation <= previous || p.formation < 0 || p.formation >= (int)formations.size()) return false;
		previous = p.formation; // Stable original formation order also refuses duplicates.
		const Formation &f = formations[p.formation];
		double source_fatigue=f.fatigue,source_rest=f.fatigue_rest;
		// This exact preview has already been regenerated from original World
		// ammo/count/tick/cooldown/mode/order/position/profile/watermark facts.
		// Read only the last ordered pulse for this original formation; every
		// other guard below is the original shared-plan validator, unchanged.
		if(ranged_preview) for(size_t k=0;k<ranged_preview->size();k+=10)
			if(int((*ranged_preview)[k+1])==p.formation){source_fatigue=(*ranged_preview)[k+6];source_rest=(*ranged_preview)[k+7];}
		for (double v : {p.before_fatigue,p.before_rest,p.work_seconds,p.run_seconds,p.fatigue,p.rest})
			if (!std::isfinite(v)) return false;
		if (p.before_count != f.fatigue_count || p.before_count <= 0 ||
			p.before_fatigue != source_fatigue || p.before_rest != source_rest ||
			p.before_fatigue < 0 || p.before_fatigue > rules::FATIGUE_LIMIT ||
			p.before_rest < 0 || p.before_rest > rules::FATIGUE_REST_DELAY ||
			p.work_seconds < 0 || p.run_seconds < 0 || seconds <= 0 ||
			!(p.work_seconds > 0 || p.run_seconds > 0) || p.rest != 0 ||
			p.fatigue < p.before_fatigue || p.fatigue > rules::FATIGUE_LIMIT) return false;
		const auto runners = work_fatigue_runners(p.formation);
		const double expected_run = double(runners.size() / 2) * seconds;
		const double total = p.work_seconds + p.run_seconds;
		if (!std::isfinite(expected_run) || !std::isfinite(total) ||
			std::abs(p.run_seconds - expected_run) > 1e-8 ||
			total > double(p.before_count) * seconds + 1e-8) return false;
		// The original native rates remain authoritative. Cold research's 0.5
		// changes productive progress; it never halves these actual effort seconds.
		const double gain = (p.work_seconds * (10.0 / 3600.0) + p.run_seconds * rules::FATIGUE_RUN_RATE) / p.before_count;
		const double expected = std::min(rules::FATIGUE_LIMIT, p.before_fatigue + gain);
		if (!std::isfinite(gain) || std::abs(p.fatigue - expected) > 1e-8) return false;
	}
	return true;
}

bool World::step_clock_work_plan(float dt, double seconds, double combat_now,
	uint32_t expected_tick, const std::vector<WorkFatigueState> &plan) {
	if (!validate_step_clock_work_plan(dt, seconds, combat_now, expected_tick, plan)) return false;
	external_clock = true;
	game_dt = seconds;
	combat_left = combat_now;
	step_body(dt, &plan); // Same original step; no pending state survives this call.
	return true;
}


bool World::step_clock_work_point(float dt, double seconds, double combat_now,
        uint32_t expected_tick, const std::vector<WorkFatigueState> &precontact_plan) {
    if (!validate_step_clock_work_plan(dt, seconds, combat_now, expected_tick, precontact_plan) || seconds <= 0) return false;
    work_point_pools_.assign(formations.size(), WorkPointPool{});
    work_point_runners_.clear(); work_point_run_seen_.assign(soldier_count(),0);
    for (size_t fi=0; fi<formations.size(); ++fi) {
        const Formation &f=formations[fi]; auto &p=work_point_pools_[fi];
        p.source.formation=(int)fi; p.source.before_count=f.fatigue_count;
        p.source.before_fatigue=f.fatigue; p.source.before_rest=f.fatigue_rest;
        p.before_training=f.training; p.training_start_eligible=training_start_ready((int)fi,combat_now,true);
        const auto initial=work_fatigue_runners((int)fi);
        p.source.run_seconds=double(initial.size()/2)*seconds;
        for(size_t k=0;k<initial.size();k+=2) {
            work_point_run_seen_[(size_t)initial[k]]=1;
            work_point_runners_.insert(work_point_runners_.end(),{int64_t(fi),initial[k],initial[k+1]});
        }
        for (const auto &base:precontact_plan) if (base.formation==(int)fi) p.source.work_seconds=base.work_seconds;
    }
    work_point_begin_tick_=tick; work_point_seconds_=seconds;
    work_point_finish_ready_=false; work_point_finish_.clear(); work_point_training_.clear(); work_point_deaths_.clear(); work_point_active_=true;
    external_clock=true; game_dt=seconds; combat_left=combat_now;
    step_body(dt,&precontact_plan); // Same ORIGINAL sustain/fatigue/people/motion/contacts exactly once.
    return true;
}

std::vector<double> World::work_point_state() const {
    return {work_point_active_?1.0:0.0,work_point_finish_ready_?1.0:0.0,
        double(work_point_begin_tick_),double(tick),work_point_seconds_};
}

std::vector<int64_t> World::work_fatigue_run_upper() const {
    std::vector<int64_t> refs;
    for(int i=0;i<soldier_count();++i) if(can_act(i)) refs.insert(refs.end(),{int64_t(form[i]),int64_t(i),person_id[i]});
    return refs; // Not predicted effort. Existing providers exclude their own held identities.
}

std::vector<int64_t> World::work_point_runners() const {
    return work_point_active_?work_point_runners_:std::vector<int64_t>{};
}

void World::capture_work_point_runners() {
    if(!work_point_active_) return;
    // Original fatigue_stage ran before original soldier_stage. Preserve its
    // already-metered runner IDs, then add TRUE newly moving RUN exactly once.
    // Capture before later projectile/exchange deaths can remove can_act.
    for(int i=0;i<soldier_count();++i) if(can_act(i)&&running[i]&&!work_point_run_seen_[i]) {
        work_point_run_seen_[i]=1;
        work_point_runners_.insert(work_point_runners_.end(),{int64_t(form[i]),int64_t(i),person_id[i]});
        work_point_pools_[form[i]].source.run_seconds+=work_point_seconds_;
    }
}

bool World::validate_work_point_training_plan(uint32_t begin_tick, const std::vector<WorkTrainingState> &targets) const {
    if(!work_point_active_ || work_point_finish_ready_ || begin_tick!=work_point_begin_tick_ ||
       tick!=begin_tick+uint32_t(1) || targets.size()>formations.size()) return false;
    int previous=-1;
    for(const auto &t:targets) {
        if(t.formation<=previous || t.formation<0 || t.formation>=(int)formations.size()) return false;
        previous=t.formation;
        const auto &source=work_point_pools_[t.formation];
        for(double v:{t.before_training,t.training,t.effort_seconds,t.productive_seconds}) if(!std::isfinite(v)) return false;
        if(!source.training_start_eligible || t.before_training!=source.before_training ||
           formations[t.formation].training!=source.before_training || t.training<t.before_training ||
           t.training>std::max(1000.0,t.before_training) || t.effort_seconds<=0 || t.productive_seconds<0 ||
           t.productive_seconds>t.effort_seconds+1e-8 || t.effort_seconds>source.source.work_seconds+1e-8) return false;
    }
    return true;
}

bool World::prepare_work_point_training_plan(uint32_t begin_tick, const std::vector<WorkTrainingState> &targets) {
    if(!validate_work_point_training_plan(begin_tick,targets)) return false;
    work_point_training_=targets; // all copying/allocation BEFORE any original cost.
    return true;
}

bool World::validate_work_point_finish(uint32_t expected_begin_tick,
        const std::vector<WorkFatigueState> &final_plan) const {
    if (!work_point_active_ || work_point_finish_ready_ || expected_begin_tick!=work_point_begin_tick_ ||
        tick!=work_point_begin_tick_+uint32_t(1) || work_point_pools_.size()!=formations.size() ||
        final_plan.size()>formations.size() || !validate_work_point_training_plan(expected_begin_tick,work_point_training_)) return false;
    // Every ORIGINAL native discrete pulse during actual contacts remains a
    // point event with its actual contemporaneous living denominator. Only the
    // continuous work/RUN component is replaced by the final joint integral.
    for (size_t fi=0; fi<formations.size(); ++fi) {
        const auto &p=work_point_pools_[fi]; const auto &f=formations[fi];
        if (!p.base_captured || !std::isfinite(p.native_charge) || p.native_charge<0 ||
            std::abs(f.fatigue-std::min(rules::FATIGUE_LIMIT,p.native_base_fatigue+p.native_charge))>1e-8 ||
            std::abs(f.fatigue_rest-(p.native_charge>0?0:p.native_base_rest))>1e-8) return false;
    }
    int previous=-1;
    for (const auto &p:final_plan) {
        if (p.formation<=previous || p.formation<0 || p.formation>=(int)formations.size()) return false;
        previous=p.formation; const auto &source=work_point_pools_[p.formation].source;
        for (double v:{p.before_fatigue,p.before_rest,p.work_seconds,p.run_seconds,p.fatigue,p.rest}) if (!std::isfinite(v)) return false;
        if (p.before_count!=source.before_count || p.before_count<=0 || p.before_fatigue!=source.before_fatigue ||
            p.before_rest!=source.before_rest || p.work_seconds+1e-8<source.work_seconds || p.run_seconds<0 ||
            std::abs(p.run_seconds-source.run_seconds)>1e-8 || p.work_seconds+p.run_seconds<=0 ||
            p.work_seconds+p.run_seconds>double(p.before_count)*work_point_seconds_+1e-8 || p.work_seconds<=0 || p.rest!=0) return false;
        const double gain=(p.work_seconds*(10.0/3600.0)+p.run_seconds*rules::FATIGUE_RUN_RATE)/p.before_count;
        if (!std::isfinite(gain) || std::abs(p.fatigue-std::min(rules::FATIGUE_LIMIT,p.before_fatigue+gain))>1e-8) return false;
    }
    for (const auto &source:work_point_pools_) {
        if (source.source.work_seconds<=0) continue; // NO WORK: original World RUN/recovery stays untouched.
        bool found=false;
        for (const auto &p:final_plan) if (p.formation==source.source.formation) { found=true; break; }
        if (!found) return false; // Cannot erase already accepted original work or RUN.
    }
    for (const auto &d:work_point_deaths_) {
        if (d.event_index>=events.size() || d.formation<0 || d.formation>=(int)formations.size()) return false;
        const auto &e=events[d.event_index];
        if (e.kind!=EV_DEATH || e.person!=d.person || e.formation!=d.formation ||
            e.fatigue!=d.before_fatigue || e.fatigue_rest!=d.before_rest || !std::isfinite(d.native_charge) || d.native_charge<0) return false;
    }
    return true;
}

bool World::prepare_work_point_finish(uint32_t expected_begin_tick,
        const std::vector<WorkFatigueState> &final_plan) {
    if (!validate_work_point_finish(expected_begin_tick,final_plan)) return false;
    // Allocate/copy/validate BEFORE the caller's FIRST real holder/material/job
    // write. Nothing in publish below decodes a packet or performs admission.
    work_point_finish_=final_plan;
    for (auto &d:work_point_deaths_) {
        d.fatigue=d.before_fatigue; d.rest=d.before_rest;
        // The event stays the ORIGINAL queue entry. Continuous accepted prefix
        // uses original start count; only native pulses BEFORE this death join it.
        for (const auto &p:final_plan) if (p.formation==d.formation) {
            d.fatigue=std::min(rules::FATIGUE_LIMIT,p.fatigue+d.native_charge); d.rest=0;
        }
    }
    for (auto &p:work_point_finish_) {
        p.fatigue=std::min(rules::FATIGUE_LIMIT,p.fatigue+work_point_pools_[p.formation].native_charge);
        p.rest=0;
    }
    work_point_finish_ready_=true;
    return true;
}

void World::publish_work_point_finish() {
    if (!work_point_finish_ready_) return; // Repeated publisher has no effect.
    for (const auto &p:work_point_finish_) {
        formations[p.formation].fatigue=p.fatigue;
        formations[p.formation].fatigue_rest=p.rest;
    }
    for(const auto &t:work_point_training_) formations[t.formation].training=t.training;
    for (const auto &d:work_point_deaths_) {
        events[d.event_index].fatigue=d.fatigue;
        events[d.event_index].fatigue_rest=d.rest;
    }
    work_point_finish_.clear(); work_point_training_.clear(); work_point_pools_.clear(); work_point_deaths_.clear();
    work_point_runners_.clear(); work_point_run_seen_.clear();
    work_point_finish_ready_=false; work_point_active_=false;
}

bool World::step(float dt) {
	if (work_point_active_ || !valid_action_dt(dt)) return false;
	external_clock = false;
	double combat = std::min((double)dt, std::max(0.0, combat_left));
	game_dt = (combat + std::max(0.0, (double)dt - combat) * 60.0) * cfg.speed;
	combat_left = std::max(0.0, combat_left - (double)dt);
	step_body(dt);
	return true;
}

bool World::step_clock(float dt, double game_seconds, double combat_left_now) {
	if (work_point_active_ || !valid_action_dt(dt) || !std::isfinite(game_seconds) || game_seconds < 0 || !std::isfinite(combat_left_now) || combat_left_now < 0) return false;
	external_clock = true;
	game_dt = std::max(0.0, game_seconds);
	combat_left = std::max(0.0, combat_left_now);
	step_body(dt);
	return true;
}

// Order follows terrain_lab._advance_combat: sustain / fatigue / person actions (game time) -> tactical AI
// -> formations -> prepare (timers, KO / wake, rescue) -> movement -> arrivals -> exchange round with
// ranged fire at its end -> settle command.
void World::step_body(float dt, const std::vector<WorkFatigueState> *work_plan) {
	PhaseTimes pt;
	pt.steps = 1;
	auto t0 = Clock::now(), t = t0;
	const int n = soldier_count();
	chunks_ = (n + cfg.chunk - 1) / cfg.chunk;
	if ((int)wake_buf_.size() < chunks_) { wake_buf_.resize(chunks_); getup_buf_.resize(chunks_); }
	combat_mark = 0;
	const double gdt = game_dt;

	build_hash();
	pt.hash = ms_since(t); t = Clock::now();

	for (int k = 0; k < cfg.max_fields_per_step && !field_queue_.empty(); ++k) {
		int s = field_queue_.front();
		field_queue_.erase(field_queue_.begin());
		if (fields_[s].dir.empty()) build_field(fields_[s]);
	}
	pt.fields = ms_since(t); t = Clock::now();

	sustain_stage(gdt);      // morale observation, rout, resupply, rally
	fatigue_stage(gdt, work_plan);      // shared fatigue charge / recovery
	pt.fatigue = ms_since(t); t = Clock::now();
	person_actions_stage(gdt); // capture (auto + ordered) and escape
	pt.actions = ms_since(t); t = Clock::now();

	if (cfg.ai && tick % 15 == 0) ai_review();
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		Formation &f = formations[fi];
		f.encircle_t -= dt;
		if (f.encircle_t <= 0) { encircle_review(f, (int)fi); f.encircle_t = 0.5 * (1.0 - command_effect((int)fi, 0, 0.20)); }
	}
	pt.ai = ms_since(t); t = Clock::now();

	formation_stage(dt);
	pt.formation = ms_since(t); t = Clock::now();

	pool_.run(chunks_, [&](int ch) { timers_stage(dt, gdt, ch); });
	for (int ch = 0; ch < chunks_; ++ch) {
		for (int i : wake_buf_[ch]) { stats.wakes++; formations[form[i]].command_dirty = true; push_event(EV_WAKE, i, -1); }
		for (int i : getup_buf_[ch]) formations[form[i]].command_dirty = true;
	}
	rescue_stage(dt);
	bleed_stage(gdt);
	pt.timers = ms_since(t); t = Clock::now();

	pool_.run(chunks_, [&](int ch) { contact_stage(ch); });
	pt.contact = ms_since(t); t = Clock::now();

	action_motion.resize(n);
	for (int i = 0; i < n; ++i) action_motion[i] = {px[i], py[i], px[i], py[i]};
	advance_siege_compounds(dt);
	convoy_stage(dt); // convoy anchors advance before the crew are steered to their slots
	pool_.run(chunks_, [&](int ch) { soldier_stage(dt, ch); });
	std::swap(px, nx); std::swap(py, ny);
	capture_work_point_runners(); // Same ORIGINAL motion phase; before projectile/exchange death.
	for (int i = 0; i < n; ++i) { action_motion[i].to_x = px[i]; action_motion[i].to_y = py[i]; }
	std::fill(housing_attendance_cell.begin(), housing_attendance_cell.end(), -1); // One host attendance reference serves fatigue then original motion, consumed for the next step.
	pt.soldier = ms_since(t); t = Clock::now();

	build_hash(); // arrivals, exchange and fire read the positions after this step's movement
	projectiles_advance(dt); // flights already in the air; this step's new shots start next step
	pt.ranged = ms_since(t); t = Clock::now();
	if (tick % 3 == 0) {
		exchange_round_run();
		pt.exchange = ms_since(t); t = Clock::now();
		if (!host_ranged_delegate) {
			pool_.run(chunks_, [&](int ch) { ranged_decide(ch); });
			ranged_commit();
		}
		pt.ranged += ms_since(t); t = Clock::now();
	}

	command_stage(dt); // settle_combat_command
	pt.command = ms_since(t); t = Clock::now();

	for (int i = 0; i < n; ++i) {
		if (state[i] != S_SLOT || slot[i] < 0 || is_convoy_crew(i)) continue; // convoy crew are not formation slot followers
		float dx = slot_tx_[i] - px[i], dy = slot_ty_[i] - py[i];
		lag_acc_[form[i]] += std::sqrt(dx * dx + dy * dy);
		lag_cnt_[form[i]]++;
	}
	for (size_t fi = 0; fi < formations.size(); ++fi) {
		Formation &f = formations[fi];
		f.compact_t -= dt;
		if (f.compact_t <= 0) { compact_slots(f); f.compact_t = 0.5 * (1.0 - command_effect((int)fi, 0, 0.20)); }
		f.contact_age += dt;
	}
	for (int ch = 0; ch < chunks_; ++ch) {
		stats.illegal_cell += illegal_buf_[(size_t)ch * 3]; stats.illegal_step += illegal_buf_[(size_t)ch * 3 + 1];
		illegal_buf_[(size_t)ch * 3] = illegal_buf_[(size_t)ch * 3 + 1] = illegal_buf_[(size_t)ch * 3 + 2] = 0;
	}
	pt.compact = ms_since(t);
	pt.total = ms_since(t0);
	last = pt;
	time += dt;
	++tick;
}

void World::build_flight_cells() {
	if (projectiles.empty()) { flight_cells_.clear(); return; }
	flight_cells_.assign((size_t)terrain.w * terrain.h, 0);
	std::vector<rules::Cell> cells;
	for (auto &p : projectiles) {
		rules::ranged_cells(p.source, p.target, cells);
		for (auto &c : cells) if (terrain.contains(c.x, c.y)) flight_cells_[terrain.idx(c.x, c.y)] = 1;
	}
}

// ---------------------------------------------------------------- G4 logistics convoys
// A convoy is an anchor with crew slots (anchor + offset rotated by facing). convoy_stage (serial, before the
// soldier pass) advances the anchor along the goal's flow field, turning toward its heading, only while it has a
// goal, has crew, and every crew member can act and stands within convoy_tolerance of its slot. convoy_steer
// (parallel soldier pass) moves each crew member toward its slot and writes only that soldier's arrays.
Convoy *World::convoy_at(int id) {
	for (auto &c : convoys) if (c.id == id) return &c;
	return nullptr;
}

const Convoy *World::convoy_at(int id) const {
	for (const auto &c : convoys) if (c.id == id) return &c;
	return nullptr;
}

int World::add_convoy(float ax, float ay, float facing) {
	if (!finalized_ || !std::isfinite(ax) || !std::isfinite(ay) || !std::isfinite(facing) || convoy_serial >= INT32_MAX - 1 || convoys.size() >= 256) return 0;
	if (ax < 0 || ay < 0 || ax >= (float)terrain.w || ay >= (float)terrain.h) return 0;
	if (!terrain.walkable((int)ax, (int)ay) || !siege_nav_cell(terrain.idx((int)ax, (int)ay)) || convoy_body_cell(terrain.idx((int)ax, (int)ay))) return 0;
	Convoy c;
	c.id = convoy_serial + 1; c.x = ax; c.y = ay; c.facing = facing;
	convoys.push_back(std::move(c));
	convoy_serial = convoys.back().id;
	return convoy_serial;
}

bool World::convoy_set_crew(int id, int i, int ox, int oy, bool assigned) {
	Convoy *c = convoy_at(id);
	if (!c || i < 0 || i >= soldier_count() || convoy_of.size() != px.size()) return false;
	auto at = std::find_if(c->crew.begin(), c->crew.end(), [i](const ConvoyCrew &k) { return k.soldier == i; });
	if (!assigned) {
		if (at == c->crew.end()) return false;
		c->crew.erase(at);
		convoy_of[i] = 0;
		if (c->formation >= 0 && c->crew.empty()) convoy_detach_formation(id); // no crew left in the formation
		compact_slots(formations[form[i]]); // the released member takes a soldier slot again
		return true;
	}
	if (ox < -8 || ox > 8 || oy < -8 || oy > 8) return false;
	if (at != c->crew.end()) { at->ox = ox; at->oy = oy; return true; }
	if (c->crew.size() >= 64 || convoy_of[i] != 0 || is_siege_crew(i) || !can_act(i) || escort_mode[i] != 0 || escort_goal[i] >= 0 || siege_group(i) >= 0 ||
	    rescue_of[i] >= 0 || capture_of[i] >= 0 || prison_id[i] != 0 || captive[i] || host_ctl[i] || formations[form[i]].garrisoned) return false;
	if (c->formation >= 0 && form[i] != c->formation) return false; // an attached convoy keeps its crew inside its formation
	c->crew.push_back(ConvoyCrew{i, ox, oy});
	convoy_of[i] = id;
	compact_slots(formations[form[i]]); // crew stand at the vehicle, not in a soldier slot
	return true;
}

bool World::convoy_reachable(int start, int goal) const {
	std::vector<uint8_t> seen(terrain.edge_ok.size(), 0);
	std::vector<int> queue{start};
	seen[start] = 1;
	for (size_t k = 0; k < queue.size() && !seen[goal]; ++k) {
		const int c = queue[k];
		for (int d = 0; d < 8; ++d) if ((terrain.edge_ok[c] >> d) & 1) {
			const int q = c + DY[d] * terrain.w + DX[d];
			// convoy reachability is judged without convoy bodies: the convoy's own body must not cut its route
			if (!seen[q] && siege_nav_cell(q) && (d < 4 || (siege_nav_cell(c + DX[d]) && siege_nav_cell(c + DY[d] * terrain.w)))) { seen[q] = 1; queue.push_back(q); }
		}
	}
	return seen[goal] != 0;
}

bool World::convoy_order_goal(int id, float gx, float gy, float gfacing) {
	Convoy *c = convoy_at(id);
	if (!c || !finalized_ || !std::isfinite(gx) || !std::isfinite(gy) || !std::isfinite(gfacing)) return false;
	if (gx < 0 || gy < 0 || gx >= (float)terrain.w || gy >= (float)terrain.h) return false;
	const int goal = terrain.idx((int)gx, (int)gy);
	if (!terrain.walkable((int)gx, (int)gy) || !siege_nav_cell(goal) || !convoy_reachable(terrain.idx((int)c->x, (int)c->y), goal)) return false;
	if (c->formation >= 0) convoy_detach_formation(id); // an explicit vehicle order leaves the formation layout
	c->has_goal = true;
	c->gx = std::floor(gx) + 0.5f; c->gy = std::floor(gy) + 0.5f;
	c->gfacing = gfacing; c->goal_cell = goal;
	c->field = request_field(goal, false); // convoy anchors steer by body-blind fields (see convoy_stage)
	return true;
}

// G4 S2: the caller gives absolute cells at the anchor's current pose. They are stored as convoy-local offsets: the
// cell centre relative to the anchor, rotated back by -facing and rounded to whole cells. The request is refused
// unless those offsets re-derive exactly the given cells at this pose (rounding can differ at other facings).
bool World::convoy_set_body(int id, const std::vector<int> &cells) {
	Convoy *c = convoy_at(id);
	if (!c || cells.size() > 64) return false;
	const int count = terrain.w * terrain.h;
	std::vector<int> given;
	for (int v : cells) {
		if (v < 0 || v >= count || !terrain.walkable(v % terrain.w, v / terrain.w) || std::find(given.begin(), given.end(), v) != given.end()) return false;
		given.push_back(v);
	}
	std::sort(given.begin(), given.end());
	// One integer offset per cell, found with the same expression convoy_footprint uses for a single offset. The round
	// trip therefore cannot disagree with rounding. A body may contain its own anchor cell (offset 0, 0).
	Convoy trial = *c;
	trial.body.clear();
	const float fx = std::cos(c->facing), fy = std::sin(c->facing);
	for (int v : cells) {
		bool found = false;
		for (int oy = -8; oy <= 8 && !found; ++oy) {
			for (int ox = -8; ox <= 8 && !found; ++ox) {
				const float x = c->x + (float)ox * fx - (float)oy * fy, y = c->y + (float)ox * fy + (float)oy * fx;
				if (!(x >= 0.f && y >= 0.f && x < (float)terrain.w && y < (float)terrain.h)) continue;
				if (terrain.idx((int)x, (int)y) != v) continue;
				trial.body.push_back(ConvoyOffset{ox, oy});
				found = true;
			}
		}
		if (!found) return false;
	}
	std::vector<int> derived;
	if (!convoy_footprint(trial, c->x, c->y, c->facing, derived) || derived != given) return false;
	if (!convoy_cells_clear(*c, derived)) return false; // another body or a living non-crew soldier is in the way
	c->body = std::move(trial.body);
	set_convoy_cells(*c, std::move(derived));
	return true;
}

bool World::convoy_body_at(int id, std::vector<int> &cells) const {
	const Convoy *c = convoy_at(id);
	if (!c) return false;
	cells = c->body_cells;
	return true;
}

bool World::convoy_footprint(const Convoy &c, float ax, float ay, float facing, std::vector<int> &cells) const {
	cells.clear();
	const float fx = std::cos(facing), fy = std::sin(facing);
	for (const auto &o : c.body) {
		// same rotation as convoy_slot: crew and body rotate together
		const float x = ax + (float)o.ox * fx - (float)o.oy * fy, y = ay + (float)o.ox * fy + (float)o.oy * fx;
		if (!(x >= 0.f && y >= 0.f && x < (float)terrain.w && y < (float)terrain.h)) return false;
		const int v = terrain.idx((int)x, (int)y);
		if (std::find(cells.begin(), cells.end(), v) == cells.end()) cells.push_back(v);
	}
	std::sort(cells.begin(), cells.end());
	return true;
}

bool World::convoy_cells_clear(const Convoy &c, const std::vector<int> &cells) const {
	for (int v : cells) {
		if (!terrain.walkable(v % terrain.w, v / terrain.w)) return false;
		if (!convoy_body_owner.empty() && convoy_body_owner[v] != 0 && convoy_body_owner[v] != c.id) return false;
	}
	for (int i = 0; i < soldier_count(); ++i) {
		if (!alive(i) || is_aboard(i) || (i < (int)convoy_of.size() && convoy_of[i] == c.id)) continue; // own crew stand in their own body
		const int x = (int)std::floor(px[i]), y = (int)std::floor(py[i]);
		if (!terrain.contains(x, y)) continue;
		if (std::binary_search(cells.begin(), cells.end(), terrain.idx(x, y))) return false;
	}
	return true;
}

void World::set_convoy_cells(Convoy &c, std::vector<int> cells) {
	if (cells == c.body_cells) return;
	const size_t count = (size_t)terrain.w * terrain.h;
	if (convoy_body_owner.size() != count) convoy_body_owner.assign(count, 0);
	for (int v : c.body_cells) if (convoy_body_owner[v] == c.id) convoy_body_owner[v] = 0;
	c.body_cells = std::move(cells);
	for (int v : c.body_cells) convoy_body_owner[v] = c.id;
	bool any = false;
	for (const auto &o : convoys) if (!o.body_cells.empty()) { any = true; break; }
	if (!any) convoy_body_owner.clear(); // no bodies: the owner map disappears and every route check is the old one
	refresh_body_fields();
}

void World::refresh_body_fields() {
	// Only body-aware fields depend on bodies. They are cleared and re-queued, then rebuilt lazily through the same
	// per-step queue as any field (max_fields_per_step). Until rebuilt, a field with an empty direction is not used.
	for (size_t k = 0; k < fields_.size(); ++k) {
		if (!fields_[k].body_aware) continue;
		fields_[k].dir.clear(); fields_[k].cost.clear();
		if (std::find(field_queue_.begin(), field_queue_.end(), (int)k) == field_queue_.end()) field_queue_.push_back((int)k);
	}
	// formation centre sight (los_goal) is body-blind, so a body change does not reset it
	std::fill(los_ok.begin(), los_ok.end(), 0);
}

bool World::rebuild_convoy_bodies() {
	convoy_claim_owner.clear(); // claims are saved per convoy; the owner map is derived
	for (const auto &cv : convoys) for (int v : cv.claim) {
		if (v < 0 || v >= terrain.w * terrain.h) return false;
		if (convoy_claim_owner.empty()) convoy_claim_owner.assign((size_t)terrain.w * terrain.h, 0);
		if (convoy_claim_owner[v] != 0) return false;
		convoy_claim_owner[v] = cv.id;
	}
	convoy_body_owner.clear();
	const size_t count = (size_t)terrain.w * terrain.h;
	for (auto &cv : convoys) cv.body_cells.clear();
	for (auto &cv : convoys) {
		std::vector<int> cells;
		if (!convoy_footprint(cv, cv.x, cv.y, cv.facing, cells)) return false;
		for (int v : cells) if (!terrain.walkable(v % terrain.w, v / terrain.w)) return false;
		if (cells.empty()) continue;
		if (convoy_body_owner.size() != count) convoy_body_owner.assign(count, 0);
		for (int v : cells) {
			if (convoy_body_owner[v] != 0) return false; // two bodies may not overlap
			convoy_body_owner[v] = cv.id;
		}
		cv.body_cells = std::move(cells);
	}
	return true;
}

std::vector<int> World::convoy_crew_soldiers(int id) const {
	std::vector<int> out;
	const Convoy *c = convoy_at(id);
	if (!c) return out;
	out.reserve(c->crew.size());
	for (const auto &k : c->crew) out.push_back(k.soldier);
	return out;
}

bool World::convoy_state(int id, ConvoyState &out) const {
	const Convoy *c = convoy_at(id);
	if (!c) return false;
	const bool at_goal = c->has_goal && std::fabs(c->x - c->gx) < 1e-4f && std::fabs(c->y - c->gy) < 1e-4f;
	const bool faced = c->has_goal && std::fabs(std::remainder(c->facing - c->gfacing, 2.f * kPi)) < 1e-3f;
	const bool complete = at_goal && faced;
	// A crew member that cannot act right now is reported live, even if the last step did not see it.
	int reason = !c->has_goal ? (c->no_slot ? CONVOY_NO_SLOT : CONVOY_NO_GOAL) : c->stall_reason;
	if (c->has_goal && !complete) for (const auto &k : c->crew) if (k.soldier < 0 || k.soldier >= soldier_count() || !can_act(k.soldier)) reason = CONVOY_CREW_CANNOT_ACT;
	if (complete || (c->has_goal && reason == CONVOY_NO_GOAL)) reason = CONVOY_OK;
	const bool stalled = (c->has_goal && !complete && reason != CONVOY_OK && reason != CONVOY_CREW_OFF_SLOT && reason != CONVOY_YIELDING) || c->no_slot;
	out.x = c->x; out.y = c->y; out.facing = c->facing;
	out.stalled = stalled ? 1 : 0; // a crew member off its slot is a transient wait: reported in reason, not stalled
	out.complete = complete ? 1 : 0;
	out.reason = reason;
	out.moving = (c->has_goal && !complete && !stalled && !c->crew.empty()) ? 1 : 0;
	return true;
}

bool World::convoy_remove(int id) {
	for (auto at = convoys.begin(); at != convoys.end(); ++at) if (at->id == id) {
		std::vector<int> released_forms;
		for (const auto &k : at->crew) if (k.soldier >= 0 && k.soldier < (int)convoy_of.size()) { convoy_of[k.soldier] = 0; released_forms.push_back(form[k.soldier]); }
		set_convoy_cells(*at, {}); // the removed body stops blocking
		convoy_release_claim(*at);
		convoys.erase(at);
		std::sort(released_forms.begin(), released_forms.end());
		released_forms.erase(std::unique(released_forms.begin(), released_forms.end()), released_forms.end());
		for (int fi : released_forms) if (fi >= 0 && fi < (int)formations.size()) compact_slots(formations[fi]); // released crew take soldier slots again
		return true;
	}
	return false;
}

void World::convoy_slot(const Convoy &c, const ConvoyCrew &k, float &x, float &y) const {
	const float fx = std::cos(c.facing), fy = std::sin(c.facing);
	x = c.x + (float)k.ox * fx - (float)k.oy * fy;
	y = c.y + (float)k.ox * fy + (float)k.oy * fx;
}

bool World::convoy_crew_aligned(const Convoy &c) const {
	if (c.crew.empty()) return false;
	for (const auto &k : c.crew) {
		if (k.soldier < 0 || k.soldier >= soldier_count() || !can_act(k.soldier)) return false;
		float sx = 0.f, sy = 0.f;
		convoy_slot(c, k, sx, sy);
		const float dx = px[k.soldier] - sx, dy = py[k.soldier] - sy;
		if (dx * dx + dy * dy > convoy_tolerance * convoy_tolerance) return false;
	}
	return true;
}

void World::convoy_stage(float dt) {
	// A claim lives from its convoy's turn in one stage to its turn in the next (so lower ids see it too); each convoy
	// releases its own claims when its turn comes and posts new ones only while it is actually advancing.
	// Formation layouts first (a changed key reassigns every attached vehicle of that formation).
	{
		std::vector<int> attached;
		for (const auto &c : convoys) if (c.formation >= 0) attached.push_back(c.formation);
		std::sort(attached.begin(), attached.end());
		attached.erase(std::unique(attached.begin(), attached.end()), attached.end());
		for (int fi : attached) convoy_plan_formation(fi);
	}
	for (auto &c : convoys) {
		c.body_stalled = false;
		c.stall_reason = CONVOY_OK;
		bool crew_ready = !c.crew.empty();
		for (const auto &k : c.crew) if (k.soldier < 0 || k.soldier >= soldier_count() || !can_act(k.soldier)) crew_ready = false;
		const bool aligned = crew_ready && convoy_crew_aligned(c);
		// an attached convoy waiting for its able crew keeps its claims (the cells of its turn or step stay reserved)
		if (!(c.formation >= 0 && c.has_goal && crew_ready && !aligned)) convoy_release_claim(c);
		if (!c.has_goal) { c.stall_reason = c.no_slot ? CONVOY_NO_SLOT : CONVOY_NO_GOAL; continue; }
		if (!crew_ready) { c.stall_reason = CONVOY_CREW_CANNOT_ACT; continue; }
		// A crew member that is up but not yet on its slot: the anchor waits and reports it.
		if (!aligned) { c.stall_reason = CONVOY_CREW_OFF_SLOT; continue; }
		if (c.formation >= 0) { convoy_follow_stage(c, dt); continue; } // attached: formation slot steering
		const float ex = c.gx - c.x, ey = c.gy - c.y, ed = std::sqrt(ex * ex + ey * ey);
		// Body-blind sight and body-blind fields: a convoy's own body never blocks its own route. Another convoy's
		// body is caught by convoy_cells_clear below and reported as stalled.
		const bool straight = los(c.x, c.y, c.gx, c.gy, nullptr, true);
		const float stride = cfg.march_speed * dt;
		float tx = c.x, ty = c.y;         // candidate anchor for this step
		float desired = c.facing; // no movement this step: hold the facing
		if (straight && ed <= stride) { // the goal is within one step on a clear line: land exactly on it
			tx = c.gx; ty = c.gy;
			desired = c.gfacing;
		} else {
			float dirx = 0.f, diry = 0.f;
			bool have = false;
			if (straight) {
				dirx = ex / ed; diry = ey / ed; have = true;
			} else {
				if (c.field < 0 || c.field >= (int)fields_.size() || fields_[c.field].goal != c.goal_cell || fields_[c.field].body_aware) c.field = request_field(c.goal_cell, false);
				const FlowField &ff = fields_[c.field];
				const int here = terrain.idx((int)c.x, (int)c.y);
				if (!ff.dir.empty() && ff.dir[here] != 255) {
					int x = (int)c.x, y = (int)c.y, bx = -1, by = -1;
					for (int k = 0; k < 6; ++k) {
						const uint8_t d = ff.dir[terrain.idx(x, y)];
						if (d == 255) break;
						x += DX[d]; y += DY[d];
						if (k == 0 || los(c.x, c.y, (float)x + 0.5f, (float)y + 0.5f, nullptr, true)) { bx = x; by = y; }
						else break;
					}
					if (bx >= 0) {
						const float ax = (float)bx + 0.5f - c.x, ay = (float)by + 0.5f - c.y, al = std::sqrt(ax * ax + ay * ay);
						if (al > 1e-4f) { dirx = ax / al; diry = ay / al; have = true; }
					}
				}
				// No usable field direction here (field unbuilt, or an edge the backward build did not reach): step to the
				// forward neighbour closest to the goal instead of holding silently.
				if (!have) have = convoy_greedy_direction(c, dirx, diry);
			}
			if (!have) { c.stall_reason = CONVOY_NO_ROUTE; continue; }
			float qx = c.x + dirx * stride, qy = c.y + diry * stride;
			resolve(c.x, c.y, qx, qy, cfg.wall_margin);
			// the anchor never enters unwalkable ground or a cell the crowd may not route through (bodies: below)
			if (!(terrain.walkable_f(qx, qy) && siege_nav_cell(terrain.idx((int)qx, (int)qy)))) { c.stall_reason = CONVOY_BLOCKED_TERRAIN; continue; }
			tx = qx; ty = qy;
			desired = std::atan2(diry, dirx);
		}
		const float mt = cfg.max_turn_rate * dt;
		const float nf = c.facing + std::clamp(std::remainder(desired - c.facing, 2.f * kPi), -mt, mt);
		if (tx != c.x || ty != c.y || nf != c.facing) {
			// The whole footprint moves with the anchor and turns with it. The anchor cell and every footprint cell must
			// not be another convoy's body, and the footprint may not cover a living non-crew soldier. Otherwise the
			// anchor holds position and facing and reports why.
			const int anchor_cell = terrain.idx((int)tx, (int)ty);
			if (convoy_body_cell(anchor_cell) && convoy_body_owner[anchor_cell] != c.id) { c.body_stalled = true; c.stall_reason = CONVOY_BLOCKED_BODY; continue; }
			std::vector<int> cells;
			if (!convoy_footprint(c, tx, ty, nf, cells)) { c.body_stalled = true; c.stall_reason = CONVOY_BLOCKED_TERRAIN; continue; }
			if (cells != c.body_cells) {
				// G4 OPUS: own-team people who can step out are asked to (claim) and the convoy waits for them, as attached
				// convoys do; other bodies, other claims and anybody else block (reported stalled).
				std::vector<int> claim;
				const int verdict = convoy_follow_cells(c, cells, {}, claim);
				if (verdict == FOLLOW_YIELD) { convoy_post_claim(c, claim); c.stall_reason = CONVOY_YIELDING; continue; }
				if (verdict != FOLLOW_CLEAR) {
					c.body_stalled = true;
					c.stall_reason = verdict == FOLLOW_SOLDIER ? CONVOY_BLOCKED_SOLDIER : verdict == FOLLOW_TERRAIN ? CONVOY_BLOCKED_TERRAIN : CONVOY_BLOCKED_BODY;
					continue;
				}
			}
			set_convoy_cells(c, std::move(cells)); // no-op unless the cell set changed
		}
		c.x = tx; c.y = ty; c.facing = nf;
	}
}

bool World::convoy_soldier_in(const Convoy &c, const std::vector<int> &cells) const {
	for (int i = 0; i < soldier_count(); ++i) {
		if (!alive(i) || is_aboard(i) || (i < (int)convoy_of.size() && convoy_of[i] == c.id)) continue; // own crew stand in their own body
		const int x = (int)std::floor(px[i]), y = (int)std::floor(py[i]);
		if (!terrain.contains(x, y)) continue;
		if (std::binary_search(cells.begin(), cells.end(), terrain.idx(x, y))) return true;
	}
	return false;
}

// Forward-edge fallback. It reads the same edges convoy_reachable checks at order time (edge_ok[here], bit d, towards
// the neighbour), so the anchor can always leave along a route that was accepted, even when the backward field is absent.
bool World::convoy_greedy_direction(const Convoy &c, float &dx, float &dy) const {
	const int hx = (int)c.x, hy = (int)c.y;
	if (!terrain.contains(hx, hy)) return false;
	const int here = terrain.idx(hx, hy);
	float best = (c.x - c.gx) * (c.x - c.gx) + (c.y - c.gy) * (c.y - c.gy);
	bool found = false;
	float bx = 0.f, by = 0.f;
	for (int d = 0; d < 8; ++d) {
		if (!((terrain.edge_ok[here] >> d) & 1)) continue;
		const int nx = hx + DX[d], ny = hy + DY[d];
		if (!terrain.contains(nx, ny)) continue;
		if (!siege_nav_cell(terrain.idx(nx, ny))) continue;
		if (d >= 4 && (!siege_nav_cell(here + DX[d]) || !siege_nav_cell(here + DY[d] * terrain.w))) continue;
		const float gx = (float)nx + 0.5f - c.gx, gy = (float)ny + 0.5f - c.gy;
		const float dist = gx * gx + gy * gy;
		if (dist < best) {
			best = dist;
			bx = (float)nx + 0.5f - c.x; by = (float)ny + 0.5f - c.y;
			found = true;
		}
	}
	if (!found) return false;
	const float len = std::sqrt(bx * bx + by * by);
	if (len < 1e-4f) return false;
	dx = bx / len; dy = by / len;
	return true;
}

bool World::convoy_steer(int i, float dt) {
	if (!is_convoy_crew(i)) return false;
	const Convoy *c = convoy_at(convoy_of[i]);
	if (!c) return false;
	const ConvoyCrew *k = nullptr;
	for (const auto &e : c->crew) if (e.soldier == i) { k = &e; break; }
	if (!k) return false;
	const float p_x = px[i], p_y = py[i];
	if (!can_act(i) || stagger[i] > 0 || knock_t[i] > 0) { // held where it stands, as siege crew are
		nx[i] = p_x; ny[i] = p_y; vx[i] = vy[i] = 0;
		state[i] = captive[i] ? S_CAPTIVE : !alive(i) ? S_DEAD : ko[i] > 0 ? S_DOWN : getup[i] > 0 ? S_GETUP : stagger[i] > 0 ? S_STAGGER : S_SLOT;
		anim_t[i] += dt;
		return true;
	}
	float sx = 0.f, sy = 0.f;
	convoy_slot(*c, *k, sx, sy);
	const float sdx = sx - p_x, sdy = sy - p_y, sd = std::sqrt(sdx * sdx + sdy * sdy);
	float dvx = 0.f, dvy = 0.f;
	if (convoy_evacuation(i, dvx, dvy)) {
		// another vehicle claimed this crew member's cell (its own vehicle is at rest): step out, come back afterwards
	} else if (sd > 1e-4f) {
		// gain 8: at 1.25 x march the crew trails its slot by 0.41 cells, inside convoy_tolerance, so the anchor does not stop-start
		const float sp = std::min(cfg.march_speed * 1.25f, sd * 8.0f);
		dvx = sdx / sd * sp; dvy = sdy / sd * sp;
	}
	float qx = p_x + dvx * dt, qy = p_y + dvy * dt;
	resolve(p_x, p_y, qx, qy, cfg.wall_margin);
	resolve_siege_person(i, p_x, p_y, qx, qy);
	if (terrain.contains((int)std::floor(qx), (int)std::floor(qy)) && siege_claims_cell(terrain.idx((int)std::floor(qx), (int)std::floor(qy)), i)) { qx = p_x; qy = p_y; }
	nx[i] = qx; ny[i] = qy;
	vx[i] = (qx - p_x) / dt; vy[i] = (qy - p_y) / dt;
	if (vx[i] * vx[i] + vy[i] * vy[i] > 0.04f) face[i] = std::atan2(vy[i], vx[i]);
	else face[i] = c->facing;
	state[i] = S_SLOT;
	running[i] = 0;
	anim_t[i] += dt;
	return true;
}

// ---------------------------------------------------------------- G4 vehicles in a formation (OPUS)
// An attached convoy's goal is its vehicle slot in its formation's layout: a rank behind the soldier grid, in the
// formation's quarter frame, so soldier slots and vehicle slots never overlap at rest (convoy_plan_formation). The
// vehicle first turns in place about its body's middle cell, then translates cell centre to cell centre along its own
// route field with its facing fixed. Bodies never overlap; own-team soldiers in the next footprint are asked to step
// out (claims) and the vehicle waits for them; anything else that blocks it makes it wait, and a long wait replans.
static constexpr int kFollowMargin = 12;         // route region margin around the anchor and the goal (cells)
static constexpr uint32_t kSoldierZoneCost = 12; // extra route cost per cell inside the formation's final soldier block
static constexpr uint32_t kTurnCost = 40;        // route cost of a quarter turn (about 4 cells of travel time)
static constexpr int kReplanStages = 20;         // stages without progress before the route is rebuilt around current bodies

// Minimum-cost assignment for a square cost matrix (rows = vehicles in id order, cols = rank positions).
static std::vector<int> min_cost_assignment(const std::vector<std::vector<double>> &a) {
	const int n = (int)a.size();
	const double INF = std::numeric_limits<double>::infinity();
	std::vector<double> u(n + 1, 0.0), v(n + 1, 0.0);
	std::vector<int> p(n + 1, 0), way(n + 1, 0);
	for (int i = 1; i <= n; ++i) {
		p[0] = i;
		int j0 = 0;
		std::vector<double> minv(n + 1, INF);
		std::vector<char> used(n + 1, 0);
		do {
			used[j0] = 1;
			const int i0 = p[j0];
			int j1 = 0;
			double delta = INF;
			for (int j = 1; j <= n; ++j) if (!used[j]) {
				const double cur = a[i0 - 1][j - 1] - u[i0] - v[j];
				if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
				if (minv[j] < delta) { delta = minv[j]; j1 = j; }
			}
			for (int j = 0; j <= n; ++j) {
				if (used[j]) { u[p[j]] += delta; v[j] -= delta; }
				else minv[j] -= delta;
			}
			j0 = j1;
		} while (p[j0] != 0);
		do { const int j1 = way[j0]; p[j0] = p[j1]; j0 = j1; } while (j0 != 0);
	}
	std::vector<int> out(n, -1);
	for (int j = 1; j <= n; ++j) if (p[j] > 0) out[p[j] - 1] = j - 1;
	return out;
}

// Soldier slots by least total squared distance from where the members stand to the slots of the formation's goal pose.
// Bounded to 160 slotted members (O(n^3)); larger formations keep their order.
void World::reslot_formation(Formation &f) {
	std::vector<int> able;
	for (int i : f.members) if (slot[i] >= 0) able.push_back(i);
	const int n = (int)able.size();
	if (n < 2 || n > 160 || n != f.slot_count) return;
	Formation goal = f;
	goal.cx = f.goal_x; goal.cy = f.goal_y; goal.facing = f.goal_facing;
	std::vector<float> sx(n), sy(n);
	for (int s = 0; s < n; ++s) slot_world(goal, s, n, sx[s], sy[s]);
	// a slot that cannot be reached straight from the goal centre (a step, a wall) is clipped toward the centre, as
	// formation_stage does every step: the assignment is made for those clipped places, where people actually go
	for (int s = 0; s < n; ++s) {
		const float c = ray_clip(f.goal_x, f.goal_y, sx[s], sy[s]);
		if (c < 1.f) { sx[s] = f.goal_x + (sx[s] - f.goal_x) * c; sy[s] = f.goal_y + (sy[s] - f.goal_y) * c; }
	}
	std::vector<std::vector<double>> cost((size_t)n, std::vector<double>((size_t)n, 0.0));
	for (int k = 0; k < n; ++k) for (int s = 0; s < n; ++s) {
		const double dx = (double)px[able[k]] - sx[s], dy = (double)py[able[k]] - sy[s];
		cost[k][s] = dx * dx + dy * dy; // squared: many short shifts beat one long walk through the block
	}
	const std::vector<int> assign = min_cost_assignment(cost);
	for (int k = 0; k < n; ++k) slot[able[k]] = assign[k];
}

bool World::formation_has_convoys(int fi) const {
	for (const auto &c : convoys) if (c.formation == fi) return true;
	return false;
}

int World::convoy_formation(int id) const {
	const Convoy *c = convoy_at(id);
	return c ? c->formation : -2;
}

// Attaching is passive: the convoy holds where it stands until the formation's layout key changes (an order, a slot
// count change, another vehicle joining a layout in use). Idle siblings are re-baselined so deployment moves nothing,
// not even the formation's facing. A vehicle leaving (detach, removal) does not re-lay the others: their slots stay valid.
bool World::convoy_attach_formation(int id, int fi) {
	Convoy *c = convoy_at(id);
	if (!c || !finalized_ || fi < 0 || fi >= (int)formations.size() || c->crew.empty() || formations[fi].garrisoned) return false;
	for (const auto &k : c->crew) if (k.soldier < 0 || k.soldier >= soldier_count() || form[k.soldier] != fi) return false;
	if (c->formation == fi) return true;
	// until its first layout the vehicle holds its own cell and facing, so it reads complete (an operator may stop it)
	c->formation = fi; c->field = -1; c->blocked = 0; c->no_slot = false; c->slot_index = -1; c->turn_to = -1; c->move_to = -1;
	c->has_goal = true; c->gx = std::floor(c->x) + 0.5f; c->gy = std::floor(c->y) + 0.5f; c->gfacing = c->facing;
	c->goal_cell = terrain.idx((int)std::floor(c->x), (int)std::floor(c->y));
	c->plan_cost.clear(); c->plan_x0 = c->plan_y0 = c->plan_w = c->plan_h = 0;
	const Formation &f = formations[fi];
	int count = 0;
	bool active = false;
	for (const auto &o : convoys) if (o.formation == fi) { ++count; if (o.slot_index >= 0 || o.no_slot) active = true; }
	for (auto &o : convoys) if (o.formation == fi) {
		if (active) { o.key_q = -1; continue; } // a layout is in use: everyone is reassigned with the new vehicle
		o.key_gx = f.goal_x; o.key_gy = f.goal_y; o.key_q = quarter_of(f.goal_facing); o.key_slots = f.slot_count; o.key_count = count;
	}
	return true;
}

// The convoy keeps its current goal and continues with the single-vehicle steering. The remaining vehicles of the
// formation keep their slots (still valid: a layout never overlaps); the next layout change reassigns them.
bool World::convoy_detach_formation(int id) {
	Convoy *c = convoy_at(id);
	if (!c || c->formation < 0) return false;
	convoy_release_claim(*c);
	c->formation = -1; c->key_q = -1; c->blocked = 0; c->no_slot = false; c->slot_index = -1; c->field = -1; c->turn_to = -1; c->move_to = -1;
	c->plan_cost.clear(); c->plan_x0 = c->plan_y0 = c->plan_w = c->plan_h = 0;
	return true;
}

void World::convoy_invalidate_plans() {
	for (auto &c : convoys) if (c.formation >= 0) { c.key_q = -1; c.plan_cost.clear(); c.plan_x0 = c.plan_y0 = c.plan_w = c.plan_h = 0; }
}

World::ConvoyShape World::convoy_shape(const Convoy &c) const {
	ConvoyShape s;
	for (const auto &o : c.body) s.occupancy.push_back(o);
	for (const auto &k : c.crew) {
		bool seen = false;
		for (const auto &o : s.occupancy) if (o.ox == k.ox && o.oy == k.oy) seen = true;
		if (!seen) s.occupancy.push_back(ConvoyOffset{k.ox, k.oy});
	}
	if (s.occupancy.empty()) s.occupancy.push_back(ConvoyOffset{0, 0});
	s.min_ox = s.max_ox = s.occupancy[0].ox; s.min_oy = s.max_oy = s.occupancy[0].oy;
	for (const auto &o : s.occupancy) { s.min_ox = std::min(s.min_ox, o.ox); s.max_ox = std::max(s.max_ox, o.ox); s.min_oy = std::min(s.min_oy, o.oy); s.max_oy = std::max(s.max_oy, o.oy); }
	// pivot: the middle of the body's bounding box (wagon (1, 0), cart (0, 0))
	if (!c.body.empty()) {
		int bx0 = c.body[0].ox, bx1 = bx0, by0 = c.body[0].oy, by1 = by0;
		for (const auto &o : c.body) { bx0 = std::min(bx0, o.ox); bx1 = std::max(bx1, o.ox); by0 = std::min(by0, o.oy); by1 = std::max(by1, o.oy); }
		s.mid_ox = floor_div(bx0 + bx1, 2); s.mid_oy = floor_div(by0 + by1, 2);
	}
	return s;
}

// Anchor cell `cell` is a route cell for c at quarter q: every body and crew cell is on the map, walkable, not a siege
// body and not a wall of this plan.
bool World::convoy_route_valid(const Convoy &c, int q, int cell, const std::vector<uint8_t> &walls) const {
	const int x = cell % terrain.w, y = cell / terrain.w;
	const ConvoyShape s = convoy_shape(c);
	for (const auto &o : s.occupancy) {
		int ox = 0, oy = 0;
		quarter_rotate(q, o.ox, o.oy, ox, oy);
		const int tx = x + ox, ty = y + oy;
		if (!terrain.contains(tx, ty) || !terrain.walkable(tx, ty)) return false;
		const int v = terrain.idx(tx, ty);
		if (!siege_nav_cell(v) || (!walls.empty() && walls[v])) return false;
	}
	return true;
}

// A turn of a quarter about the pivot cell centre: the cells (offsets from the pivot cell) that the body and crew pass
// through. It contains every pose the turn steps through at the 30 Hz step (step mt, exact landing) and a fine
// sampling besides, so the planner never accepts a turn that the step-by-step check would refuse. dir = +1 or -1.
struct TurnMove { int fx, fy, tx, ty; };
static void turn_sweep_offsets(const World::ConvoyShape &s, int q, int dir, float mt, std::vector<std::pair<int, int>> &out,
	std::vector<TurnMove> &moves) {
	out.clear(); moves.clear();
	const float a0 = quarter_angle(q);
	std::vector<float> ts;
	const int steps = std::max(1, (int)std::ceil(0.5f * kPi / mt));
	for (int k = 0; k <= steps; ++k) ts.push_back(k == steps ? 0.5f * kPi : mt * (float)k);
	for (int k = 0; k <= 96; ++k) ts.push_back(0.5f * kPi * (float)k / 96.f);
	std::sort(ts.begin(), ts.end());
	for (const auto &o : s.occupancy) {
		const float rx = (float)(o.ox - s.mid_ox), ry = (float)(o.oy - s.mid_oy);
		std::pair<int, int> prev{0, 0};
		bool first = true;
		for (const float t : ts) {
			const float a = a0 + (float)dir * t, fx = std::cos(a), fy = std::sin(a);
			const std::pair<int, int> cell{(int)std::floor(0.5f + rx * fx - ry * fy), (int)std::floor(0.5f + rx * fy + ry * fx)};
			if (std::find(out.begin(), out.end(), cell) == out.end()) out.push_back(cell);
			if (!first && cell != prev) {
				bool seen = false;
				for (const auto &m : moves) if (m.fx == prev.first && m.fy == prev.second && m.tx == cell.first && m.ty == cell.second) seen = true;
				if (!seen) moves.push_back(TurnMove{prev.first, prev.second, cell.first, cell.second});
			}
			prev = cell; first = false;
		}
	}
}

// A body or crew point passing from cell (fx, fy) to cell (tx, ty) during a turn crosses legal terrain edges only
// (a person cannot cross a height step; a diagonal needs one legal two-step way round the corner).
static bool turn_move_legal(const Terrain &t, int fx, int fy, int tx, int ty) {
	const int dx = tx - fx, dy = ty - fy;
	if (dx == 0 && dy == 0) return true;
	if (std::abs(dx) > 1 || std::abs(dy) > 1 || !t.contains(fx, fy) || !t.contains(tx, ty)) return false;
	const int h = dx > 0 ? E : W, v = dy > 0 ? S : N;
	if (dy == 0) return t.edge(fx, fy, h);
	if (dx == 0) return t.edge(fx, fy, v);
	return (t.edge(fx, fy, h) && t.edge(fx + dx, fy, v)) || (t.edge(fx, fy, v) && t.edge(fx, fy + dy, h));
}

// Route field over (pivot cell, quarter) states: Dijkstra from the goal state. A state is valid when every body and
// crew cell is walkable, not a siege body and not a wall of this plan. Moves: rigid translation (every body and crew
// cell crosses a legal edge; diagonals need both side states) and a quarter turn about the pivot when the whole sweep
// is valid. Cells covering the formation's final soldier block cost extra, so vehicles go around the block. The
// region is the bounding box of start and goal plus a margin; when the start is not connected there, the whole map.
bool World::convoy_build_route(Convoy &c, const std::vector<uint8_t> &walls, int fi) {
	c.plan_cost.clear(); c.plan_x0 = c.plan_y0 = c.plan_w = c.plan_h = 0;
	if (!c.has_goal || c.goal_cell < 0) return false;
	const ConvoyShape s = convoy_shape(c);
	const int qg = quarter_of(c.gfacing);
	int gmx = 0, gmy = 0;
	quarter_rotate(qg, s.mid_ox, s.mid_oy, gmx, gmy);
	const int gx = c.goal_cell % terrain.w + gmx, gy = c.goal_cell / terrain.w + gmy; // goal pivot cell
	const float cfx = std::cos(c.facing), cfy = std::sin(c.facing);
	const int px0 = (int)std::floor(c.x + (float)s.mid_ox * cfx - (float)s.mid_oy * cfy), py0 = (int)std::floor(c.y + (float)s.mid_ox * cfy + (float)s.mid_oy * cfx);
	const int q0 = quarter_of(c.facing);
	if (!terrain.contains(gx, gy)) return false;
	// relative cells of every quarter, and the two turn sweeps of every quarter
	std::vector<std::pair<int, int>> rel[4], sweep[4][2];
	std::vector<TurnMove> sweep_moves[4][2];
	for (int q = 0; q < 4; ++q) {
		for (const auto &o : s.occupancy) { int ox = 0, oy = 0; quarter_rotate(q, o.ox - s.mid_ox, o.oy - s.mid_oy, ox, oy); rel[q].push_back({ox, oy}); }
		turn_sweep_offsets(s, q, +1, cfg.max_turn_rate / 30.f, sweep[q][0], sweep_moves[q][0]);
		turn_sweep_offsets(s, q, -1, cfg.max_turn_rate / 30.f, sweep[q][1], sweep_moves[q][1]);
	}
	float zx = 0, zy = 0, ze = -1, zw = -1;
	if (fi >= 0 && fi < (int)formations.size()) {
		const Formation &f = formations[fi];
		const int n = f.slot_count;
		if (n > 0) {
			const int cols = std::max(1, std::min(f.cols, n)), rows = (n + cols - 1) / cols;
			ze = (float)(rows - 1) * 0.5f * f.spacing + 0.5f; zw = (float)(cols - 1) * 0.5f * f.spacing + 0.5f;
			zx = f.goal_x; zy = f.goal_y;
		}
	}
	const auto open_cell = [&](int x, int y) {
		if (!terrain.contains(x, y) || !terrain.walkable(x, y)) return false;
		const int v = terrain.idx(x, y);
		return siege_nav_cell(v) && (walls.empty() || !walls[v]);
	};
	for (int pass = 0; pass < 2; ++pass) {
		const int margin = pass == 0 ? kFollowMargin : 4096;
		const int x0 = std::max(0, std::min(px0, gx) - margin), x1 = std::min(terrain.w - 1, std::max(px0, gx) + margin);
		const int y0 = std::max(0, std::min(py0, gy) - margin), y1 = std::min(terrain.h - 1, std::max(py0, gy) + margin);
		const int W = x1 - x0 + 1, H = y1 - y0 + 1;
		const size_t N = (size_t)W * H;
		std::vector<uint8_t> valid(N * 4, 0), zone(N * 4, 0);
		for (int y = y0; y <= y1; ++y) for (int x = x0; x <= x1; ++x) for (int q = 0; q < 4; ++q) {
			const size_t k = ((size_t)(y - y0) * W + (x - x0)) * 4 + q;
			bool ok = true;
			for (const auto &r : rel[q]) if (!open_cell(x + r.first, y + r.second)) { ok = false; break; }
			valid[k] = ok ? 1 : 0;
			if (!ok || ze < 0) continue;
			for (const auto &r : rel[q]) {
				const float rx = (float)(x + r.first) + 0.5f - zx, ry = (float)(y + r.second) + 0.5f - zy;
				const float lx = rx * (float)QX[qg] + ry * (float)QY[qg], ly = -rx * (float)QY[qg] + ry * (float)QX[qg];
				if (std::fabs(lx) <= ze && std::fabs(ly) <= zw) { zone[k] = 1; break; }
			}
		}
		const auto at = [&](int x, int y, int q) -> long long { return (x < x0 || y < y0 || x > x1 || y > y1) ? -1 : (((long long)(y - y0) * W + (x - x0)) * 4 + q); };
		const long long goal_k = at(gx, gy, qg);
		if (goal_k < 0 || !valid[(size_t)goal_k]) return false;
		std::vector<uint32_t> cost(N * 4, UINT32_MAX);
		using Item = std::pair<uint32_t, long long>;
		std::priority_queue<Item, std::vector<Item>, std::greater<Item>> open;
		cost[(size_t)goal_k] = 0;
		open.push({0u, goal_k});
		while (!open.empty()) {
			const Item top = open.top(); open.pop();
			const long long k = top.second;
			if (top.first != cost[(size_t)k]) continue;
			const int q = (int)(k % 4), cell = (int)(k / 4), cx = x0 + cell % W, cy = y0 + cell / W;
			// translations into (cx, cy, q) from (cx - d, cy - d, q)
			for (int d = 0; d < 8; ++d) {
				const int qx = cx - DX[d], qy = cy - DY[d];
				const long long pk = at(qx, qy, q);
				if (pk < 0 || !valid[(size_t)pk]) continue;
				if (d >= 4) {
					const long long s1 = at(qx + DX[d], qy, q), s2 = at(qx, qy + DY[d], q);
					if (s1 < 0 || s2 < 0 || !valid[(size_t)s1] || !valid[(size_t)s2]) continue;
				}
				bool legal = true;
				for (const auto &r : rel[q]) if (!terrain.edge(qx + r.first, qy + r.second, d)) { legal = false; break; }
				if (!legal) continue;
				const uint32_t nc = top.first + (d < 4 ? 10u : 14u) + (zone[(size_t)k] ? kSoldierZoneCost : 0u);
				if (nc < cost[(size_t)pk]) { cost[(size_t)pk] = nc; open.push({nc, pk}); }
			}
			// turns into (cx, cy, q) from (cx, cy, q -/+ 1): the sweep of that turn must be open
			for (int side = 0; side < 2; ++side) {
				const int from = side == 0 ? (q + 3) % 4 : (q + 1) % 4; // from turns +1 (side 0) or -1 (side 1) into q
				const long long pk = at(cx, cy, from);
				if (pk < 0 || !valid[(size_t)pk]) continue;
				bool ok = true;
				for (const auto &r : sweep[from][side]) if (!open_cell(cx + r.first, cy + r.second)) { ok = false; break; }
				if (ok) for (const auto &m : sweep_moves[from][side]) if (!turn_move_legal(terrain, cx + m.fx, cy + m.fy, cx + m.tx, cy + m.ty)) { ok = false; break; }
				if (!ok) continue;
				const uint32_t nc = top.first + kTurnCost;
				if (nc < cost[(size_t)pk]) { cost[(size_t)pk] = nc; open.push({nc, pk}); }
			}
		}
		const long long start = at(px0, py0, q0);
		const bool reached = start >= 0 && cost[(size_t)start] != UINT32_MAX;
		if (reached || pass == 1) {
			c.plan_x0 = x0; c.plan_y0 = y0; c.plan_w = W; c.plan_h = H;
			c.plan_cost = std::move(cost);
			return reached;
		}
	}
	return false;
}

// Marks a convoy shape (body and crew cells) at anchor cell (ax, ay) and quarter q.
static void mark_shape(const World &w, std::vector<uint8_t> &walls, const World::ConvoyShape &s, int ax, int ay, int q) {
	for (const auto &o : s.occupancy) {
		int ox = 0, oy = 0;
		quarter_rotate(q, o.ox, o.oy, ox, oy);
		if (w.terrain.contains(ax + ox, ay + oy)) walls[w.terrain.idx(ax + ox, ay + oy)] = 1;
	}
}

// Walls of a convoy's route: the goal footprints (body and crew) of the other vehicles of its layout, and every other
// convoy's present body and crew cells. The convoy's own goal footprint and its own present cells are never walls.
std::vector<uint8_t> World::convoy_route_walls(const Convoy &c) const {
	std::vector<uint8_t> walls((size_t)terrain.w * terrain.h, 0);
	for (const auto &o : convoys) if (o.id != c.id) {
		if (o.formation == c.formation && c.formation >= 0 && o.has_goal) mark_shape(*this, walls, convoy_shape(o), o.goal_cell % terrain.w, o.goal_cell / terrain.w, quarter_of(o.gfacing));
		for (int v : o.body_cells) walls[v] = 1;
		for (const auto &k : o.crew) if (k.soldier >= 0 && k.soldier < soldier_count() && terrain.contains((int)px[k.soldier], (int)py[k.soldier])) walls[terrain.idx((int)px[k.soldier], (int)py[k.soldier])] = 1;
	}
	if (c.has_goal && c.goal_cell >= 0) {
		std::vector<uint8_t> own((size_t)terrain.w * terrain.h, 0);
		mark_shape(*this, own, convoy_shape(c), c.goal_cell % terrain.w, c.goal_cell / terrain.w, quarter_of(c.gfacing));
		for (size_t v = 0; v < own.size(); ++v) if (own[v]) walls[v] = 0;
	}
	// where the convoy stands now is never a wall of its own route (it may overlap another vehicle's future slot)
	walls[terrain.idx((int)std::floor(c.x), (int)std::floor(c.y))] = 0;
	for (int v : c.body_cells) walls[v] = 0;
	for (const auto &k : c.crew) {
		float sx = 0.f, sy = 0.f;
		convoy_slot(c, k, sx, sy);
		if (terrain.contains((int)std::floor(sx), (int)std::floor(sy))) walls[terrain.idx((int)std::floor(sx), (int)std::floor(sy))] = 0;
	}
	// a standing person who will not step out for this convoy: the route goes round them, and a goal they stand on has
	// no route (the layout is planned again)
	convoy_mark_fixed_people(convoy_team(c), walls);
	return walls;
}

// Cells of standing people (not convoy crew) who will not step out for a convoy of my_team: the host-controlled player,
// another team, a captive, an escort, a siege crew. Someone passing by (|v| > 0.2) is waited for instead.
void World::convoy_mark_fixed_people(int my_team, std::vector<uint8_t> &walls) const {
	for (int i = 0; i < soldier_count(); ++i) {
		if (!alive(i) || is_aboard(i) || is_convoy_crew(i) || convoy_person_yields(i, my_team)) continue;
		if (vx[i] * vx[i] + vy[i] * vy[i] > 0.04f) continue;
		const int x = (int)std::floor(px[i]), y = (int)std::floor(py[i]);
		if (terrain.contains(x, y)) walls[terrain.idx(x, y)] = 1;
	}
}

void World::convoy_plan_formation(int fi) {
	Formation &f = formations[fi];
	std::vector<Convoy *> group;
	for (auto &c : convoys) if (c.formation == fi) group.push_back(&c);
	if (group.empty() || f.host_center) return; // a host-led company re-centres on its leader every step: its vehicles hold
	const int q = quarter_of(f.goal_facing), m = (int)group.size();
	bool stale = false;
	for (const Convoy *c : group)
		if (c->key_q != q || c->key_gx != f.goal_x || c->key_gy != f.goal_y || c->key_slots != f.slot_count) stale = true;
	if (!stale) return;
	f.goal_facing = quarter_angle(q); // a formation with a vehicle layout rests on the layout's quarter facing
	for (Convoy *c : group) { c->key_q = q; c->key_gx = f.goal_x; c->key_gy = f.goal_y; c->key_slots = f.slot_count; c->key_count = m; }
	formations[fi].reslot_pending = true; // soldiers take the nearest final slots when the block arrives
	// soldier grid extent behind the centre, and the front row of the vehicle rank (>= 1 cell behind the rear line)
	const int n = f.slot_count;
	const int cols = std::max(1, std::min(f.cols, std::max(1, n))), rows = n > 0 ? (n + cols - 1) / cols : 0;
	const float E = rows > 0 ? (float)(rows - 1) * 0.5f * f.spacing : 0.f;
	const int c0x = (int)std::floor(f.goal_x), c0y = (int)std::floor(f.goal_y);
	const float u = (f.goal_x - ((float)c0x + 0.5f)) * (float)QX[q] + (f.goal_y - ((float)c0y + 0.5f)) * (float)QY[q];
	const int front = (int)std::floor(-E - 1.5f + u + 1e-3f);
	std::vector<ConvoyShape> shapes;
	int pitch = 2;
	for (const Convoy *c : group) { shapes.push_back(convoy_shape(*c)); pitch = std::max(pitch, shapes.back().max_oy - shapes.back().min_oy + 2); }
	const int lat0 = floor_div((m - 1) * pitch, 2);
	// anchor cell of vehicle v at rank position j, moved `back` cells further back and `side` cells sideways
	const auto nominal = [&](int v, int j, int back, int side, int &X, int &Y) {
		const int lx = front - shapes[v].max_ox - back, ly = j * pitch - lat0 - floor_div(shapes[v].min_oy + shapes[v].max_oy, 2) + side;
		int ox = 0, oy = 0;
		quarter_rotate(q, lx, ly, ox, oy);
		X = c0x + ox; Y = c0y + oy;
	};
	std::vector<std::vector<double>> cost((size_t)m, std::vector<double>((size_t)m, 0.0));
	for (int v = 0; v < m; ++v) for (int j = 0; j < m; ++j) {
		int X = 0, Y = 0;
		nominal(v, j, 0, 0, X, Y);
		const double dx = (double)X + 0.5 - group[v]->x, dy = (double)Y + 0.5 - group[v]->y;
		cost[v][j] = std::sqrt(dx * dx + dy * dy);
	}
	const std::vector<int> assign = min_cost_assignment(cost);
	// fix each slot in id order: the nominal cell, else the first feasible cell further back or sideways
	std::vector<uint8_t> reserved((size_t)terrain.w * terrain.h, 0);
	std::vector<uint8_t> foreign((size_t)terrain.w * terrain.h, 0);
	for (const auto &o : convoys) if (o.formation != fi) for (int v : o.body_cells) foreign[v] = 1;
	convoy_mark_fixed_people(f.team, foreign); // no vehicle place on a person who will not step out
	// fallback candidates: further back and sideways first, then the nearest free place anywhere around the block that
	// keeps one clear cell from the soldier grid (a wall or the map edge behind the block)
	std::vector<std::pair<int, int>> candidates;
	static const int SIDE[7] = {0, 1, -1, 2, -2, 3, -3};
	for (int back = 0; back <= 4; ++back) for (int s = 0; s < 7; ++s) candidates.push_back({-back, SIDE[s]});
	{
		std::vector<std::pair<int, int>> ring;
		for (int dy = -12; dy <= 12; ++dy) for (int dx = -12; dx <= 12; ++dx) ring.push_back({dx, dy});
		std::stable_sort(ring.begin(), ring.end(), [](const std::pair<int, int> &a, const std::pair<int, int> &b) {
			return a.first * a.first + a.second * a.second < b.first * b.first + b.second * b.second; });
		candidates.insert(candidates.end(), ring.begin(), ring.end());
	}
	const float W = n > 0 ? (float)(cols - 1) * 0.5f * f.spacing : 0.f;
	const auto clear_of_block = [&](int v, int X, int Y) {
		if (n <= 0) return true;
		for (const auto &o : shapes[v].occupancy) {
			int ox = 0, oy = 0;
			quarter_rotate(q, o.ox, o.oy, ox, oy);
			const float rx = (float)(X + ox) + 0.5f - f.goal_x, ry = (float)(Y + oy) + 0.5f - f.goal_y;
			const float lx = rx * (float)QX[q] + ry * (float)QY[q], ly = -rx * (float)QY[q] + ry * (float)QX[q];
			if (std::fabs(lx) <= E + 1.f && std::fabs(ly) <= W + 1.f) return false;
		}
		return true;
	};
	std::vector<size_t> chosen((size_t)m, 0);
	for (int v = 0; v < m; ++v) {
		Convoy &c = *group[v];
		const int j = assign[v];
		int X = -1, Y = -1;
		bool found = false;
		for (size_t k = 0; k < candidates.size() && !found; ++k) {
			chosen[v] = k;
			// candidate offsets are in the formation frame: first = along forward (negative = further back), second = lateral
			const int back = -candidates[k].first, side = candidates[k].second;
			nominal(v, j, back, side, X, Y);
			if (!terrain.contains(X, Y)) continue;
			bool ok = convoy_route_valid(c, q, terrain.idx(X, Y), foreign) && (k < 35 || clear_of_block(v, X, Y));
			if (ok) for (const auto &o : shapes[v].occupancy) {
				int ox = 0, oy = 0;
				quarter_rotate(q, o.ox, o.oy, ox, oy);
				if (reserved[terrain.idx(X + ox, Y + oy)]) { ok = false; break; }
			}
			found = ok;
		}
		c.blocked = 0; c.field = -1; c.turn_to = -1; c.move_to = -1;
		c.plan_cost.clear(); c.plan_x0 = c.plan_y0 = c.plan_w = c.plan_h = 0;
		if (!found) { c.has_goal = false; c.no_slot = true; c.slot_index = -1; c.goal_cell = -1; continue; }
		mark_shape(*this, reserved, shapes[v], X, Y, q);
		c.has_goal = true; c.no_slot = false; c.slot_index = j;
		c.gx = (float)X + 0.5f; c.gy = (float)Y + 0.5f; c.gfacing = quarter_angle(q); c.goal_cell = terrain.idx(X, Y);
	}
	// a slot this vehicle cannot reach from where it stands (a wall, a pocket) is exchanged for the next candidate
	// places it can reach, at most 12 tries; otherwise it keeps the slot, waits and re-plans
	for (int v = 0; v < m; ++v) {
		Convoy &c = *group[v];
		if (!c.has_goal || convoy_build_route(c, convoy_route_walls(c), fi)) continue;
		const float ogx = c.gx, ogy = c.gy;
		const int ocell = c.goal_cell;
		std::vector<uint8_t> others = reserved;
		{
			std::vector<uint8_t> own((size_t)terrain.w * terrain.h, 0);
			mark_shape(*this, own, shapes[v], ocell % terrain.w, ocell / terrain.w, q);
			for (size_t k = 0; k < own.size(); ++k) if (own[k]) others[k] = 0;
		}
		bool moved = false;
		int tries = 0;
		for (size_t k = chosen[v] + 1; k < candidates.size() && tries < 12 && !moved; ++k) {
			int X = -1, Y = -1;
			nominal(v, assign[v], -candidates[k].first, candidates[k].second, X, Y);
			if (!terrain.contains(X, Y) || !convoy_route_valid(c, q, terrain.idx(X, Y), foreign) || !(k < 35 || clear_of_block(v, X, Y))) continue;
			bool ok = true;
			for (const auto &o : shapes[v].occupancy) {
				int ox = 0, oy = 0;
				quarter_rotate(q, o.ox, o.oy, ox, oy);
				if (others[terrain.idx(X + ox, Y + oy)]) { ok = false; break; }
			}
			if (!ok) continue;
			++tries;
			c.gx = (float)X + 0.5f; c.gy = (float)Y + 0.5f; c.goal_cell = terrain.idx(X, Y);
			moved = convoy_build_route(c, convoy_route_walls(c), fi);
			if (moved) { reserved = others; mark_shape(*this, reserved, shapes[v], X, Y, q); }
		}
		if (!moved) { c.gx = ogx; c.gy = ogy; c.goal_cell = ocell; convoy_build_route(c, convoy_route_walls(c), fi); }
	}
}

// Cells an attached convoy would occupy: CLEAR, YIELD (only own-team soldiers who can step out stand on new cells;
// `claim` lists the new cells), BODY (another body, another convoy's claim or another vehicle's crew), TERRAIN, SOLDIER
// (anybody else: knocked out, captive, enemy, host-controlled, held by a job). `cells` are sorted body cells, `crew`
// the crew cells (they must be standable, never inside another body).
// own team: the attached formation's, else the crew's (an explicitly ordered convoy)
int World::convoy_team(const Convoy &c) const {
	if (c.formation >= 0 && c.formation < (int)formations.size()) return formations[c.formation].team;
	if (!c.crew.empty() && c.crew[0].soldier >= 0 && c.crew[0].soldier < soldier_count()) return (int)team[c.crew[0].soldier];
	return -1;
}

// a person (not convoy crew) who steps out of a claimed cell for a convoy of my_team
bool World::convoy_person_yields(int i, int my_team) const {
	return (int)team[i] == my_team && can_act(i) && !host_ctl[i] && !captive[i] && escort_mode[i] == 0 && !is_siege_crew(i) && siege_group(i) < 0;
}

int World::convoy_follow_cells(const Convoy &c, const std::vector<int> &cells, const std::vector<int> &crew, std::vector<int> &claim) const {
	claim.clear();
	for (int v : crew) {
		if (v < 0 || !terrain.walkable(v % terrain.w, v / terrain.w) || !siege_nav_cell(v)) return FOLLOW_TERRAIN;
		if (convoy_body_cell(v) && convoy_body_owner[v] != c.id) return FOLLOW_BODY;
		if (!convoy_claim_owner.empty() && convoy_claim_owner[v] != 0 && convoy_claim_owner[v] != c.id) return FOLLOW_BODY;
	}
	for (int v : cells) {
		if (v < 0 || !terrain.walkable(v % terrain.w, v / terrain.w) || !siege_nav_cell(v)) return FOLLOW_TERRAIN;
		if (convoy_body_cell(v) && convoy_body_owner[v] != c.id) return FOLLOW_BODY;
		if (!convoy_claim_owner.empty() && convoy_claim_owner[v] != 0 && convoy_claim_owner[v] != c.id) return FOLLOW_BODY;
	}
	std::vector<int> fresh;
	for (int v : cells) if (!std::binary_search(c.body_cells.begin(), c.body_cells.end(), v)) fresh.push_back(v);
	// the crew's cells are claimed with the body's new cells, so no other vehicle drives into the crew's way
	std::vector<int> reserve = fresh;
	for (int v : crew) if (!std::binary_search(c.body_cells.begin(), c.body_cells.end(), v)) reserve.push_back(v);
	std::sort(reserve.begin(), reserve.end());
	reserve.erase(std::unique(reserve.begin(), reserve.end()), reserve.end());
	if (fresh.empty()) { claim = reserve; return FOLLOW_CLEAR; }
	const int my_team = convoy_team(c);
	bool yield = false, body = false, other = false;
	for (int i = 0; i < soldier_count(); ++i) {
		if (!alive(i) || is_aboard(i) || convoy_of[i] == c.id) continue;
		const int x = (int)std::floor(px[i]), y = (int)std::floor(py[i]);
		if (!terrain.contains(x, y) || !std::binary_search(fresh.begin(), fresh.end(), terrain.idx(x, y))) continue;
		if (is_convoy_crew(i)) {
			// another vehicle's crew: if that vehicle is at rest, its crew steps aside like an own-team soldier;
			// otherwise wait for that vehicle to move on
			const Convoy *o = convoy_at(convoy_of[i]);
			const bool resting = o && (!o->has_goal || (std::fabs(o->x - o->gx) < 1e-4f && std::fabs(o->y - o->gy) < 1e-4f &&
				std::fabs(std::remainder(o->facing - o->gfacing, 2.f * kPi)) < 1e-3f));
			if (resting && (int)team[i] == my_team && can_act(i) && stagger[i] <= 0 && knock_t[i] <= 0) yield = true;
			else body = true;
		}
		else if (convoy_person_yields(i, my_team)) yield = true;
		else other = true;
	}
	if (other) return FOLLOW_SOLDIER;
	if (body) return FOLLOW_BODY;
	claim = reserve;
	return yield ? FOLLOW_YIELD : FOLLOW_CLEAR;
}

// Body cells (sorted) and crew cells of c at a pose; false when a cell is off the map.
bool World::convoy_pose_cells(const Convoy &c, float ax, float ay, float facing, std::vector<int> &cells, std::vector<int> &crew) const {
	crew.clear();
	if (!(ax >= 0.f && ay >= 0.f && ax < (float)terrain.w && ay < (float)terrain.h)) return false;
	if (!convoy_footprint(c, ax, ay, facing, cells)) return false;
	const float fx = std::cos(facing), fy = std::sin(facing);
	crew.push_back(terrain.idx((int)ax, (int)ay)); // the anchor cell must be standable too
	for (const auto &k : c.crew) {
		const float x = ax + (float)k.ox * fx - (float)k.oy * fy, y = ay + (float)k.ox * fy + (float)k.oy * fx;
		if (!(x >= 0.f && y >= 0.f && x < (float)terrain.w && y < (float)terrain.h)) return false;
		crew.push_back(terrain.idx((int)x, (int)y));
	}
	return true;
}

int World::convoy_follow_check(const Convoy &c, float ax, float ay, float facing, std::vector<int> &cells, std::vector<int> &claim) const {
	std::vector<int> crew;
	claim.clear();
	if (!convoy_pose_cells(c, ax, ay, facing, cells, crew)) return FOLLOW_TERRAIN;
	return convoy_follow_cells(c, cells, crew, claim);
}

// Posts c's claim on cells (only cells nobody else claimed) so own-team soldiers step out and nobody else enters.
void World::convoy_post_claim(Convoy &c, const std::vector<int> &cells) {
	if (cells.empty()) return;
	if (convoy_claim_owner.size() != (size_t)terrain.w * terrain.h) convoy_claim_owner.assign((size_t)terrain.w * terrain.h, 0);
	for (int v : cells) if (convoy_claim_owner[v] == 0) { convoy_claim_owner[v] = c.id; c.claim.push_back(v); }
}

void World::convoy_release_claim(Convoy &c) {
	if (!convoy_claim_owner.empty()) for (int v : c.claim) if (v >= 0 && v < (int)convoy_claim_owner.size() && convoy_claim_owner[v] == c.id) convoy_claim_owner[v] = 0;
	c.claim.clear();
}

void World::convoy_follow_stage(Convoy &c, float dt) {
	const int qg = quarter_of(c.gfacing);
	const float stride = cfg.march_speed * 1.25f * dt, mt = cfg.max_turn_rate * dt;
	const bool at_goal = std::fabs(c.x - c.gx) < 1e-4f && std::fabs(c.y - c.gy) < 1e-4f;
	if (at_goal && std::fabs(std::remainder(c.gfacing - c.facing, 2.f * kPi)) < 1e-3f) { c.blocked = 0; c.turn_to = -1; c.move_to = -1; return; }
	const ConvoyShape shape = convoy_shape(c);
	// the pivot (middle of the body) and its cell; a turn runs only with the pivot on its cell centre
	const float cfx = std::cos(c.facing), cfy = std::sin(c.facing);
	const float pvx = c.x + (float)shape.mid_ox * cfx - (float)shape.mid_oy * cfy, pvy = c.y + (float)shape.mid_ox * cfy + (float)shape.mid_oy * cfx;
	const int pcx = (int)std::floor(pvx), pcy = (int)std::floor(pvy);
	const float ccx = (float)pcx + 0.5f, ccy = (float)pcy + 0.5f;
	const bool centred = std::fabs(pvx - ccx) < 2e-3f && std::fabs(pvy - ccy) < 2e-3f;
	const bool mid_turn = std::fabs(std::remainder(c.facing - quarter_angle(quarter_of(c.facing)), 2.f * kPi)) > 1e-3f;
	const int q = quarter_of(c.facing);
	if (c.turn_to >= 0 && !mid_turn && !centred) c.turn_to = -1;
	if (mid_turn) c.move_to = -1;  // a turn starts only on a cell centre
	if (mid_turn && c.turn_to < 0) c.turn_to = q;                 // an unfinished turn (detached or loaded) ends on the nearest quarter
	std::vector<int> cells, claim;
	int result = -1; // -1: no route
	float tx = c.x, ty = c.y, nf = c.facing;
	// anchor of a pose given the pivot point and the facing (the landing pose of a turn is exact)
	const auto anchor_of = [&](float px_, float py_, float facing, bool exact, float &ax, float &ay) {
		if (exact) {
			int ox = 0, oy = 0;
			quarter_rotate(quarter_of(facing), shape.mid_ox, shape.mid_oy, ox, oy);
			ax = px_ - (float)ox; ay = py_ - (float)oy;
		} else {
			const float gx2 = std::cos(facing), gy2 = std::sin(facing);
			ax = px_ - ((float)shape.mid_ox * gx2 - (float)shape.mid_oy * gy2); ay = py_ - ((float)shape.mid_ox * gy2 + (float)shape.mid_oy * gx2);
		}
	};
	// the remaining sweep of a quarter turn toward `to` about the pivot cell centre (body and crew cells of every step)
	const auto turn_verdict = [&](int to, std::vector<int> &sweep_claim) -> int {
		const float target = quarter_angle(to);
		const float remaining = std::remainder(target - c.facing, 2.f * kPi);
		std::vector<int> sweep, sweep_crew, body, crew;
		const int steps = std::max(1, (int)std::ceil(std::fabs(remaining) / mt));
		std::vector<std::pair<int, int>> last(shape.occupancy.size(), {INT32_MIN, INT32_MIN});
		for (int k = 0; k <= steps; ++k) {
			const float a = k == steps ? target : c.facing + (remaining > 0.f ? mt : -mt) * (float)k;
			float ax = 0.f, ay = 0.f;
			anchor_of(ccx, ccy, a, k == steps, ax, ay);
			// every body and crew point moves between neighbouring cells across legal edges only
			const float fx = std::cos(a), fy = std::sin(a);
			for (size_t n = 0; n < shape.occupancy.size(); ++n) {
				const auto &o = shape.occupancy[n];
				const std::pair<int, int> now{(int)std::floor(ax + (float)o.ox * fx - (float)o.oy * fy), (int)std::floor(ay + (float)o.ox * fy + (float)o.oy * fx)};
				if (last[n].first != INT32_MIN && !turn_move_legal(terrain, last[n].first, last[n].second, now.first, now.second)) return (int)FOLLOW_TERRAIN;
				last[n] = now;
			}
			if (k == 0) continue;
			if (!convoy_pose_cells(c, ax, ay, a, body, crew)) return (int)FOLLOW_TERRAIN;
			sweep.insert(sweep.end(), body.begin(), body.end());
			sweep_crew.insert(sweep_crew.end(), crew.begin(), crew.end());
		}
		std::sort(sweep.begin(), sweep.end()); sweep.erase(std::unique(sweep.begin(), sweep.end()), sweep.end());
		std::sort(sweep_crew.begin(), sweep_crew.end()); sweep_crew.erase(std::unique(sweep_crew.begin(), sweep_crew.end()), sweep_crew.end());
		return convoy_follow_cells(c, sweep, sweep_crew, sweep_claim);
	};
	if (!mid_turn && centred && c.turn_to < 0) {
		// choose the next move from the route field: a translation to a neighbour cell or a quarter turn here
		c.move_to = -1;
		const auto cost_at = [&](int x, int y, int qq) -> uint32_t {
			if (c.plan_cost.empty() || x < c.plan_x0 || y < c.plan_y0 || x >= c.plan_x0 + c.plan_w || y >= c.plan_y0 + c.plan_h) return UINT32_MAX;
			return c.plan_cost[((size_t)(y - c.plan_y0) * c.plan_w + (x - c.plan_x0)) * 4 + qq];
		};
		if (c.plan_cost.empty()) convoy_build_route(c, convoy_route_walls(c), c.formation);
		int gmx = 0, gmy = 0;
		quarter_rotate(qg, shape.mid_ox, shape.mid_oy, gmx, gmy);
		const int gpx = c.goal_cell % terrain.w + gmx, gpy = c.goal_cell / terrain.w + gmy;
		if (pcx == gpx && pcy == gpy && q == qg) { tx = c.gx; ty = c.gy; result = FOLLOW_CLEAR; } // centred on the goal
		else {
			const uint32_t here = cost_at(pcx, pcy, q);
			uint32_t best = UINT32_MAX;
			int bd = -1, bturn = 0;
			for (int d = 0; d < 8; ++d) {
				const uint32_t cn = cost_at(pcx + DX[d], pcy + DY[d], q);
				if (cn == UINT32_MAX || (here != UINT32_MAX && cn >= here)) continue;
				if (d >= 4 && (cost_at(pcx + DX[d], pcy, q) == UINT32_MAX || cost_at(pcx, pcy + DY[d], q) == UINT32_MAX)) continue;
				bool legal = true;
				for (const auto &o : shape.occupancy) {
					int ox = 0, oy = 0;
					quarter_rotate(q, o.ox - shape.mid_ox, o.oy - shape.mid_oy, ox, oy);
					if (!terrain.contains(pcx + ox, pcy + oy) || !terrain.edge(pcx + ox, pcy + oy, d)) { legal = false; break; }
				}
				if (legal && cn < best) { best = cn; bd = d; bturn = 0; }
			}
			// a turn is taken only when its sweep is passable now (a cheaper rotated state can be reached by another way
			// than this turn); otherwise the best translation is taken, which still lowers the route cost
			const uint32_t c1 = cost_at(pcx, pcy, (q + 1) % 4), c2 = cost_at(pcx, pcy, (q + 3) % 4);
			const int order[2] = {c2 < c1 ? -1 : 1, c2 < c1 ? 1 : -1};
			for (int dir : order) {
				const uint32_t cn = dir > 0 ? c1 : c2;
				if (cn == UINT32_MAX || (here != UINT32_MAX && cn >= here) || cn >= best) continue;
				std::vector<int> probe;
				const int verdict = turn_verdict((q + 4 + dir) % 4, probe);
				if (verdict == FOLLOW_CLEAR || verdict == FOLLOW_YIELD) { best = cn; bd = -1; bturn = dir; break; }
			}
			if (bturn != 0) c.turn_to = (q + 4 + bturn) % 4; // start a turn now (below)
			else if (bd >= 0) {
				// translate: the pivot to the centre of the next cell
				const float npx = (float)(pcx + DX[bd]) + 0.5f, npy = (float)(pcy + DY[bd]) + 0.5f;
				c.move_to = terrain.idx(pcx + DX[bd], pcy + DY[bd]);
				anchor_of(npx, npy, c.facing, true, tx, ty);
				result = FOLLOW_CLEAR;
			}
		}
	} else if (!mid_turn && !centred && c.turn_to < 0) {
		// between two cells: finish the step to the cell chosen on the last centre (or settle on this cell's centre)
		float npx = ccx, npy = ccy;
		if (c.move_to >= 0) { npx = (float)(c.move_to % terrain.w) + 0.5f; npy = (float)(c.move_to / terrain.w) + 0.5f; }
		anchor_of(npx, npy, c.facing, true, tx, ty);
		result = FOLLOW_CLEAR;
	}
	if (c.turn_to >= 0 && (centred || mid_turn)) {
		// quarter turn about the pivot cell centre toward turn_to. The whole remaining sweep is checked and claimed first.
		const float target = quarter_angle(c.turn_to);
		const float remaining = std::remainder(target - c.facing, 2.f * kPi);
		const int swept = turn_verdict(c.turn_to, claim);
		if (swept == FOLLOW_CLEAR || swept == FOLLOW_YIELD) {
			convoy_post_claim(c, claim);
			const bool land = std::fabs(remaining) <= mt;
			nf = land ? target : c.facing + (remaining > 0.f ? mt : -mt);
			anchor_of(ccx, ccy, nf, land, tx, ty);
			result = convoy_follow_check(c, tx, ty, nf, cells, claim);
			if (result == FOLLOW_CLEAR && land) c.turn_to = -1;
		} else {
			result = swept;
			if (!mid_turn) c.turn_to = -1; // a turn that has not started is chosen again from the (re-planned) field
		}
	} else if (result == FOLLOW_CLEAR) {
		// translate toward the chosen anchor (tx, ty) with the facing fixed; the target pose is checked and claimed one
		// cell ahead so own soldiers step out before the body reaches the cell boundary, and other vehicles keep out
		const float px_ = tx, py_ = ty;
		nf = c.facing;
		const int ahead = convoy_follow_check(c, px_, py_, nf, cells, claim);
		if (ahead == FOLLOW_CLEAR || ahead == FOLLOW_YIELD) {
			convoy_post_claim(c, claim);
			const float dx = px_ - c.x, dy = py_ - c.y, dist = std::sqrt(dx * dx + dy * dy);
			if (dist <= stride) { tx = px_; ty = py_; }
			else { tx = c.x + dx / dist * stride; ty = c.y + dy / dist * stride; }
			result = convoy_follow_check(c, tx, ty, nf, cells, claim);
		} else result = ahead;
	}
	if (result == FOLLOW_CLEAR) {
		set_convoy_cells(c, std::move(cells)); // no-op unless the cell set changed
		c.x = tx; c.y = ty; c.facing = nf;
		c.blocked = 0;
		// claims the body now covers are released (they are body cells)
		if (!c.claim.empty()) {
			std::vector<int> keep;
			for (int v : c.claim) {
				if (std::binary_search(c.body_cells.begin(), c.body_cells.end(), v)) { if (convoy_claim_owner[v] == c.id) convoy_claim_owner[v] = 0; }
				else keep.push_back(v);
			}
			c.claim.swap(keep);
		}
		return;
	}
	if (result == FOLLOW_YIELD) {
		convoy_post_claim(c, claim);
		c.stall_reason = CONVOY_YIELDING;
	} else {
		c.body_stalled = result == FOLLOW_BODY || result == FOLLOW_SOLDIER;
		c.stall_reason = result == FOLLOW_BODY ? CONVOY_BLOCKED_BODY : result == FOLLOW_SOLDIER ? CONVOY_BLOCKED_SOLDIER : result == FOLLOW_TERRAIN ? CONVOY_BLOCKED_TERRAIN : CONVOY_NO_ROUTE;
	}
	if (++c.blocked >= kReplanStages) {
		// a long wait: route again around what stands there now (other bodies and crew)
		// a person who will not step out stands on this vehicle's place (D p12: the player on a cart's operator cell):
		// the formation's vehicle layout is planned again around the people standing there now
		if (!convoy_build_route(c, convoy_route_walls(c), c.formation)) c.key_q = -1;
		c.blocked = 0;
	}
}

// The step-out wish of a standing person whose cell a convoy claimed: toward the nearest unclaimed standable cell (legal
// steps, through claimed cells when needed), the one nearest the person's slot, at run speed. Writes only the caller's velocity wish (parallel soldier pass).
bool World::convoy_evacuation(int i, float &dvx, float &dvy) const {
	if (convoy_claim_owner.empty() || cell[i] < 0 || cell[i] >= (int)convoy_claim_owner.size()) return false;
	const int here = cell[i];
	if (convoy_claim_owner[here] == 0 || convoy_claim_owner[here] == convoy_of[i]) return false;
	const int hx = here % terrain.w, hy = here / terrain.w;
	float tx = slot[i] >= 0 ? slot_tx_[i] : px[i], ty = slot[i] >= 0 ? slot_ty_[i] : py[i];
	if (is_convoy_crew(i)) { // a crew member steps toward the side of its own crew slot
		const Convoy *own = convoy_at(convoy_of[i]);
		if (own) for (const auto &k : own->crew) if (k.soldier == i) convoy_slot(*own, k, tx, ty);
	}
	// cells a person may stand on (claimed ones only to pass through), and legal steps between them
	const auto standable = [&](int x, int y) {
		if (!terrain.contains(x, y) || !terrain.walkable(x, y)) return false;
		const int v = terrain.idx(x, y);
		return siege_route_cell(v) && !siege_claims_cell(v, i);
	};
	const auto step_ok = [&](int x, int y, int d) {
		const int nx_ = x + DX[d], ny_ = y + DY[d];
		if (!standable(nx_, ny_) || !terrain.edge(x, y, d)) return false;
		return d < 4 || (standable(x + DX[d], y) && standable(x, y + DY[d]));
	};
	// breadth-first over legal steps, through claimed cells, to the nearest unclaimed cell (at most 6 steps): the free
	// cell nearest the person's slot among the closest ones is the goal; the person steps toward its first cell
	const int R = 6, S = 2 * R + 1;
	std::vector<int> dist((size_t)S * S, -1), first((size_t)S * S, -1);
	std::vector<int> queue;
	const auto key = [&](int x, int y) { return (y - hy + R) * S + (x - hx + R); };
	dist[(size_t)key(hx, hy)] = 0;
	queue.push_back(here);
	int found_dist = -1;
	float best = 1e30f;
	int bfirst = -1;
	for (size_t h = 0; h < queue.size(); ++h) {
		const int cx = queue[h] % terrain.w, cy = queue[h] / terrain.w, cd = dist[(size_t)key(cx, cy)];
		if (found_dist >= 0 && cd >= found_dist) break;
		for (int d = 0; d < 8; ++d) {
			const int nx_ = cx + DX[d], ny_ = cy + DY[d];
			if (std::abs(nx_ - hx) > R || std::abs(ny_ - hy) > R || dist[(size_t)key(nx_, ny_)] >= 0 || !step_ok(cx, cy, d)) continue;
			const int k = key(nx_, ny_);
			dist[(size_t)k] = cd + 1;
			first[(size_t)k] = cd == 0 ? d : first[(size_t)key(cx, cy)];
			const int v = terrain.idx(nx_, ny_);
			if (convoy_claim_owner[v] == 0) {
				const float ex = (float)nx_ + 0.5f - tx, ey = (float)ny_ + 0.5f - ty, score = ex * ex + ey * ey;
				if (found_dist < 0 || score < best) { found_dist = cd + 1; best = score; bfirst = first[(size_t)k]; }
			} else queue.push_back(v);
		}
	}
	if (bfirst < 0) return false;
	const int bd = bfirst;
	const float gx = (float)(hx + DX[bd]) + 0.5f - px[i], gy = (float)(hy + DY[bd]) + 0.5f - py[i], gd = std::sqrt(gx * gx + gy * gy);
	if (gd < 1e-4f) return false;
	dvx = gx / gd * cfg.run_speed; dvy = gy / gd * cfg.run_speed;
	return true;
}

// ---------------------------------------------------------------- present
int World::pack_render(std::vector<float> &out, float cell_pixels) {
	const int n = soldier_count();
	std::vector<uint32_t> &keys = sort_a_, &idx = sort_b_;
	keys.clear(); idx.clear();
	for (int i = 0; i < n; ++i)
		if (alive(i)) {
			keys.push_back((uint32_t)std::clamp(py[i] * 64.f, 0.f, 65535.f));
			idx.push_back((uint32_t)i);
		}
	const int m = (int)keys.size();
	static thread_local std::vector<uint32_t> keys2, idx2;
	keys2.resize(m); idx2.resize(m);
	for (int pass = 0; pass < 2; ++pass) {
		int shift = pass * 8;
		uint32_t count[257] = {0};
		for (int k = 0; k < m; ++k) count[((keys[k] >> shift) & 255) + 1]++;
		for (int c = 0; c < 256; ++c) count[c + 1] += count[c];
		for (int k = 0; k < m; ++k) {
			uint32_t pos = count[(keys[k] >> shift) & 255]++;
			keys2[pos] = keys[k]; idx2[pos] = idx[k];
		}
		std::swap(keys, keys2); std::swap(idx, idx2);
	}
	out.resize((size_t)m * 12);
	const int chunks = (m + cfg.chunk - 1) / cfg.chunk;
	pool_.run(chunks, [&](int ch) {
		int a = ch * cfg.chunk, b = std::min(m, a + cfg.chunk);
		for (int k = a; k < b; ++k) {
			int i = (int)idx[k];
			float *o = &out[(size_t)k * 12];
			o[0] = 1; o[1] = 0; o[2] = 0; o[3] = px[i] * cell_pixels;
			o[4] = 0; o[5] = 1; o[6] = 0; o[7] = py[i] * cell_pixels;
			o[8] = (float)state[i];
			o[9] = (float)((int)(anim_t[i] * 12.f) & 7);
			o[10] = (float)team[i];
			float a8 = std::round(face[i] / (kPi / 4));
			o[11] = (float)(((int)a8 % 8 + 8) % 8);
		}
	});
	return m;
}

void World::measure() {
	const int n = soldier_count();
	const float R2 = cfg.radius * cfg.radius;
	uint64_t cnt = 0;
	build_hash();
	for (int i = 0; i < n; ++i) {
		if (!alive(i) || ko[i] > 0) continue;
		int cx = (int)px[i], cy = (int)py[i];
		for (int yy = std::max(0, cy - 1); yy <= std::min(terrain.h - 1, cy + 1); ++yy)
			for (int xx = std::max(0, cx - 1); xx <= std::min(terrain.w - 1, cx + 1); ++xx) {
				int c = terrain.idx(xx, yy);
				for (int k = hash_start_[c]; k < hash_start_[c + 1]; ++k) {
					int j = hash_items_[k];
					if (j <= i || ko[j] > 0) continue;
					float dx = px[i] - px[j], dy = py[i] - py[j];
					if (dx * dx + dy * dy < R2) ++cnt;
				}
			}
	}
	stats.deep_overlap_pairs = cnt;
	int fighting = 0, engaging = 0, al = 0, down = 0, cap = 0;
	for (int i = 0; i < n; ++i) {
		if (!alive(i)) continue;
		++al;
		if (state[i] == S_FIGHT) ++fighting;
		if (state[i] == S_ENGAGE || state[i] == S_ENCIRCLE) ++engaging;
		if (ko[i] > 0) ++down;
		if (captive[i]) ++cap;
	}
	stats.fighting = fighting; stats.engaging = engaging; stats.alive = al; stats.down = down; stats.captive = cap;
}

uint64_t World::state_hash() const {
	// Full simulation state (Astra review 2026-09-29): every soldier array that feeds the next step,
	// projectiles in flight, formation orders / command / timers / RNG, and the world counters.
	// Derived scratch (spatial hash, block counts, render buffers, flow-field caches) is excluded;
	// it is rebuilt from this state. Stats counters are excluded (reporting only).
	uint64_t h = 1469598103934665603ull;
	auto mixb = [&](const void *p, size_t len) {
		const uint8_t *b = (const uint8_t *)p;
		for (size_t k = 0; k < len; ++k) { h ^= b[k]; h *= 1099511628211ull; }
	};
	auto mv = [&](const auto &v) { if (!v.empty()) mixb(v.data(), v.size() * sizeof(v[0])); };
	auto m = [&](const auto &x) { mixb(&x, sizeof(x)); };
	m(terrain.w); m(terrain.h);
	for (const auto *v : {&terrain.height, &terrain.flags, &terrain.ramp_edges, &terrain.static_blocked, &terrain.facility, &terrain.base_height}) mv(*v);
	for (auto *v : {&px, &py, &nx, &ny, &vx, &vy, &face, &anim_t, &knock_dx, &knock_dy}) mv(*v);
	mv(rest_hold); mv(rest_x); mv(rest_y); mv(rest_best); mv(rest_t);
	for (auto *v : {&hp, &stun, &grace, &ko, &getup, &stagger, &exch_cd, &ranged_cd, &skill_cd, &knock_t, &act_t, &escape_t}) mv(*v);
	for (auto *v : {&team, &state, &los_ok, &skill, &role, &captive, &present, &troop, &running, &near_enemy, &fire_blocked, &bandaged}) mv(*v);
	for (auto *v : {&host_ctl, &host_run, &host_engage}) mv(*v);
	mv(prison_id); mv(escort_goal); mv(escort_mode); mv(housing_attendance_cell);
	mv(contact_revision);
	mv(siege_crew); mv(siege_member_group); mv(siege_step_source); mv(siege_person_blocked);
	for(const auto &cells:siege_wreck_exit)mv(cells); // Derived person-purpose inputs are rebuilt by Site after load.
	for (const auto &g:siege_compounds) {
		m(g.token); m(g.elapsed); m(g.duration); m(g.cancelled); m(g.complete); m(g.aborted); mv(g.claims); mv(g.heights);
		for (const auto &member:g.members) { m(member.soldier); m(member.person); m(member.from); m(member.to); }
	}
	mv(host_vx); mv(host_vy);
	mv(convoy_of); m(convoy_serial);
	for (const auto &cv : convoys) {
		m(cv.id); m(cv.x); m(cv.y); m(cv.facing); m(cv.has_goal); m(cv.gx); m(cv.gy); m(cv.gfacing); m(cv.goal_cell); m(cv.field);
		mv(cv.crew); mv(cv.body); m(cv.body_stalled); m(cv.stall_reason); // body_cells are derived from the hashed anchor, facing and offsets
		m(cv.formation); m(cv.key_gx); m(cv.key_gy); m(cv.key_q); m(cv.key_slots); m(cv.key_count); m(cv.slot_index); m(cv.blocked); m(cv.no_slot); m(cv.turn_to); m(cv.move_to);
		m(cv.plan_x0); m(cv.plan_y0); m(cv.plan_w); m(cv.plan_h); mv(cv.plan_cost); mv(cv.claim);
	}
	for (auto *v : {&form, &slot, &target, &cell, &enc_target, &rescue_of, &capture_of, &captor, &rescued_by_, &capturing_by_}) mv(*v);
	mv(ammo); mv(person_id);
	mv(military_role); mv(post_holder); mv(released); mv(aboard); mv(aboard_vehicle); mv(absent); mv(absent_kind); mv(surrendered);
	for (const auto &e : equip) { m(e.family); m(e.material); m(e.armor); m(e.shield); }
	for (const auto &c : ability) { m(c.tactics); m(c.leadership); m(c.coach); }
	for (const auto &p : projectiles) {
		m(p.shooter); m(p.faction); m(p.shooter_id); m(p.shot_id); m(p.source.x); m(p.source.y); m(p.target.x); m(p.target.y); m(p.left); m(p.source_eye); m(p.goal_eye);
		m(p.stats.ability); m(p.stats.training); m(p.stats.fatigue); m(p.stats.skill);
		m(p.stats.equip.family); m(p.stats.equip.material); m(p.stats.equip.armor); m(p.stats.equip.shield);
	}
	for (int v : rescuers_) m(v);
	for (int v : capturers_) m(v);
	for (int v : captives_) m(v);
	for (const auto &f : formations) {
		m(f.team); m(f.troop); m(f.order); m(f.cx); m(f.cy); m(f.facing); m(f.goal_x); m(f.goal_y); m(f.goal_facing);
		m(f.arrived); m(f.los_goal); m(f.roster); m(f.slot_count); m(f.compact_t); mv(f.members);
		m(f.target_person); m(f.origin_x); m(f.origin_y); m(f.pursuit_left); m(f.order_delay); m(f.attacking); m(f.needs_attack_order);
		m(f.formal_cmd); m(f.acting_cmd); m(f.current_cmd); mv(f.officer_order); m(f.ref_x); m(f.ref_y); m(f.ref_valid); m(f.rng);
		m(f.training); m(f.morale); m(f.rally_rest); m(f.routed); m(f.fatigue); m(f.fatigue_rest); m(f.fatigue_count);
		m(f.recovery_multiplier); m(f.housing_recovery_multiplier); // Pending host inputs affect the next step, never KW06 layout.
		m(f.contact_age); m(f.in_contact); m(f.threat); m(f.ai_enabled); m(f.ai_recovering); m(f.ai_order_cd); m(f.ai_chase_cd);
		m(f.ai_target); m(f.ai_status); m(f.encircle_t);
		m(f.no_orders); m(f.host_center); m(f.fully_fed); m(f.sustain_morale_delta);
		m(f.garrisoned); m(f.reslot_pending); m(f.rest_gx); m(f.rest_gy); m(f.rest_gf); m(f.rest_slots);
		m(f.cols); m(f.spacing); m(f.field); m(f.lag); m(f.command_dirty); m(f.commander_present); m(f.resupplying); m(f.charged_this_step);
	}
	m(tick); m(exchange_round); m(shot_serial); m(time);
	m(host_ranged_delegate); m(host_last_release_id);
	m(combat_left); m(game_dt); m(combat_mark); m(external_clock);
	mv(life_ck); mv(hostile_); mv(slot_tx_); mv(slot_ty_); mv(slot_clip_); mv(lag_acc_); mv(lag_cnt_); mv(attackers_); m(attackers_tick_); mv(touch_); mv(field_queue_);
	for(const auto &f:fields_) {m(f.goal);m(f.last_used);m(f.body_aware);const bool built=!f.dir.empty();m(built);}
	for(const auto &e:events) {m(e.kind);m(e.soldier);m(e.formation);m(e.person);m(e.other);m(e.time);m(e.fatigue);m(e.fatigue_rest);}
	m(cfg.radius);
	m(cfg.wall_margin);
	m(cfg.march_speed);
	m(cfg.run_speed);
	m(cfg.max_turn_rate);
	m(cfg.engage_radius);
	m(cfg.reach);
	m(cfg.leash);
	m(cfg.encircle_cells);
	m(cfg.encircle_budget);
	m(cfg.ranged_keep);
	m(cfg.ranged_leash);
	m(cfg.ally_push);
	m(cfg.enemy_push);
	m(cfg.push_clamp);
	m(cfg.los_period);
	m(cfg.contact_period);
	m(cfg.los_max_cells);
	m(cfg.chunk);
	m(cfg.max_fields_per_step);
	m(cfg.ko_seconds);
	m(cfg.rescued_ko_seconds);
	m(cfg.bleed_per_game_hour);
	m(cfg.rescue_seek_cells);
	m(cfg.auto_capture);
	m(cfg.capture_seek_cells);
	m(cfg.speed);
	m(cfg.combat_grace);
	m(cfg.shot_grace);
	m(cfg.seed);
	m(cfg.ai);

	return h;
}

} // namespace wg
