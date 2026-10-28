// Movement core: terrain edges, flow fields, formations, soldiers, hash, render packing.
#include "crowd_core.hpp"
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
	if(changed && invalidate_fields) {
		fields_.clear();field_queue_.clear();
		for(auto &f:formations){f.field=-1;f.los_goal=false;}
		for(auto &f:formations)if(!f.arrived && f.order!=Order::HOLD)f.field=request_field(nearest_walkable(terrain.idx(int(f.goal_x),int(f.goal_y))));
		std::fill(los_ok.begin(),los_ok.end(),0);
	}
	return true;
}

bool World::siege_person_cell(int i,int from,int to) const {
	if(siege_route_cell(to))return true;
	if(i<0 || i>=(int)siege_wreck_exit.size())return false;
	const auto &allowed=siege_wreck_exit[i];
	return std::find(allowed.begin(),allowed.end(),from)!=allowed.end() && std::find(allowed.begin(),allowed.end(),to)!=allowed.end();
}

void World::resolve_siege_person(int i,float ox,float oy,float &x,float &y) const {
	if(siege_person_blocked.empty())return;
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
	// Validate the entire new terrain before cancelling any original commitment.
	for (size_t k=0;k<abort.size();++k) if (abort[k]) abort_siege_compound((int)k);
	for(int i=0;i<soldier_count();++i)if(abort_single[i]) {
		const int source=siege_step_source[i];px[i]=nx[i]=float(source%terrain.w)+.5f;py[i]=ny[i]=float(source/terrain.w)+.5f;cell[i]=source;vx[i]=vy[i]=0;knock_t[i]=0;escort_goal[i]=-1;escort_mode[i]=0;siege_step_source[i]=-1;
	}
	const auto old_heights = terrain.height;
	terrain = std::move(ground);
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
		if (std::find(ignored.begin(), ignored.end(), person_id[i]) != ignored.end()) continue;
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

int World::request_field(int goal_cell) {
	goal_cell = nearest_walkable(goal_cell);
	for (size_t k = 0; k < fields_.size(); ++k)
		if (fields_[k].goal == goal_cell) { fields_[k].last_used = tick; return (int)k; }
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
	f.goal = goal_cell; f.last_used = tick; f.dir.clear(); f.cost.clear();
	field_queue_.push_back(slot_index);
	return slot_index;
}

void World::build_field(FlowField &f) {
	const int n = terrain.w * terrain.h;
	const uint32_t INF = std::numeric_limits<uint32_t>::max();
	f.cost.assign(n, INF);
	f.dir.assign(n, 255);
	std::vector<int> buckets[16];
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
				if (!siege_route_cell(nb) || (d>=4 && (!siege_route_cell(c+DX[d]) || !siege_route_cell(c+DY[d]*terrain.w)))) continue;
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
	f.order = Order::HOLD; f.attacking = false; f.target_person = -1;
	f.goal_x = f.cx; f.goal_y = f.cy; f.arrived = true; f.goal_facing = f.facing;
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
	set_goal(f, gx, gy);
	clear_encircle(*this, f);
}

// ---------------------------------------------------------------- geometry
bool World::los(float ax, float ay, float bx, float by, const std::vector<int> *rescue_domain) const {
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
	for (int guard = 0; guard < 4 * cfg.los_max_cells + 4; ++guard) {
		const int crossed = terrain.idx(x, y);
		// Only rescue_stage supplies the original patient's invalid-surface
		// domain. Terrain edges and every unrelated siege body stay blocking.
		if (!siege_route_cell(crossed) && (rescue_domain == nullptr ||
		    std::find(rescue_domain->begin(), rescue_domain->end(), crossed) == rescue_domain->end())) return false;
		if (x == tx && y == ty) return true;
		if (std::fabs(tmx - tmy) < 1e-6f) {
			int d = sx > 0 ? (sy > 0 ? SE : NE) : (sy > 0 ? SW : NW);
			if (!terrain.edge(x, y, d)) return false;
			if (rescue_domain != nullptr) {
				// This exceptional rescue ray may cross only its own wreck,
				// including the two side cells of a diagonal corner.
				for (int side : {terrain.idx(x + sx, y), terrain.idx(x, y + sy)})
					if (!siege_route_cell(side) && std::find(rescue_domain->begin(), rescue_domain->end(), side) == rescue_domain->end()) return false;
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
		if (std::fabs(tmx - tmy) < 1e-6f) {
			int d = sx > 0 ? (sy > 0 ? SE : NE) : (sy > 0 ? SW : NW);
			if (!terrain.edge(x, y, d)) return std::max(0.f, tc - back);
			x += sx; y += sy; tmx += tdx; tmy += tdy;
		} else if (tmx < tmy) {
			if (!terrain.edge(x, y, sx > 0 ? E : W)) return std::max(0.f, tc - back);
			x += sx; tmx += tdx;
		} else {
			if (!terrain.edge(x, y, sy > 0 ? S : N)) return std::max(0.f, tc - back);
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
		hash_start_[c + 1]++;
		if (can_act(i)) block_count_[faction_slot_[team[i]]][(y >> 3) * bw_ + (x >> 3)]++;
	}
	for (int c = 0; c < cells; ++c) hash_start_[c + 1] += hash_start_[c];
	std::vector<int32_t> fill(hash_start_.begin(), hash_start_.end() - 1);
	for (int i = 0; i < n; ++i)
		if (alive(i)) hash_items_[fill[cell[i]]++] = i;
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
				if ((tick + fi) % 8 == 0) f.los_goal = los(f.cx, f.cy, f.goal_x, f.goal_y);
				float dirx = dx / dist, diry = dy / dist;
				if (!f.los_goal && f.field >= 0 && !fields_[f.field].dir.empty()) {
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
				} else if (!f.los_goal) {
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
		for (int i : f.members) {
			if (slot[i] < 0) continue;
			float x, y;
			slot_world(f, slot[i], m, x, y);
			if ((tick + (uint32_t)i) % 4 == 0) slot_clip_[i] = ray_clip(f.cx, f.cy, x, y);
			float c = slot_clip_[i];
			if (c < 1.f) { x = f.cx + (x - f.cx) * c; y = f.cy + (y - f.cy) * c; }
			slot_tx_[i] = x; slot_ty_[i] = y;
		}
	}
}

// ---------------------------------------------------------------- contact (nearest able enemy, threat bit)
void World::contact_stage(int ch) {
	const int n = soldier_count();
	const int a = ch * cfg.chunk, b = std::min(n, a + cfg.chunk);
	for (int i = a; i < b; ++i) {
		if (!can_act(i)) { target[i] = -1; near_enemy[i] = 0; continue; }
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
		if (move_siege_member(i,dt)) continue;
		if (convoy_steer(i, dt)) continue; // convoy crew: steered to their convoy slot, never by ordinary motion
		if (is_siege_crew(i) && !controlled_step_pending(i)) {
			nx[i]=px[i]; ny[i]=py[i]; vx[i]=vy[i]=0;
			state[i]=!alive(i)?S_DEAD:ko[i]>0?S_DOWN:getup[i]>0?S_GETUP:stagger[i]>0?S_STAGGER:S_SLOT;
			anim_t[i]+=dt; continue;
		}
		const bool committed = controlled_step_pending(i);
		if (!alive(i) && !committed) { nx[i] = px[i]; ny[i] = py[i]; vx[i] = vy[i] = 0; state[i] = S_DEAD; continue; }
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
		float blend = sliding || escorting ? 1.f : 0.4f;
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
		if (j == i || !can_act(j) || !hostile(team[i], team[j])) continue;
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
		if (!can_act(i)) continue;
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
		if (can_act(i) || getup[i] > 0) able.push_back(i);
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
	if (!terrain.walkable((int)ax, (int)ay) || !siege_route_cell(terrain.idx((int)ax, (int)ay))) return 0;
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
		return true;
	}
	if (ox < -8 || ox > 8 || oy < -8 || oy > 8) return false;
	if (at != c->crew.end()) { at->ox = ox; at->oy = oy; return true; }
	if (c->crew.size() >= 64 || convoy_of[i] != 0 || is_siege_crew(i) || !can_act(i) || escort_mode[i] != 0 || escort_goal[i] >= 0 || siege_group(i) >= 0 ||
	    rescue_of[i] >= 0 || capture_of[i] >= 0 || prison_id[i] != 0 || captive[i] || host_ctl[i] || formations[form[i]].garrisoned) return false;
	c->crew.push_back(ConvoyCrew{i, ox, oy});
	convoy_of[i] = id;
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
			if (!seen[q] && siege_route_cell(q) && (d < 4 || (siege_route_cell(c + DX[d]) && siege_route_cell(c + DY[d] * terrain.w)))) { seen[q] = 1; queue.push_back(q); }
		}
	}
	return seen[goal] != 0;
}

bool World::convoy_order_goal(int id, float gx, float gy, float gfacing) {
	Convoy *c = convoy_at(id);
	if (!c || !finalized_ || !std::isfinite(gx) || !std::isfinite(gy) || !std::isfinite(gfacing)) return false;
	if (gx < 0 || gy < 0 || gx >= (float)terrain.w || gy >= (float)terrain.h) return false;
	const int goal = terrain.idx((int)gx, (int)gy);
	if (!terrain.walkable((int)gx, (int)gy) || !siege_route_cell(goal) || !convoy_reachable(terrain.idx((int)c->x, (int)c->y), goal)) return false;
	c->has_goal = true;
	c->gx = std::floor(gx) + 0.5f; c->gy = std::floor(gy) + 0.5f;
	c->gfacing = gfacing; c->goal_cell = goal;
	c->field = request_field(goal);
	return true;
}

bool World::convoy_set_body(int id, const std::vector<int> &cells) {
	Convoy *c = convoy_at(id);
	if (!c || cells.size() > 64) return false;
	const int count = terrain.w * terrain.h;
	std::vector<int> footprint;
	for (int v : cells) {
		if (v < 0 || v >= count || !terrain.walkable(v % terrain.w, v / terrain.w) || std::find(footprint.begin(), footprint.end(), v) != footprint.end()) return false;
		footprint.push_back(v);
	}
	c->body = std::move(footprint);
	return true;
}

bool World::convoy_state(int id, ConvoyState &out) const {
	const Convoy *c = convoy_at(id);
	if (!c) return false;
	bool stalled = false;
	for (const auto &k : c->crew) if (k.soldier < 0 || k.soldier >= soldier_count() || !can_act(k.soldier)) stalled = true;
	const bool at_goal = c->has_goal && std::fabs(c->x - c->gx) < 1e-4f && std::fabs(c->y - c->gy) < 1e-4f;
	const bool faced = c->has_goal && std::fabs(std::remainder(c->facing - c->gfacing, 2.f * kPi)) < 1e-3f;
	const bool complete = at_goal && faced;
	out.x = c->x; out.y = c->y; out.facing = c->facing;
	out.stalled = stalled ? 1 : 0;
	out.complete = complete ? 1 : 0;
	out.moving = (c->has_goal && !complete && !stalled && !c->crew.empty()) ? 1 : 0;
	return true;
}

bool World::convoy_remove(int id) {
	for (auto at = convoys.begin(); at != convoys.end(); ++at) if (at->id == id) {
		for (const auto &k : at->crew) if (k.soldier >= 0 && k.soldier < (int)convoy_of.size()) convoy_of[k.soldier] = 0;
		convoys.erase(at);
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
	for (auto &c : convoys) {
		if (!c.has_goal || !convoy_crew_aligned(c)) continue; // stalled, or a crew member is not yet on its slot: the anchor waits
		const float ex = c.gx - c.x, ey = c.gy - c.y, ed = std::sqrt(ex * ex + ey * ey);
		const bool straight = los(c.x, c.y, c.gx, c.gy);
		const float stride = cfg.march_speed * dt;
		float desired = c.facing; // no movement this step: hold the facing
		if (straight && ed <= stride) { // the goal is within one step on a clear line: land exactly on it
			c.x = c.gx; c.y = c.gy;
			desired = c.gfacing;
		} else {
			float dirx = 0.f, diry = 0.f;
			bool have = false;
			if (straight) {
				dirx = ex / ed; diry = ey / ed; have = true;
			} else {
				if (c.field < 0 || c.field >= (int)fields_.size() || fields_[c.field].goal != c.goal_cell) c.field = request_field(c.goal_cell);
				const FlowField &ff = fields_[c.field];
				if (!ff.dir.empty()) {
					int x = (int)c.x, y = (int)c.y, bx = -1, by = -1;
					for (int k = 0; k < 6; ++k) {
						const uint8_t d = ff.dir[terrain.idx(x, y)];
						if (d == 255) break;
						x += DX[d]; y += DY[d];
						if (k == 0 || los(c.x, c.y, (float)x + 0.5f, (float)y + 0.5f)) { bx = x; by = y; }
						else break;
					}
					if (bx >= 0) {
						const float ax = (float)bx + 0.5f - c.x, ay = (float)by + 0.5f - c.y, al = std::sqrt(ax * ax + ay * ay);
						if (al > 1e-4f) { dirx = ax / al; diry = ay / al; have = true; }
					}
				}
			}
			if (have) {
				float tx = c.x + dirx * stride, ty = c.y + diry * stride;
				resolve(c.x, c.y, tx, ty, cfg.wall_margin);
				// the anchor never enters unwalkable ground or a cell the crowd may not route through
				if (terrain.walkable_f(tx, ty) && siege_route_cell(terrain.idx((int)tx, (int)ty))) {
					c.x = tx; c.y = ty;
					desired = std::atan2(diry, dirx);
				}
			}
		}
		const float df = std::remainder(desired - c.facing, 2.f * kPi);
		const float mt = cfg.max_turn_rate * dt;
		c.facing += std::clamp(df, -mt, mt);
	}
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
	if (sd > 1e-4f) {
		const float sp = std::min(cfg.march_speed * 1.25f, sd * 3.0f);
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
		mv(cv.crew); mv(cv.body);
	}
	for (auto *v : {&form, &slot, &target, &cell, &enc_target, &rescue_of, &capture_of, &captor, &rescued_by_, &capturing_by_}) mv(*v);
	mv(ammo); mv(person_id);
	mv(military_role); mv(post_holder); mv(released);
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
		m(f.garrisoned);
		m(f.cols); m(f.spacing); m(f.field); m(f.lag); m(f.command_dirty); m(f.commander_present); m(f.resupplying); m(f.charged_this_step);
	}
	m(tick); m(exchange_round); m(shot_serial); m(time);
	m(host_ranged_delegate); m(host_last_release_id);
	m(combat_left); m(game_dt); m(combat_mark); m(external_clock);
	mv(life_ck); mv(hostile_); mv(slot_tx_); mv(slot_ty_); mv(slot_clip_); mv(lag_acc_); mv(lag_cnt_); mv(attackers_); m(attackers_tick_); mv(touch_); mv(field_queue_);
	for(const auto &f:fields_) {m(f.goal);m(f.last_used);const bool built=!f.dir.empty();m(built);}
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
