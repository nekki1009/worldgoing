// FormationTransitPlanner.calculate_transit_slots, synchronous and call-local.
// Original owner dictionaries are borrowed; all writes go to a result packet.
struct TrCell {
    int32_t x = -1, y = -1;
    bool operator==(TrCell b) const { return x == b.x && y == b.y; }
    bool operator!=(TrCell b) const { return !(*this == b); }
    TrCell operator+(TrCell b) const { return {x + b.x, y + b.y}; }
    TrCell operator-(TrCell b) const { return {x - b.x, y - b.y}; }
    TrCell operator*(int n) const { return {x * n, y * n}; }
};
struct TrHash { size_t operator()(TrCell c) const { return (uint64_t(uint32_t(c.x)) << 32) | uint32_t(c.y); } };
struct TrValue {
    VariantStorage v;
    explicit TrValue(GDExtensionVariantType t = NIL) { GDExtensionCallError e{}; variant_construct(t, &v, nullptr, 0, &e); }
    explicit TrValue(const void *p) { copy_variant(&v, p); }
    TrValue(const TrValue &o) { copy_variant(&v, &o.v); }
    TrValue &operator=(const TrValue &o) { if (this != &o) { destroy(&v); copy_variant(&v, &o.v); } return *this; }
    ~TrValue() { destroy(&v); }
    void *raw() const { return const_cast<VariantStorage *>(&v); }
    void *data() const { const auto variant_type=type_of(&v); return internal[static_cast<size_t>(variant_type)](raw()); }
    bool is(GDExtensionVariantType t) const { return type_of(&v) == t; }
};
TrValue tr_int(int64_t n) { TrValue v; destroy(v.raw()); from_int(v.raw(), &n); return v; }
TrValue tr_float(double n) { TrValue v; destroy(v.raw()); from_float(v.raw(), &n); return v; }
TrValue tr_bool(bool n) { TrValue v; GDExtensionBool b = n; destroy(v.raw()); from_bool(v.raw(), &b); return v; }
TrValue tr_cell(TrCell c) { TrValue v; destroy(v.raw()); from_v2i(v.raw(), &c); return v; }
TrValue tr_text(const char *s) { TextStorage t; make_string(&t, s); TrValue v; destroy(v.raw()); from_string(v.raw(), &t); destroy_string(&t); return v; }
TrValue tr_get(const TrValue &o, const TrValue &key) {
    TrValue v; destroy(v.raw()); GDExtensionBool valid = false;
    get_keyed(o.raw(), key.raw(), v.raw(), &valid);
    return v;
}
TrValue tr_get(const TrValue &o, const char *key) { return tr_get(o, tr_text(key)); }
TrValue tr_call(const TrValue &o, const char *method, std::initializer_list<const void *> args = {}) {
    TextStorage name; make_name(&name, method, false); TrValue v; destroy(v.raw()); GDExtensionCallError e{};
    variant_call(o.raw(), &name, args.begin(), static_cast<int>(args.size()), v.raw(), &e); destroy_name(&name); return v;
}
struct TrUnsupportedInput {};
int64_t tr_i(const TrValue &v, int64_t fallback = 0) {
    if(v.is(INT))return *static_cast<int64_t *>(v.data());
    if(v.is(FLOAT)) {
        const double n=*static_cast<double *>(v.data());
        if(!std::isfinite(n)||n < -9223372036854775808.0||n >= 9223372036854775808.0)throw TrUnsupportedInput{};
        return static_cast<int64_t>(n);
    }
    return fallback;
}
double tr_f(const TrValue &v, double fallback = 0) {
    if(v.is(FLOAT)) {const double n=*static_cast<double *>(v.data());if(std::isnan(n))throw TrUnsupportedInput{};return n;}
    return v.is(INT)?double(tr_i(v)):fallback;
}
bool tr_b(const TrValue &v, bool fallback = false) { return v.is(BOOL) ? *static_cast<GDExtensionBool *>(v.data()) != 0 : (v.is(INT) ? tr_i(v) != 0 : fallback); }
TrCell tr_c(const TrValue &v, TrCell fallback = {-1,-1}) { return v.is(V2I) ? *static_cast<TrCell *>(v.data()) : fallback; }
bool tr_has(const TrValue &o, const TrValue &key) { return o.is(DICT) && has(o.data(), key.raw()); }
void tr_set(TrValue &d, const TrValue &key, const TrValue &v) { void *p = dict_write(d.data(), key.raw()); destroy(p); copy_variant(p, v.raw()); }
void tr_set(TrValue &d, const char *key, const TrValue &v) { tr_set(d, tr_text(key), v); }
void tr_erase(TrValue &d, const TrValue &key) { tr_call(d, "erase", {key.raw()}); }
TrValue tr_copy_dict(const TrValue &d) { return d.is(DICT) ? tr_call(d, "duplicate") : TrValue(DICT); }
TrValue tr_meta(const TrValue &o, const char *name, const TrValue &fallback) { auto k = tr_text(name); return tr_call(o, "get_meta", {k.raw(), fallback.raw()}); }
bool tr_array_equal(const TrValue &a, const TrValue &b) {
    if (!a.is(ARRAY) || !b.is(ARRAY) || size(a.data()) != size(b.data())) return false;
    for (int64_t i = 0; i < size(a.data()); ++i)
        if (leaf_equal(array_at(a.data(), i), array_at(b.data(), i)) != ExactResult::EQUAL) return false;
    return true;
}
TrValue tr_array(std::initializer_list<TrValue> values) {
    TrValue a(ARRAY); resize(resize_array, a.data(), values.size()); int64_t i = 0;
    for (const auto &v : values) { void *p = array_write(a.data(), i++); destroy(p); copy_variant(p, v.raw()); } return a;
}
std::vector<TrCell> tr_cells(const TrValue &a, bool &valid) {
    std::vector<TrCell> out; if (!a.is(ARRAY)) { valid = false; return out; }
    out.reserve(size(a.data())); for (int64_t i=0; i<size(a.data()); ++i) { TrValue v(array_at(a.data(),i)); if (!v.is(V2I)) { valid=false; return {}; } out.push_back(tr_c(v)); } return out;
}
TrValue tr_cell_array(const std::vector<TrCell> &cells, const TrValue &prototype) {
    auto zero_index=tr_int(0);
    TrValue a=tr_call(prototype,"slice",{zero_index.raw(),zero_index.raw()}); resize(resize_array,a.data(),cells.size());
    for (size_t i=0;i<cells.size();++i) { auto v=tr_cell(cells[i]); void *p=array_write(a.data(),i); destroy(p); copy_variant(p,v.raw()); } return a;
}
int tr_dist(TrCell a, TrCell b) { return std::abs(a.x-b.x)+std::abs(a.y-b.y); }
int tr_dot(TrCell a, TrCell b) { return a.x*b.x+a.y*b.y; }
TrCell tr_side(TrCell f) {
    TrCell n{-f.y,f.x}; if(n==TrCell{0,0}) return {0,1};
    if(n.x && n.y) { n=std::abs(f.x)>=std::abs(f.y)?TrCell{-f.y,0}:TrCell{0,f.x}; if(n==TrCell{0,0}) return {0,1}; } return n;
}
struct TrTerrain {
    TrValue flags, heights, ramps, blocked;
    TrCell extent;
    int max_step=1; bool can_ramp=true, present=false, profile_present=false;
    const uint8_t *f=nullptr,*h=nullptr,*r=nullptr,*b=nullptr;
    bool read(const TrValue &terrain, const TrValue &profile) {
        profile_present=profile.is(OBJECT);
        if(profile_present) { auto ms=tr_get(profile,"max_step_height"), cr=tr_get(profile,"can_use_ramp"); if(!ms.is(INT)||!cr.is(BOOL)) return false; max_step=int(tr_i(ms)); can_ramp=tr_b(cr); }
        if(terrain.is(NIL)) return true;
        if(!terrain.is(OBJECT)) return false;
        present=true; auto sz=tr_get(terrain,"size"); if(!sz.is(V2I)) return false; extent=tr_c(sz);
        flags=tr_get(terrain,"flags"); heights=tr_get(terrain,"height_levels"); ramps=tr_get(terrain,"ramp_edges"); blocked=tr_get(terrain,"static_blocked");
        if(extent.x<=0||extent.y<=0||!flags.is(BYTES)||!heights.is(BYTES)||!ramps.is(BYTES)||!blocked.is(BYTES)) return false;
        int64_t n=int64_t(extent.x)*extent.y;
        auto surface_heights=tr_get(terrain,"walk_height_levels"), surface_ramps=tr_get(terrain,"walk_ramp_edges");
        if(tr_b(tr_get(terrain,"has_navigation_overrides"))) {
            if(surface_heights.is(BYTES)&&packed_size(size_bytes,surface_heights.data())==n) heights=surface_heights;
            if(surface_ramps.is(BYTES)&&packed_size(size_bytes,surface_ramps.data())==n) ramps=surface_ramps;
        }
        if(packed_size(size_bytes,flags.data())!=n||packed_size(size_bytes,heights.data())!=n||packed_size(size_bytes,ramps.data())!=n) return false;
        int64_t nb=packed_size(size_bytes,blocked.data()); if(nb!=0&&nb!=n)return false;
        f=bytes_read(flags.data(),0); h=bytes_read(heights.data(),0); r=bytes_read(ramps.data(),0); b=nb?bytes_read(blocked.data(),0):nullptr; return true;
    }
    bool contains(TrCell c) const { return present&&c.x>=0&&c.y>=0&&c.x<extent.x&&c.y<extent.y; }
    int idx(TrCell c) const { return c.y*extent.x+c.x; }
    int height(TrCell c) const { return contains(c)?h[idx(c)]:0; }
    bool walk(TrCell c) const { return contains(c)&&(f[idx(c)]&1)&&(!b||!b[idx(c)]); }
    bool step(TrCell a,TrCell c,bool profile_check=true) const {
        if(!walk(a)||!walk(c))return false; TrCell d=c-a; int dir=-1;
        const TrCell dirs[]={{0,-1},{1,0},{0,1},{-1,0}}; for(int i=0;i<4;++i)if(d==dirs[i])dir=i; if(dir<0)return false;
        if((r[idx(a)]&(1<<(dir+4)))||(r[idx(c)]&(1<<(((dir+2)%4)+4))))return false;
        int hd=std::abs(height(a)-height(c)); if(hd!=0&&(hd!=1||!(r[idx(a)]&(1<<dir))||!(r[idx(c)]&(1<<((dir+2)%4)))))return false;
        if(profile_present&&(hd>max_step||(profile_check&&hd!=0&&!can_ramp)))return false; return true;
    }
};

// FormationTransitPlanner.get_transit_distance_field: one cold, reverse-edge
// search over the canonical TerrainData arrays. No plan/cache state lives here.
void call_transit_distance_field(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr output, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0}; reset_variant(output, DICT);
    if (argc != 3 || type_of(args[0]) != OBJECT ||
            (type_of(args[1]) != OBJECT && type_of(args[1]) != NIL) || type_of(args[2]) != V2I) return;
    TrValue terrain(args[0]), profile(args[1]);
    if (profile.is(OBJECT)) {
        auto max_step = tr_get(profile, "max_step_height");
        if (!max_step.is(INT) || tr_i(max_step) < std::numeric_limits<int>::min() ||
                tr_i(max_step) > std::numeric_limits<int>::max()) return;
    }
    TrTerrain ground;
    if (!ground.read(terrain, profile) || !ground.present || ground.extent.x > 128 || ground.extent.y > 128) return;
    const TrCell goal = *static_cast<TrCell *>(internal[V2I](const_cast<void *>(args[2])));
    TrValue field(DICT);
    if (!ground.contains(goal)) {
        tr_set(field, tr_cell(goal), tr_int(0));
    } else {
        const int count = ground.extent.x * ground.extent.y;
        std::vector<int32_t> distances(count, -1);
        std::vector<TrCell> queue;
        queue.reserve(count);
        distances[ground.idx(goal)] = 0;
        queue.push_back(goal);
        constexpr TrCell directions[] = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}};
        for (size_t head = 0; head < queue.size(); ++head) {
            const TrCell cell = queue[head];
            const int32_t next_distance = distances[ground.idx(cell)] + 1;
            for (const TrCell direction : directions) {
                const TrCell neighbor = cell + direction;
                if (!ground.contains(neighbor) || distances[ground.idx(neighbor)] >= 0 ||
                        !ground.step(neighbor, cell)) continue;
                distances[ground.idx(neighbor)] = next_distance;
                queue.push_back(neighbor);
            }
        }
        // Original Dictionary insertion follows BFS order, including an
        // unwalkable goal at distance zero.
        for (const TrCell cell : queue) tr_set(field, tr_cell(cell), tr_int(distances[ground.idx(cell)]));
    }
    destroy(output); copy_variant(output, field.raw());
}

struct TrTransit {
    TrValue plan, dest, terrain, profile, mids_arg, cells, fields{DICT}, meta{DICT}, dest_fields{DICT}, dest_meta{DICT}, result{DICT};
    TrValue ranks, observed, assigned, rows, lanes, staging, epochs, prior_slots, prior_retry, prior_cells, checkpoint, retry, defer, rejects;
    std::vector<TrCell> path; std::vector<std::vector<TrCell>> static_rows;
    std::vector<int64_t> flow,other,sorted, result_order;
    std::unordered_map<TrCell,int,TrHash> exact;
    std::unordered_map<int64_t,int> physical;
    std::unordered_set<int64_t> exact_members;
    TrTerrain ground;
    int64_t path_epoch=0, terrain_revision=0, profile_hash=0;
    int cursor=0, width=1,pending=1,confirm=0;
    int64_t assignment_epoch=0;
    bool debug=false,inertia=false,valid=true;
    int64_t di(const TrValue &d,int64_t id,int64_t def=0) { return tr_i(tr_get(d,tr_int(id)),def); }
    double df(const TrValue &d,int64_t id,double def=0) { return tr_f(tr_get(d,tr_int(id)),def); }
    TrCell dc(const TrValue &d,int64_t id,TrCell def={-1,-1}) { return tr_c(tr_get(d,tr_int(id)),def); }
    bool dh(const TrValue &d,int64_t id) { return tr_has(d,tr_int(id)); }
    void put(TrValue &d,int64_t id,const TrValue &v) { tr_set(d,tr_int(id),v); }
    TrCell direction(int k) const { if(k+1<int(path.size()))return path[k+1]-path[k]; if(k>0)return path[k]-path[k-1]; return {1,0}; }
    std::vector<TrCell> cross(int k,int count) const {
        if(k<0||k>=int(path.size())||(ground.present&&!ground.walk(path[k])))return {};
        TrCell center=path[k],normal=tr_side(direction(k)); std::vector<int> offsets{0}; int h=ground.height(center);
        for(int sign : {1,-1}) { TrCell previous=center; for(int n=1;n<4;++n) { TrCell c=center+normal*(n*sign); if(!ground.walk(c)||std::abs(ground.height(c)-h)>ground.max_step||!ground.step(previous,c))break; offsets.push_back(n*sign); previous=c; } }
        std::sort(offsets.begin(),offsets.end(),[](int a,int b){return std::abs(a)!=std::abs(b)?std::abs(a)<std::abs(b):a>b;});
        std::vector<TrCell> out; for(int i=0;i<std::min(count,int(offsets.size()));++i)out.push_back(center+normal*offsets[i]); return out;
    }
    int corridor(int k) const { if(!ground.contains(path[k]))return 1; return std::max(1,int(cross(k,4).size())); }
    bool predecessor(const std::vector<TrCell> &previous,TrCell c) const {
        if(previous.empty())return true;
        for(TrCell p:previous) { int distance=tr_dist(p,c); if(distance>2)continue; if(!ground.present)return true;
            if(std::abs(ground.height(p)-ground.height(c))>ground.max_step)continue;
            if(distance==1) { if(ground.step(c,p,false))return true; }
            else { TrCell m1{c.x,p.y},m2{p.x,c.y}; if(ground.walk(m1)&&ground.step(c,m1,false)&&ground.step(m1,p,false))return true; if(ground.walk(m2)&&ground.step(c,m2,false)&&ground.step(m2,p,false))return true; }
        } return false;
    }
    int head() const {
        int start=std::clamp(cursor,0,int(path.size())-1), requested=std::clamp(cursor+std::clamp(width,2,4),start,int(path.size())-1), verified=start;
        auto previous=cross(start,width); if(previous.empty())return start;
        for(int k=start+1;k<=requested;++k) {
            if(ground.present&&(!ground.walk(path[k])||!ground.step(path[k-1],path[k])))break;
            // The original lookahead uses RIGHT at the final path node.
            if(pending!=width&&confirm>0) {
                int detected=corridor(k);
                if(k==int(path.size())-1 && direction(k)!=TrCell{1,0}) {
                    TrCell center=path[k]; int span=1; for(int sign:{1,-1}) {TrCell prev=center;for(int n=1;n<4;++n){TrCell c=center+TrCell{0,n*sign};if(!ground.walk(c)||std::abs(ground.height(c)-ground.height(center))>ground.max_step||!ground.step(prev,c))break;++span;prev=c;}} detected=std::clamp(span,1,4);
                }
                if(detected!=width)break;
            }
            auto current=cross(k,width); if(current.empty())break; bool legal=false; for(auto c:current)if(predecessor(previous,c)){legal=true;break;} if(!legal)break;
            if(current.size()==1&&previous.size()==1&&current[0]==previous[0])break; previous=current; verified=k;
        } return verified;
    }
    TrCell legal_staging(TrCell ideal,const std::unordered_set<TrCell,TrHash> &allocated) const {
        if(!allocated.count(ideal)&&(!ground.present||ground.walk(ideal)))return ideal;
        std::vector<TrCell> queue{ideal}; std::unordered_set<TrCell,TrHash> seen{ideal};
        const TrCell directions[]={{0,-1},{1,0},{0,1},{-1,0}};
        for(size_t at=0;at<queue.size()&&at<60;++at)for(auto d:directions) {TrCell n=queue[at]+d;if(!seen.insert(n).second||tr_dist(n,ideal)>6)continue;if(ground.present&&(!ground.walk(n)||!ground.step(queue[at],n)||std::abs(ground.height(n)-ground.height(ideal))>ground.max_step))continue;if(!allocated.count(n))return n;queue.push_back(n);} return ideal;
    }
    void count(const char *key) { tr_set(rejects,key,tr_int(tr_i(tr_get(rejects,key))+1)); }
    bool run();
};

bool TrTransit::run() {
    auto path_arg=tr_get(plan,"macro_path"); path=tr_cells(path_arg,valid);
    if(!valid||!mids_arg.is(ARRAY)||!cells.is(DICT)||!ground.read(terrain,profile))return false;
    if(path.empty()||size(mids_arg.data())==0)return true;
    for(int64_t i=0;i<size(mids_arg.data());++i)if(type_of(array_at(mids_arg.data(),i))!=INT)return false;
    path_epoch=tr_i(tr_get(plan,"path_epoch")); terrain_revision=tr_i(tr_get(plan,"terrain_revision"));
    profile_hash=profile.is(OBJECT)?tr_i(tr_get(profile,"profile_hash")):0;
    cursor=int(tr_i(tr_get(plan,"macro_cursor"))); width=std::clamp(int(tr_i(tr_get(plan,"current_width"))),1,4);
    pending=int(tr_i(tr_get(plan,"pending_width"))); confirm=int(tr_i(tr_get(plan,"width_confirm_counter")));
    dest=tr_get(plan,"destination_plan");
    TrValue role(DICT),final_slots(DICT); std::unordered_set<int64_t> admitted;
    std::vector<TrCell> platform,footprint; std::unordered_set<TrCell,TrHash> footprint_set;
    TrCell handoff,anchor,facing,ingress,last_choke; int bottleneck=-1;
    if(dest.is(OBJECT)) {
        role=tr_get(dest,"member_role_map"); final_slots=tr_get(dest,"member_slot_map");
        auto admission=tr_get(dest,"admitted_platform_member_ids");
        if(!role.is(DICT)||!final_slots.is(DICT)||!admission.is(ARRAY))return false;
        for(int64_t i=0;i<size(admission.data());++i) {TrValue v(array_at(admission.data(),i));if(!v.is(INT))return false;admitted.insert(tr_i(v));}
        platform=tr_cells(tr_get(dest,"platform_slots"),valid); footprint=tr_cells(tr_get(dest,"platform_footprint"),valid); if(!valid)return false;
        footprint_set.insert(footprint.begin(),footprint.end());
        handoff=tr_c(tr_get(dest,"centered_platform_handoff"));anchor=tr_c(tr_get(dest,"resolved_anchor"));facing=tr_c(tr_get(dest,"final_facing"));ingress=tr_c(tr_get(dest,"ingress_cell"));
        bottleneck=int(tr_i(tr_get(dest,"approach_bottlenecked"),-1));last_choke=tr_c(tr_get(dest,"approach_last_bottleneck_cell"));
        TrCell scan_key{int32_t(path_epoch),int32_t(terrain_revision)};
        if(bottleneck<0||tr_c(tr_meta(dest,"_transit_bottleneck_scan_key",tr_cell({-1,-1})))!=scan_key) {
            bottleneck=0;last_choke={-1,-1};for(int k=int(path.size())-1;k>=0;--k)if(corridor(k)==1){bottleneck=1;last_choke=path[k];break;}
            handoff={-1,-1};tr_set(dest_fields,"approach_bottlenecked",tr_int(bottleneck));tr_set(dest_fields,"approach_last_bottleneck_cell",tr_cell(last_choke));tr_set(dest_fields,"centered_platform_handoff",tr_cell(handoff));
            tr_set(dest_meta,"_transit_bottleneck_scan_key",tr_cell(scan_key));
        }
    } else if(!dest.is(NIL))return false;
    for(int64_t i=0;i<size(mids_arg.data());++i) {
        int64_t mid=tr_i(TrValue(array_at(mids_arg.data(),i)));bool flowing=!dest.is(OBJECT);
        if(dest.is(OBJECT)&&dh(role,mid)&&di(role,mid)==0) {
            flowing=!admitted.count(mid);
            if(!flowing) {
                TrCell c=dc(cells,mid),final=dc(final_slots,mid);
                if(footprint_set.count(c)&&tr_dist(c,final)>2&&tr_dist(final,ingress)>8) {
                    if(handoff==TrCell{-1,-1}) {
                        handoff=anchor;
                        if(platform.size()>=20&&footprint.size()>=platform.size()*2) {
                            int shallow=0;for(auto slot:platform)shallow=std::min(shallow,tr_dot(slot-anchor,facing));
                            if(shallow<0) {TrCell approach=handoff+facing*(shallow-1);if(bottleneck==0||(last_choke!=TrCell{-1,-1}&&tr_dot(approach-last_choke,facing)>=2))handoff=approach;}
                        }
                        tr_set(dest_fields,"centered_platform_handoff",tr_cell(handoff));
                    }
                    flowing=tr_dot(c-handoff,handoff-ingress)<0;
                }
            }
        }
        (flowing?flow:other).push_back(mid);
    }
    if(flow.empty()) {tr_set(fields,"member_transit_slots",result);return true;}
    const char *dict_fields[]={"member_sequence_rank","member_observed_path_s","member_path_s","member_row_map","member_lane_map","pre_route_staging_slots","member_soft_assignment_epoch","member_transit_slots","member_checkpoint_path_k","member_route_retry_count","member_defer_count"};
    TrValue *dict_values[]={&ranks,&observed,&assigned,&rows,&lanes,&staging,&epochs,&prior_slots,&checkpoint,&retry,&defer};
    for(size_t i=0;i<sizeof(dict_fields)/sizeof(*dict_fields);++i) {auto source=tr_get(plan,dict_fields[i]);if(!source.is(DICT))return false;*dict_values[i]=i<7?tr_copy_dict(source):source;}
    assignment_epoch=tr_i(tr_get(plan,"assignment_epoch"));
    auto prior_rank=tr_copy_dict(ranks);
    auto inertia_key=tr_array({tr_int(path_epoch),tr_int(terrain_revision),tr_int(profile_hash)});
    inertia=tr_array_equal(tr_meta(plan,"_transit_soft_key",TrValue(ARRAY)),inertia_key);
    prior_retry=inertia?tr_meta(plan,"_transit_soft_retry",TrValue(DICT)):TrValue(DICT);
    prior_cells=inertia?tr_meta(plan,"_transit_soft_cells",TrValue(DICT)):TrValue(DICT);
    debug=tr_b(tr_meta(plan,"_transit_soft_debug_enabled",tr_bool(false)));
    rejects=debug?tr_copy_dict(tr_meta(plan,"_transit_soft_reject_counts",TrValue(DICT))):TrValue(DICT);
    if(!prior_retry.is(DICT)||!prior_cells.is(DICT))return false;
    auto row_key=tr_array({tr_int(path_epoch),tr_int(terrain_revision),tr_int(profile_hash),tr_int(path.size())});
    auto cache=tr_meta(plan,"_transit_row_sections",TrValue(ARRAY));
    if(tr_array_equal(tr_meta(plan,"_transit_row_sections_key",TrValue(ARRAY)),row_key)&&cache.is(ARRAY)&&size(cache.data())==int64_t(path.size())) {
        for(int64_t k=0;k<size(cache.data());++k)static_rows.push_back(tr_cells(TrValue(array_at(cache.data(),k)),valid));if(!valid)return false;
    } else {
        TrValue sections(ARRAY);resize(resize_array,sections.data(),path.size());
        for(int k=0;k<int(path.size());++k) {static_rows.push_back(cross(k,4));auto row=tr_cell_array(static_rows.back(),path_arg);void *p=array_write(sections.data(),k);destroy(p);copy_variant(p,row.raw());}
        tr_set(meta,"_transit_row_sections",sections);tr_set(meta,"_transit_row_sections_key",row_key);
    }
    int head_k=head(),tail=head_k;
    for(size_t i=0;i<flow.size();++i) {
        int64_t mid=flow[i];if(!dh(ranks,mid))put(ranks,mid,tr_int(i));
        if(!dh(observed,mid)&&dh(cells,mid)) {TrCell c=dc(cells,mid);int nearest=0,distance=999999;for(int k=0;k<int(path.size());++k){int d=tr_dist(path[k],c);if(d<distance){distance=d;nearest=k;}}put(observed,mid,tr_float(double(nearest)-double(distance)*0.25));}
    }
    sorted=flow;
    std::sort(sorted.begin(),sorted.end(),[&](int64_t a,int64_t b){double sa=df(observed,a,-9999),sb=df(observed,b,-9999);if(sa!=sb)return sa>sb;int64_t ra=di(ranks,a,9999),rb=di(ranks,b,9999);return ra!=rb?ra<rb:a<b;});
    for(size_t i=0;i<sorted.size();++i)put(ranks,sorted[i],tr_int(i));
    auto path_cache=tr_meta(plan,"_transit_exact_path_indices",TrValue(DICT));auto cached_path=tr_get(path_cache,"path");
    GDExtensionBool same=false; const void *same_args[]={cached_path.raw(),path_arg.raw()};same_variant(&same,same_args,2);
    if(tr_i(tr_get(path_cache,"epoch"),-1)==path_epoch&&tr_i(tr_get(path_cache,"size"),-1)==int64_t(path.size())&&same) {
        // Rebuild only the call-local C++ lookup; preserve the original cache object.
        auto index=tr_get(path_cache,"indices"); if(!index.is(DICT))return false;
        for(auto c:path)exact[c]=int(tr_i(tr_get(index,tr_cell(c)),-1));
    } else {
        TrValue indices(DICT),next(DICT);for(int k=0;k<int(path.size());++k){exact[path[k]]=k;tr_set(indices,tr_cell(path[k]),tr_int(k));}
        tr_set(next,"epoch",tr_int(path_epoch));tr_set(next,"size",tr_int(path.size()));tr_set(next,"path",path_arg);tr_set(next,"indices",indices);tr_set(meta,"_transit_exact_path_indices",next);
    }
    std::vector<int> crossed(path.size(),0);const TrCell directions[]={{0,-1},{1,0},{0,1},{-1,0}};
    for(int64_t mid:sorted) {
        int check=std::clamp(int(di(checkpoint,mid)),0,int(path.size())-1);
        if(dh(cells,mid)) {TrCell c=dc(cells,mid);auto it=exact.find(c);if(it!=exact.end()&&it->second>=0){check=it->second;exact_members.insert(mid);}else{int adjacent=-1;for(auto d:directions){auto at=exact.find(c+d);if(at!=exact.end()&&ground.step(c,c+d))adjacent=std::max(adjacent,at->second);}if(adjacent>=0)check=std::min(check,adjacent);}}
        physical[mid]=check;tail=std::min(tail,check);++crossed[check];
    }
    int cumulative=0;for(int k=int(path.size())-1;k>=0;--k){cumulative+=crossed[k];crossed[k]=cumulative;}
    std::vector<int> chokes;for(int k=std::max(0,tail);k<=head_k;++k)if(static_rows[k].size()==1)chokes.push_back(k);
    if(!chokes.empty()) {
        // The GD comparator switches between rank and projection for mixed
        // rank presence and can form a cycle. It is not a valid std::sort
        // ordering; leave that entire invocation with the original oracle.
        const bool ranked=dh(prior_rank,sorted.front());
        for(auto mid:sorted)if(dh(prior_rank,mid)!=ranked)return false;
        std::sort(sorted.begin(),sorted.end(),[&](int64_t a,int64_t b){if(physical[a]!=physical[b])return physical[a]>physical[b];if(exact_members.count(a)!=exact_members.count(b))return exact_members.count(a)!=0;if(dh(prior_rank,a)&&dh(prior_rank,b)&&di(prior_rank,a)!=di(prior_rank,b))return di(prior_rank,a)<di(prior_rank,b);double sa=df(observed,a,-9999),sb=df(observed,b,-9999);return sa!=sb?sa>sb:a<b;});
        for(size_t i=0;i<sorted.size();++i)put(ranks,sorted[i],tr_int(i));
    }
    std::sort(other.begin(),other.end(),[&](int64_t a,int64_t b){int64_t ra=di(ranks,a,9999),rb=di(ranks,b,9999);return ra!=rb?ra<rb:a<b;});
    for(size_t i=0;i<other.size();++i)put(ranks,other[i],tr_int(sorted.size()+i));
    struct Slot {TrCell c;int s,row,lane=0;};std::vector<Slot> available;std::vector<std::vector<int>> groups;std::vector<TrCell> previous;
    std::unordered_set<TrCell,TrHash> allocated,nonflow;
    for(auto mid:other)if(dh(cells,mid))nonflow.insert(dc(cells,mid));int choke_cursor=int(chokes.size())-1;
    for(int k=head_k;k>=0;--k) {
        const auto &candidates=static_rows[k];std::vector<TrCell> row;std::vector<int> items;
        while(choke_cursor>=0&&chokes[choke_cursor]>k)--choke_cursor;int count_for_row=int(candidates.size());
        if(choke_cursor>=0) {int ck=chokes[choke_cursor],allowed=crossed[ck];if(k==ck){++allowed;if(choke_cursor>0)allowed=std::min(allowed,crossed[chokes[choke_cursor-1]]);}count_for_row=std::min(count_for_row,std::max(0,allowed-int(available.size())));}
        for(int oi=0;oi<count_for_row;++oi){TrCell c=candidates[oi];if(!allocated.count(c)&&!nonflow.count(c)&&predecessor(previous,c)){allocated.insert(c);row.push_back(c);items.push_back(int(available.size()));available.push_back({c,k,int(groups.size()),0});}}
        if(!row.empty()){previous=row;groups.push_back(items);}else previous.clear();if(available.size()>=sorted.size()+4)break;
    }
    size_t member_cursor=0;
    for(size_t row_idx=0;row_idx<groups.size()&&member_cursor<sorted.size();++row_idx) {
        auto &slots=groups[row_idx];size_t end=std::min(sorted.size(),member_cursor+slots.size());std::vector<int64_t> members(sorted.begin()+member_cursor,sorted.begin()+end);
        if(members.size()>1) {TrCell side=tr_side(direction(available[slots[0]].s));
            std::sort(members.begin(),members.end(),[&](int64_t a,int64_t b){int sa=tr_dot(dc(cells,a,path[0]),side),sb=tr_dot(dc(cells,b,path[0]),side);return sa!=sb?sa<sb:di(ranks,a,9999)<di(ranks,b,9999);});
            std::sort(slots.begin(),slots.end(),[&](int a,int b){int sa=tr_dot(available[a].c,side),sb=tr_dot(available[b].c,side);return sa!=sb?sa<sb:available[a].s>available[b].s;});
        }
        for(size_t i=0;i<members.size();++i) {int64_t mid=members[i];const auto &slot=available[slots[i]];put(result,mid,tr_cell(slot.c));result_order.push_back(mid);put(assigned,mid,tr_float(slot.s));put(rows,mid,tr_int(row_idx));put(lanes,mid,tr_int(i));tr_erase(staging,tr_int(mid));}
        member_cursor=end;
    }
    for(size_t i=member_cursor;i<sorted.size();++i) {int64_t mid=sorted[i],rank=di(ranks,mid);int row=int(std::floor(double(rank)/width));put(assigned,mid,tr_float(-1.0-row));put(rows,mid,tr_int(row));put(lanes,mid,tr_int(rank%width));TrCell c=legal_staging(dc(staging,mid,dc(cells,mid,path[0])),allocated);put(staging,mid,tr_cell(c));allocated.insert(c);put(result,mid,tr_cell(c));result_order.push_back(mid);}
    const bool active_gate=!chokes.empty();std::unordered_map<TrCell,int64_t,TrHash> default_owner;
    for(auto mid:result_order)default_owner[dc(result,mid)]=mid;
    std::vector<int> segment_at(path.size(),0);int gates=0;if(active_gate)for(int k=head_k;k>=0;--k){segment_at[k]=gates;if(static_rows[k].size()==1)++gates;}
    std::vector<int> segment_order;std::unordered_map<int,std::vector<int>> segments;
    for(auto &slots:groups) {
        if(slots.empty())continue;int k=available[slots[0]].s,segment=active_gate?segment_at[k]:0;
        bool adjacent=active_gate&&(static_rows[k].size()==1||(k>0&&static_rows[k-1].size()==1)||(k<head_k&&static_rows[k+1].size()==1));
        if(adjacent) {if(debug&&inertia)for(int idx:slots){auto it=default_owner.find(available[idx].c);if(it!=default_owner.end()&&it->second>=0&&dh(prior_slots,it->second)&&dc(prior_slots,it->second)!=available[idx].c)count("gate_adjacency");}continue;}
        TrCell dir=direction(k),side{-dir.y,dir.x};std::sort(slots.begin(),slots.end(),[&](int a,int b){auto ca=available[a].c,cb=available[b].c;bool aa=default_owner.count(ca)!=0,bb=default_owner.count(cb)!=0;if(aa!=bb)return aa;if(aa)return di(lanes,default_owner[ca])<di(lanes,default_owner[cb]);return tr_dot(ca,side)<tr_dot(cb,side);});
        if(!segments.count(segment))segment_order.push_back(segment);auto &list=segments[segment];for(size_t i=0;i<slots.size();++i){available[slots[i]].lane=int(i);list.push_back(slots[i]);}
    }
    for(int segment:segment_order) {
        auto &candidates=segments[segment];std::unordered_map<TrCell,int,TrHash> index;for(size_t i=0;i<candidates.size();++i)index[available[candidates[i]].c]=int(i);
        std::vector<int64_t> members;for(auto mid:sorted)if(dh(result,mid)&&index.count(dc(result,mid)))members.push_back(mid);
        std::sort(members.begin(),members.end(),[&](int64_t a,int64_t b){int64_t ra=di(rows,a,9999),rb=di(rows,b,9999);return ra!=rb?ra<rb:di(lanes,a,9999)<di(lanes,b,9999);});
        int next=0;for(size_t i=0;i<members.size();++i) {
            int64_t mid=members[i];int chosen=next;TrCell old=dc(prior_slots,mid);auto at=index.find(old);int old_index=at==index.end()?-1:at->second;
            int64_t retry_now=di(retry,mid),retry_then=di(prior_retry,mid,retry_now);bool past=old_index>=0&&physical[mid]>available[candidates[old_index]].s;
            bool retrying=retry_now-retry_then>=3||di(defer,mid)>=8, same_section=old_index>=0&&segment_at[physical[mid]]==segment;
            bool stationary=dc(cells,mid)==dc(prior_cells,mid,{-2,-2});int max_index=int(candidates.size()-(members.size()-i));
            bool retained=inertia&&old_index>=next&&old_index<=max_index&&(!active_gate||same_section||stationary)&&dc(cells,mid)!=old&&!past&&!retrying;
            if(retained)chosen=old_index;
            else if(debug&&inertia&&dh(prior_slots,mid)&&old!=dc(result,mid)) {
                const char *reason=nullptr;
                if(old_index<0)reason="old_index_absent";
                else if(old_index<next||old_index>max_index) {
                    count("capacity_bound");const char *detail=old_index<next?"capacity_behind_prefix":"capacity_tail_reservation";count(detail);
                    // Four fixed combinations avoid runtime string ownership beyond this call.
                    if(old_index<next)count(stationary?(active_gate?"capacity_behind_prefix_stationary_gate":"capacity_behind_prefix_stationary_open"):(active_gate?"capacity_behind_prefix_moving_gate":"capacity_behind_prefix_moving_open"));
                    else count(stationary?(active_gate?"capacity_tail_reservation_stationary_gate":"capacity_tail_reservation_stationary_open"):(active_gate?"capacity_tail_reservation_moving_gate":"capacity_tail_reservation_moving_open"));
                } else if(active_gate&&!same_section&&!stationary)reason="section_mismatch";else if(past)reason="physical_past";else if(retrying)reason="retry_defer";
                if(reason)count(reason);
            }
            const auto &kept=available[candidates[chosen]];put(result,mid,tr_cell(kept.c));put(assigned,mid,tr_float(kept.s));put(rows,mid,tr_int(kept.row));put(lanes,mid,tr_int(kept.lane));next=chosen+1;
        }
    }
    TrValue next_retry(DICT),next_cells(DICT);
    for(auto mid:result_order) {
        TrCell slot=dc(result,mid);if(dc(prior_slots,mid)!=slot){++assignment_epoch;put(epochs,mid,tr_int(di(epochs,mid)+1));}
        int64_t now=di(retry,mid);put(next_retry,mid,tr_int(inertia&&dc(prior_slots,mid)==slot?di(prior_retry,mid,now):now));put(next_cells,mid,tr_cell(dc(cells,mid)));
    }
    tr_set(meta,"_transit_soft_key",inertia_key);tr_set(meta,"_transit_soft_retry",next_retry);tr_set(meta,"_transit_soft_cells",next_cells);if(debug)tr_set(meta,"_transit_soft_reject_counts",rejects);
    for(size_t i=0;i<7;++i)tr_set(fields,dict_fields[i],*dict_values[i]);tr_set(fields,"member_transit_slots",result);tr_set(fields,"assignment_epoch",tr_int(assignment_epoch));return true;
}

void call_calculate_transit_slots(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr output, GDExtensionCallError *error) {
    *error={GDEXTENSION_CALL_OK,0,0};reset_variant(output,DICT);
    if(argc!=5||type_of(args[0])!=OBJECT||type_of(args[3])!=ARRAY||type_of(args[4])!=DICT)return;
    TrTransit task;task.plan=TrValue(args[0]);task.terrain=TrValue(args[1]);task.profile=TrValue(args[2]);task.mids_arg=TrValue(args[3]);task.cells=TrValue(args[4]);
    try { if(!task.run())return; }
    catch(const TrUnsupportedInput &) { return; }
    TrValue packet(DICT);tr_set(packet,"slots",task.result);tr_set(packet,"fields",task.fields);tr_set(packet,"meta",task.meta);tr_set(packet,"destination_fields",task.dest_fields);tr_set(packet,"destination_meta",task.dest_meta);
    destroy(output);copy_variant(output,packet.raw());
}
