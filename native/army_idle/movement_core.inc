// Synchronous calculations over the original owners. No borrowed reference or
// person state survives a call; the Reservation Grid still performs commits.
struct MValue {
    VariantStorage v;
    explicit MValue(GDExtensionVariantType type = NIL) { GDExtensionCallError e{}; variant_construct(type, &v, nullptr, 0, &e); }
    explicit MValue(const void *value) { copy_variant(&v, value); }
    explicit MValue(int64_t value) { from_int(&v, &value); }
    explicit MValue(bool value) { GDExtensionBool b = value; from_bool(&v, &b); }
    explicit MValue(const char *value) { TextStorage text; make_string(&text, value); from_string(&v, &text); destroy_string(&text); }
    MValue(const MValue &other) { copy_variant(&v, &other.v); }
    ~MValue() { destroy(&v); }
    MValue &operator=(const MValue &other) { if (this != &other) { destroy(&v); copy_variant(&v, &other.v); } return *this; }
    void *ptr() { return &v; }
    const void *ptr() const { return &v; }
};
struct MCell {
    int32_t x = -1, y = -1;
    bool operator==(MCell b) const { return x == b.x && y == b.y; }
    bool operator!=(MCell b) const { return !(*this == b); }
    MCell operator+(MCell b) const { return {x + b.x, y + b.y}; }
    MCell operator-(MCell b) const { return {x - b.x, y - b.y}; }
};
MValue mcell(MCell cell) { MValue value; destroy(value.ptr()); from_v2i(value.ptr(), &cell); return value; }
MCell mxy(const void *value) { return value && type_of(value) == V2I ? *static_cast<MCell *>(read_internal(V2I, value)) : MCell{}; }
int64_t mint(const void *value, int64_t fallback = 0) {
    if (!value) return fallback;
    if (type_of(value) == INT) return *static_cast<int64_t *>(read_internal(INT, value));
    if (type_of(value) == FLOAT) {
        const double n = *static_cast<double *>(read_internal(FLOAT, value));
        if (std::isfinite(n) && n >= -9223372036854775808.0 && n < 9223372036854775808.0) return static_cast<int64_t>(n);
    }
    return fallback;
}
double mnum(const void *value, double fallback = 0.0) {
    if (!value) return fallback;
    return type_of(value) == FLOAT ? *static_cast<double *>(read_internal(FLOAT, value)) :
        (type_of(value) == INT ? static_cast<double>(mint(value)) : fallback);
}
bool mbool(const void *value, bool fallback = false) {
    return value && type_of(value) == BOOL ? *static_cast<GDExtensionBool *>(read_internal(BOOL, value)) != 0 : fallback;
}
int64_t msize(const void *value) { return value && type_of(value) == ARRAY ? size(read_internal(ARRAY, value)) : 0; }
const void *mat(const void *value, int64_t index) {
    return index >= 0 && index < msize(value) ? array_at(read_internal(ARRAY, value), index) : nullptr;
}
const void *mget(const void *dict, const MValue &key) {
    if (!dict || type_of(dict) != DICT) return nullptr;
    void *d = read_internal(DICT, dict);
    return has(d, key.ptr()) ? dict_at(d, key.ptr()) : nullptr;
}
const void *mget(const void *dict, const char *key) { return mget(dict, MValue(key)); }
void mput(void *dict, const MValue &key, const MValue &value) {
    void *slot = dict_write(read_internal(DICT, dict), key.ptr()); destroy(slot); copy_variant(slot, value.ptr());
}
void mput(void *dict, const char *key, const MValue &value) { mput(dict, MValue(key), value); }
void mappend(void *array, const MValue &value) {
    void *a = read_internal(ARRAY, array); const int64_t count = size(a); resize(resize_array, a, count + 1);
    void *slot = array_write(a, count); destroy(slot); copy_variant(slot, value.ptr());
}
bool mcontains(const void *array, MCell cell) { for (int64_t i = 0; i < msize(array); ++i) if (mxy(mat(array, i)) == cell) return true; return false; }
bool mcontains_id(const void *array, int64_t id) { for (int64_t i = 0; i < msize(array); ++i) if (mint(mat(array, i), -1) == id) return true; return false; }
MValue mcall(const void *object, const char *name, const void *arg = nullptr) {
    TextStorage method; make_name(&method, name, false); MValue result; destroy(result.ptr()); GDExtensionCallError e{};
    const void *args[] = {arg}; variant_call(const_cast<void *>(object), &method, arg ? args : nullptr, arg ? 1 : 0, result.ptr(), &e);
    destroy_name(&method); return result;
}
struct MProperties {
    const void *object;
    std::unordered_map<std::string, MValue> values;
    explicit MProperties(const void *value) : object(value) {}
    const void *get(const char *key) {
        auto found = values.find(key); if (found != values.end()) return found->second.ptr();
        MValue name(key); auto inserted = values.emplace(key, mcall(object, "get", name.ptr())); return inserted.first->second.ptr();
    }
};
bool movement_hot_marker;
bool mcan_act(void *row, HotStore *store, int64_t index, bool &valid) {
    ReadField exited(row, SITE_EXITED, store, index), surrender(row, SURRENDER_PENDING, store, index);
    bool exited_flag, surrender_flag;
    if (!optional_bool(exited.get(), exited_flag) || !optional_bool(surrender.get(), surrender_flag)) { valid = false; return false; }
    if (exited_flag || surrender_flag) return false;
    ReadField hp(row, HP, store, index), ko(row, KO, store, index), pose(row, POSE, store, index),
        captive(row, CAPTIVE, store, index), departed(row, DEPARTED, store, index);
    double hp_n, ko_n;
    if (!number(hp.get(), hp_n) || !number(ko.get(), ko_n) || !pose.get() || type_of(pose.get()) != STRING ||
            (captive.get() && type_of(captive.get()) != BOOL) || (departed.get() && type_of(departed.get()) != BOOL)) { valid = false; return false; }
    GDExtensionBool getting_up = false; string_equal(internal[STRING](pose.get()), &get_up_string, &getting_up);
    return hp_n > 0 && ko_n <= 0 && !getting_up && !mbool(captive.get()) && !mbool(departed.get());
}
bool mmember(void *row, HotStore *store, int64_t index, bool &valid) {
    ReadField value(row, MEMBER, store, index);
    if (value.get() && type_of(value.get()) != BOOL) { valid = false; return false; }
    return mbool(value.get(), true);
}
int mdistance(MCell a, MCell b) { return std::abs(a.x - b.x) + std::abs(a.y - b.y); }
int mdot(MCell a, MCell b) { return a.x * b.x + a.y * b.y; }
struct MTargets {
    MProperties move, deployment;
    MValue footprint{DICT};
    bool handoff_read = false;
    MCell handoff_cell;
    explicit MTargets(const void *m, const void *d) : move(m), deployment(d) {
        const void *cells = deployment.get("platform_footprint");
        for (int64_t i = 0; i < msize(cells); ++i) mput(footprint.ptr(), MValue(mat(cells, i)), MValue(true));
    }
    bool contains(const char *name, const MValue &id) { return mget(move.get(name), id) != nullptr; }
    MCell handoff() {
        if (!handoff_read) { handoff_cell = mxy(mcall(deployment.object, "get_platform_handoff_cell").ptr()); handoff_read = true; }
        return handoff_cell;
    }
    MValue resolve(int64_t member, MCell current) {
        MValue id(member); const void *final_value = mget(deployment.get("member_slot_map"), id);
        const int64_t epoch = final_value ? mint(mget(move.get("member_assignment_epoch"), id)) +
            mint(mget(move.get("member_soft_assignment_epoch"), id)) + mint(deployment.get("assignment_epoch")) : 0;
        auto answer = [&](MCell cell, const char *kind, const char *reason = "") {
            MValue out(DICT); mput(out.ptr(), "target", mcell(cell)); mput(out.ptr(), "kind", MValue(kind));
            mput(out.ptr(), "wait_reason", MValue(reason)); mput(out.ptr(), "assignment_epoch", MValue(epoch)); return out;
        };
        if (!final_value) return answer(current, "invalid", "NO_ACTIVE_PLAN");
        const MCell final_cell = mxy(final_value);
        if (contains("member_crossed_swap_hold", id)) return answer(current, "crossed_swap_hold", "TARGET_EXCHANGE_WAIT");
        if (contains("member_vacancy_chain_target", id)) return answer(final_cell, "vacancy_chain");
        if (contains("member_recovery_hold", id)) return answer(current, "recovery_hold", "VACANCY_CHAIN_WAIT");
        const int64_t role = mint(mget(deployment.get("member_role_map"), id));
        const bool platform = role == 0, inside = mget(footprint.ptr(), mcell(current)) != nullptr;
        if (platform && mget(deployment.get("ever_admitted_platform_member_ids"), id) && !inside) return answer(final_cell, "platform_return");
        if (const void *waypoint = mget(move.get("member_entry_waypoint"), id)) return answer(mxy(waypoint), "entry_waypoint", "KEEP_INGRESS_OPEN");
        if (current == final_cell) return answer(final_cell, "settled");
        if (platform && mcontains_id(deployment.get("admitted_platform_member_ids"), member) && inside) return answer(final_cell, "platform");
        if (platform && inside && mdistance(current, final_cell) <= 2) return answer(final_cell, "platform");
        const void *path = move.get("macro_path"); const MCell ingress = mxy(deployment.get("ingress_cell"));
        if (platform && msize(path)) {
            const bool far = mdistance(final_cell, ingress) > 8;
            const bool broad = msize(deployment.get("platform_footprint")) >= msize(deployment.get("platform_slots")) * 2;
            if (far && (!broad || handoff() == mxy(deployment.get("resolved_anchor")))) {
                MCell end = mxy(mat(path, msize(path) - 1)), approach = end - ingress, facing = mxy(deployment.get("final_facing"));
                MCell stage{end.x + facing.x * 2, end.y + facing.y * 2};
                if (inside && mdot(current - end, approach) < mdot(stage - end, approach) && mget(footprint.ptr(), mcell(stage))) return answer(stage, "platform_stage");
            }
        }
        if (contains("member_entry_hold", id)) return answer(current, "ingress_wait", "SIDE_SLOT_WAIT");
        bool on_ingress = mcontains(deployment.get("queue_hold_cross_section"), current) || mcontains(deployment.get("ingress_buffer_cells"), current) || inside;
        if (on_ingress && msize(path) && mdistance(final_cell, ingress) > 8) {
            MCell end = handoff(); const bool passed = mdot(current - end, end - ingress) >= 0;
            // needs_transit_soft_target is false when this same handoff was passed.
            on_ingress = inside && passed;
        }
        if (platform && on_ingress) return answer(final_cell, "platform");
        if (role == 1) {
            if (const void *waypoint = mget(move.get("member_queue_egress_waypoint"), id)) return answer(mxy(waypoint), "queue_egress", "CLEAR_INGRESS");
            return answer(final_cell, "queue", mbool(deployment.get("queue_released")) ? "" : "QUEUE_HOLD");
        }
        const void *soft = mget(move.get("member_transit_slots"), id); MCell cell = soft ? mxy(soft) : current;
        const double target_s = mnum(mget(move.get("member_path_s"), id), -INFINITY), observed = mnum(mget(move.get("member_observed_path_s"), id), -INFINITY);
        if (target_s < observed - 0.5 && mcontains(path, current)) cell = current;
        return answer(cell, "transit", cell != current ? "" : "FLOW_WAIT");
    }
};
void call_movement_targets(void *mode, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0}; reset_variant(result, DICT);
    if (argc != 4 || type_of(args[0]) != ARRAY || type_of(args[1]) != ARRAY || type_of(args[2]) != OBJECT || type_of(args[3]) != OBJECT) return;
    HotStore *store = mode == &movement_hot_marker ? static_cast<HotStore *>(instance) : nullptr;
    const int64_t count = msize(args[0]); if (msize(args[1]) != count || (store && hot_row_count(store) != count)) return;
    std::vector<int64_t> active;
    for (int64_t i = 0; i < count; ++i) {
        void *row = const_cast<void *>(mat(args[0], i)); if (type_of(row) != DICT || type_of(mat(args[1], i)) != V2I) return;
        bool valid = true; if (mmember(row, store, i, valid) && mcan_act(row, store, i, valid)) active.push_back(i); if (!valid) return;
    }
    MTargets resolver(args[2], args[3]); MValue targets(DICT);
    for (int64_t i : active) {
        ReadField identity(const_cast<void *>(mat(args[0], i)), PERSON_ID); const int64_t id = mint(identity.get(), -1);
        const MCell cell = mxy(mat(args[1], i)); MValue cells(DICT);
        mput(cells.ptr(), mcell(cell), resolver.resolve(id, cell)); mput(targets.ptr(), MValue(id), cells);
    }
    mput(result, "footprint", resolver.footprint); mput(result, "targets", targets);
}

struct MTerrain {
    int width = 0, height = 0;
    const uint8_t *flags = nullptr, *levels = nullptr, *ramps = nullptr, *blocked = nullptr;
    bool level_only = false;
    bool load(const void *packet) {
        if (msize(packet) != 6 || type_of(mat(packet, 0)) != V2I) return false;
        const MCell dimensions = mxy(mat(packet, 0)); width = dimensions.x; height = dimensions.y;
        if (width <= 0 || height <= 0 || int64_t(width) * height > 1048576) return false;
        const uint8_t **out[] = {&flags, &levels, &ramps, &blocked};
        for (int i = 0; i < 4; ++i) {
            const void *value = mat(packet, i + 1); if (!value || type_of(value) != BYTES) return false;
            void *data = read_internal(BYTES, value); const int64_t count = packed_size(size_bytes, data);
            if (i == 3 && count == 0) continue;
            if (count != int64_t(width) * height) return false;
            *out[i] = bytes_read(data, 0);
        }
        level_only = mbool(mat(packet, 5)); return true;
    }
    bool inside(MCell c) const { return c.x >= 0 && c.y >= 0 && c.x < width && c.y < height; }
    int index(MCell c) const { return c.y * width + c.x; }
    bool step(MCell a, MCell b, int direction) const {
        if (!inside(a) || !inside(b)) return false; const int i = index(a), j = index(b);
        if (!(flags[i] & 1) || !(flags[j] & 1) || (blocked && (blocked[i] || blocked[j]))) return false;
        if ((ramps[i] & (1 << (direction + 4))) || (ramps[j] & (1 << (((direction + 2) % 4) + 4)))) return false;
        const int difference = std::abs(int(levels[i]) - int(levels[j]));
        return difference == 0 || (difference == 1 && !level_only && (ramps[i] & (1 << direction)) && (ramps[j] & (1 << ((direction + 2) % 4))));
    }
};
constexpr MCell mdirections[] = {{0,-1},{1,0},{0,1},{-1,0}};
bool mexternal(const void *maps, MCell cell) {
    MValue key = mcell(cell); for (int64_t i = 0; i < msize(maps); ++i) if (mget(mat(maps, i), key)) return true; return false;
}
bool mtransit(const void *context, int64_t mid, MCell cell) {
    const void *target = mget(mget(mget(context, "targets"), MValue(mid)), mcell(cell));
    const void *kind = mget(target, "kind"); if (!kind || type_of(kind) != STRING) return false;
    MValue transit("transit"); GDExtensionBool equal = false;
    string_equal(read_internal(STRING, kind), read_internal(STRING, transit.ptr()), &equal); return equal != 0;
}
bool mstring_is(const void *value, const MValue &expected) {
    if (!value || type_of(value) != STRING) return false;
    GDExtensionBool equal = false;
    string_equal(read_internal(STRING, value), read_internal(STRING, expected.ptr()), &equal);
    return equal != 0;
}
// All field candidates, eligibility and occupancy are read here, not packed
// per person in GDScript. Maps are the originals borrowed for this stage only.
void call_movement_field(void *mode, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0}; reset_variant(result, DICT);
    if (argc != 1 || msize(args[0]) != 14) return;
    const void *p = args[0], *rows = mat(p, 0), *cells = mat(p, 1), *moving = mat(p, 2), *members = mat(p, 3),
        *context = mat(p, 4), *field_map = mat(p, 5), *owners = mat(p, 6), *reserved = mat(p, 7),
        *blocked = mat(p, 8), *initial = mat(p, 9), *external = mat(p, 10), *leases = mat(p, 11);
    const void *settings = mat(p, 12); const int64_t fid = mint(mat(settings, 0)), controlled = mint(mat(settings, 1), -1);
    MTerrain terrain; if (!terrain.load(mat(p, 13))) return;
    const int64_t count = msize(rows); if (msize(cells) != count || msize(moving) != count) return;
    HotStore *store = mode == &movement_hot_marker ? static_cast<HotStore *>(instance) : nullptr;
    if (store && hot_row_count(store) != count) return;
    std::unordered_map<int64_t, int64_t> indexes; std::vector<uint8_t> eligible(static_cast<size_t>(count));
    for (int64_t i = 0; i < count; ++i) {
        void *row = const_cast<void *>(mat(rows, i)); if (type_of(row) != DICT || type_of(mat(cells, i)) != V2I || type_of(mat(moving, i)) != V2I) return;
        ReadField identity(row, PERSON_ID); const int64_t mid = mint(identity.get(), -1); indexes[mid] = i; bool valid = true;
        eligible[static_cast<size_t>(i)] = mmember(row, store, i, valid) && mcan_act(row, store, i, valid) && mid != controlled;
        if (!valid) return;
    }
    MValue intents(DICT);
    for (int64_t m = 0; m < msize(members); ++m) {
        const int64_t mid = mint(mat(members, m), -1); auto found = indexes.find(mid); if (found == indexes.end()) continue;
        const int64_t i = found->second; if (!eligible[static_cast<size_t>(i)] || mxy(mat(moving, i)) != MCell{}) continue;
        const MCell here = mxy(mat(cells, i)); const int64_t distance = mint(mget(field_map, mcell(here)), -1);
        MValue intent(DICT); MCell best; int score = 2; bool temporary = false;
        if (mtransit(context, mid, here) && distance > 0) for (int d = 0; d < 4; ++d) {
            const MCell next = here + mdirections[d]; const MValue key = mcell(next);
            if (mint(mget(field_map, key), -1) != distance - 1 || !terrain.step(here, next, d) || mexternal(external, next)) continue;
            if (const void *lease = mget(leases, key)) { if (type_of(lease) != NIL) { MProperties entry(lease); if (mint(entry.get("formation_id")) != fid) continue; } }
            if (mget(reserved, key) || mget(blocked, key)) { temporary = true; continue; }
            const int64_t owner = mint(mget(owners, key), -1); int occupancy = 0;
            if (owner < 0 && mget(initial, key)) continue;
            if (owner >= 0) {
                if (owner >= count) return;
                if (mxy(mat(moving, owner)) != MCell{}) { temporary = true; continue; }
                if (!eligible[static_cast<size_t>(owner)]) continue;
                ReadField identity(const_cast<void *>(mat(rows, owner)), PERSON_ID);
                if (!mtransit(context, mint(identity.get(), -1), next)) continue;
                occupancy = 1;
            }
            if (occupancy < score) { best = next; score = occupancy; }
        }
        if (score < 2 || temporary) { mput(intent.ptr(), "handled", MValue(true)); mput(intent.ptr(), "step", mcell(best)); }
        mput(intents.ptr(), MValue(mid), intent);
    }
    destroy(result); copy_variant(result, intents.ptr());
}

// One propose-stage read: warm the original target resolver in roster order,
// then choose field/route/direct steps without making per-person GD packets.
// The Army still applies blocked waits and submits each proposal to the Grid.
void call_movement_propose(void *mode, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0}; reset_variant(result, DICT);
    if (argc != 1 || msize(args[0]) != 17) return;
    const void *p = args[0], *rows = mat(p, 0), *cells = mat(p, 1), *moving = mat(p, 2),
        *slots = mat(p, 3), *members = mat(p, 4), *move = mat(p, 5), *deployment = mat(p, 6),
        *field_map = mat(p, 7), *owners = mat(p, 8), *reserved = mat(p, 9), *blocked = mat(p, 10),
        *initial = mat(p, 11), *proposed = mat(p, 12), *external = mat(p, 13), *leases = mat(p, 14),
        *settings = mat(p, 15);
    if (type_of(rows) != ARRAY || type_of(cells) != ARRAY || type_of(moving) != ARRAY ||
            type_of(slots) != ARRAY || type_of(members) != ARRAY || type_of(move) != OBJECT ||
            type_of(deployment) != OBJECT || type_of(field_map) != DICT || type_of(owners) != DICT ||
            type_of(reserved) != DICT || type_of(blocked) != DICT || type_of(initial) != DICT ||
            type_of(proposed) != DICT || type_of(external) != ARRAY || type_of(leases) != DICT ||
            msize(settings) != 3 || type_of(mat(settings, 0)) != INT ||
            type_of(mat(settings, 1)) != INT || type_of(mat(settings, 2)) != BOOL) return;
    MTerrain terrain; if (!terrain.load(mat(p, 16))) return;
    const int64_t count = msize(rows), member_count = msize(members);
    if (count > 10000 || member_count > count || msize(cells) != count ||
            msize(moving) != count || msize(slots) != count || msize(external) == 0) return;
    for (int64_t i = 0; i < msize(external); ++i) if (type_of(mat(external, i)) != DICT) return;
    HotStore *store = mode == &movement_hot_marker ? static_cast<HotStore *>(instance) : nullptr;
    if (store && hot_row_count(store) != count) return;
    const int64_t fid = mint(mat(settings, 0)), controlled = mint(mat(settings, 1));
    const bool exchange = mbool(mat(settings, 2));
    std::unordered_map<int64_t, int64_t> indexes;
    std::vector<int64_t> identities(static_cast<size_t>(count));
    std::vector<uint8_t> target_active(static_cast<size_t>(count)), eligible(static_cast<size_t>(count)), transit(static_cast<size_t>(count));
    for (int64_t i = 0; i < count; ++i) {
        void *row = const_cast<void *>(mat(rows, i));
        if (type_of(row) != DICT || type_of(mat(cells, i)) != V2I ||
                type_of(mat(moving, i)) != V2I || type_of(mat(slots, i)) != V2I) return;
        ReadField identity(row, PERSON_ID);
        if (!identity.get() || type_of(identity.get()) != INT) return;
        const int64_t mid = mint(identity.get());
        if (!indexes.emplace(mid, i).second) return; // Unusual identity aliasing uses the old path.
        identities[static_cast<size_t>(i)] = mid;
        bool valid = true;
        const bool active = mmember(row, store, i, valid) && mcan_act(row, store, i, valid);
        if (!valid) return;
        target_active[static_cast<size_t>(i)] = active;
        eligible[static_cast<size_t>(i)] = active && mid != controlled;
    }
    MTargets resolver(move, deployment);
    const MValue transit_label("transit"), guard("guard"), guard_raise("guard_raise"),
        guard_break("guard_break"), guard_lower("guard_lower"), rescue("rescue");
    for (int64_t i = 0; i < count; ++i) {
        if (!target_active[static_cast<size_t>(i)]) continue;
        MValue target = resolver.resolve(identities[static_cast<size_t>(i)], mxy(mat(cells, i)));
        transit[static_cast<size_t>(i)] = mstring_is(mget(target.ptr(), "kind"), transit_label);
    }
    MValue output(ARRAY);
    void *out = read_internal(ARRAY, output.ptr());
    resize(resize_array, out, member_count * 4);
    int64_t used = 0, field_count = 0;
    auto emit = [&](const MValue &value) {
        void *slot = array_write(out, used++); destroy(slot); copy_variant(slot, value.ptr());
    };
    for (int64_t ordinal = 0; ordinal < member_count; ++ordinal) {
        const void *id_value = mat(members, ordinal);
        if (type_of(id_value) != INT) return;
        const int64_t mid = mint(id_value);
        auto found = indexes.find(mid); if (found == indexes.end()) continue;
        const int64_t i = found->second;
        if (!eligible[static_cast<size_t>(i)] || mxy(mat(moving, i)) != MCell{}) continue;
        ++field_count; // Matches movement_field's diagnostic count before side-pocket/action skips.
        const MCell here = mxy(mat(cells, i)), goal = mxy(mat(slots, i));
        const int64_t distance = mint(mget(field_map, mcell(here)), -1);
        MCell step; bool handled = false, temporary = false; int best_score = 2;
        if (transit[static_cast<size_t>(i)] && distance > 0) for (int d = 0; d < 4; ++d) {
            const MCell next = here + mdirections[d]; const MValue key = mcell(next);
            if (mint(mget(field_map, key), -1) != distance - 1 || !terrain.step(here, next, d) ||
                    mexternal(external, next)) continue;
            if (const void *lease = mget(leases, key)) {
                if (type_of(lease) != NIL) {
                    if (type_of(lease) != OBJECT) return;
                    MProperties entry(lease); if (mint(entry.get("formation_id")) != fid) continue;
                }
            }
            if (mget(reserved, key) || mget(blocked, key)) { temporary = true; continue; }
            const int64_t owner = mint(mget(owners, key), -1); int score = 0;
            if (owner < 0 && mget(initial, key)) continue;
            if (owner >= 0) {
                if (owner >= count || mxy(mat(cells, owner)) != next) return;
                if (mxy(mat(moving, owner)) != MCell{}) { temporary = true; continue; }
                if (!eligible[static_cast<size_t>(owner)] || !transit[static_cast<size_t>(owner)]) continue;
                score = 1;
            }
            if (score < best_score) { step = next; best_score = score; }
        }
        handled = best_score < 2 || temporary;
        if (mget(proposed, MValue(mid))) continue;
        void *row = const_cast<void *>(mat(rows, i));
        ReadField attack(row, ATTACK, store, i), stagger(row, STAGGER, store, i), pose(row, POSE, store, i);
        if ((attack.get() && type_of(attack.get()) != NIL && type_of(attack.get()) != BOOL) ||
                (stagger.get() && type_of(stagger.get()) != NIL && type_of(stagger.get()) != INT &&
                    type_of(stagger.get()) != FLOAT) || !pose.get() || type_of(pose.get()) != STRING) return;
        if ((!exchange && mbool(attack.get())) || (exchange && mnum(stagger.get()) > 0.0) ||
                mstring_is(pose.get(), guard) || mstring_is(pose.get(), guard_raise) ||
                mstring_is(pose.get(), guard_break) || mstring_is(pose.get(), guard_lower) ||
                mstring_is(pose.get(), rescue)) continue;
        if (handled && step == MCell{}) continue;
        if (!handled) {
            if (here == goal) continue;
            const MValue id(mid);
            const void *path = mget(resolver.move.get("member_paths"), id);
            const void *target = mget(resolver.move.get("member_route_target"), id);
            const void *epoch = mget(resolver.move.get("member_route_epoch"), id);
            const int64_t expected[] = {mint(resolver.move.get("path_epoch")),
                mint(mget(resolver.move.get("member_assignment_epoch"), id)),
                mint(resolver.move.get("terrain_revision")), mint(resolver.move.get("order_serial"))};
            bool current = path && type_of(path) == ARRAY && target && type_of(target) == V2I &&
                mxy(target) == goal && msize(epoch) == 4;
            for (int j = 0; current && j < 4; ++j)
                current = type_of(mat(epoch, j)) == INT && mint(mat(epoch, j)) == expected[j];
            if (current && msize(path) > 1) {
                if (type_of(mat(path, 0)) != V2I || type_of(mat(path, 1)) != V2I ||
                        type_of(mat(path, msize(path) - 1)) != V2I) return;
                const MCell candidate = mxy(mat(path, 1));
                if (mxy(mat(path, 0)) == here && mxy(mat(path, msize(path) - 1)) == goal)
                    for (int d = 0; d < 4; ++d)
                        if (here + mdirections[d] == candidate && terrain.step(here, candidate, d)) { step = candidate; break; }
            }
            const int64_t dx = int64_t(goal.x) - here.x, dy = int64_t(goal.y) - here.y;
            if (step == MCell{} && (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy) == 1)
                for (int d = 0; d < 4; ++d)
                    if (here + mdirections[d] == goal && terrain.step(here, goal, d)) { step = goal; break; }
        }
        emit(MValue(mid)); emit(MValue(i)); emit(MValue(handled)); emit(mcell(step));
    }
    resize(resize_array, out, used);
    mput(result, "rows", output);
    mput(result, "field_count", MValue(field_count));
}

// Exact canonical foot A*: N/E/S/W, f/h/insertion ordering, stale-pop budget,
// occupancy costs and failed-query dependencies match _find_local_route.
void call_movement_route(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0}; reset_variant(result, DICT);
    if (argc != 1 || msize(args[0]) != 11) return;
    const void *p = args[0], *owners = mat(p, 3), *reserved = mat(p, 4), *external = mat(p, 5),
        *blocked = mat(p, 6), *cells = mat(p, 7), *slots = mat(p, 8), *settings = mat(p, 9);
    MTerrain terrain; if (!terrain.load(mat(p, 0)) || type_of(mat(p, 1)) != V2I || type_of(mat(p, 2)) != V2I) return;
    if (!owners || type_of(owners) != DICT || !reserved || type_of(reserved) != DICT || msize(cells) != msize(slots) || msize(settings) != 5) return;
    const MCell start = mxy(mat(p, 1)), goal = mxy(mat(p, 2));
    if (!terrain.inside(start) || !terrain.inside(goal) || start == goal) return;
    const int limit = static_cast<int>(mint(mat(settings, 0))), people = static_cast<int>(msize(cells));
    const bool allow = mbool(mat(settings, 1)), avoid = mbool(mat(settings, 2)), cheap = mbool(mat(settings, 3)), track = mbool(mat(settings, 4));
    MValue route(ARRAY), dependencies(DICT); bool incomplete = false; int head = 0; const char *outcome = "exhausted";
    auto occupied_first = [&](MCell next) { const MValue key = mcell(next); return mget(owners, key) || mget(blocked, key) || mexternal(external, next); };
    // Keep both exact L routes before the heap, including their original order.
    if (mbool(mat(p, 10)) && mdistance(start, goal) <= 12 && limit >= mdistance(start, goal) + 1) {
        for (bool horizontal_first : {true, false}) {
            std::vector<MCell> direct{start}; MCell current = start;
            while (current != goal) {
                const MCell diff = goal - current; const bool horizontal = diff.x != 0 && (horizontal_first || diff.y == 0);
                const int d = horizontal ? (diff.x > 0 ? 1 : 3) : (diff.y > 0 ? 2 : 0);
                const MCell next = current + mdirections[d]; const MValue key = mcell(next);
                if (!terrain.step(current, next, d) || (avoid && current == start && occupied_first(next)) ||
                    (mexternal(external, next) && next != goal) ||
                    (mget(reserved, key) && mint(mget(reserved, key)) != -1) || (mget(owners, key) && next != goal)) break;
                direct.push_back(next); current = next;
            }
            if (current == goal) {
                for (MCell c : direct) mappend(route.ptr(), mcell(c)); outcome = "direct"; break;
            }
        }
    }
    if (msize(route.ptr()) == 0) {
        struct Node { int index, cost, h, sequence; };
        auto later = [](const Node &a, const Node &b) { const int af = a.cost + a.h, bf = b.cost + b.h;
            return af != bf ? af > bf : (a.h != b.h ? a.h > b.h : a.sequence > b.sequence); };
        const int count = terrain.width * terrain.height, start_index = terrain.index(start), goal_index = terrain.index(goal);
        std::vector<int> previous(static_cast<size_t>(count), -2), costs(static_cast<size_t>(count), 0);
        std::vector<uint8_t> closed(static_cast<size_t>(count), 0);
        std::vector<Node> heap{{start_index, 0, mdistance(start, goal), 0}};
        previous[start_index] = -1; int sequence = 1; bool found = false; size_t dependency_count = 0;
        while (!heap.empty() && head < limit) {
            std::pop_heap(heap.begin(), heap.end(), later); const Node item = heap.back(); heap.pop_back();
            ++head; if (closed[item.index] || item.cost != costs[item.index]) continue;
            closed[item.index] = 1; const MCell current{item.index % terrain.width, item.index / terrain.width};
            if (current == goal) { found = true; break; }
            for (int d = 0; d < 4; ++d) {
                const MCell next = current + mdirections[d]; if (!terrain.inside(next)) continue;
                const int index = terrain.index(next); if (closed[index] || !terrain.step(current, next, d)) continue;
                if (avoid && current == start && occupied_first(next)) continue;
                const MValue key = mcell(next); const bool external_block = mexternal(external, next);
                const void *reservation = mget(reserved, key), *owner = mget(owners, key);
                if (track) {
                    const bool already = mget(dependencies.ptr(), key) != nullptr;
                    if (already || dependency_count < 512) {
                        MValue entry(ARRAY); mappend(entry.ptr(), MValue(external_block));
                        mappend(entry.ptr(), reservation ? MValue(reservation) : MValue()); mappend(entry.ptr(), owner ? MValue(owner) : MValue());
                        mput(dependencies.ptr(), key, entry); if (!already) ++dependency_count;
                    } else incomplete = true;
                }
                if ((external_block && next != goal) || (reservation && mint(reservation) != -1)) continue;
                int cost = item.cost + 1;
                if (owner && next != goal) {
                    const int64_t own = mint(owner, -1);
                    if (own >= 0 && own < people) {
                        if (mxy(mat(cells, own)) == mxy(mat(slots, own))) continue;
                        if (!allow) continue; cost += cheap ? 1 : 3;
                    } else if (!allow) continue;
                }
                if (previous[index] != -2 && costs[index] <= cost) continue;
                heap.push_back({index, cost, mdistance(next, goal), sequence++}); std::push_heap(heap.begin(), heap.end(), later);
                previous[index] = item.index; costs[index] = cost;
            }
        }
        if (found || previous[goal_index] != -2) {
            std::vector<MCell> reverse;
            for (int cursor = goal_index; cursor >= 0; cursor = previous[cursor]) reverse.push_back({cursor % terrain.width, cursor / terrain.width});
            for (auto i = reverse.rbegin(); i != reverse.rend(); ++i) mappend(route.ptr(), mcell(*i));
            outcome = "success";
        } else if (!heap.empty() && head >= limit) outcome = "capped";
    }
    mput(result, "route", route); mput(result, "head", MValue(int64_t(head))); mput(result, "outcome", MValue(outcome));
    mput(result, "capped", MValue(std::strcmp(outcome, "capped") == 0));
    if (track) { mput(result, "dependencies", dependencies); mput(result, "dependency_incomplete", MValue(incomplete)); }
}
