// Original TerrainArmy idle rows, synchronously borrowed for one consecutive run.
// No retained person pointers, copied state, jobs, clocks, callbacks or simulation.
// Uses the public Godot 4.4+ C interface, not Godot's private Dictionary layout.
#include "vendor/gdextension_interface.h"
#include <cmath>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <memory>
#include <vector>
#include <algorithm>
#include <array>
#include <unordered_map>
#include <unordered_set>

namespace {
constexpr auto ARRAY = GDEXTENSION_VARIANT_TYPE_ARRAY;
constexpr auto DICT = GDEXTENSION_VARIANT_TYPE_DICTIONARY;
constexpr auto FLOAT = GDEXTENSION_VARIANT_TYPE_FLOAT;
constexpr auto INT = GDEXTENSION_VARIANT_TYPE_INT;
constexpr auto STRING = GDEXTENSION_VARIANT_TYPE_STRING;
constexpr auto NAME = GDEXTENSION_VARIANT_TYPE_STRING_NAME;
constexpr auto V2I = GDEXTENSION_VARIANT_TYPE_VECTOR2I;
constexpr auto V2 = GDEXTENSION_VARIANT_TYPE_VECTOR2;
constexpr auto BOOL = GDEXTENSION_VARIANT_TYPE_BOOL;
constexpr auto BYTES = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
constexpr auto INTS = GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY;
constexpr auto LONGS = GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY;
constexpr auto VECTORS = GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY;
constexpr auto FLOATS = GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY;
constexpr auto DOUBLES = GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY;
constexpr auto NIL = GDEXTENSION_VARIANT_TYPE_NIL;
constexpr auto OBJECT = GDEXTENSION_VARIANT_TYPE_OBJECT;
// Opaque storage, not a reimplementation of Variant. The generated 4.7.2 API
// specifies 24/40 bytes for float/double Variant and 8 for x64 String/StringName.
struct alignas(8) VariantStorage { unsigned char bytes[40]; };
struct alignas(8) TextStorage { unsigned char bytes[8]; };
static_assert(sizeof(void *) == 8, "This library targets x64 only");
GDExtensionClassLibraryPtr library;
bool recovery_marker; // Stateless entry-point tag, never person data.
GDExtensionInterfaceVariantGetType type_of;
GDExtensionInterfaceVariantDestroy destroy;
GDExtensionInterfaceVariantNewCopy copy_variant;
GDExtensionInterfaceVariantGetKeyed get_keyed;
GDExtensionInterfaceVariantCall variant_call;
GDExtensionInterfaceVariantHash variant_hash;
GDExtensionInterfaceVariantGetObjectInstanceId object_instance_id;
GDExtensionInterfaceArrayOperatorIndexConst array_at;
GDExtensionInterfaceArrayOperatorIndex array_write;
GDExtensionInterfaceVariantConstruct variant_construct;
GDExtensionInterfacePackedByteArrayOperatorIndex bytes_write;
GDExtensionInterfacePackedByteArrayOperatorIndexConst bytes_read;
GDExtensionInterfacePackedInt32ArrayOperatorIndex ints_write;
GDExtensionInterfacePackedInt32ArrayOperatorIndexConst ints_read;
GDExtensionInterfacePackedFloat32ArrayOperatorIndex floats_write;
GDExtensionInterfacePackedInt64ArrayOperatorIndex longs_write;
GDExtensionInterfacePackedInt64ArrayOperatorIndexConst longs_read;
GDExtensionInterfacePackedVector2ArrayOperatorIndex vectors_write;
GDExtensionInterfacePackedVector2ArrayOperatorIndexConst vectors_read;
GDExtensionInterfacePackedFloat64ArrayOperatorIndexConst doubles_read;
GDExtensionInterfacePackedFloat64ArrayOperatorIndex doubles_write;
GDExtensionPtrBuiltInMethod resize_array, resize_bytes, resize_ints, resize_vectors, size_vectors, size_doubles;
GDExtensionPtrBuiltInMethod resize_longs, resize_doubles, resize_floats, size_ints, size_longs, size_bytes;
GDExtensionPtrBuiltInMethod vector_distance, vector_squared_distance;
GDExtensionPtrUtilityFunction same_variant;
GDExtensionInterfaceDictionaryOperatorIndexConst dict_at;
GDExtensionInterfaceDictionaryOperatorIndex dict_write;
GDExtensionInterfaceClassdbConstructObject2 construct_object;
GDExtensionInterfaceObjectSetInstance set_instance;
GDExtensionInterfaceClassdbRegisterExtensionClass4 register_class;
GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
GDExtensionInterfaceWorkerThreadPoolAddNativeGroupTask add_group_task;
GDExtensionInterfaceObjectMethodBindPtrcall method_ptrcall;
GDExtensionInterfaceGlobalGetSingleton get_singleton;
GDExtensionInterfaceClassdbGetMethodBind get_method_bind;
GDExtensionObjectPtr worker_pool;
GDExtensionMethodBindPtr wait_group_task;
GDExtensionInterfaceStringNameNewWithLatin1Chars make_name;
GDExtensionInterfaceStringNewWithLatin1Chars make_string;
GDExtensionVariantGetInternalPtrFunc internal[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
GDExtensionVariantFromTypeConstructorFunc from_float, from_int, from_string, from_name, from_v2i, from_bool;
GDExtensionPtrDestructor destroy_string, destroy_name;
GDExtensionPtrBuiltInMethod array_size, array_readonly, array_typed, dict_size, dict_has, dict_empty, dict_readonly, dict_typed;
GDExtensionPtrOperatorEvaluator string_equal, name_equal;
TextStorage class_name, hot_class_name, parent_name, idle_string, unconscious_string, down_string, guard_raise_string, guard_lower_string, guard_break_string, rescue_string, male_string, female_string, get_up_string, empty_name, empty_string;
TextStorage keys_method_name, typed_builtin_method_name, typed_class_method_name, typed_script_method_name;
enum Key { AGE, THINK, POSE, HP, KO, STUN, GRACE, VISUAL, DURATION, COOLDOWN, STAGGER, SKILL, RANGED, FATIGUE, REST, PERSON_ID, PAGE, PALETTE, ROLE, CAPTIVE, DEPARTED, OWNER, UNIT, IDENTITY, CELL, FACTION, READY, RECEIVE, MEMBER, CARGO, PRESENT, ATTACK, LEFT, FACING, KEY_COUNT };
VariantStorage keys[KEY_COUNT];
VariantStorage lookup_keys[KEY_COUNT];
const char *key_text[KEY_COUNT] = {"age", "think", "pose", "hp", "ko", "stun", "grace", "exchange_visual", "exchange_pose_duration", "exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown", "fatigue", "fatigue_rest", "person_id", "page", "palette", "visual_role", "captive", "departed", "owner", "unit", "id", "cell", "faction", "ready", "receive", "member", "cargo", "present", "attack", "left", "facing"};
struct HotStore;
int64_t hot_row_count(HotStore *store);
bool hot_owns(Key key);
void *hot_value(HotStore *store, int64_t index, Key key);
bool hot_render_marker, hot_capture_columns_marker, hot_capture_people_marker, hot_presence_marker, hot_presence_delta_marker;

// Bounded, joined, read-only ranges. No callback or original-state write may
// enter a task; callers allocate all output containers before dispatch.
template <typename Function> void project_ranges(int64_t count, Function project) {
    const uint32_t chunks = count >= 1024 && worker_pool && wait_group_task ? 4 : 1;
    auto run = [&](uint32_t chunk) { project(count * chunk / chunks, count * (chunk + 1) / chunks, chunk); };
    if (chunks == 1) { run(0); return; }
    const auto callback = [](void *context, uint32_t chunk) { (*static_cast<const decltype(run) *>(context))(chunk); };
    const int64_t group = add_group_task(worker_pool, callback, &run, chunks, chunks, true, &empty_string);
    if (group < 0) {
        for (uint32_t chunk = 0; chunk < chunks; ++chunk) run(chunk);
        return;
    }
    const void *wait_args[] = {&group};
    method_ptrcall(wait_group_task, worker_pool, wait_args, nullptr);
}

bool predicate(GDExtensionPtrBuiltInMethod method, void *self) {
    GDExtensionBool result = false;
    method(self, nullptr, &result, 0);
    return result != 0;
}
bool has(void *dict, const void *key) {
    const void *args[] = {key};
    GDExtensionBool result = false;
    dict_has(dict, args, &result, 1);
    return result != 0;
}
void *field(void *dict, Key key) {
    return has(dict, &lookup_keys[key]) ? dict_at(dict, &lookup_keys[key]) : nullptr;
}
// Read-only projection only. One public lookup reports absence separately from
// NIL; the returned Variant belongs to this stack scope, never a person mirror.
struct ReadField {
    VariantStorage value;
    GDExtensionBool valid = false;
    bool owned = false;
    void *borrowed = nullptr;
    ReadField(void *row, Key key, HotStore *store = nullptr, int64_t index = 0) {
        if (store && hot_owns(key)) {
            borrowed = hot_value(store, index, key);
            valid = borrowed != nullptr;
        } else {
            get_keyed(row, &lookup_keys[key], &value, &valid);
            owned = true;
        }
    }
    ~ReadField() { if (owned) destroy(&value); }
    ReadField(const ReadField &) = delete;
    ReadField &operator=(const ReadField &) = delete;
    void *get() { return borrowed ? borrowed : (valid ? &value : nullptr); }
};
bool number(void *value, double &result, double **storage = nullptr) {
    if (storage) *storage = nullptr;
    if (!value) return false;
    const auto type = type_of(value);
    if (type == FLOAT) {
        auto *data = static_cast<double *>(internal[FLOAT](value));
        result = *data;
        if (storage) *storage = data;
    }
    else if (type == INT) result = static_cast<double>(*static_cast<int64_t *>(internal[INT](value)));
    else return false;
    return std::isfinite(result);
}
bool zero(void *value, bool optional = false) {
    if (!value) return optional;
    double n;
    return number(value, n) && n == 0.0;
}
void assign_float(void *slot, double value) {
    if (type_of(slot) == FLOAT) *static_cast<double *>(internal[FLOAT](slot)) = value;
    else { destroy(slot); from_float(slot, &value); }
}
void write_float(void *dict, Key key, double value) {
    // Reacquire on every write: an absent optional key can grow the dictionary.
    void *slot = dict_write(dict, &keys[key]);
    assign_float(slot, value);
}
int64_t size(void *array) {
    int64_t count = 0;
    array_size(array, nullptr, &count, 0);
    return count;
}

// Test-only logical snapshot comparison. Dictionary insertion order is not
// gameplay state, but every admitted leaf type and every key type is exact.
enum class ExactResult : int64_t { UNSUPPORTED = -1, UNEQUAL = 0, EQUAL = 1 };
void *read_internal(GDExtensionVariantType type, const void *value) {
    return internal[type](const_cast<void *>(value));
}
bool noargs(const void *value, const TextStorage &method, VariantStorage &output) {
    GDExtensionCallError error{};
    variant_call(const_cast<void *>(value), &method, nullptr, 0, &output, &error);
    return error.error == GDEXTENSION_CALL_OK;
}
bool supported_leaf(GDExtensionVariantType type) {
    return type == NIL || type == BOOL || type == INT || type == FLOAT || type == STRING ||
        type == NAME || type == V2I || type == V2 || type == DOUBLES;
}
ExactResult leaf_equal(const void *left, const void *right) {
    const auto type = type_of(left);
    if (type != type_of(right)) return ExactResult::UNEQUAL;
    switch (type) {
        case NIL: return ExactResult::EQUAL;
        case BOOL: return *static_cast<GDExtensionBool *>(read_internal(BOOL, left)) ==
            *static_cast<GDExtensionBool *>(read_internal(BOOL, right)) ? ExactResult::EQUAL : ExactResult::UNEQUAL;
        case INT: return *static_cast<int64_t *>(read_internal(INT, left)) ==
            *static_cast<int64_t *>(read_internal(INT, right)) ? ExactResult::EQUAL : ExactResult::UNEQUAL;
        case FLOAT: return std::memcmp(read_internal(FLOAT, left), read_internal(FLOAT, right), sizeof(double)) == 0 ?
            ExactResult::EQUAL : ExactResult::UNEQUAL;
        case V2I: return std::memcmp(read_internal(V2I, left), read_internal(V2I, right), sizeof(int32_t) * 2) == 0 ?
            ExactResult::EQUAL : ExactResult::UNEQUAL;
        case V2: return std::memcmp(read_internal(V2, left), read_internal(V2, right), sizeof(float) * 2) == 0 ?
            ExactResult::EQUAL : ExactResult::UNEQUAL;
        case STRING:
        case NAME: {
            GDExtensionBool equal = false;
            (type == STRING ? string_equal : name_equal)(read_internal(type, left), read_internal(type, right), &equal);
            return equal ? ExactResult::EQUAL : ExactResult::UNEQUAL;
        }
        case DOUBLES: {
            void *a = read_internal(DOUBLES, left), *b = read_internal(DOUBLES, right);
            int64_t count = 0, other = 0;
            size_doubles(a, nullptr, &count, 0); size_doubles(b, nullptr, &other, 0);
            if (count != other) return ExactResult::UNEQUAL;
            for (int64_t i = 0; i < count; ++i)
                if (std::memcmp(doubles_read(a, i), doubles_read(b, i), sizeof(double)) != 0) return ExactResult::UNEQUAL;
            return ExactResult::EQUAL;
        }
        default: return ExactResult::UNSUPPORTED;
    }
}
bool typed_array_builtin(const void *value, int64_t &builtin) {
    VariantStorage result{};
    const bool called = noargs(value, typed_builtin_method_name, result);
    const bool valid = called && type_of(&result) == INT;
    if (valid) builtin = *static_cast<int64_t *>(internal[INT](&result));
    destroy(&result);
    return valid;
}
bool supported_array_type(const void *value) {
    if (!predicate(array_typed, read_internal(ARRAY, value))) return true;
    int64_t builtin = -1;
    if (!typed_array_builtin(value, builtin) || builtin == GDEXTENSION_VARIANT_TYPE_OBJECT ||
            builtin == GDEXTENSION_VARIANT_TYPE_CALLABLE || builtin == GDEXTENSION_VARIANT_TYPE_SIGNAL ||
            (!supported_leaf(static_cast<GDExtensionVariantType>(builtin)) && builtin != ARRAY && builtin != DICT)) return false;
    VariantStorage class_name_result{}, script_result{};
    const bool class_ok = noargs(value, typed_class_method_name, class_name_result) &&
        type_of(&class_name_result) == NAME;
    GDExtensionBool class_empty = false;
    if (class_ok) name_equal(read_internal(NAME, &class_name_result), &empty_name, &class_empty);
    const bool script_called = noargs(value, typed_script_method_name, script_result);
    const auto script_type = type_of(&script_result);
    const bool script_ok = script_called && (script_type == NIL ||
        (script_type == OBJECT && object_instance_id(&script_result) == 0));
    destroy(&class_name_result);
    destroy(&script_result);
    return class_ok && class_empty && script_ok;
}
bool get_keys(const void *value, VariantStorage &output) {
    return noargs(value, keys_method_name, output) && type_of(&output) == ARRAY;
}
int64_t dictionary_size(void *value) {
    int64_t count = 0;
    dict_size(value, nullptr, &count, 0);
    return count;
}
bool contains_unsupported(const void *value, int depth = 0) {
    if (depth > 64) return true;
    const auto type = type_of(value);
    if (type == ARRAY) {
        if (!supported_array_type(value)) return true;
        void *array = read_internal(ARRAY, value);
        for (int64_t i = 0, count = size(array); i < count; ++i)
            if (contains_unsupported(array_at(array, i), depth + 1)) return true;
        return false;
    }
    if (type == DICT) {
        void *dict = read_internal(DICT, value);
        if (predicate(dict_typed, dict)) return true;
        VariantStorage keys_result{};
        if (!get_keys(value, keys_result)) { destroy(&keys_result); return true; }
        void *keys_array = internal[ARRAY](&keys_result);
        bool unsupported = size(keys_array) != dictionary_size(dict);
        for (int64_t i = 0, count = size(keys_array); !unsupported && i < count; ++i) {
            void *key = array_at(keys_array, i);
            void *child = dict_at(dict, key);
            unsupported = !child || contains_unsupported(key, depth + 1) || contains_unsupported(child, depth + 1);
        }
        destroy(&keys_result);
        return unsupported;
    }
    return !supported_leaf(type);
}
struct KeyEntry { uint64_t token; int64_t ordinal; };
uint64_t key_token(const void *key) {
    return (static_cast<uint64_t>(type_of(key)) << 56) ^ static_cast<uint64_t>(variant_hash(key));
}
ExactResult exact_value_equal(const void *left, const void *right, int depth = 0) {
    if (depth > 64) return ExactResult::UNSUPPORTED;
    const auto type = type_of(left);
    if (type != type_of(right)) return ExactResult::UNEQUAL;
    if (type == ARRAY) {
        void *a = read_internal(ARRAY, left), *b = read_internal(ARRAY, right);
        const int64_t count = size(a);
        if (count != size(b)) return ExactResult::UNEQUAL;
        const bool typed_a = predicate(array_typed, a), typed_b = predicate(array_typed, b);
        if (typed_a != typed_b) return ExactResult::UNEQUAL;
        if (typed_a) {
            int64_t builtin_a = -1, builtin_b = -1;
            if (!typed_array_builtin(left, builtin_a) || !typed_array_builtin(right, builtin_b) ||
                    !supported_array_type(left) || !supported_array_type(right)) return ExactResult::UNSUPPORTED;
            if (builtin_a != builtin_b) return ExactResult::UNEQUAL;
        }
        for (int64_t i = 0; i < count; ++i) {
            const auto result = exact_value_equal(array_at(a, i), array_at(b, i), depth + 1);
            if (result != ExactResult::EQUAL) return result;
        }
        return ExactResult::EQUAL;
    }
    if (type == DICT) {
        void *a = read_internal(DICT, left), *b = read_internal(DICT, right);
        const int64_t count = dictionary_size(a);
        if (count != dictionary_size(b)) return ExactResult::UNEQUAL;
        if (predicate(dict_typed, a) || predicate(dict_typed, b)) return ExactResult::UNSUPPORTED;
        VariantStorage left_keys{}, right_keys{};
        const bool keys_ok = get_keys(left, left_keys) && get_keys(right, right_keys);
        if (!keys_ok) { destroy(&left_keys); destroy(&right_keys); return ExactResult::UNSUPPORTED; }
        void *left_array = internal[ARRAY](&left_keys), *right_array = internal[ARRAY](&right_keys);
        ExactResult result = ExactResult::EQUAL;
        if (size(left_array) != count || size(right_array) != count) result = ExactResult::UNSUPPORTED;
        std::array<KeyEntry, 32> local_entries{};
        std::unique_ptr<KeyEntry[]> heap_entries;
        if (count > static_cast<int64_t>(local_entries.size())) heap_entries = std::make_unique<KeyEntry[]>(count);
        KeyEntry *entries = heap_entries ? heap_entries.get() : local_entries.data();
        for (int64_t i = 0; result == ExactResult::EQUAL && i < count; ++i) {
            void *key = array_at(right_array, i);
            if (!supported_leaf(type_of(key))) { result = ExactResult::UNSUPPORTED; break; }
            entries[i] = {key_token(key), i};
        }
        if (result == ExactResult::EQUAL) std::sort(entries, entries + count,
            [](const KeyEntry &x, const KeyEntry &y) { return x.token < y.token; });
        for (int64_t i = 0; result == ExactResult::EQUAL && i < count; ++i) {
            void *key = array_at(left_array, i);
            if (!supported_leaf(type_of(key))) { result = ExactResult::UNSUPPORTED; break; }
            const uint64_t token = key_token(key);
            const KeyEntry probe{token, 0};
            auto *entry = std::lower_bound(entries, entries + count, probe,
                [](const KeyEntry &x, const KeyEntry &y) { return x.token < y.token; });
            void *matched = nullptr;
            for (; entry != entries + count && entry->token == token; ++entry) {
                void *candidate = array_at(right_array, entry->ordinal);
                if (leaf_equal(key, candidate) == ExactResult::EQUAL) { matched = candidate; break; }
            }
            if (!matched) { result = ExactResult::UNEQUAL; break; }
            void *child_a = dict_at(a, key), *child_b = dict_at(b, matched);
            result = child_a && child_b ? exact_value_equal(child_a, child_b, depth + 1) : ExactResult::UNSUPPORTED;
        }
        destroy(&left_keys); destroy(&right_keys);
        return result;
    }
    return leaf_equal(left, right);
}
int exact_oracle_modes[] = {0, 1};
void call_exact_oracle(void *mode_ptr, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    const int mode = *static_cast<int *>(mode_ptr);
    const int expected = mode == 0 ? 2 : 1;
    if (argc != expected) {
        error->error = argc < expected ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = expected;
        return;
    }
    destroy(result);
    if (mode == 0) {
        int64_t answer = static_cast<int64_t>(exact_value_equal(args[0], args[1]));
        from_int(result, &answer);
    } else {
        GDExtensionBool answer = contains_unsupported(args[0]);
        from_bool(result, &answer);
    }
}

int64_t advance(void *rows, void *moving, void *rescues, int64_t start, int64_t end, double delta, double recovery = -1.0) {
    if (!std::isfinite(delta) || delta <= 0.0 || start < 0 || end < start || end > size(rows) || end > size(moving)) return start;
    const bool no_rescues = predicate(dict_empty, rescues);
    for (int64_t i = start; i < end; ++i) {
        void *row = array_at(rows, i);
        void *cell = array_at(moving, i);
        if (type_of(row) != DICT || type_of(cell) != V2I) return i;
        void *dict = internal[DICT](row);
        // Never bypass read-only or typed-value enforcement through raw slots.
        if (predicate(dict_readonly, dict) || predicate(dict_typed, dict)) return i;
        void *pose = field(dict, POSE);
        if (!pose || type_of(pose) != STRING) return i;
        GDExtensionBool idle = false;
        string_equal(internal[STRING](pose), &idle_string, &idle);
        GDExtensionBool unconscious = false;
        if (!idle && recovery >= 0.0) string_equal(internal[STRING](pose), &unconscious_string, &unconscious);
        if (!idle && !unconscious) return i;
        double hp, ko, age, think;
        if (!number(field(dict, HP), hp) || hp <= 0.0 || !number(field(dict, KO), ko) ||
                (unconscious ? !(ko > delta) : ko > 0.0)) return i;
        const auto *xy = static_cast<int32_t *>(internal[V2I](cell));
        if (xy[0] != -1 || xy[1] != -1) return i;
        if (!no_rescues) {
            VariantStorage index;
            from_int(&index, &i);
            const bool rescuing = has(rescues, &index);
            destroy(&index);
            if (rescuing) return i;
        }
        if (unconscious) {
            // The original KO branch ages the row, normalizes four timers, then
            // reduces KO. It does not touch grace, stun or think. An existing
            // visual key is erased by GDScript, so leave that row to the owner.
            if (field(dict, VISUAL)) return i;
            void *age_slot = field(dict, AGE);
            if (!number(age_slot, age) || !std::isfinite(age + delta) || !std::isfinite(ko - delta)) return i;
            double timers[4]{};
            int timer_index = 0;
            for (Key key : {COOLDOWN, STAGGER, SKILL, RANGED}) {
                void *slot = field(dict, key);
                double value = 0.0;
                if (slot && (!number(slot, value) || !std::isfinite(value))) return i;
                const double remaining = 0.0 > value - delta ? 0.0 : value - delta;
                timers[timer_index++] = remaining <= 0.000000001 ? 0.0 : remaining;
            }
            write_float(dict, AGE, age + delta);
            timer_index = 0;
            for (Key key : {COOLDOWN, STAGGER, SKILL, RANGED}) write_float(dict, key, timers[timer_index++]);
            write_float(dict, KO, 0.0 > ko - delta ? 0.0 : ko - delta);
            continue;
        }
        void *slots[KEY_COUNT]{};
        double *float_slots[KEY_COUNT]{}; // This row only; never used after key insertion.
        slots[STUN] = field(dict, STUN); slots[GRACE] = field(dict, GRACE);
        double stun, grace;
        if (!number(slots[STUN], stun, &float_slots[STUN]) || !number(slots[GRACE], grace, &float_slots[GRACE])) return i;
        if (recovery < 0.0 && (stun != 0.0 || grace != 0.0)) return i;
        bool zero_state = stun == 0.0 && grace == 0.0;
        if (void *visual = field(dict, VISUAL)) {
            if (type_of(visual) != DICT || !predicate(dict_empty, internal[DICT](visual))) return i;
        }
        slots[DURATION] = field(dict, DURATION);
        if (!zero(slots[DURATION], true)) return i;
        double timers[4]{};
        int timer_index = 0;
        for (Key key : {COOLDOWN, STAGGER, SKILL, RANGED}) {
            slots[key] = field(dict, key);
            double value = 0.0;
            if (slots[key] && !number(slots[key], value, &float_slots[key])) return i;
            if (recovery < 0.0 && value != 0.0) return i;
            zero_state = zero_state && value == 0.0;
            // Most rows are the old all-zero case. Preserve positive zero and
            // do recovery arithmetic only when this row actually needs it.
            if (value != 0.0) timers[timer_index] = value;
            ++timer_index;
        }
        slots[AGE] = field(dict, AGE); slots[THINK] = field(dict, THINK);
        if (!number(slots[AGE], age, &float_slots[AGE]) || !number(slots[THINK], think, &float_slots[THINK]) || !std::isfinite(age + delta)) return i;
        // Same write order/key types, float conversions and positive zero as GD.
        // Qualification does not read age, so rejection leaves the WHOLE row
        // untouched for the original GDScript path to advance exactly once.
        const double remaining = think - delta;
        const double next_think = 0.0 > remaining ? 0.0 : remaining;
        double next_grace = 0.0, next_stun = 0.0;
        if (recovery >= 0.0 && !zero_state) {
            for (double &timer : timers) {
                const double left = timer - delta;
                timer = left <= 0.000000001 ? 0.0 : left;
            }
            const double difference = delta - grace;
            const double decay = 0.0 > difference ? 0.0 : difference;
            const double recovered = decay * recovery;
            const double grace_left = grace - delta, stun_left = stun - recovered;
            if (!std::isfinite(difference) || !std::isfinite(recovered) || !std::isfinite(grace_left) || !std::isfinite(stun_left)) return i;
            next_grace = 0.0 > grace_left ? 0.0 : grace_left;
            next_stun = 0.0 > stun_left ? 0.0 : stun_left;
        }
        if (slots[COOLDOWN] && slots[STAGGER] && slots[SKILL] && slots[RANGED]) {
            // No structural mutations: reuse this row's checked slots for the
            // writes, then discard ALL pointers before advancing the ordinal.
            // FLOAT storage was already obtained during validation. INT slots
            // still use the original Variant conversion; all keys exist here.
            const auto write = [&](Key key, double value) {
                if (float_slots[key]) *float_slots[key] = value;
                else assign_float(slots[key], value);
            };
            write(AGE, age + delta);
            timer_index = 0;
            for (Key key : {COOLDOWN, STAGGER, SKILL, RANGED}) write(key, timers[timer_index++]);
            write(GRACE, next_grace);
            write(STUN, next_stun);
            write(THINK, next_think);
        } else {
            write_float(dict, AGE, age + delta);
            timer_index = 0;
            for (Key key : {COOLDOWN, STAGGER, SKILL, RANGED}) write_float(dict, key, timers[timer_index++]);
            write_float(dict, GRACE, next_grace);
            write_float(dict, STUN, next_stun);
            write_float(dict, THINK, next_think);
        }
    }
    return end;
}

int64_t fatigue_prefix(void *rows, void *moving, int64_t start, int64_t end) {
    if (start < 0 || end < start || end > size(rows) || end > size(moving)) return start;
    for (int64_t i = start; i < end; ++i) {
        void *row = array_at(rows, i), *cell = array_at(moving, i);
        if (type_of(row) != DICT || type_of(cell) != V2I) return i;
        const auto *xy = static_cast<int32_t *>(internal[V2I](cell));
        if (xy[0] != -1 || xy[1] != -1) return i;
        void *dict = internal[DICT](row);
        if (predicate(dict_readonly, dict) || predicate(dict_typed, dict)) return i;
        void *fatigue = field(dict, FATIGUE), *rest = field(dict, REST);
        double value;
        if (!rest || !number(fatigue, value) || value != 0.0) return i;
        // Preserve fatigue's signed zero; only rest resets to positive zero.
        assign_float(fatigue, value);
        assign_float(rest, 0.0);
    }
    return end;
}

void reset_variant(void *value, GDExtensionVariantType type) {
    destroy(value);
    GDExtensionCallError error{};
    variant_construct(type, value, nullptr, 0, &error);
}
void resize(GDExtensionPtrBuiltInMethod method, void *value, int64_t count) {
    const void *args[] = {&count};
    int64_t error = 0;
    method(value, args, &error, 1);
}
bool integer(void *value, int64_t &out) {
    if (!value || type_of(value) != INT) return false;
    out = *static_cast<int64_t *>(internal[INT](value));
    return true;
}
bool person_identity_value(void *value, int64_t &identity) {
    if (integer(value, identity)) return true;
    // JSON restores exact small IDs as FLOAT; preserve the raw field type.
    double parsed;
    if (!value || type_of(value) != FLOAT || !number(value, parsed) ||
            parsed < 1.0 || parsed > 2147483647.0 || std::trunc(parsed) != parsed) return false;
    identity = static_cast<int64_t>(parsed);
    return true;
}
int64_t packed_size(GDExtensionPtrBuiltInMethod method, void *value) {
    int64_t count = 0;
    method(value, nullptr, &count, 0);
    return count;
}

struct Point { float x, y; };
double point_distance(Point a, Point b, bool squared) {
    // Same public Godot Vector2 method and real_t rounding, without boxing
    // three Variants and resolving a method name for every measured distance.
    const void *args[] = {&b};
    double value = -1.0;
    (squared ? vector_squared_distance : vector_distance)(&a, args, &value, 1);
    return std::isfinite(value) ? value : -1.0;
}

struct PresenceInputs {
    std::vector<Point> positions;
    std::vector<int64_t> identities;
    std::vector<uint8_t> admitted, active, present;
};

// Public owner rows/movement can change without dirty notification. Re-read
// them every time; only derived geometry, never person state, may be reused.
bool collect_presence(void *rows, void *cells, void *moving, PresenceInputs &input, bool delta, HotStore *store) {
    const int64_t count = size(rows);
    if (count < 0 || count > 10000 || size(cells) != count || (store && hot_row_count(store) != count)) return false;
    input.positions.resize(count); input.identities.resize(count);
    input.admitted.resize(count); input.active.resize(count);
    if (delta) input.present.resize(count);
    std::unordered_set<const void *> present_slots;
    if (delta) present_slots.reserve(count);
    for (int64_t i = 0; i < count; ++i) {
        void *row = array_at(rows, i), *cell = array_at(cells, i);
        if (type_of(row) != DICT || type_of(cell) != V2I) return false;
        void *dict = internal[DICT](row);
        void *identity_value = field(dict, PERSON_ID);
        if (delta) {
            if (predicate(dict_readonly, dict) || predicate(dict_typed, dict)) return false;
            void *present = store ? hot_value(store, i, PRESENT) : field(dict, PRESENT);
            if (!present || type_of(present) != BOOL) return false;
            // Public const access returns the existing slot; no writes occur
            // while these call-local addresses are used to detect shared rows.
            if (!present_slots.insert(store ? identity_value : present).second) return false;
            input.present[i] = *static_cast<GDExtensionBool *>(internal[BOOL](present));
        }
        double hp, ko;
        int64_t identity;
        if (!number(store ? hot_value(store, i, HP) : field(dict, HP), hp) ||
                !number(store ? hot_value(store, i, KO) : field(dict, KO), ko) || !integer(identity_value, identity)) return false;
        void *member = store ? hot_value(store, i, MEMBER) : field(dict, MEMBER);
        void *departed = store ? hot_value(store, i, DEPARTED) : field(dict, DEPARTED);
        void *captive = store ? hot_value(store, i, CAPTIVE) : field(dict, CAPTIVE);
        void *pose = store ? hot_value(store, i, POSE) : field(dict, POSE);
        if ((member && type_of(member) != BOOL) || !departed || type_of(departed) != BOOL || !captive || type_of(captive) != BOOL || !pose || type_of(pose) != STRING) return false;
        const bool admitted = (!member || *static_cast<GDExtensionBool *>(internal[BOOL](member))) && hp > 0.0 &&
            !*static_cast<GDExtensionBool *>(internal[BOOL](departed)) && !*static_cast<GDExtensionBool *>(internal[BOOL](captive));
        GDExtensionBool getting_up = false;
        string_equal(internal[STRING](pose), &get_up_string, &getting_up);
        input.admitted[i] = admitted;
        input.active[i] = admitted && ko <= 0.0 && !getting_up;
        const auto *xy = static_cast<int32_t *>(internal[V2I](cell));
        // Exact half-cell centres for this bounded range; *64 /64 is exact.
        if (xy[0] < -10000 || xy[0] > 10000 || xy[1] < -10000 || xy[1] > 10000) return false;
        Point point{static_cast<float>(xy[0]) + 0.5f, static_cast<float>(xy[1]) + 0.5f};
        VariantStorage ordinal;
        from_int(&ordinal, &i);
        void *override_value = has(moving, &ordinal) ? dict_at(moving, &ordinal) : nullptr;
        destroy(&ordinal);
        if (override_value) {
            if (type_of(override_value) != V2) return false;
            point = *static_cast<Point *>(internal[V2](override_value));
            if (!std::isfinite(point.x) || !std::isfinite(point.y) || std::abs(point.x) > 10000.0f || std::abs(point.y) > 10000.0f) return false;
        }
        input.positions[i] = point; input.identities[i] = identity;
    }
    return true;
}

bool presence_geometry(const PresenceInputs &input, Point &reference, bool &valid, std::vector<double> &distances, bool compute_inactive) {
    std::vector<int64_t> members;
    std::vector<double> horizontal, vertical;
    for (size_t i = 0; i < input.positions.size(); ++i) if (input.admitted[i]) {
        members.push_back(i); horizontal.push_back(input.positions[i].x); vertical.push_back(input.positions[i].y);
    }
    valid = !members.empty();
    if (!members.empty()) {
        std::sort(horizontal.begin(), horizontal.end()); std::sort(vertical.begin(), vertical.end());
        const size_t middle = members.size() / 2, lower = (members.size() - 1) / 2;
        Point median{static_cast<float>((horizontal[middle] + horizontal[lower]) * 0.5), static_cast<float>((vertical[middle] + vertical[lower]) * 0.5)};
        double best = INFINITY;
        int64_t best_identity = 2147483647;
        for (int64_t i : members) {
            const double distance = point_distance(input.positions[i], median, true);
            if (distance < 0.0) return false;
            if (distance < best || (distance == best && input.identities[i] < best_identity)) {
                best = distance; best_identity = input.identities[i]; reference = input.positions[i];
            }
        }
    }
    distances.assign(input.positions.size(), -1.0);
    // KO/get_up changes eligibility, not the reference. Retain those distances.
    for (size_t i = 0; i < input.positions.size(); ++i) if (compute_inactive ? input.admitted[i] : input.active[i]) {
        distances[i] = point_distance(reference, input.positions[i], false);
        if (distances[i] < 0.0) return false;
    }
    return true;
}

// Original read-only projection API, including alias/typed/read-only rows.
void call_presence(void *mode, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, ARRAY);
    if (argc != 3 || type_of(args[0]) != ARRAY || type_of(args[1]) != ARRAY || type_of(args[2]) != DICT) return;
    PresenceInputs input;
    if (!collect_presence(internal[ARRAY](const_cast<void *>(args[0])), internal[ARRAY](const_cast<void *>(args[1])),
            internal[DICT](const_cast<void *>(args[2])), input, false,
            mode == &hot_presence_marker ? static_cast<HotStore *>(instance) : nullptr)) return;
    Point reference{};
    bool valid = false;
    std::vector<double> distances;
    if (!presence_geometry(input, reference, valid, distances, false)) return;
    const int64_t count = input.positions.size();
    for (int64_t i = 0; i < count; ++i) if (!input.active[i]) distances[i] = -1.0;
    void *output = internal[ARRAY](result);
    resize(resize_array, output, 2);
    void *ref_slot = array_write(output, 0), *dist_slot = array_write(output, 1);
    reset_variant(ref_slot, VECTORS); reset_variant(dist_slot, DOUBLES);
    void *ref_out = internal[VECTORS](ref_slot), *dist_out = internal[DOUBLES](dist_slot);
    resize(resize_vectors, ref_out, valid ? 1 : 0);
    resize(resize_doubles, dist_out, count);
    if (valid) *static_cast<Point *>(vectors_write(ref_out, 0)) = reference;
    if (count) std::copy(distances.begin(), distances.end(), doubles_write(dist_out, 0));
}

// An Army owns this read-only Array of packed geometry. Packed copies use COW;
// no row pointers survive a call. Invalid/changed geometry is rebuilt atomically.
bool reuse_presence_geometry(void *cache, const PresenceInputs &input, Point &reference, bool &valid,
        std::vector<double> &distances) {
    if (size(cache) != 5 || !predicate(array_readonly, cache)) return false;
    const GDExtensionVariantType types[] = {VECTORS, LONGS, BYTES, VECTORS, DOUBLES};
    void *columns[5];
    for (int i = 0; i < 5; ++i) {
        void *slot = array_at(cache, i);
        if (type_of(slot) != types[i]) return false;
        columns[i] = internal[types[i]](slot);
    }
    const int64_t count = input.positions.size();
    valid = std::find(input.admitted.begin(), input.admitted.end(), uint8_t(1)) != input.admitted.end();
    if (packed_size(size_vectors, columns[0]) != count || packed_size(size_longs, columns[1]) != count ||
            packed_size(size_bytes, columns[2]) != count || packed_size(size_vectors, columns[3]) != (valid ? 1 : 0) ||
            packed_size(size_doubles, columns[4]) != count) return false;
    for (int64_t i = 0; i < count; ++i) {
        if (std::memcmp(vectors_read(columns[0], i), &input.positions[i], sizeof(Point)) != 0 ||
                *longs_read(columns[1], i) != input.identities[i] || *bytes_read(columns[2], i) != input.admitted[i]) return false;
    }
    if (valid) {
        reference = *static_cast<const Point *>(vectors_read(columns[3], 0));
        if (!std::isfinite(reference.x) || !std::isfinite(reference.y)) return false;
    }
    distances.resize(count);
    for (int64_t i = 0; i < count; ++i) {
        const double distance = *doubles_read(columns[4], i);
        if (!std::isfinite(distance) || (input.admitted[i] ? distance < 0.0 : distance != -1.0)) return false;
        distances[i] = distance;
    }
    return true;
}

void call_presence_delta(void *mode, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, ARRAY);
    if (argc != 5 || type_of(args[0]) != ARRAY || type_of(args[1]) != ARRAY || type_of(args[2]) != DICT || type_of(args[4]) != ARRAY) return;
    double radius;
    if (!number(const_cast<void *>(args[3]), radius)) return;
    PresenceInputs input;
    if (!collect_presence(internal[ARRAY](const_cast<void *>(args[0])), internal[ARRAY](const_cast<void *>(args[1])),
            internal[DICT](const_cast<void *>(args[2])), input, true,
            mode == &hot_presence_delta_marker ? static_cast<HotStore *>(instance) : nullptr)) return;
    Point reference{};
    bool valid = false;
    std::vector<double> distances;
    const bool rebuilt = !reuse_presence_geometry(internal[ARRAY](const_cast<void *>(args[4])), input, reference, valid, distances);
    if (rebuilt && !presence_geometry(input, reference, valid, distances, true)) return;
    std::vector<int32_t> indices;
    std::vector<uint8_t> values;
    const int64_t count = input.positions.size();
    for (int64_t i = 0; i < count; ++i) {
        const uint8_t next = valid && input.active[i] && distances[i] <= radius + (input.present[i] ? 2.0 : 0.0);
        if (next != input.present[i]) { indices.push_back(static_cast<int32_t>(i)); values.push_back(next); }
    }
    void *output = internal[ARRAY](result);
    resize(resize_array, output, 5);
    void *ref_slot = array_write(output, 0), *index_slot = array_write(output, 1), *value_slot = array_write(output, 2);
    reset_variant(ref_slot, VECTORS); reset_variant(index_slot, INTS); reset_variant(value_slot, BYTES);
    void *ref_out = internal[VECTORS](ref_slot), *index_out = internal[INTS](index_slot), *value_out = internal[BYTES](value_slot);
    resize(resize_vectors, ref_out, valid ? 1 : 0);
    resize(resize_ints, index_out, indices.size()); resize(resize_bytes, value_out, values.size());
    if (valid) *static_cast<Point *>(vectors_write(ref_out, 0)) = reference;
    if (!indices.empty()) {
        std::copy(indices.begin(), indices.end(), ints_write(index_out, 0));
        std::copy(values.begin(), values.end(), bytes_write(value_out, 0));
    }
    void *cache_slot = array_write(output, 3);
    if (!rebuilt) {
        destroy(cache_slot); copy_variant(cache_slot, args[4]);
    } else {
        reset_variant(cache_slot, ARRAY);
        void *cache = internal[ARRAY](cache_slot);
        resize(resize_array, cache, 5);
        const GDExtensionVariantType types[] = {VECTORS, LONGS, BYTES, VECTORS, DOUBLES};
        for (int i = 0; i < 5; ++i) reset_variant(array_write(cache, i), types[i]);
        void *positions = internal[VECTORS](array_write(cache, 0)), *identities = internal[LONGS](array_write(cache, 1));
        void *admitted = internal[BYTES](array_write(cache, 2)), *cached_distances = internal[DOUBLES](array_write(cache, 4));
        resize(resize_vectors, positions, count); resize(resize_longs, identities, count);
        resize(resize_bytes, admitted, count); resize(resize_doubles, cached_distances, count);
        void *cached_ref = array_write(cache, 3);
        destroy(cached_ref); copy_variant(cached_ref, ref_slot);
        if (count) {
            std::copy(input.positions.begin(), input.positions.end(), static_cast<Point *>(vectors_write(positions, 0)));
            std::copy(input.identities.begin(), input.identities.end(), longs_write(identities, 0));
            std::copy(input.admitted.begin(), input.admitted.end(), bytes_write(admitted, 0));
            std::copy(distances.begin(), distances.end(), doubles_write(cached_distances, 0));
        }
    }
    void *rebuilt_slot = array_write(output, 4);
    destroy(rebuilt_slot);
    GDExtensionBool rebuilt_value = rebuilt;
    from_bool(rebuilt_slot, &rebuilt_value);
}

// Read-only presentation projection. Fresh output buffers belong to this call;
// input PackedArrays are NEVER written through a shared/COW pointer. Only exact
// already-admitted immutable appearance identities qualify. No callbacks/nodes,
// gameplay writes, retained row pointers or alternate clock exist in this path.
// Pack only already admitted presentation columns. No gameplay objects or
// renderer ownership crosses this call; invalid inputs return the GD fallback.
// Build only this frame's presentation order. Original ordinal order determines
// row insertion; pages never merge across a Sprite or a different page.
void call_group_rows(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, ARRAY);
    const GDExtensionVariantType types[] = {BYTES, INTS, ARRAY, ARRAY, INTS};
    if (argc != 5) return;
    void *input[5]{};
    for (int i = 0; i < 5; ++i) {
        if (type_of(args[i]) != types[i]) return;
        input[i] = internal[types[i]](const_cast<void *>(args[i]));
    }
    const int64_t count = packed_size(size_bytes, input[0]), fallback_count = size(input[2]);
    if (count > 10000 || packed_size(size_ints, input[1]) != count || packed_size(size_ints, input[4]) != count ||
            fallback_count != size(input[3]) || fallback_count > count) return;
    std::vector<uint8_t> admitted(static_cast<size_t>(count), 0);
    std::vector<int32_t> rows(static_cast<size_t>(count), 0);
    int64_t prepared_count = 0;
    const auto *mask = count ? bytes_read(input[0], 0) : nullptr;
    const auto *native_rows = count ? ints_read(input[1], 0) : nullptr;
    const auto *pages = count ? ints_read(input[4], 0) : nullptr;
    for (int64_t i = 0; i < count; ++i) {
        if (mask[i] > 1 || (mask[i] && pages[i] < 0)) return;
        if (mask[i]) {
            admitted[static_cast<size_t>(i)] = 1;
            rows[static_cast<size_t>(i)] = native_rows[i];
            ++prepared_count;
        }
    }
    std::unordered_map<int32_t, size_t> lookup;
    int64_t fallback_members = 0;
    for (int64_t r = 0; r < fallback_count; ++r) {
        int64_t row;
        if (!integer(array_at(input[2], r), row) || row < INT32_MIN || row > INT32_MAX ||
                !lookup.emplace(static_cast<int32_t>(row), 0).second) return;
        void *members_value = array_at(input[3], r);
        if (type_of(members_value) != ARRAY) return;
        void *members = internal[ARRAY](members_value);
        const int64_t length = size(members);
        fallback_members += length;
        if (fallback_members > count) return;
        for (int64_t m = 0; m < length; ++m) {
            int64_t index;
            if (!integer(array_at(members, m), index) || index < 0 || index >= count ||
                    admitted[static_cast<size_t>(index)]) return;
            admitted[static_cast<size_t>(index)] = 1;
            rows[static_cast<size_t>(index)] = static_cast<int32_t>(row);
        }
    }
    struct Bucket { int32_t row; std::vector<int64_t> members; };
    std::vector<Bucket> buckets;
    lookup.clear();
    for (int64_t i = 0; i < count; ++i) {
        if (!admitted[static_cast<size_t>(i)]) continue;
        const int32_t row = rows[static_cast<size_t>(i)];
        const auto inserted = lookup.emplace(row, buckets.size());
        if (inserted.second) buckets.push_back({row, {}});
        buckets[inserted.first->second].members.push_back(i);
    }
    std::vector<int32_t> spans;
    for (const auto &bucket : buckets) {
        int32_t run = 0;
        size_t start = 0;
        while (start < bucket.members.size()) {
            const int32_t page = pages[bucket.members[start]];
            size_t stop = start + 1;
            if (page >= 0) while (stop < bucket.members.size() && pages[bucket.members[stop]] == page) ++stop;
            spans.insert(spans.end(), {bucket.row, run++, static_cast<int32_t>(start), static_cast<int32_t>(stop), page});
            start = stop;
        }
    }
    void *output = internal[ARRAY](result);
    resize(resize_array, output, 3);
    void *row_slot = array_write(output, 0);
    reset_variant(row_slot, DICT);
    void *row_dict = internal[DICT](row_slot);
    for (const auto &bucket : buckets) {
        VariantStorage key;
        int64_t row = bucket.row;
        from_int(&key, &row);
        void *slot = dict_write(row_dict, &key);
        destroy(&key);
        reset_variant(slot, ARRAY);
        void *members = internal[ARRAY](slot);
        resize(resize_array, members, static_cast<int64_t>(bucket.members.size()));
        for (size_t m = 0; m < bucket.members.size(); ++m) {
            void *member = array_write(members, static_cast<int64_t>(m));
            destroy(member);
            int64_t index = bucket.members[m];
            from_int(member, &index);
        }
    }
    void *span_slot = array_write(output, 1);
    reset_variant(span_slot, INTS);
    void *span_output = internal[INTS](span_slot);
    resize(resize_ints, span_output, static_cast<int64_t>(spans.size()));
    if (!spans.empty()) std::copy(spans.begin(), spans.end(), ints_write(span_output, 0));
    void *count_slot = array_write(output, 2);
    destroy(count_slot);
    from_int(count_slot, &prepared_count);
}

void call_pack(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, ARRAY);
    const GDExtensionVariantType types[] = {ARRAY, INT, INT, VECTORS, INTS, INTS, INTS, FLOAT};
    if (argc != 8) return;
    void *input[8]{};
    for (int i = 0; i < 8; ++i) {
        if (type_of(args[i]) != types[i]) return;
        input[i] = internal[types[i]](const_cast<void *>(args[i]));
    }
    const int64_t begin = *static_cast<int64_t *>(input[1]), end = *static_cast<int64_t *>(input[2]);
    const int64_t count = packed_size(size_vectors, input[3]);
    const double scale = *static_cast<double *>(input[7]);
    if (count <= 0 || count > 10000 || begin < 0 || end <= begin || end > size(input[0]) || end - begin > 10000 ||
            !std::isfinite(scale) || !std::isfinite(static_cast<float>(scale))) return;
    for (int i : {4, 5, 6}) if (packed_size(size_ints, input[i]) != count) return;
    std::vector<int64_t> indices;
    indices.reserve(static_cast<size_t>(end - begin));
    for (int64_t i = begin; i < end; ++i) {
        int64_t index;
        if (!integer(array_at(input[0], i), index) || index < 0 || index >= count) return;
        const auto *p = static_cast<const Point *>(vectors_read(input[3], index));
        if (!std::isfinite(p->x) || !std::isfinite(p->y)) return;
        indices.push_back(index);
    }
    void *output = internal[ARRAY](result);
    resize(resize_array, output, 2);
    void *buffer_slot = array_write(output, 0);
    reset_variant(buffer_slot, FLOATS);
    void *buffer = internal[FLOATS](buffer_slot);
    resize(resize_floats, buffer, static_cast<int64_t>(indices.size()) * 12);
    float *values = floats_write(buffer, 0);
    std::fill_n(values, indices.size() * 12, 0.0f);
    Point position = *static_cast<const Point *>(vectors_read(input[3], indices.front()));
    Point extent{};
    for (size_t ordinal = 0; ordinal < indices.size(); ++ordinal) {
        const auto index = indices[ordinal];
        const auto p = *static_cast<const Point *>(vectors_read(input[3], index));
        float *row = values + ordinal * 12;
        row[0] = row[5] = static_cast<float>(scale);
        row[3] = p.x; row[7] = p.y;
        row[8] = static_cast<float>(*ints_read(input[4], index));
        row[9] = static_cast<float>(*ints_read(input[5], index));
        row[10] = static_cast<float>(*ints_read(input[6], index));
        // Match repeated Rect2.expand, including real_t addition/subtraction
        // rounding, not a different min/max reduction.
        Point corner{std::max(position.x + extent.x, p.x), std::max(position.y + extent.y, p.y)};
        position = {std::min(position.x, p.x), std::min(position.y, p.y)};
        extent = {corner.x - position.x, corner.y - position.y};
    }
    void *bounds_slot = array_write(output, 1);
    reset_variant(bounds_slot, VECTORS);
    void *bounds = internal[VECTORS](bounds_slot);
    resize(resize_vectors, bounds, 2);
    *static_cast<Point *>(vectors_write(bounds, 0)) = position;
    *static_cast<Point *>(vectors_write(bounds, 1)) = extent;
}

void call_render(void *mode, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, ARRAY);
    if (argc != 10) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return; }
    const GDExtensionVariantType types[] = {ARRAY, ARRAY, ARRAY, ARRAY, DICT, ARRAY, ARRAY, ARRAY, ARRAY, FLOAT};
    void *input[10]{};
    for (int i = 0; i < 10; ++i) {
        if (type_of(args[i]) != types[i]) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; error->argument = i; error->expected = types[i]; return; }
        input[i] = internal[types[i]](const_cast<void *>(args[i]));
    }
    const int64_t count = size(input[0]);
    HotStore *store = mode == &hot_render_marker ? static_cast<HotStore *>(instance) : nullptr;
    // TerrainGenerator admits at most 128x128; bound rows and projections.
    if (count <= 0 || count > 10000 || (store && hot_row_count(store) != count) ||
            *static_cast<double *>(input[9]) != 64.0) return;
    for (int i : {1, 2, 3, 5, 6, 8}) if (size(input[i]) != count) return;
    void *output = internal[ARRAY](result);
    resize(resize_array, output, 7);
    void *columns[7]{};
    for (int i = 0; i < 7; ++i) {
        const auto type = i == 0 ? BYTES : (i == 1 ? VECTORS : INTS);
        void *slot = array_write(output, i);
        reset_variant(slot, type);
        columns[i] = internal[type](slot);
        resize(i == 0 ? resize_bytes : (i == 1 ? resize_vectors : resize_ints), columns[i], count);
    }
    auto *mask = bytes_write(columns[0], 0);
    auto *positions = static_cast<float *>(vectors_write(columns[1], 0));
    int32_t *values[5];
    for (int i = 0; i < 5; ++i) values[i] = ints_write(columns[i + 2], 0);
    // Only independent read-only projection runs in the existing engine pool.
    // All allocations/COW and owner calls precede the tasks; each chunk writes
    // disjoint output ranges. Join before returning any presentation buffer.
    project_ranges(count, [&](int64_t begin, int64_t end, uint32_t) {
    // Same exact atlas request as the preceding successful sample. Call-local
    // scalar results only: no person state or borrowed pointer survives a row.
    int64_t last_page = -1, last_sequence = 0, last_frame = 0;
    int last_direction = -1, last_pose = -1;
    double last_age = -1.0;
    float last_anchor_x = 0.0f, last_anchor_y = 0.0f;
    for (int64_t i = begin; i < end; ++i) {
        mask[i] = 0;
        positions[i * 2] = positions[i * 2 + 1] = 0.0f;
        for (auto *column : values) column[i] = 0;
        // An existing Sprite includes every live presenter and any recipe that
        // still needs the original admission/free/reparent path.
        if (type_of(array_at(input[8], i)) != GDEXTENSION_VARIANT_TYPE_NIL) continue;
        void *row = array_at(input[0], i), *cell = array_at(input[1], i), *moving = array_at(input[2], i), *facing = array_at(input[3], i);
        if (type_of(row) != DICT || type_of(cell) != V2I || type_of(moving) != V2I || type_of(facing) != V2I) continue;
        const auto *xy = static_cast<int32_t *>(internal[V2I](cell));
        const auto *destination = static_cast<int32_t *>(internal[V2I](moving));
        if (destination[0] != -1 || destination[1] != -1 || xy[0] < 0 || xy[0] >= 128 || xy[1] < 0 || xy[1] >= 128) continue;
        void *dict = internal[DICT](row);
        ReadField pose_field(row, POSE, store, i), role_field(row, ROLE, store, i);
        void *pose = pose_field.get();
        if (void *role = role_field.get()) {
            if (type_of(role) != STRING) continue;
            GDExtensionBool male = false;
            string_equal(internal[STRING](role), &male_string, &male);
            if (!male) {
                GDExtensionBool female = false;
                string_equal(internal[STRING](role), &female_string, &female);
                if (!female) continue;
            }
        }
        if (!pose || type_of(pose) != STRING ||
                (store ? hot_value(store, i, VISUAL) != nullptr : has(dict, &lookup_keys[VISUAL]))) continue;
        GDExtensionBool idle = false, unconscious = false;
        string_equal(internal[STRING](pose), &idle_string, &idle);
        if (!idle) {
            string_equal(internal[STRING](pose), &unconscious_string, &unconscious);
            if (!unconscious) continue;
            double hp, ko;
            ReadField hp_field(row, HP, store, i), ko_field(row, KO, store, i);
            if (!number(hp_field.get(), hp) || hp <= 0.0 ||
                    !number(ko_field.get(), ko) || ko <= 0.0) continue;
        }
        double age;
        ReadField age_field(row, AGE, store, i);
        if (!number(age_field.get(), age) || !std::isfinite(age) || age < 0.0) continue;
        ReadField identity_field(row, PERSON_ID);
        void *identity = identity_field.get();
        int64_t person_id;
        if (!person_identity_value(identity, person_id)) continue;
        // Publications use integer person IDs even when JSON restored the
        // roster's ID field as a float. Keep the owner row untouched.
        VariantStorage integer_key;
        void *publication_key = identity;
        const bool restored_float_id = type_of(identity) == FLOAT;
        if (restored_float_id) {
            from_int(&integer_key, &person_id);
            publication_key = &integer_key;
        }
        const bool published = has(input[4], publication_key);
        void *appearance = published ? dict_at(input[4], publication_key) : nullptr;
        if (restored_float_id) destroy(&integer_key);
        if (!published) continue;
        void *previous = array_at(input[5], i);
        const void *same_args[] = {appearance, previous};
        GDExtensionBool same = false;
        same_variant(&same, same_args, 2);
        if (!same || type_of(appearance) != DICT || !predicate(dict_readonly, internal[DICT](appearance))) continue;
        void *descriptor = array_at(input[6], i);
        if (type_of(descriptor) != DICT) continue;
        int64_t page, palette;
        ReadField page_field(descriptor, PAGE), palette_field(descriptor, PALETTE);
        if (!integer(page_field.get(), page) || !integer(palette_field.get(), palette)
                || page < 0 || page >= size(input[7]) || palette < 0 || palette >= count) continue;
        const auto *direction = static_cast<int32_t *>(internal[V2I](facing));
        int d = 2; // Original _soldier_direction_id fallback is down.
        if (direction[0] == 0 && direction[1] == -1) d = 0;
        else if (direction[0] == 1 && direction[1] == 0) d = 1;
        else if (direction[0] == -1 && direction[1] == 0) d = 3;
        const int pose_index = unconscious ? 1 : 0;
        if (page != last_page || d != last_direction || age != last_age || pose_index != last_pose) {
            void *directions = array_at(input[7], page);
            if (type_of(directions) != ARRAY) continue;
            void *direction_samples = internal[ARRAY](directions);
            if (size(direction_samples) != 4 && size(direction_samples) != 8) continue;
            if (unconscious && size(direction_samples) != 8) continue;
            void *record = array_at(direction_samples, d + pose_index * 4);
            if (type_of(record) != ARRAY || size(internal[ARRAY](record)) != 5) continue;
            void *sample = internal[ARRAY](record);
            int64_t sequence;
            double duration;
            if (!integer(array_at(sample, 0), sequence) || sequence < 0 || sequence > INT32_MAX
                    || !number(array_at(sample, 1), duration) || duration <= 0.0 || type_of(array_at(sample, 2)) != BOOL
                    || type_of(array_at(sample, 3)) != DOUBLES || type_of(array_at(sample, 4)) != VECTORS) continue;
            void *times_value = internal[DOUBLES](array_at(sample, 3)), *anchors_value = internal[VECTORS](array_at(sample, 4));
            const int64_t frames = packed_size(size_doubles, times_value);
            if (frames < 1 || frames > 64 || packed_size(size_vectors, anchors_value) != frames) continue;
            const auto *times = doubles_read(times_value, 0);
            const auto *anchors = static_cast<const float *>(vectors_read(anchors_value, 0));
            const bool loop = *static_cast<GDExtensionBool *>(internal[BOOL](array_at(sample, 2))) != 0;
            const double elapsed = loop ? std::fmod(age, duration) : (age < duration ? age : duration);
            int64_t low = 0, high = frames;
            while (low + 1 < high) {
                const int64_t middle = low + ((high - low) >> 1);
                if (times[middle] <= elapsed + 0.000000001) low = middle;
                else high = middle;
            }
            last_page = page; last_direction = d; last_age = age; last_pose = pose_index;
            last_sequence = sequence; last_frame = low;
            last_anchor_x = anchors[low * 2]; last_anchor_y = anchors[low * 2 + 1];
        }
        // Original Vector2 construction -> float32 add -> float32 scale ->
        // float32 subtract, with the original pre-scaled frame anchor.
        const float gx = (static_cast<float>(xy[0]) + 0.5f) * 64.0f;
        const float gy = (static_cast<float>(xy[1]) + 0.5f) * 64.0f;
        positions[i * 2] = gx - last_anchor_x;
        positions[i * 2 + 1] = gy - last_anchor_y;
        values[0][i] = static_cast<int32_t>(last_sequence);
        values[1][i] = static_cast<int32_t>(last_frame);
        values[2][i] = static_cast<int32_t>(page);
        values[3][i] = static_cast<int32_t>(palette);
        values[4][i] = 10 + static_cast<int32_t>(static_cast<double>(gy) / 64.0);
        mask[i] = 1;
    }
    });
}

struct QueryPerson { int64_t index, identity; int32_t x, y; };

// Same bounded reverse field, only for the canonical pure terrain/occupancy
// readers. No movement, eligibility, reservations or callbacks run here.
void call_encirclement_field(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, ARRAY);
    const GDExtensionVariantType types[] = {ARRAY, BYTES, V2I, BYTES, BYTES, BYTES, BYTES, DICT, INT, INT};
    if (argc != 10) return;
    void *input[10]{};
    for (int i = 0; i < 10; ++i) {
        if (type_of(args[i]) != types[i]) return;
        input[i] = internal[types[i]](const_cast<void *>(args[i]));
    }
    const int64_t enemy_count = size(input[0]);
    const auto *dimensions = static_cast<int32_t *>(input[2]);
    const int32_t width = dimensions[0], height = dimensions[1];
    const int64_t limit = *static_cast<int64_t *>(input[8]), reach = *static_cast<int64_t *>(input[9]);
    if (width < 1 || width > 128 || height < 1 || height > 128 || enemy_count > 10000 ||
            packed_size(size_bytes, input[1]) != enemy_count || limit < 1 || limit > 1024 || reach < 1 || reach > 32) return;
    const int32_t count = width * height;
    for (int i : {3, 4, 5}) if (packed_size(size_bytes, input[i]) != count) return;
    const int64_t blocked_count = packed_size(size_bytes, input[6]);
    if (blocked_count != 0 && blocked_count != count) return;
    const auto *near = enemy_count ? bytes_read(input[1], 0) : nullptr;
    const auto *flags = bytes_read(input[3], 0), *levels = bytes_read(input[4], 0), *ramps = bytes_read(input[5], 0);
    const auto *blocked = blocked_count ? bytes_read(input[6], 0) : nullptr;
    for (int64_t i = 0; i < enemy_count; ++i) {
        void *value = array_at(input[0], i);
        if (type_of(value) != V2I || near[i] > 1) return;
        const auto *cell = static_cast<int32_t *>(internal[V2I](value));
        if (cell[0] < -10000 || cell[0] > 10000 || cell[1] < -10000 || cell[1] > 10000) return;
    }
    const auto cell_index = [&](int32_t x, int32_t y) { return x < 0 || y < 0 || x >= width || y >= height ? -1 : y * width + x; };
    const auto can_step = [&](int32_t from, int32_t to, int direction) {
        if (from < 0 || to < 0 || !(flags[from] & 1) || !(flags[to] & 1) || (blocked && (blocked[from] || blocked[to]))) return false;
        const int difference = std::abs(static_cast<int>(levels[from]) - static_cast<int>(levels[to]));
        return difference == 0 || (difference == 1 && (ramps[from] & (1 << direction)) && (ramps[to] & (1 << ((direction + 2) % 4))));
    };
    const auto occupied = [&](int32_t x, int32_t y) {
        int32_t xy[] = {x, y};
        VariantStorage cell;
        from_v2i(&cell, xy);
        const bool present = has(input[7], &cell);
        destroy(&cell);
        return present;
    };
    const int32_t dx[] = {0, 1, 0, -1}, dy[] = {-1, 0, 1, 0};
    std::vector<int32_t> distance(static_cast<size_t>(count), -1), pending;
    pending.reserve(static_cast<size_t>(limit));
    for (int64_t i = 0; i < enemy_count; ++i) if (near[i]) {
        const auto *cell = static_cast<int32_t *>(internal[V2I](array_at(input[0], i)));
        const int32_t enemy = cell_index(cell[0], cell[1]);
        for (int d = 0; d < 4; ++d) {
            const int32_t x = cell[0] + dx[d], y = cell[1] + dy[d], goal = cell_index(x, y);
            if (goal < 0 || distance[goal] >= 0 || static_cast<int64_t>(pending.size()) >= limit ||
                    occupied(x, y) || !can_step(goal, enemy, (d + 2) % 4)) continue;
            distance[goal] = 0; pending.push_back(goal);
        }
    }
    for (size_t head = 0; head < pending.size(); ++head) {
        const int32_t cell = pending[head];
        if (distance[cell] >= reach - 1) continue;
        for (int d = 0; d < 4; ++d) {
            const int32_t x = cell % width + dx[d], y = cell / width + dy[d], next = cell_index(x, y);
            if (next < 0 || distance[next] >= 0 || static_cast<int64_t>(pending.size()) >= limit ||
                    !can_step(next, cell, (d + 2) % 4) || occupied(x, y)) continue;
            distance[next] = distance[cell] + 1; pending.push_back(next);
        }
    }
    void *output = internal[ARRAY](result);
    resize(resize_array, output, 1);
    void *slot = array_write(output, 0);
    reset_variant(slot, DICT);
    void *field = internal[DICT](slot);
    for (int32_t index : pending) {
        int32_t xy[] = {index % width, index / width};
        VariantStorage cell;
        from_v2i(&cell, xy);
        void *value = dict_write(field, &cell);
        destroy(value);
        int64_t cost = distance[index];
        from_int(value, &cost);
        destroy(&cell);
    }
}

// Fresh geometry from the existing Snapshot, never a second roster. The owner
// still checks membership, terrain and claims in the original ordinal order.
void call_encirclement(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, ARRAY);
    const GDExtensionVariantType types[] = {INTS, INTS, LONGS, INTS, INT, INT};
    if (argc != 6) return;
    void *input[6]{};
    for (int i = 0; i < 6; ++i) {
        if (type_of(args[i]) != types[i]) return;
        input[i] = internal[types[i]](const_cast<void *>(args[i]));
    }
    const int64_t count = packed_size(size_ints, input[0]);
    const int64_t owner = *static_cast<int64_t *>(input[4]), faction = *static_cast<int64_t *>(input[5]);
    if (count > 10000 || owner < 0 || owner > INT32_MAX || packed_size(size_ints, input[1]) != count ||
            packed_size(size_longs, input[2]) != count || packed_size(size_ints, input[3]) != count) return;
    const auto *xs = count ? ints_read(input[0], 0) : nullptr, *ys = count ? ints_read(input[1], 0) : nullptr;
    const auto *factions = count ? longs_read(input[2], 0) : nullptr;
    const auto *owners = count ? ints_read(input[3], 0) : nullptr;
    // Bound coordinates so native and GD neighbour addition cannot disagree
    // through int32 wrapping. Unsupported packets retain the complete GD path.
    for (int64_t i = 0; i < count; ++i) {
        if (xs[i] < -10000 || xs[i] > 10000 || ys[i] < -10000 || ys[i] > 10000 ||
                owners[i] < 0 || (owners[i] == owner && factions[i] != faction)) return;
    }
    const auto key = [](int32_t x, int32_t y) {
        return (static_cast<uint64_t>(static_cast<uint32_t>(x)) << 32) | static_cast<uint32_t>(y);
    };
    std::unordered_set<uint64_t> enemy_cells;
    enemy_cells.reserve(static_cast<size_t>(count));
    void *output = internal[ARRAY](result);
    resize(resize_array, output, 2);
    void *enemy_slot = array_write(output, 0), *front_slot = array_write(output, 1);
    reset_variant(enemy_slot, DICT); reset_variant(front_slot, INTS);
    void *enemies = internal[DICT](enemy_slot), *front = internal[INTS](front_slot);
    for (int64_t i = 0; i < count; ++i) if (factions[i] != faction) {
        if (!enemy_cells.insert(key(xs[i], ys[i])).second) continue;
        int32_t cell[] = {xs[i], ys[i]};
        VariantStorage cell_variant;
        from_v2i(&cell_variant, cell);
        void *slot = dict_write(enemies, &cell_variant);
        destroy(slot);
        GDExtensionBool value = true;
        from_bool(slot, &value);
        destroy(&cell_variant);
    }
    std::vector<int32_t> candidates;
    for (int64_t i = 0; i < count; ++i) if (owners[i] == owner) {
        const int32_t x = xs[i], y = ys[i];
        if (enemy_cells.count(key(x, y - 1)) || enemy_cells.count(key(x + 1, y)) ||
                enemy_cells.count(key(x, y + 1)) || enemy_cells.count(key(x - 1, y)))
            candidates.push_back(static_cast<int32_t>(i));
    }
    resize(resize_ints, front, static_cast<int64_t>(candidates.size()));
    if (!candidates.empty()) std::copy(candidates.begin(), candidates.end(), ints_write(front, 0));
}

bool collect_people_range(void *rows, void *cells, int64_t begin, int64_t end,
        std::vector<QueryPerson> &people, HotStore *store) {
    people.reserve(static_cast<size_t>(end - begin));
    for (int64_t i = begin; i < end; ++i) {
        void *row = array_at(rows, i);
        if (type_of(row) != DICT) return false;
        double hp, ko;
        // Same short circuit and predicate as the canonical combat_can_act.
        // Unusual coercions/types reject the WHOLE capture to untouched GD.
        // Reuse the existing read-only lookup: one hash lookup per field,
        // without retaining a pointer into the original person's Dictionary.
        ReadField hp_value(row, HP, store, i);
        if (!number(hp_value.get(), hp)) return false;
        if (hp <= 0.0) continue;
        ReadField ko_value(row, KO, store, i);
        if (!number(ko_value.get(), ko)) return false;
        if (ko > 0.0) continue;
        ReadField pose_value(row, POSE, store, i);
        void *pose = pose_value.get();
        if (!pose || type_of(pose) != STRING) return false;
        GDExtensionBool getting_up = false;
        string_equal(internal[STRING](pose), &get_up_string, &getting_up);
        if (getting_up) continue;
        ReadField captive_value(row, CAPTIVE, store, i);
        void *captive = captive_value.get();
        if (!captive || type_of(captive) != BOOL) return false;
        if (*static_cast<GDExtensionBool *>(internal[BOOL](captive))) continue;
        ReadField departed_value(row, DEPARTED, store, i);
        void *departed = departed_value.get();
        if (!departed || type_of(departed) != BOOL) return false;
        if (*static_cast<GDExtensionBool *>(internal[BOOL](departed))) continue;
        int64_t identity;
        ReadField identity_value(row, PERSON_ID);
        if (!integer(identity_value.get(), identity)) return false;
        void *cell = array_at(cells, i);
        if (type_of(cell) != V2I) return false;
        const auto *xy = static_cast<int32_t *>(internal[V2I](cell));
        people.push_back({i, identity, xy[0], xy[1]});
    }
    return true;
}

bool collect_people(void *rows, void *cells, std::vector<QueryPerson> &people, HotStore *store) {
    const int64_t count = size(rows);
    if (count < 0 || count > 10000 || size(cells) != count || (store && hot_row_count(store) != count)) return false;
    std::vector<QueryPerson> ranges[4];
    bool valid[4] = {true, true, true, true};
    project_ranges(count, [&](int64_t begin, int64_t end, uint32_t chunk) {
        valid[chunk] = collect_people_range(rows, cells, begin, end, ranges[chunk], store);
    });
    for (bool accepted : valid) if (!accepted) return false;
    people.reserve(static_cast<size_t>(count));
    for (const auto &range : ranges) people.insert(people.end(), range.begin(), range.end());
    return true;
}

void assign_copy(void *slot, const void *value) {
    destroy(slot);
    copy_variant(slot, value);
}

// Call-local query references only. No readiness calls, member filtering,
// cross-tick reuse, world changes or writes to the original person rows.
void call_capture(void *mode, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, ARRAY);
    const bool materialize = mode == &library || mode == &hot_capture_people_marker;
    HotStore *store = mode == &hot_capture_columns_marker || mode == &hot_capture_people_marker ?
        static_cast<HotStore *>(instance) : nullptr;
    const int expected_count = materialize ? 4 : 2;
    if (argc != expected_count) {
        error->error = argc < expected_count ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = expected_count;
        return;
    }
    const GDExtensionVariantType expected[] = {ARRAY, ARRAY, GDEXTENSION_VARIANT_TYPE_OBJECT, INT};
    for (int i = 0; i < expected_count; ++i) {
        if (type_of(args[i]) != expected[i]) {
            error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
            error->argument = i;
            error->expected = expected[i];
            return;
        }
    }
    void *rows = internal[ARRAY](const_cast<void *>(args[0]));
    void *cells = internal[ARRAY](const_cast<void *>(args[1]));
    std::vector<QueryPerson> people;
    if (!collect_people(rows, cells, people, store)) return;
    void *output = internal[ARRAY](result);
    const int64_t count = static_cast<int64_t>(people.size());
    if (materialize) {
        resize(resize_array, output, count);
        for (int64_t i = 0; i < count; ++i) {
            const auto &person = people[static_cast<size_t>(i)];
            void *slot = array_write(output, i);
            reset_variant(slot, DICT);
            void *dict = internal[DICT](slot);
            // Same String keys and insertion order as _exchange_people(false).
            assign_copy(dict_write(dict, &keys[OWNER]), args[2]);
            int64_t value = person.index;
            void *index_slot = dict_write(dict, &keys[UNIT]);
            destroy(index_slot); from_int(index_slot, &value);
            value = person.identity;
            void *identity_slot = dict_write(dict, &keys[IDENTITY]);
            destroy(identity_slot); from_int(identity_slot, &value);
            assign_copy(dict_write(dict, &keys[CELL]), array_at(cells, person.index));
            assign_copy(dict_write(dict, &keys[FACTION]), args[3]);
            // Inserting an absent key creates precisely the original null.
            dict_write(dict, &keys[READY]);
            dict_write(dict, &keys[RECEIVE]);
        }
    } else {
        resize(resize_array, output, 4);
        void *columns[4]{};
        for (int i = 0; i < 4; ++i) {
            void *slot = array_write(output, i);
            const auto type = i == 1 ? LONGS : INTS;
            reset_variant(slot, type);
            columns[i] = internal[type](slot);
            resize(i == 1 ? resize_longs : resize_ints, columns[i], count);
        }
        if (count == 0) return; // Do not request index 0 of an empty PackedArray.
        auto *indices = ints_write(columns[0], 0);
        auto *identities = longs_write(columns[1], 0);
        auto *xs = ints_write(columns[2], 0), *ys = ints_write(columns[3], 0);
        for (int64_t i = 0; i < count; ++i) {
            const auto &person = people[static_cast<size_t>(i)];
            indices[i] = static_cast<int32_t>(person.index);
            identities[i] = person.identity;
            xs[i] = person.x;
            ys[i] = person.y;
        }
    }
}

// Skip only a consecutive empty-inventory prefix from one captured owner.
// No classification cache: stop BEFORE a nonempty/exceptional row's callbacks.
void call_empty_cargo(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    int64_t next = 0;
    if (argc == 4 && type_of(args[3]) == INT)
        next = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[3])));
    destroy(result); from_int(result, &next);
    if (argc != 4 || type_of(args[0]) != ARRAY || type_of(args[1]) != INTS ||
            type_of(args[2]) != INTS || type_of(args[3]) != INT) return;
    void *rows = internal[ARRAY](const_cast<void *>(args[0]));
    void *indices = internal[INTS](const_cast<void *>(args[1]));
    void *slots = internal[INTS](const_cast<void *>(args[2]));
    const int64_t count = packed_size(size_ints, indices), row_count = size(rows);
    if (count > 10000 || row_count > 10000 || packed_size(size_ints, slots) != count || next < 0 || next >= count) return;
    const auto *unit = ints_read(indices, 0), *owner = ints_read(slots, 0);
    const int32_t selected_owner = owner[next];
    for (; next < count && owner[next] == selected_owner; ++next) {
        const int64_t index = unit[next];
        if (index < 0 || index >= row_count) break;
        void *row = array_at(rows, index);
        if (type_of(row) != DICT) break;
        ReadField cargo(row, CARGO);
        void *value = cargo.get();
        if (value && (type_of(value) != DICT || !predicate(dict_empty, internal[DICT](value)))) break;
    }
    destroy(result); from_int(result, &next);
}

// Pure call-local Manhattan membership only; no terrain/owner callbacks or writes.
void call_near_front(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    reset_variant(result, BYTES);
    if (argc != 3 || type_of(args[0]) != ARRAY || type_of(args[1]) != ARRAY || type_of(args[2]) != INT) return;
    void *enemies = internal[ARRAY](const_cast<void *>(args[0]));
    void *contacts = internal[ARRAY](const_cast<void *>(args[1]));
    const int64_t count = size(enemies), front_count = size(contacts);
    const int64_t radius = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[2])));
    // Bounded native brute force is cheaper for the current short front. Large
    // contact products keep the original spatial buckets; no new index/cache.
    if (count < 0 || count > 10000 || front_count < 0 || front_count > 10000 ||
            count * front_count > 2000000 || radius < 0 || radius > 8) return;
    struct Cell { int64_t x, y; };
    std::vector<Cell> positions, front;
    auto read_cells = [&](void *input, int64_t length, std::vector<Cell> &output) {
        output.reserve(static_cast<size_t>(length));
        for (int64_t i = 0; i < length; ++i) {
            void *cell = array_at(input, i);
            if (type_of(cell) != V2I) return false;
            const auto *xy = static_cast<int32_t *>(internal[V2I](cell));
            output.push_back({xy[0], xy[1]});
        }
        return true;
    };
    if (!read_cells(enemies, count, positions) || !read_cells(contacts, front_count, front)) return;
    void *output = internal[BYTES](result);
    resize(resize_bytes, output, count);
    if (count == 0) return;
    auto *mask = bytes_write(output, 0);
    for (int64_t i = 0; i < count; ++i) {
        const auto &cell = positions[static_cast<size_t>(i)];
        mask[i] = 0;
        for (const auto &contact : front) {
            const int64_t dx = cell.x - contact.x, dy = cell.y - contact.y;
            if ((dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy) <= radius) { mask[i] = 1; break; }
        }
    }
}

void call_advance(void *mode, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args, GDExtensionInt count, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    int64_t next = -1;
    const bool recovering = mode == &recovery_marker;
    const bool fatigue = mode && !recovering;
    const int argc = recovering ? 7 : (fatigue ? 4 : 6);
    if (count != argc) {
        error->error = count < argc ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = argc;
    } else {
        const GDExtensionVariantType expected[] = {ARRAY, ARRAY, fatigue ? INT : DICT, INT, INT, FLOAT, FLOAT};
        for (int i = 0; i < argc; ++i) {
            if (type_of(args[i]) != expected[i]) {
                error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
                error->argument = i;
                error->expected = expected[i];
                break;
            }
        }
        if (error->error == GDEXTENSION_CALL_OK) {
            if (fatigue) next = fatigue_prefix(internal[ARRAY](const_cast<void *>(args[0])), internal[ARRAY](const_cast<void *>(args[1])),
                *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[2]))), *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[3]))));
            else {
                const double recovery = recovering ? *static_cast<double *>(internal[FLOAT](const_cast<void *>(args[6]))) : -1.0;
                next = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[3])));
                if (!recovering || (std::isfinite(recovery) && recovery >= 0.0)) next = advance(internal[ARRAY](const_cast<void *>(args[0])), internal[ARRAY](const_cast<void *>(args[1])), internal[DICT](const_cast<void *>(args[2])),
                *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[3]))), *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[4]))),
                *static_cast<double *>(internal[FLOAT](const_cast<void *>(args[5]))), recovery);
            }
        }
    }
    destroy(result); // ClassMethodCall receives an initialized Variant.
    from_int(result, &next);
}

// One instance belongs to one TerrainArmy. The old shared ArmyIdleKernel stays
// stateless; these fields have no Dictionary lookup on their active read path.
constexpr Key hot_keys[] = {HP, KO, AGE, THINK, STUN, GRACE, COOLDOWN, STAGGER, SKILL, RANGED, DURATION,
    POSE, ATTACK, MEMBER, CAPTIVE, DEPARTED, PRESENT, VISUAL};
constexpr int HOT_NUMBERS = 11;
constexpr int HOT_COUNT = sizeof(hot_keys) / sizeof(hot_keys[0]);
struct HotRow {
    VariantStorage values[HOT_COUNT];
    bool present[HOT_COUNT]{};
    uint32_t name_keys = 0; // Dictionary key type is part of the logical row.
    HotRow() {
        for (auto &value : values) {
            GDExtensionCallError error{};
            variant_construct(NIL, &value, nullptr, 0, &error);
        }
    }
    ~HotRow() { for (auto &value : values) destroy(&value); }
    HotRow(const HotRow &) = delete;
    HotRow &operator=(const HotRow &) = delete;
};
struct HotStore {
    std::unique_ptr<HotRow[]> rows;
    int64_t count = 0;
};
int64_t hot_row_count(HotStore *store) { return store->count; }
int hot_slot(Key key) {
    switch (key) {
        case HP: return 0; case KO: return 1; case AGE: return 2; case THINK: return 3;
        case STUN: return 4; case GRACE: return 5; case COOLDOWN: return 6;
        case STAGGER: return 7; case SKILL: return 8; case RANGED: return 9;
        case DURATION: return 10; case POSE: return 11; case ATTACK: return 12;
        case MEMBER: return 13; case CAPTIVE: return 14; case DEPARTED: return 15;
        case PRESENT: return 16; case VISUAL: return 17;
        default: return -1;
    }
}
bool hot_owns(Key key) { return hot_slot(key) >= 0; }
void *hot_value(HotStore *store, int64_t index, Key key) {
    const int slot = hot_slot(key);
    if (slot < 0 || index < 0 || index >= store->count) return nullptr;
    HotRow &row = store->rows[index];
    return row.present[slot] ? &row.values[slot] : nullptr;
}
enum HotBarrier { HOT_END = 0, HOT_MOVE = 1, HOT_WAKE = 2, HOT_OWNER = 3 };
// Stable diagnostic-only reason codes. The ordinary two-int advance ABI does
// not classify rows; Army requests a three-int result only in diagnostics.
enum HotOwnerReason { REASON_NONE = 0, REASON_INPUT_INVALID, REASON_STATE_INVALID,
    REASON_MOVEMENT_INVALID, REASON_RESCUE, REASON_VISUAL_CLEAR, REASON_VISUAL_EXPIRY,
    REASON_VISUAL_INVALID, REASON_NUMERIC_INVALID, REASON_ATTACK_ACTIVE,
    REASON_POSE_OWNER, REASON_POSE_EXPIRY, REASON_THINK_NONHOLD, REASON_THINK_HOLD };
struct HotAdvance { int64_t next; HotBarrier barrier; HotOwnerReason reason = REASON_NONE; };
bool hot_number(HotRow &row, int field, double &out) {
    if (!row.present[field]) { out = 0.0; return field >= 6 && field <= 10; }
    return number(&row.values[field], out);
}
void hot_float(HotRow &row, int field, double value) {
    assign_float(&row.values[field], value);
    if (!row.present[field]) row.name_keys &= ~(uint32_t(1) << field); // Native timer writes use String keys.
    row.present[field] = true;
}
HotAdvance advance_hot(HotStore *store, void *moving, void *progress, void *durations, void *rescues,
        int64_t start, int64_t end, double delta, double game_seconds, double recovery, bool holding) {
    if (start < 0 || end < start || end > store->count || size(moving) != store->count ||
            packed_size(size_doubles, progress) != store->count || packed_size(size_doubles, durations) != store->count ||
            !std::isfinite(delta) || delta <= 0.0 || !std::isfinite(game_seconds) || game_seconds <= 0.0 ||
            !std::isfinite(recovery) || recovery < 0.0) return {start, HOT_OWNER, REASON_INPUT_INVALID};
    for (int64_t i = start; i < end; ++i) {
        HotRow &row = store->rows[i];
        double hp, ko, age, think, stun, grace, pose_duration, timers[4];
        if (!hot_number(row, 0, hp) || !hot_number(row, 1, ko) || !hot_number(row, 2, age) ||
                !hot_number(row, 3, think) || !hot_number(row, 4, stun) || !hot_number(row, 5, grace) ||
                !hot_number(row, 10, pose_duration)) return {i, HOT_OWNER, REASON_STATE_INVALID};
        for (int t = 0; t < 4; ++t) if (!hot_number(row, 6 + t, timers[t])) return {i, HOT_OWNER, REASON_STATE_INVALID};
        void *cell = array_at(moving, i);
        if (type_of(cell) != V2I || !row.present[11] || type_of(&row.values[11]) != STRING ||
                !row.present[12] || type_of(&row.values[12]) != BOOL) return {i, HOT_OWNER, REASON_STATE_INVALID};
        const auto *xy = static_cast<int32_t *>(internal[V2I](cell));
        const bool moving_now = xy[0] != -1 || xy[1] != -1;
        double movement_next = 0.0;
        if (moving_now) {
            const double current = *doubles_read(progress, i), duration = *doubles_read(durations, i);
            if (!std::isfinite(current) || !std::isfinite(duration) || duration <= 0.0) return {i, HOT_OWNER, REASON_MOVEMENT_INVALID};
            movement_next = 1.0 < current + delta / duration ? 1.0 : current + delta / duration;
            if ((1.0 - movement_next) * duration <= 0.000000001) movement_next = 1.0;
            if (movement_next >= 1.0) return {i, HOT_MOVE}; // Owner advances this row once, then commits occupancy.
        }
        VariantStorage ordinal;
        from_int(&ordinal, &i);
        const bool rescue = has(rescues, &ordinal);
        destroy(&ordinal);
        if (rescue) return {i, HOT_OWNER, REASON_RESCUE};
        // A live short result has a pure age/left update until expiry. Keep
        // the expiry itself on the ordered owner path so it erases the key and
        // marks that presentation row exactly once.
        void *visual_dict = row.present[17] ? internal[DICT](&row.values[17]) : nullptr;
        bool visual_active = false;
        double visual_age = 0.0, visual_left = 0.0;
        if (visual_dict) {
            if (hp <= 0.0 || ko > 0.0) return {i, HOT_OWNER, REASON_VISUAL_CLEAR}; // Owner erases even an empty key.
            if (!predicate(dict_empty, visual_dict)) {
                if (predicate(dict_readonly, visual_dict) || predicate(dict_typed, visual_dict) ||
                        !number(field(visual_dict, AGE), visual_age) || !number(field(visual_dict, LEFT), visual_left) ||
                        !field(visual_dict, POSE) || type_of(field(visual_dict, POSE)) != STRING ||
                        !field(visual_dict, FACING) || type_of(field(visual_dict, FACING)) != V2I ||
                        !std::isfinite(visual_age + delta))
                    return {i, HOT_OWNER, REASON_VISUAL_INVALID};
                if (visual_left - delta <= 0.000000001) return {i, HOT_OWNER, REASON_VISUAL_EXPIRY};
                visual_active = true;
            }
        }
        GDExtensionBool idle = false, unconscious = false, down = false, getting_up = false, guard_raise = false, guard_lower = false, guard_break = false, rescue_pose = false;
        void *pose = internal[STRING](&row.values[11]);
        string_equal(pose, &idle_string, &idle);
        string_equal(pose, &unconscious_string, &unconscious);
        string_equal(pose, &get_up_string, &getting_up);
        string_equal(pose, &down_string, &down);
        string_equal(pose, &guard_raise_string, &guard_raise);
        string_equal(pose, &guard_lower_string, &guard_lower);
        string_equal(pose, &guard_break_string, &guard_break);
        string_equal(pose, &rescue_string, &rescue_pose);
        if (visual_dict && (unconscious || down || getting_up || guard_raise || guard_lower || guard_break || rescue_pose))
            return {i, HOT_OWNER, REASON_VISUAL_CLEAR}; // These poses clear the visual facet before other state work.
        const double aged = age + delta;
        if (!std::isfinite(aged)) return {i, HOT_OWNER, REASON_NUMERIC_INVALID};
        bool timers_zero = true;
        for (double timer : timers) timers_zero = timers_zero && timer == 0.0;
        for (double &timer : timers) {
            const double left = timer - delta;
            timer = left <= 0.000000001 ? 0.0 : (0.0 > left ? 0.0 : left);
        }
        if (moving_now && !std::isfinite(movement_next)) return {i, HOT_OWNER, REASON_MOVEMENT_INVALID};
        if (hp > 0.0 && ko > 0.0) {
            if (ko <= game_seconds) return {i, HOT_WAKE};
            if (down && aged >= 2.875) return {i, HOT_OWNER, REASON_POSE_EXPIRY};
            hot_float(row, 2, aged);
            for (int t = 0; t < 4; ++t) hot_float(row, 6 + t, timers[t]);
            if (moving_now) *doubles_write(progress, i) = movement_next;
            hot_float(row, 1, 0.0 > ko - game_seconds ? 0.0 : ko - game_seconds);
            continue;
        }
        if (hp <= 0.0) {
            hot_float(row, 2, aged);
            for (int t = 0; t < 4; ++t) hot_float(row, 6 + t, timers[t]);
            if (moving_now) *doubles_write(progress, i) = movement_next;
            continue;
        }
        // The original special rear-rank branch performs one think decrement.
        bool idle_fast = !visual_active && !holding && idle && !moving_now && stun == 0.0 && grace == 0.0 && pose_duration == 0.0 && timers_zero;
        if (idle_fast) {
            hot_float(row, 2, aged);
            for (int t = 0; t < 4; ++t) hot_float(row, 6 + t, 0.0);
            hot_float(row, 5, 0.0); hot_float(row, 4, 0.0);
            hot_float(row, 3, 0.0 > think - delta ? 0.0 : think - delta);
            continue;
        }
        // Non-idle rows are admitted when pose/AI work will not cross a
        // callback boundary on this step. They no longer exit merely by pose.
        // In admitted exchange mode ATTACK is a state flag, not a per-tick
        // callback. _advance_exchange_pose only changes it at pose expiry,
        // already stopped below in ordinal order.
        if (guard_raise || guard_lower || guard_break || down || unconscious) return {i, HOT_OWNER, REASON_POSE_OWNER};
        if (getting_up && aged + 0.000000001 >= 2.2) return {i, HOT_OWNER, REASON_POSE_EXPIRY};
        if (pose_duration > 0.0 && aged + 0.000000001 >= pose_duration) return {i, HOT_OWNER, REASON_POSE_EXPIRY};
        // Exchange mode continues before the legacy second think decrement.
        const double next_think = 0.0 > think - delta ? 0.0 : think - delta;
        // Non-HOLD exchange prepares only decrement think and continue; the
        // sole think-expiry callback is HOLD's automatic rescue search.
        if (next_think <= 0.0 && holding) return {i, HOT_OWNER, REASON_THINK_HOLD};
        const double difference = delta - grace, decay = 0.0 > difference ? 0.0 : difference;
        const double recovered = decay * recovery;
        const double grace_left = grace - delta, stun_left = stun - recovered;
        if (!std::isfinite(recovered) || !std::isfinite(grace_left) || !std::isfinite(stun_left)) return {i, HOT_OWNER, REASON_NUMERIC_INVALID};
        hot_float(row, 2, aged);
        for (int t = 0; t < 4; ++t) hot_float(row, 6 + t, timers[t]);
        if (moving_now) *doubles_write(progress, i) = movement_next;
        hot_float(row, 5, 0.0 > grace_left ? 0.0 : grace_left);
        hot_float(row, 4, 0.0 > stun_left ? 0.0 : stun_left);
        hot_float(row, 3, next_think);
        if (visual_active) {
            write_float(visual_dict, AGE, visual_age + delta);
            write_float(visual_dict, LEFT, visual_left - delta);
        }
    }
    return {end, HOT_END};
}
int hot_field(void *name) {
    const auto type = type_of(name);
    if (type != STRING && type != NAME) return -1;
    for (int field = 0; field < HOT_COUNT; ++field) {
        GDExtensionBool equal = false;
        (type == STRING ? string_equal : name_equal)(internal[type](name),
            internal[type](type == STRING ? static_cast<void *>(&keys[hot_keys[field]]) :
                static_cast<void *>(&lookup_keys[hot_keys[field]])), &equal);
        if (equal) return field;
    }
    return -1;
}
bool hot_key_masks(void *source, uint32_t &seen, uint32_t &names) {
    seen = names = 0;
    VariantStorage all_keys{};
    if (!get_keys(source, all_keys)) { destroy(&all_keys); return false; }
    void *array = internal[ARRAY](&all_keys);
    bool valid = true;
    for (int64_t i = 0, count = size(array); i < count; ++i) {
        void *key = array_at(array, i);
        const int slot = hot_field(key);
        if (slot < 0) continue;
        const uint32_t bit = uint32_t(1) << slot;
        if (seen & bit) { valid = false; break; } // String and StringName aliases are ambiguous.
        seen |= bit;
        if (type_of(key) == NAME) names |= bit;
    }
    destroy(&all_keys);
    return valid;
}
const void *hot_key(const HotRow &row, int field) {
    return (row.name_keys & (uint32_t(1) << field)) ?
        static_cast<const void *>(&lookup_keys[hot_keys[field]]) : static_cast<const void *>(&keys[hot_keys[field]]);
}
bool hot_valid(int field, void *value) {
    if (field < HOT_NUMBERS) { double parsed; return number(value, parsed); }
    if (field == HOT_NUMBERS) return type_of(value) == STRING;
    if (field == 17) return type_of(value) == DICT;
    return type_of(value) == BOOL;
}
bool hot_optional(int field) { return field >= 6 && field <= 10 || field == 13 || field == 17; }
bool load_hot(HotStore *store, void *input) {
    const int64_t count = size(input);
    if (count < 0 || count > 10000) return false;
    std::unique_ptr<HotRow[]> next(count ? new HotRow[static_cast<size_t>(count)] : nullptr);
    for (int64_t i = 0; i < count; ++i) {
        void *row = array_at(input, i);
        if (type_of(row) != DICT) return false;
        void *dict = internal[DICT](row);
        if (predicate(dict_readonly, dict) || predicate(dict_typed, dict)) return false;
        uint32_t seen = 0, names = 0;
        if (!hot_key_masks(row, seen, names)) return false;
        for (int field = 0; field < HOT_COUNT; ++field) {
            const uint32_t bit = uint32_t(1) << field;
            if (!(seen & bit)) {
                if (!hot_optional(field)) return false;
                continue;
            }
            const void *key = names & bit ? static_cast<const void *>(&lookup_keys[hot_keys[field]]) :
                static_cast<const void *>(&keys[hot_keys[field]]);
            void *value = dict_at(dict, key);
            if (!value || !hot_valid(field, value)) return false;
            auto &slot = next[i].values[field];
            destroy(&slot);
            copy_variant(&slot, value);
            next[i].present[field] = true;
        }
        next[i].name_keys = names;
    }
    store->rows = std::move(next);
    store->count = count;
    return true;
}
enum class HotMethod { LOAD, GET, HAS, SET, ERASE, COLUMN, CAPTURE, SIZE, ADVANCE, CAPTURE_ROW, ABSORB_ROW, CAN_ACT, RETAINED_IDLE_MASK, ADVANCE_HOLD, ADVANCE_REASON, ADVANCE_HOLD_REASON };
HotMethod hot_methods[] = {HotMethod::LOAD, HotMethod::GET, HotMethod::HAS, HotMethod::SET,
    HotMethod::ERASE, HotMethod::COLUMN, HotMethod::CAPTURE, HotMethod::SIZE, HotMethod::ADVANCE,
    HotMethod::CAPTURE_ROW, HotMethod::ABSORB_ROW, HotMethod::CAN_ACT, HotMethod::RETAINED_IDLE_MASK, HotMethod::ADVANCE_HOLD,
    HotMethod::ADVANCE_REASON, HotMethod::ADVANCE_HOLD_REASON};
void call_hot(void *mode_ptr, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
        GDExtensionInt argc, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    *error = {GDEXTENSION_CALL_OK, 0, 0};
    auto *store = static_cast<HotStore *>(instance);
    const auto mode = *static_cast<HotMethod *>(mode_ptr);
    const int expected = mode == HotMethod::ADVANCE || mode == HotMethod::ADVANCE_HOLD ||
        mode == HotMethod::ADVANCE_REASON || mode == HotMethod::ADVANCE_HOLD_REASON ? 9 :
        mode == HotMethod::LOAD || mode == HotMethod::COLUMN || mode == HotMethod::CAPTURE_ROW || mode == HotMethod::CAN_ACT ? 1 :
        mode == HotMethod::GET || mode == HotMethod::SET ? 3 :
        mode == HotMethod::HAS || mode == HotMethod::ERASE || mode == HotMethod::ABSORB_ROW ? 2 : 0;
    if (argc != expected) {
        error->error = argc < expected ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = expected;
        return;
    }
    const auto result_bool = [&](bool value) { destroy(result); GDExtensionBool flag = value; from_bool(result, &flag); };
    if (mode == HotMethod::SIZE) { destroy(result); from_int(result, &store->count); return; }
    if (mode == HotMethod::RETAINED_IDLE_MASK) {
        reset_variant(result, BYTES);
        void *output = internal[BYTES](result);
        resize(resize_bytes, output, store->count);
        if (!store->count) return;
        auto *mask = bytes_write(output, 0);
        for (int64_t i = 0; i < store->count; ++i) {
            HotRow &row = store->rows[i];
            GDExtensionBool idle = false, unconscious = false;
            void *pose = internal[STRING](&row.values[11]);
            string_equal(pose, &idle_string, &idle);
            string_equal(pose, &unconscious_string, &unconscious);
            mask[i] = (idle || unconscious) && !row.present[17];
        }
        return;
    }
    if (mode == HotMethod::CAN_ACT) {
        bool capable = false;
        if (type_of(args[0]) == INT) {
            const int64_t index = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[0])));
            if (index >= 0 && index < store->count) {
                HotRow &row = store->rows[index];
                double hp, ko;
                GDExtensionBool getting_up = false;
                string_equal(internal[STRING](&row.values[11]), &get_up_string, &getting_up);
                capable = hot_number(row, 0, hp) && hp > 0.0 && hot_number(row, 1, ko) && ko <= 0.0 &&
                    !getting_up && !*static_cast<GDExtensionBool *>(internal[BOOL](&row.values[14])) &&
                    !*static_cast<GDExtensionBool *>(internal[BOOL](&row.values[15]));
            }
        }
        result_bool(capable);
        return;
    }
    if (mode == HotMethod::ADVANCE || mode == HotMethod::ADVANCE_HOLD ||
            mode == HotMethod::ADVANCE_REASON || mode == HotMethod::ADVANCE_HOLD_REASON) {
        const bool diagnostic = mode == HotMethod::ADVANCE_REASON || mode == HotMethod::ADVANCE_HOLD_REASON;
        reset_variant(result, INTS);
        void *output = internal[INTS](result);
        resize(resize_ints, output, diagnostic ? 3 : 2);
        auto *status = ints_write(output, 0);
        status[0] = 0; status[1] = HOT_OWNER;
        if (diagnostic) status[2] = REASON_INPUT_INVALID;
        const GDExtensionVariantType types[] = {ARRAY, DOUBLES, DOUBLES, DICT, INT, INT, FLOAT, FLOAT, FLOAT};
        for (int i = 0; i < 9; ++i) if (type_of(args[i]) != types[i]) return;
        const int64_t start = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[4])));
        const int64_t end = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[5])));
        const HotAdvance advanced = advance_hot(store,
            internal[ARRAY](const_cast<void *>(args[0])), internal[DOUBLES](const_cast<void *>(args[1])),
            internal[DOUBLES](const_cast<void *>(args[2])), internal[DICT](const_cast<void *>(args[3])),
            start, end, *static_cast<double *>(internal[FLOAT](const_cast<void *>(args[6]))),
            *static_cast<double *>(internal[FLOAT](const_cast<void *>(args[7]))),
            *static_cast<double *>(internal[FLOAT](const_cast<void *>(args[8]))),
            mode == HotMethod::ADVANCE_HOLD || mode == HotMethod::ADVANCE_HOLD_REASON);
        status[0] = static_cast<int32_t>(advanced.next);
        status[1] = advanced.barrier;
        if (diagnostic) status[2] = advanced.reason;
        return;
    }
    if (mode == HotMethod::LOAD) {
        result_bool(type_of(args[0]) == ARRAY && load_hot(store, internal[ARRAY](const_cast<void *>(args[0]))));
        return;
    }
    if (mode == HotMethod::CAPTURE) {
        reset_variant(result, ARRAY);
        void *output = internal[ARRAY](result);
        resize(resize_array, output, store->count);
        for (int64_t i = 0; i < store->count; ++i) {
            void *row = array_write(output, i);
            reset_variant(row, DICT);
            void *dict = internal[DICT](row);
            for (int field = 0; field < HOT_COUNT; ++field) {
                if (!store->rows[i].present[field]) continue;
                void *slot = dict_write(dict, hot_key(store->rows[i], field));
                destroy(slot);
                copy_variant(slot, &store->rows[i].values[field]);
            }
        }
        return;
    }
    if (mode == HotMethod::CAPTURE_ROW) {
        reset_variant(result, DICT);
        if (type_of(args[0]) != INT) return;
        const int64_t index = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[0])));
        if (index < 0 || index >= store->count) return;
        void *dict = internal[DICT](result);
        for (int field = 0; field < HOT_COUNT; ++field) {
            if (!store->rows[index].present[field]) continue;
            void *slot = dict_write(dict, hot_key(store->rows[index], field));
            destroy(slot);
            copy_variant(slot, &store->rows[index].values[field]);
        }
        return;
    }
    if (mode == HotMethod::ABSORB_ROW) {
        if (type_of(args[0]) != INT || type_of(args[1]) != DICT) { result_bool(false); return; }
        const int64_t index = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[0])));
        if (index < 0 || index >= store->count) { result_bool(false); return; }
        void *source = internal[DICT](const_cast<void *>(args[1]));
        uint32_t seen = 0, names = 0;
        if (!hot_key_masks(const_cast<void *>(args[1]), seen, names)) { result_bool(false); return; }
        for (int column = 0; column < HOT_COUNT; ++column) {
            const uint32_t bit = uint32_t(1) << column;
            const void *key = names & bit ? static_cast<const void *>(&lookup_keys[hot_keys[column]]) :
                static_cast<const void *>(&keys[hot_keys[column]]);
            void *value = seen & bit ? dict_at(source, key) : nullptr;
            if ((!value && !hot_optional(column)) || (value && !hot_valid(column, value))) { result_bool(false); return; }
        }
        HotRow &row = store->rows[index];
        for (int column = 0; column < HOT_COUNT; ++column) {
            const uint32_t bit = uint32_t(1) << column;
            const void *key = names & bit ? static_cast<const void *>(&lookup_keys[hot_keys[column]]) :
                static_cast<const void *>(&keys[hot_keys[column]]);
            void *value = seen & bit ? dict_at(source, key) : nullptr;
            destroy(&row.values[column]);
            if (value) copy_variant(&row.values[column], value);
            else {
                GDExtensionCallError construct_error{};
                variant_construct(NIL, &row.values[column], nullptr, 0, &construct_error);
            }
            row.present[column] = value != nullptr;
        }
        row.name_keys = names;
        result_bool(true);
        return;
    }
    int field = -1;
    int64_t index = -1;
    if (mode == HotMethod::COLUMN) field = hot_field(const_cast<void *>(args[0]));
    else if (type_of(args[0]) == INT && (type_of(args[1]) == STRING || type_of(args[1]) == NAME)) {
        index = *static_cast<int64_t *>(internal[INT](const_cast<void *>(args[0])));
        field = hot_field(const_cast<void *>(args[1]));
    }
    if (mode == HotMethod::COLUMN) {
        reset_variant(result, DOUBLES);
        if (field < 0 || field == HOT_NUMBERS || field == 17) return;
        void *output = internal[DOUBLES](result);
        resize(resize_doubles, output, store->count);
        if (!store->count) return;
        auto *values = doubles_write(output, 0);
        for (int64_t i = 0; i < store->count; ++i) {
            double value = field == 13 ? 1.0 : 0.0;
            if (store->rows[i].present[field]) {
                if (field < HOT_NUMBERS) number(&store->rows[i].values[field], value);
                else value = *static_cast<GDExtensionBool *>(internal[BOOL](&store->rows[i].values[field])) ? 1.0 : 0.0;
            }
            values[i] = value;
        }
        return;
    }
    if (field < 0 || index < 0 || index >= store->count) {
        if (mode == HotMethod::GET) { destroy(result); copy_variant(result, args[2]); }
        else result_bool(false);
        return;
    }
    auto &row = store->rows[index];
    if (mode == HotMethod::GET) {
        destroy(result);
        copy_variant(result, row.present[field] ? &row.values[field] : args[2]);
    } else if (mode == HotMethod::HAS) result_bool(row.present[field]);
    else if (mode == HotMethod::ERASE) {
        if (!hot_optional(field)) { result_bool(false); return; }
        destroy(&row.values[field]);
        GDExtensionCallError construct_error{};
        variant_construct(NIL, &row.values[field], nullptr, 0, &construct_error);
        row.present[field] = false;
        row.name_keys &= ~(uint32_t(1) << field);
        result_bool(true);
    } else {
        if (!hot_valid(field, const_cast<void *>(args[2]))) { result_bool(false); return; }
        if (!row.present[field]) {
            const uint32_t bit = uint32_t(1) << field;
            if (type_of(args[1]) == NAME) row.name_keys |= bit;
            else row.name_keys &= ~bit;
        }
        destroy(&row.values[field]);
        copy_variant(&row.values[field], args[2]);
        row.present[field] = true;
        result_bool(true);
    }
}
GDExtensionObjectPtr create_hot(void *, GDExtensionBool) {
    auto object = construct_object(&parent_name);
    set_instance(object, &hot_class_name, new HotStore);
    return object;
}
void free_hot(void *, GDExtensionClassInstancePtr instance) { delete static_cast<HotStore *>(instance); }
void register_hot() {
    make_name(&hot_class_name, "ArmyCombatHot", false);
    GDExtensionClassCreationInfo4 info{};
    info.is_exposed = true;
    info.create_instance_func = create_hot;
    info.free_instance_func = free_hot;
    register_class(library, &hot_class_name, &parent_name, &info);
    const char *names[] = {"load_rows", "get_field", "has_field", "set_field", "erase_field", "column", "capture_rows", "row_count"};
    const int arities[] = {1, 3, 2, 3, 2, 1, 0, 0};
    const GDExtensionVariantType return_types[] = {BOOL, NIL, BOOL, BOOL, BOOL, DOUBLES, ARRAY, INT};
    const GDExtensionVariantType arg_types[][3] = {
        {ARRAY, NIL, NIL}, {INT, STRING, NIL}, {INT, STRING, NIL}, {INT, NIL, NIL},
        {INT, STRING, NIL}, {STRING, NIL, NIL}, {NIL, NIL, NIL}, {NIL, NIL, NIL}};
    const char *arg_text[] = {"index", "field", "value"};
    for (int mode = 0; mode < 8; ++mode) {
        TextStorage name, arg_names[3];
        GDExtensionPropertyInfo arguments[3];
        GDExtensionClassMethodArgumentMetadata metadata[3]{};
        make_name(&name, names[mode], false);
        for (int i = 0; i < arities[mode]; ++i) {
            make_name(&arg_names[i], mode == 0 ? "rows" : arg_text[i], false);
            arguments[i] = {arg_types[mode][i], &arg_names[i], &empty_name, 0, &empty_string, 6};
        }
        GDExtensionPropertyInfo result_info{return_types[mode], &empty_name, &empty_name, 0, &empty_string, 6};
        GDExtensionClassMethodInfo method{};
        method.name = &name;
        method.method_userdata = &hot_methods[mode];
        method.call_func = call_hot;
        method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
        method.has_return_value = true;
        method.return_value_info = &result_info;
        method.argument_count = arities[mode];
        method.arguments_info = arguments;
        method.arguments_metadata = metadata;
        register_method(library, &hot_class_name, &method);
        for (int i = 0; i < arities[mode]; ++i) destroy_name(&arg_names[i]);
        destroy_name(&name);
    }
    const char *arg_text_advance[] = {"moving", "progress", "durations", "rescues", "start", "end", "delta", "game_seconds", "recovery"};
    const GDExtensionVariantType arg_types_advance[] = {ARRAY, DOUBLES, DOUBLES, DICT, INT, INT, FLOAT, FLOAT, FLOAT};
    for (int mode : {8, 13, 14, 15}) {
        TextStorage name, arg_names[9];
        const char *advance_name = mode == 8 ? "advance_numeric" : mode == 13 ? "advance_numeric_hold" :
            mode == 14 ? "advance_numeric_reason" : "advance_numeric_hold_reason";
        make_name(&name, advance_name, false);
        GDExtensionPropertyInfo arguments[9];
        GDExtensionClassMethodArgumentMetadata metadata[9]{};
        for (int i = 0; i < 9; ++i) {
            make_name(&arg_names[i], arg_text_advance[i], false);
            arguments[i] = {arg_types_advance[i], &arg_names[i], &empty_name, 0, &empty_string, 6};
        }
        GDExtensionPropertyInfo result_info{INTS, &empty_name, &empty_name, 0, &empty_string, 6};
        GDExtensionClassMethodInfo method{};
        method.name = &name;
        method.method_userdata = &hot_methods[mode];
        method.call_func = call_hot;
        method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
        method.has_return_value = true;
        method.return_value_info = &result_info;
        method.argument_count = 9;
        method.arguments_info = arguments;
        method.arguments_metadata = metadata;
        register_method(library, &hot_class_name, &method);
        for (auto &arg_name : arg_names) destroy_name(&arg_name);
        destroy_name(&name);
    }
    for (int mode = 9; mode <= 10; ++mode) {
        TextStorage row_name, row_arg_names[2];
        const bool absorb = mode == 10;
        make_name(&row_name, absorb ? "absorb_row" : "capture_row", false);
        GDExtensionPropertyInfo row_arguments[2];
        GDExtensionClassMethodArgumentMetadata row_metadata[2]{};
        make_name(&row_arg_names[0], "index", false);
        row_arguments[0] = {INT, &row_arg_names[0], &empty_name, 0, &empty_string, 6};
        if (absorb) {
            make_name(&row_arg_names[1], "row", false);
            row_arguments[1] = {DICT, &row_arg_names[1], &empty_name, 0, &empty_string, 6};
        }
        GDExtensionPropertyInfo row_result{absorb ? BOOL : DICT, &empty_name, &empty_name, 0, &empty_string, 6};
        GDExtensionClassMethodInfo row_method{};
        row_method.name = &row_name;
        row_method.method_userdata = &hot_methods[mode];
        row_method.call_func = call_hot;
        row_method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
        row_method.has_return_value = true;
        row_method.return_value_info = &row_result;
        row_method.argument_count = absorb ? 2 : 1;
        row_method.arguments_info = row_arguments;
        row_method.arguments_metadata = row_metadata;
        register_method(library, &hot_class_name, &row_method);
        destroy_name(&row_arg_names[0]);
        if (absorb) destroy_name(&row_arg_names[1]);
        destroy_name(&row_name);
    }
    TextStorage can_name, index_name;
    make_name(&can_name, "can_act", false);
    make_name(&index_name, "index", false);
    GDExtensionPropertyInfo can_argument{INT, &index_name, &empty_name, 0, &empty_string, 6};
    GDExtensionClassMethodArgumentMetadata can_metadata{};
    GDExtensionPropertyInfo can_result{BOOL, &empty_name, &empty_name, 0, &empty_string, 6};
    GDExtensionClassMethodInfo can_method{};
    can_method.name = &can_name;
    can_method.method_userdata = &hot_methods[11];
    can_method.call_func = call_hot;
    can_method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    can_method.has_return_value = true;
    can_method.return_value_info = &can_result;
    can_method.argument_count = 1;
    can_method.arguments_info = &can_argument;
    can_method.arguments_metadata = &can_metadata;
    register_method(library, &hot_class_name, &can_method);
    destroy_name(&index_name);
    destroy_name(&can_name);
    TextStorage mask_name;
    make_name(&mask_name, "retained_idle_mask", false);
    GDExtensionPropertyInfo mask_result{BYTES, &empty_name, &empty_name, 0, &empty_string, 6};
    GDExtensionClassMethodInfo mask_method{};
    mask_method.name = &mask_name;
    mask_method.method_userdata = &hot_methods[12];
    mask_method.call_func = call_hot;
    mask_method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    mask_method.has_return_value = true;
    mask_method.return_value_info = &mask_result;
    register_method(library, &hot_class_name, &mask_method);
    destroy_name(&mask_name);
}
GDExtensionObjectPtr create(void *, GDExtensionBool) {
    auto object = construct_object(&parent_name);
    // A stateless marker only. All row references exist on the call stack.
    set_instance(object, &class_name, object);
    return object;
}
void free_instance(void *, GDExtensionClassInstancePtr) {}

void initialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    make_name(&class_name, "ArmyIdleKernel", false);
    make_name(&parent_name, "RefCounted", false);
    make_name(&empty_name, "", false);
    make_string(&empty_string, "");
    make_string(&idle_string, "idle");
    make_string(&unconscious_string, "unconscious");
    make_string(&down_string, "down");
    make_string(&guard_raise_string, "guard_raise");
    make_string(&guard_lower_string, "guard_lower");
    make_string(&guard_break_string, "guard_break");
    make_string(&rescue_string, "rescue");
    make_string(&male_string, "male_atlas");
    make_string(&female_string, "female_atlas");
    make_string(&get_up_string, "get_up");
    TextStorage pool_name, wait_name;
    make_name(&pool_name, "WorkerThreadPool", false);
    make_name(&wait_name, "wait_for_group_task_completion", false);
    worker_pool = get_singleton(&pool_name);
    wait_group_task = get_method_bind(&pool_name, &wait_name, 1286410249);
    destroy_name(&pool_name); destroy_name(&wait_name);
    for (int i = 0; i < KEY_COUNT; ++i) {
        TextStorage text;
        make_string(&text, key_text[i]);
        from_string(&keys[i], &text);
        destroy_string(&text);
        make_name(&text, key_text[i], false);
        from_name(&lookup_keys[i], &text);
        destroy_name(&text);
    }
    GDExtensionClassCreationInfo4 info{};
    info.is_exposed = true;
    info.create_instance_func = create;
    info.free_instance_func = free_instance;
    register_class(library, &class_name, &parent_name, &info);
    register_hot();
    make_name(&keys_method_name, "keys", false);
    make_name(&typed_builtin_method_name, "get_typed_builtin", false);
    make_name(&typed_class_method_name, "get_typed_class_name", false);
    make_name(&typed_script_method_name, "get_typed_script", false);
    for (int mode = 0; mode < 2; ++mode) {
        TextStorage method_name, argument_names[2];
        make_name(&method_name, mode == 0 ? "exact_value_equal" : "contains_unsupported", false);
        const int count = mode == 0 ? 2 : 1;
        GDExtensionPropertyInfo arguments[2];
        GDExtensionClassMethodArgumentMetadata metadata[2]{};
        for (int i = 0; i < count; ++i) {
            make_name(&argument_names[i], i == 0 ? "expected" : "actual", false);
            arguments[i] = {NIL, &argument_names[i], &empty_name, 0, &empty_string, 6};
        }
        GDExtensionPropertyInfo return_info{mode == 0 ? INT : BOOL, &empty_name, &empty_name, 0, &empty_string, 6};
        GDExtensionClassMethodInfo method{};
        method.name = &method_name;
        method.method_userdata = &exact_oracle_modes[mode];
        method.call_func = call_exact_oracle;
        method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
        method.has_return_value = true;
        method.return_value_info = &return_info;
        method.argument_count = count;
        method.arguments_info = arguments;
        method.arguments_metadata = metadata;
        register_method(library, &class_name, &method);
        for (int i = 0; i < count; ++i) destroy_name(&argument_names[i]);
        destroy_name(&method_name);
    }
    TextStorage method_name;
    make_name(&method_name, "advance_prefix", false);
    const GDExtensionVariantType types[] = {ARRAY, ARRAY, DICT, INT, INT, FLOAT, FLOAT};
    const char *names[] = {"rows", "moving", "rescues", "start", "end", "delta", "stun_recovery"};
    TextStorage arg_names[7];
    GDExtensionPropertyInfo arguments[7];
    GDExtensionClassMethodArgumentMetadata metadata[7]{};
    for (int i = 0; i < 7; ++i) {
        make_name(&arg_names[i], names[i], false);
        arguments[i] = {types[i], &arg_names[i], &empty_name, 0, &empty_string, 6};
    }
    GDExtensionPropertyInfo return_info{INT, &empty_name, &empty_name, 0, &empty_string, 6};
    GDExtensionClassMethodInfo method{};
    method.name = &method_name;
    method.call_func = call_advance;
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    method.has_return_value = true;
    method.return_value_info = &return_info;
    method.argument_count = 6;
    method.arguments_info = arguments;
    method.arguments_metadata = metadata;
    register_method(library, &class_name, &method);
    destroy_name(&method_name);
    make_name(&method_name, "advance_recovery_prefix", false);
    method.argument_count = 7;
    method.method_userdata = &recovery_marker;
    register_method(library, &class_name, &method);
    destroy_name(&method_name);
    make_name(&method_name, "fatigue_prefix", false);
    // Same synchronous boundary, with no work/supply/seconds calculation here.
    arguments[2].type = INT;
    destroy_name(&arg_names[2]); make_name(&arg_names[2], "start", false);
    destroy_name(&arg_names[3]); make_name(&arg_names[3], "end", false);
    method.argument_count = 4;
    method.method_userdata = &library; // Non-null mode marker, never person state.
    register_method(library, &class_name, &method);
    for (auto &name : arg_names) destroy_name(&name);
    destroy_name(&method_name);
    make_name(&method_name, "pack_instances", false);
    const GDExtensionVariantType pack_types[] = {ARRAY, INT, INT, VECTORS, INTS, INTS, INTS, FLOAT};
    const char *pack_text[] = {"members", "start", "stop", "positions", "sequences", "frames", "palettes", "scale"};
    TextStorage pack_names[8];
    GDExtensionPropertyInfo pack_args[8];
    GDExtensionClassMethodArgumentMetadata pack_meta[8]{};
    for (int i = 0; i < 8; ++i) {
        make_name(&pack_names[i], pack_text[i], false);
        pack_args[i] = {pack_types[i], &pack_names[i], &empty_name, 0, &empty_string, 6};
    }
    return_info.type = ARRAY;
    method.call_func = call_pack;
    method.method_userdata = nullptr;
    method.argument_count = 8;
    method.arguments_info = pack_args;
    method.arguments_metadata = pack_meta;
    register_method(library, &class_name, &method);
    for (auto &name : pack_names) destroy_name(&name);
    destroy_name(&method_name);
    make_name(&method_name, "group_render_rows", false);
    const GDExtensionVariantType group_types[] = {BYTES, INTS, ARRAY, ARRAY, INTS};
    const char *group_text[] = {"mask", "native_rows", "fallback_rows", "fallback_members", "pages"};
    TextStorage group_names[5];
    GDExtensionPropertyInfo group_args[5];
    GDExtensionClassMethodArgumentMetadata group_meta[5]{};
    for (int i = 0; i < 5; ++i) {
        make_name(&group_names[i], group_text[i], false);
        group_args[i] = {group_types[i], &group_names[i], &empty_name, 0, &empty_string, 6};
    }
    method.call_func = call_group_rows;
    method.argument_count = 5;
    method.arguments_info = group_args;
    method.arguments_metadata = group_meta;
    register_method(library, &class_name, &method);
    for (auto &name : group_names) destroy_name(&name);
    destroy_name(&method_name);
    make_name(&method_name, "render_idle", false);
    const GDExtensionVariantType render_types[] = {ARRAY, ARRAY, ARRAY, ARRAY, DICT, ARRAY, ARRAY, ARRAY, ARRAY, FLOAT};
    const char *render_names[] = {"rows", "cells", "moving", "facing", "publications", "previous", "descriptors", "samples", "sprites", "cell_pixels"};
    TextStorage render_arg_names[10];
    GDExtensionPropertyInfo render_arguments[10];
    GDExtensionClassMethodArgumentMetadata render_metadata[10]{};
    for (int i = 0; i < 10; ++i) {
        make_name(&render_arg_names[i], render_names[i], false);
        render_arguments[i] = {render_types[i], &render_arg_names[i], &empty_name, 0, &empty_string, 6};
    }
    return_info.type = ARRAY;
    method.call_func = call_render;
    method.method_userdata = nullptr;
    method.argument_count = 10;
    method.arguments_info = render_arguments;
    method.arguments_metadata = render_metadata;
    register_method(library, &class_name, &method);
    method.method_userdata = &hot_render_marker;
    register_method(library, &hot_class_name, &method);
    method.method_userdata = nullptr;
    for (auto &name : render_arg_names) destroy_name(&name);
    destroy_name(&method_name);
    make_name(&method_name, "encirclement_field", false);
    const char *field_names[] = {"enemies", "near", "size", "flags", "levels", "ramps", "blocked", "occupied", "limit", "reach"};
    const GDExtensionVariantType field_types[] = {ARRAY, BYTES, V2I, BYTES, BYTES, BYTES, BYTES, DICT, INT, INT};
    for (int i = 0; i < 10; ++i) {
        make_name(&render_arg_names[i], field_names[i], false);
        render_arguments[i] = {field_types[i], &render_arg_names[i], &empty_name, 0, &empty_string, 6};
    }
    method.call_func = call_encirclement_field;
    register_method(library, &class_name, &method);
    for (auto &name : render_arg_names) destroy_name(&name);
    destroy_name(&method_name);
    const char *capture_names[] = {"rows", "cells", "owner", "faction"};
    const GDExtensionVariantType capture_types[] = {ARRAY, ARRAY, GDEXTENSION_VARIANT_TYPE_OBJECT, INT};
    TextStorage capture_arg_names[4];
    GDExtensionPropertyInfo capture_arguments[4];
    GDExtensionClassMethodArgumentMetadata capture_metadata[4]{};
    for (int i = 0; i < 4; ++i) {
        make_name(&capture_arg_names[i], capture_names[i], false);
        capture_arguments[i] = {capture_types[i], &capture_arg_names[i], &empty_name, 0, &empty_string, 6};
    }
    method.call_func = call_capture;
    method.arguments_info = capture_arguments;
    method.arguments_metadata = capture_metadata;
    for (int mode = 0; mode < 2; ++mode) {
        make_name(&method_name, mode ? "capture_people" : "capture_columns", false);
        method.method_userdata = mode ? &library : nullptr;
        method.argument_count = mode ? 4 : 2;
        register_method(library, &class_name, &method);
        method.method_userdata = mode ? &hot_capture_people_marker : &hot_capture_columns_marker;
        register_method(library, &hot_class_name, &method);
        destroy_name(&method_name);
    }
    for (auto &name : capture_arg_names) destroy_name(&name);
    make_name(&method_name, "encirclement_front", false);
    const char *front_text[] = {"xs", "ys", "factions", "owner_slots", "owner", "faction"};
    const GDExtensionVariantType front_types[] = {INTS, INTS, LONGS, INTS, INT, INT};
    TextStorage front_names[6];
    GDExtensionPropertyInfo front_args[6];
    GDExtensionClassMethodArgumentMetadata front_meta[6]{};
    for (int i = 0; i < 6; ++i) {
        make_name(&front_names[i], front_text[i], false);
        front_args[i] = {front_types[i], &front_names[i], &empty_name, 0, &empty_string, 6};
    }
    method.call_func = call_encirclement;
    method.method_userdata = nullptr;
    method.argument_count = 6;
    method.arguments_info = front_args;
    method.arguments_metadata = front_meta;
    register_method(library, &class_name, &method);
    for (auto &name : front_names) destroy_name(&name);
    destroy_name(&method_name);
    make_name(&method_name, "empty_cargo_prefix", false);
    const char *cargo_text[] = {"rows", "units", "owner_slots", "start"};
    const GDExtensionVariantType cargo_types[] = {ARRAY, INTS, INTS, INT};
    for (int i = 0; i < 4; ++i) {
        make_name(&capture_arg_names[i], cargo_text[i], false);
        capture_arguments[i] = {cargo_types[i], &capture_arg_names[i], &empty_name, 0, &empty_string, 6};
    }
    return_info.type = INT;
    method.call_func = call_empty_cargo;
    method.method_userdata = nullptr;
    method.argument_count = 4;
    method.arguments_info = capture_arguments;
    method.arguments_metadata = capture_metadata;
    register_method(library, &class_name, &method);
    for (auto &name : capture_arg_names) destroy_name(&name);
    destroy_name(&method_name);
    make_name(&method_name, "near_front", false);
    TextStorage near_names[3];
    const char *near_text[] = {"enemies", "contacts", "radius"};
    GDExtensionPropertyInfo near_args[3];
    GDExtensionClassMethodArgumentMetadata near_meta[3]{};
    for (int i = 0; i < 3; ++i) {
        make_name(&near_names[i], near_text[i], false);
        near_args[i] = {i == 2 ? INT : ARRAY, &near_names[i], &empty_name, 0, &empty_string, 6};
    }
    return_info.type = BYTES;
    method.call_func = call_near_front;
    method.method_userdata = nullptr;
    method.argument_count = 3;
    method.arguments_info = near_args;
    method.arguments_metadata = near_meta;
    register_method(library, &class_name, &method);
    for (auto &name : near_names) destroy_name(&name);
    destroy_name(&method_name);
    make_name(&method_name, "command_presence", false);
    const char *presence_text[] = {"rows", "cells", "moving_positions"};
    for (int i = 0; i < 3; ++i) {
        make_name(&near_names[i], presence_text[i], false);
        near_args[i] = {i == 2 ? DICT : ARRAY, &near_names[i], &empty_name, 0, &empty_string, 6};
    }
    return_info.type = ARRAY;
    method.call_func = call_presence;
    register_method(library, &class_name, &method);
    method.method_userdata = &hot_presence_marker;
    register_method(library, &hot_class_name, &method);
    method.method_userdata = nullptr;
    for (auto &name : near_names) destroy_name(&name);
    destroy_name(&method_name);
    make_name(&method_name, "command_presence_delta", false);
    const char *delta_text[] = {"rows", "cells", "moving_positions", "radius", "cache"};
    const GDExtensionVariantType delta_types[] = {ARRAY, ARRAY, DICT, FLOAT, ARRAY};
    TextStorage delta_names[5];
    GDExtensionPropertyInfo delta_args[5];
    GDExtensionClassMethodArgumentMetadata delta_meta[5]{};
    for (int i = 0; i < 5; ++i) {
        make_name(&delta_names[i], delta_text[i], false);
        delta_args[i] = {delta_types[i], &delta_names[i], &empty_name, 0, &empty_string, 6};
    }
    method.call_func = call_presence_delta;
    method.argument_count = 5;
    method.arguments_info = delta_args;
    method.arguments_metadata = delta_meta;
    register_method(library, &class_name, &method);
    method.method_userdata = &hot_presence_delta_marker;
    register_method(library, &hot_class_name, &method);
    for (auto &name : delta_names) destroy_name(&name);
    destroy_name(&method_name);
}
void deinitialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    unregister_class(library, &hot_class_name);
    unregister_class(library, &class_name);
    for (auto &key : keys) destroy(&key);
    for (auto &key : lookup_keys) destroy(&key);
    destroy_string(&idle_string);
    destroy_string(&unconscious_string);
    destroy_string(&down_string);
    destroy_string(&guard_raise_string);
    destroy_string(&guard_lower_string);
    destroy_string(&guard_break_string);
    destroy_string(&rescue_string);
    destroy_string(&male_string);
    destroy_string(&female_string);
    destroy_string(&get_up_string);
    destroy_string(&empty_string);
    destroy_name(&typed_builtin_method_name);
    destroy_name(&typed_class_method_name);
    destroy_name(&typed_script_method_name);
    destroy_name(&keys_method_name);
    destroy_name(&empty_name);
    destroy_name(&parent_name);
    destroy_name(&hot_class_name);
    destroy_name(&class_name);
}
} // namespace

extern "C" __declspec(dllexport) GDExtensionBool army_idle_init(GDExtensionInterfaceGetProcAddress get, GDExtensionClassLibraryPtr lib, GDExtensionInitialization *init) {
    library = lib;
#define LOAD(variable, api_type, name) variable = reinterpret_cast<api_type>(get(name)); if (!variable) return false
    LOAD(type_of, GDExtensionInterfaceVariantGetType, "variant_get_type");
    LOAD(destroy, GDExtensionInterfaceVariantDestroy, "variant_destroy");
    LOAD(copy_variant, GDExtensionInterfaceVariantNewCopy, "variant_new_copy");
    LOAD(get_keyed, GDExtensionInterfaceVariantGetKeyed, "variant_get_keyed");
    LOAD(variant_call, GDExtensionInterfaceVariantCall, "variant_call");
    LOAD(variant_hash, GDExtensionInterfaceVariantHash, "variant_hash");
    LOAD(object_instance_id, GDExtensionInterfaceVariantGetObjectInstanceId, "variant_get_object_instance_id");
    LOAD(array_at, GDExtensionInterfaceArrayOperatorIndexConst, "array_operator_index_const");
    LOAD(array_write, GDExtensionInterfaceArrayOperatorIndex, "array_operator_index");
    LOAD(variant_construct, GDExtensionInterfaceVariantConstruct, "variant_construct");
    LOAD(bytes_read, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
    LOAD(bytes_write, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
    LOAD(ints_read, GDExtensionInterfacePackedInt32ArrayOperatorIndexConst, "packed_int32_array_operator_index_const");
    LOAD(floats_write, GDExtensionInterfacePackedFloat32ArrayOperatorIndex, "packed_float32_array_operator_index");
    LOAD(ints_write, GDExtensionInterfacePackedInt32ArrayOperatorIndex, "packed_int32_array_operator_index");
    LOAD(longs_write, GDExtensionInterfacePackedInt64ArrayOperatorIndex, "packed_int64_array_operator_index");
    LOAD(longs_read, GDExtensionInterfacePackedInt64ArrayOperatorIndexConst, "packed_int64_array_operator_index_const");
    LOAD(vectors_write, GDExtensionInterfacePackedVector2ArrayOperatorIndex, "packed_vector2_array_operator_index");
    LOAD(vectors_read, GDExtensionInterfacePackedVector2ArrayOperatorIndexConst, "packed_vector2_array_operator_index_const");
    LOAD(doubles_read, GDExtensionInterfacePackedFloat64ArrayOperatorIndexConst, "packed_float64_array_operator_index_const");
    LOAD(doubles_write, GDExtensionInterfacePackedFloat64ArrayOperatorIndex, "packed_float64_array_operator_index");
    LOAD(dict_at, GDExtensionInterfaceDictionaryOperatorIndexConst, "dictionary_operator_index_const");
    LOAD(dict_write, GDExtensionInterfaceDictionaryOperatorIndex, "dictionary_operator_index");
    LOAD(construct_object, GDExtensionInterfaceClassdbConstructObject2, "classdb_construct_object2");
    LOAD(set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
    LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass4, "classdb_register_extension_class4");
    LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
    LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
    LOAD(add_group_task, GDExtensionInterfaceWorkerThreadPoolAddNativeGroupTask, "worker_thread_pool_add_native_group_task");
    LOAD(method_ptrcall, GDExtensionInterfaceObjectMethodBindPtrcall, "object_method_bind_ptrcall");
    LOAD(get_singleton, GDExtensionInterfaceGlobalGetSingleton, "global_get_singleton");
    LOAD(get_method_bind, GDExtensionInterfaceClassdbGetMethodBind, "classdb_get_method_bind");
    LOAD(make_name, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
    LOAD(make_string, GDExtensionInterfaceStringNewWithLatin1Chars, "string_new_with_latin1_chars");
    GDExtensionInterfaceGetVariantGetInternalPtrFunc get_internal;
    GDExtensionInterfaceGetVariantFromTypeConstructor get_constructor;
    GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
    GDExtensionInterfaceVariantGetPtrBuiltinMethod get_method;
    GDExtensionInterfaceVariantGetPtrOperatorEvaluator get_operator;
    GDExtensionInterfaceVariantGetPtrUtilityFunction get_utility;
    LOAD(get_internal, GDExtensionInterfaceGetVariantGetInternalPtrFunc, "variant_get_ptr_internal_getter");
    LOAD(get_constructor, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
    LOAD(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
    LOAD(get_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");
    LOAD(get_operator, GDExtensionInterfaceVariantGetPtrOperatorEvaluator, "variant_get_ptr_operator_evaluator");
    LOAD(get_utility, GDExtensionInterfaceVariantGetPtrUtilityFunction, "variant_get_ptr_utility_function");
#undef LOAD
    for (auto type : {ARRAY, DICT, FLOAT, INT, STRING, NAME, V2I, V2, BOOL, BYTES, INTS, LONGS, VECTORS, DOUBLES, FLOATS}) {
        internal[type] = get_internal(type);
        if (!internal[type]) return false;
    }
    from_float = get_constructor(FLOAT); from_int = get_constructor(INT); from_string = get_constructor(STRING); from_name = get_constructor(NAME);
    from_v2i = get_constructor(V2I); from_bool = get_constructor(BOOL);
    if (!from_v2i || !from_bool) return false;
    destroy_string = get_destructor(STRING); destroy_name = get_destructor(NAME);
    auto builtin = [&](GDExtensionVariantType type, const char *name, int64_t hash) {
        TextStorage method;
        make_name(&method, name, false);
        auto function = get_method(type, &method, hash);
        destroy_name(&method);
        return function;
    };
    array_size = builtin(ARRAY, "size", 3173160232);
    array_readonly = builtin(ARRAY, "is_read_only", 3918633141);
    array_typed = builtin(ARRAY, "is_typed", 3918633141);
    vector_distance = builtin(V2, "distance_to", 3819070308);
    vector_squared_distance = builtin(V2, "distance_squared_to", 3819070308);
    if (!vector_distance || !vector_squared_distance) return false;
    size_longs = builtin(LONGS, "size", 3173160232);
    if (!size_longs) return false;
    dict_has = builtin(DICT, "has", 3680194679);
    dict_size = builtin(DICT, "size", 3173160232);
    dict_empty = builtin(DICT, "is_empty", 3918633141);
    dict_readonly = builtin(DICT, "is_read_only", 3918633141);
    dict_typed = builtin(DICT, "is_typed", 3918633141);
    resize_array = builtin(ARRAY, "resize", 848867239);
    resize_bytes = builtin(BYTES, "resize", 848867239);
    resize_ints = builtin(INTS, "resize", 848867239);
    resize_longs = builtin(LONGS, "resize", 848867239);
    resize_floats = builtin(FLOATS, "resize", 848867239);
    size_ints = builtin(INTS, "size", 3173160232);
    size_bytes = builtin(BYTES, "size", 3173160232);
    if (!resize_floats || !size_ints || !size_bytes) return false;
    resize_doubles = builtin(DOUBLES, "resize", 848867239);
    if (!resize_doubles) return false;
    resize_vectors = builtin(VECTORS, "resize", 848867239);
    size_vectors = builtin(VECTORS, "size", 3173160232);
    size_doubles = builtin(DOUBLES, "size", 3173160232);
    TextStorage same_name;
    make_name(&same_name, "is_same", false);
    same_variant = get_utility(&same_name, 1409423524);
    destroy_name(&same_name);
    string_equal = get_operator(GDEXTENSION_VARIANT_OP_EQUAL, STRING, STRING);
    name_equal = get_operator(GDEXTENSION_VARIANT_OP_EQUAL, NAME, NAME);
    if (!from_float || !from_int || !from_string || !from_name || !destroy_string || !destroy_name || !array_size || !array_readonly || !array_typed || !dict_size || !dict_has || !dict_empty || !dict_readonly || !dict_typed || !string_equal || !name_equal) return false;
    if (!resize_array || !resize_bytes || !resize_ints || !resize_longs || !resize_vectors || !size_vectors || !size_doubles || !same_variant) return false;
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->userdata = nullptr;
    init->initialize = initialize;
    init->deinitialize = deinitialize;
    return true;
}
