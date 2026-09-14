class_name HumanCharacter3DEditor
extends CanvasLayer

const RIGHT_HAND_BONE := "J_Bip_R_Hand"
const JUMP_HEAVY_VERTICAL_SCALE := 0.55
signal closed

const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"
const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const COMBAT_PROPS_PATH := "res://assets/characters/human/q35/combat/combat_props.glb"
const CombatTimings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
var combat_props: Node3D
var combat_ammo_count := 3
var combat_ammo_available := true
var lazy_combat_visual_bones_enabled := true # A/B false keeps full-force; native getters update required bone chains.
var _rigid_scabbards: Array[Dictionary] = []
var _combat_cloth: Array[Dictionary] = []
const HAIR_OPTIONS := [
	[
		{"id": &"hair_male_01", "label": "男 01 / 層次短髮", "prefixes": ["Hair_Short_01"]},
		{"id": &"hair_male_02", "label": "男 02 / 側分短髮", "prefixes": ["Hair_Short_02"]},
		{"id": &"hair_male_03", "label": "男 03 / 狂野狼尾", "prefixes": ["Hair_Short_03"]},
		{"id": &"hair_male_04", "label": "男 04 / 戰士束髮", "prefixes": ["Hair_Short_04"]},
		{"id": &"hair_male_05", "label": "男 05 / 中分簾髮", "prefixes": ["Hair_Male_05"]},
		{"id": &"hair_male_06", "label": "男 06 / 後梳背頭", "prefixes": ["Hair_Male_06"]},
		{"id": &"hair_male_07", "label": "男 07 / 低束編辮", "prefixes": ["Hair_Male_07"]},
		{"id": &"hair_male_08", "label": "男 08 / 清爽短寸", "prefixes": ["Hair_Male_08"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	],
	[
		{"id": &"hair_female_01", "label": "女 01 / 雙馬尾", "prefixes": ["Hair_Long_01"]},
		{"id": &"hair_female_02", "label": "女 02 / 垂肩長髮", "prefixes": ["Hair_Long_02"]},
		{"id": &"hair_female_03", "label": "女 03 / 俐落短髮", "prefixes": ["Hair_Long_03", "Hair_Female_03"]},
		{"id": &"hair_female_04", "label": "女 04 / 戰鬥高馬尾", "prefixes": ["Hair_Long_04", "Hair_Female_04"]},
		{"id": &"hair_female_05", "label": "女 05 / 精靈短髮", "prefixes": ["Hair_Female_05"]},
		{"id": &"hair_female_06", "label": "女 06 / 雙丸子髮", "prefixes": ["Hair_Female_06"]},
		{"id": &"hair_female_07", "label": "女 07 / 側垂編辮", "prefixes": ["Hair_Female_07"]},
		{"id": &"hair_female_08", "label": "女 08 / 半束波浪", "prefixes": ["Hair_Female_08"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	],
]
const PART_SLOTS := [
	{
		"id": &"face",
		"label": "Face / 五官",
		"options": [
			{"id": &"face_standard_01", "label": "Face 01 / 目前版本", "prefixes": ["Face_Standard_01"]},
			{"id": &"face_standard_02", "label": "Face 02 / 第二套", "prefixes": ["Face_Standard_02"]},
			{"id": &"face_standard_03", "label": "Face 03 / 銳利戰鬥 (男) · 高冷貓眼 (女)", "prefixes": ["Face_Standard_03"]},
			{"id": &"face_standard_04", "label": "Face 04 / 開朗微笑 (男) · 溫柔元氣 (女)", "prefixes": ["Face_Standard_04"]},
			{"id": &"none", "label": "None / 無", "prefixes": []},
		],
	},
	{"id": &"hair", "label": "Hair / 頭髮", "options": []},
	{"id": &"helmet", "label": "Helmet / 頭盔", "options": [
		{"id": &"helmet_leather_01", "label": "Leather Helmet 01 / 皮革頭盔", "prefixes": ["Helmet_Leather_01"]},
		{"id": &"helmet_iron_01", "label": "Chinese Iron Helmet 01 / 中國風鐵盔", "prefixes": ["Helmet_Iron_01"]},
		{"id": &"helmet_steel_01", "label": "Chinese Steel Helmet 01 / 中國風鋼盔", "prefixes": ["Helmet_Steel_01"]},
		{"id": &"helmet_mingguang_01", "label": "Mingguang Helmet 01 / 明光盔", "prefixes": ["Helmet_Mingguang_01"]},
		{"id": &"helmet_chinese_leather_01", "label": "Chinese Leather Helmet 01 / 中式皮盔", "prefixes": ["Helmet_Chinese_Leather_01"]},
		{"id": &"helmet_western_iron_01", "label": "Western Iron Helmet 01 / 西式鐵盔", "prefixes": ["Helmet_Western_Iron_01"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	]},
	{"id": &"outfit", "label": "Outfit / 內衣", "options": [
		{"id": &"outfit_underlayer_01", "label": "Outfit 01 / 內衣", "prefixes": ["Outfit_Underlayer_01"]},
		{"id": &"outfit_chinese_lining_01", "label": "Chinese Lining 01 / 甲內襯衣", "prefixes": ["Outfit_Chinese_Lining_01"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	]},
	{"id": &"armor", "label": "Armor / 護甲", "options": [
		{"id": &"armor_light_leather_01", "label": "Light Armor 01 / 皮革輕甲", "prefixes": ["Armor_Light_Leather_01"]},
		{"id": &"armor_iron_01", "label": "Chinese Iron Armor 01 / 中式鐵甲", "prefixes": ["Armor_Iron_01"]},
		{"id": &"armor_mingguang_01", "label": "Mingguang Armor 01 / 明光鎧", "prefixes": ["Armor_Mingguang_01"]},
		{"id": &"armor_chinese_leather_01", "label": "Chinese Leather Armor 01 / 中式皮甲", "prefixes": ["Armor_Chinese_Leather_01"]},
		{"id": &"armor_western_iron_01", "label": "Western Iron Armor 01 / 西式鐵甲", "prefixes": ["Armor_Western_Iron_01"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	]},
	{"id": &"cape", "label": "Cape / 披風", "options": [
		{"id": &"cape_travel_01", "label": "Cape 01 / 旅行披風", "prefixes": ["Cape_Travel_01"]},
		{"id": &"cape_chinese_01", "label": "Chinese Cloak 01 / 中式披風", "prefixes": ["Cape_Chinese_01"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	]},
	{"id": &"weapon", "label": "Weapon / 武器", "options": [
		{"id": &"longsword_01", "label": "Longsword 01 / 長劍", "prefixes": ["Weapon_Longsword_01"]},
		{"id": &"spear_01", "label": "Spear 01 / 長槍", "prefixes": ["Weapon_Spear_01"]},
		{"id": &"axe_01", "label": "Axe 01 / 戰斧", "prefixes": ["Weapon_Axe_01"]},
		{"id": &"wood_axe_01", "label": "Wood Axe 01 / 伐木斧", "prefixes": ["Weapon_WoodAxe_01"]},
		{"id": &"hammer_01", "label": "Hammer 01 / 戰鎚", "prefixes": ["Weapon_Hammer_01"]},
		{"id": &"dagger_01", "label": "Dagger 01 / 匕首", "prefixes": ["Weapon_Dagger_01"]},
		{"id": &"bow_01", "label": "Bow 01 / 長弓", "prefixes": ["Weapon_Bow_01"]},
		{"id": &"crossbow_01", "label": "Crossbow 01 / 十字弩", "prefixes": ["Weapon_Crossbow_01"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	]},
	{"id": &"shield", "label": "Shield / 盾牌", "options": [
		{"id": &"shield_heater_01", "label": "Shield 01 / 加熱盾", "prefixes": ["Shield_Heater_01"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	]},
	{"id": &"boots", "label": "Boots / 鞋靴", "options": [
		{"id": &"boots_leather_01", "label": "Boots 01 / 皮靴", "prefixes": ["Boots_Leather_01"]},
		{"id": &"boots_chinese_leather_01", "label": "Chinese Leather Boots 01 / 中式皮靴", "prefixes": ["Boots_Chinese_Leather_01"]},
		{"id": &"boots_iron_01", "label": "Chinese Iron Boots 01 / 中式鐵靴", "prefixes": ["Boots_Iron_01"]},
		{"id": &"boots_mingguang_01", "label": "Mingguang War Boots 01 / 明光鎧戰靴", "prefixes": ["Boots_Mingguang_01"]},
		{"id": &"boots_western_iron_01", "label": "Western Iron Boots 01 / 西式鐵靴", "prefixes": ["Boots_Western_Iron_01"]},
		{"id": &"none", "label": "None / 無", "prefixes": []},
	]},
]
const ANIMATION_SLOTS := [
	{"id": &"T-Pose", "label": "T-Pose / 基準姿勢", "state": "connected"},
	{"id": &"idle", "label": "Idle / 待機", "state": "connected"},
	{"id": &"walk", "label": "Walk / 走路", "state": "connected"},
	{"id": &"run", "label": "Run / 跑步", "state": "connected"},
	{"id": &"guard", "label": "Guard / 防禦", "state": "connected"},
	{"id": &"guard_raise", "label": "Raise Guard / 舉盾", "state": "connected"},
	{"id": &"guard_lower", "label": "Lower Guard / 放盾", "state": "connected"},
	{"id": &"guard_break", "label": "Guard Break / 破防", "state": "connected"},
	{"id": &"guard_weapon", "label": "Weapon Guard / 無盾持武器防禦", "state": "connected"},
	{"id": &"guard_weapon_raise", "label": "Weapon Guard Raise / 持武器進入防禦", "state": "connected"},
	{"id": &"guard_weapon_lower", "label": "Weapon Guard Lower / 持武器解除防禦", "state": "connected"},
	{"id": &"guard_weapon_break", "label": "Weapon Guard Break / 持武器破防", "state": "connected"},
	{"id": &"guard_polearm", "label": "Polearm Guard / 無盾長槍防禦", "state": "connected"},
	{"id": &"guard_polearm_raise", "label": "Polearm Guard Raise / 長槍進入防禦", "state": "connected"},
	{"id": &"guard_polearm_lower", "label": "Polearm Guard Lower / 長槍解除防禦", "state": "connected"},
	{"id": &"guard_polearm_break", "label": "Polearm Guard Break / 長槍破防", "state": "connected"},
	{"id": &"unconscious", "label": "Unconscious / 昏迷維持", "state": "connected"},
	{"id": &"get_up", "label": "Get Up / 起身", "state": "connected"},
	{"id": &"rescue", "label": "Rescue / 現場救助", "state": "connected"},
	{"id": &"reload_bow", "label": "Nock Arrow / 取箭搭弦", "state": "connected"},
	{"id": &"reload_crossbow", "label": "Reload Crossbow / 裝填弩矢", "state": "connected"},
	{"id": &"hit", "label": "Hit / 受擊 (正面)", "state": "connected"},
	{"id": &"hit_back", "label": "Hit Back / 背後受擊", "state": "connected"},
	{"id": &"knockback", "label": "Knockback / 擊退", "state": "connected"},
	{"id": &"down", "label": "Down / 倒地", "state": "connected"},
	{"id": &"attack", "label": "Attack / 攻擊 (依武器匹配)", "state": "connected"},
	{"id": &"attack_unarmed", "label": "Attack (Kick) / 踢擊", "state": "connected"},
	{"id": &"attack_jump_heavy", "label": "Jump Heavy Attack (All Weapons) / 跳躍重擊（全武器通用）", "state": "connected"},
	{"id": &"attack_spear", "label": "Attack (Spear) / 槍刺", "state": "connected"},
	{"id": &"attack_axe", "label": "Attack (Axe) / 斧劈", "state": "connected"},
	{"id": &"attack_hammer", "label": "Attack (Hammer) / 鎚砸", "state": "connected"},
	{"id": &"attack_dagger", "label": "Attack (Dagger) / 匕首連刺", "state": "connected"},
	{"id": &"attack_bow", "label": "Attack (Bow) / 弓射", "state": "connected"},
	{"id": &"attack_crossbow", "label": "Attack (Crossbow) / 弩射", "state": "connected"},
	{"id": &"ride_idle", "label": "Ride Idle / 騎馬待機", "state": "connected"},
	{"id": &"ride_walk", "label": "Ride Walk / 騎馬慢步", "state": "connected"},
	{"id": &"ride_run", "label": "Ride Run / 跑馬奔馳", "state": "connected"},
	{"id": &"ride_slash", "label": "Ride Slash / 馬上揮劍", "state": "connected"},
	{"id": &"ride_thrust", "label": "Ride Thrust / 馬上刺長槍", "state": "connected"},
	{"id": &"walk_slash", "label": "Walk Slash / 步行揮劍", "state": "connected"},
]
const WEAPON_ATTACK_MAP := {
	&"longsword_01": &"walk_slash",
	&"spear_01": &"attack_spear",
	&"axe_01": &"attack_axe",
	&"wood_axe_01": &"attack_axe",
	&"hammer_01": &"attack_hammer",
	&"dagger_01": &"attack_dagger",
	&"bow_01": &"attack_bow",
	&"crossbow_01": &"attack_crossbow",
	&"none": &"attack_unarmed",
}
const WEAPON_ATTACK_ANIMATIONS := [
	&"walk_slash", &"attack_spear", &"attack_axe", &"attack_hammer",
	&"attack_dagger", &"attack_bow", &"attack_crossbow", &"attack_unarmed",
]
const BODY_MODELS := [
	{"id": &"male_standard_anime", "label": "Male / 標準動漫男（全套模組化裝備）", "path": MALE_MODEL_PATH},
	{"id": &"female_standard_anime", "label": "Female / 標準動漫女（全套模組化裝備）", "path": FEMALE_MODEL_PATH},
]
const EQUIPMENT_PREFIXES := [
	"Armor_Western_Iron_01", "Helmet_Western_Iron_01", "Boots_Western_Iron_01",
	"Armor_Chinese_Leather_01", "Helmet_Mingguang_01",
	"Helmet_Chinese_Leather_01", "Outfit_Chinese_Lining_01",
	"Outfit_Underlayer_01", "Armor_Light_Leather_01", "Armor_Iron_01", "Armor_Mingguang_01", "Cape_Travel_01", "Cape_Chinese_01", "Helmet_Leather_01", "Helmet_Iron_01", "Helmet_Steel_01",
	"Weapon_Longsword_01", "Weapon_Spear_01", "Weapon_Axe_01", "Weapon_WoodAxe_01", "Weapon_Hammer_01",
	"Weapon_Dagger_01", "Weapon_Bow_01", "Weapon_Crossbow_01",
	"Shield_Heater_01", "Boots_Leather_01", "Boots_Iron_01", "Boots_Mingguang_01", "Boots_Chinese_Leather_01",
]
const OUTLINE_DETAIL_EXCLUSIONS := [
	"_Buckle", "_Flap", "_FrontSeam", "_BeltTopEdge", "_Rivet", "_Strap", "_KneePad", "_Rosette", "_Emblem",
	"_BeastEmblem", "_Finial", "_Plume", "_Lining", "_SideMedallions", "_CordTassels",
	"_ChestEmblem", "_ChestMotif", "_ShinEmblem", "_Pauldron_Beast", "_Tassels", "_BeltTassels", "_BeltBuckle",
	"_Buckles", "_Instep", "_ToeCap", "_Heel",
]
const EQUIPMENT_OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.012, 0.008, 0.006, 1.0);
uniform float outline_width = 0.0012;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
"""
const EQUIPMENT_TOON_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.7, 0.3, 0.1, 1.0);
uniform float base_metallic = 0.0;
uniform float base_roughness = 0.8;

void fragment() {
	ALBEDO = base_color.rgb;
	EMISSION = base_color.rgb * 0.035;
	METALLIC = base_metallic;
	ROUGHNESS = base_roughness;
}
"""

const HAIR_CLIP_MASK_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 dye_color : source_color = vec4(1.0);
uniform bool dye_enabled = false;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform bool mask_enabled = false;
uniform mat4 inv_head_transform = mat4(1.0);
uniform float brow_cut_y = 0.113;
uniform vec2 scalp_radii = vec2(0.113, 0.130);
uniform bool tuck_hair_piece = false;

void fragment() {
	if (mask_enabled) {
		if (tuck_hair_piece) { discard; }
		vec4 world_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
		vec4 head_local = inv_head_transform * world_pos;
		bool keep_bangs = head_local.z >= 0.045 && abs(head_local.x) <= 0.060
			&& head_local.y <= brow_cut_y && head_local.y >= -0.060;
		// Hair INSIDE the crown is still needed behind openings and at the nape.
		// Only trim the outer volume and long ends, not the entire rear scalp.
		// ponytail: fitted to current closed helmets; new open hats need their own envelope.
		float nape_taper = mix(0.80, 1.0, smoothstep(-0.025, 0.040, head_local.y));
		vec2 radial = (head_local.xz - vec2(0.0, 0.003)) / (scalp_radii * nape_taper);
		float strand_edge = 0.004 * sin(atan(head_local.x, -head_local.z) * 29.0);
		float hairline = -0.020 + 0.028 * pow(abs(head_local.x) / scalp_radii.x, 2.0) + strand_edge;
		bool keep_scalp = head_local.z <= -0.025
			&& head_local.y >= hairline && head_local.y <= brow_cut_y
			&& dot(radial, radial) <= 1.0;
		if (!keep_bangs && !keep_scalp) {
			discard;
		}
	}

	vec4 color = base_color;
	if (has_texture) {
		color *= texture(albedo_texture, UV);
		// Compress baked bright streaks without altering the source texture.
		float peak = max(max(color.r, color.g), color.b);
		color.rgb /= 1.0 + max(peak - 0.06, 0.0) * 7.0;
	}
	if (dye_enabled) {
		// Preserve authored lock shading, replacing hue even on dark source hair.
		float shade = clamp(sqrt(max(max(color.r, color.g), color.b)) * 2.0, 0.48, 1.0);
		color.rgb = dye_color.rgb * shade;
	}
	ALBEDO = color.rgb;
	ROUGHNESS = 0.78;
	SPECULAR = 0.18;
	EMISSION = color.rgb * 0.035;
}
"""


var editor_root: Control
var preview_viewport: SubViewport
## Optional host for sharing the live character with a 2D map.
var preview_host: Node
var use_imported_model := false # Fixed runtime query only; authoring keeps raw GLB reloads.
var visual_state: CharacterVisualState = CharacterVisualState.new()
var combat_ready: bool = false
var preview_container: SubViewportContainer
var preview_clip: Control
var preview_texture: TextureRect
var preview_zoom_label: Label
var preview_zoom_out_button: Button
var preview_zoom_in_button: Button
var preview_reset_view_button: Button
var preview_world: Node3D
var preview_pivot: Node3D
var model_root: Node3D
var animation_player: AnimationPlayer
var camera: Camera3D

var body_option: OptionButton
var hair_mask_option: OptionButton
var hair_dye_button: ColorPickerButton
var hair_dye_label: Label
var _hair_dye_color := Color("9b775d")
var _hair_dye_enabled: bool = false
var _hair_selections: Array[StringName] = [&"hair_male_01", &"hair_female_01"]
var animation_option: OptionButton
var play_button: Button
var reset_button: Button
var loop_toggle: CheckBox
var speed_slider: HSlider
var speed_value_label: Label
var timeline_slider: HSlider
var timeline_label: Label
var status_label: Label
var model_label: Label
var animation_state_label: Label
var parts_footer: Label
var part_options: Dictionary = {}
var part_selection_request: Callable # Optional gameplay UI authority; returns the currently permitted asset.
var body_selection_request: Callable # Optional gameplay UI authority; returns the original body index.

var mount_horse: MountHorse3D
var mount_toggle: CheckBox
var mount_coat_option: OptionButton
var mount_tack_toggle: CheckBox
var _is_mounted: bool = false
var _current_mount_coat: StringName = &"bay"
var _mount_tack_enabled: bool = true
const MOUNT_RIDER_OFFSET := Vector3.ZERO
const MOUNT_SEAT_CLEARANCE := 0.06
const MOUNT_RIDER_HIP_BONES: Array[StringName] = [
	&"J_Bip_C_Hips",
	&"J_Bip_C_Pelvis",
	&"J_Bip_C_Root",
]

var _body_index: int = 0
var _hair_mask_mode: StringName = &"auto"
var _selected_animation: StringName = &"walk"
var _is_playing: bool = true
var _available_animation_ids: Dictionary = {}
var _initialized: bool = false
var _preview_yaw: float = 0.0
var _preview_pitch: float = 0.0
var exact_preview_rotation_guard_enabled := true # Exact actual pivot state; false retains every original setter.
var _dragging_preview: bool = false
var _panning_preview: bool = false
var _preview_zoom: float = 1.0
var _preview_pan := Vector2.ZERO
var _ui_font_scale: float = 1.0
const PREVIEW_MIN_ZOOM := 0.5
const PREVIEW_MAX_ZOOM := 4.0
const PREVIEW_ZOOM_STEP := 1.1
var _equipment_outline_material: ShaderMaterial
var _equipment_toon_shader: Shader
var _hair_mask_shader: Shader
var hair_node_lookup_cache_enabled := true # Same-editor A/B; only the current root/hair node list.
var hair_node_lookup_profile_enabled := false
var hair_node_lookup_profile := {"calls": 0, "hits": 0, "searches": 0, "lookup_usec": 0}
var _hair_nodes_model_id := 0
var _hair_nodes_id: StringName = &""
var _hair_nodes: Array[MeshInstance3D] = []

func _ready() -> void:
	_build_ui()
	hide()
	call_deferred("_open_when_run_as_scene")

func _open_when_run_as_scene() -> void:
	if get_tree().current_scene == self:
		open()

func open() -> void:
	show()
	if not _initialized:
		_initialize_preview()
	_initialized = true
	_set_playing(true)

func close() -> void:
	if not visible:
		return
	_dragging_preview = false
	_panning_preview = false
	_set_playing(false)
	hide()
	closed.emit()

var selected_animation: StringName:
	get:
		return _selected_animation

var is_mounted: bool:
	get:
		return _is_mounted

func is_open() -> bool:
	return visible

func _normalize_animation_id(animation_id: StringName) -> StringName:
	if animation_id in [&"attack_kick", &"kick"]:
		return &"attack_unarmed"
	if animation_id == &"attack_sword":
		return &"walk_slash"
	if animation_id in [&"guard", &"guard_raise", &"guard_lower", &"guard_break"]:
		var shield := part_options.get(&"shield") as OptionButton
		var weapon := _selected_weapon_id()
		if shield != null and shield.selected >= 0 and str(shield.get_item_metadata(shield.selected)) == "none" and weapon in [&"longsword_01", &"spear_01", &"axe_01", &"wood_axe_01", &"hammer_01", &"dagger_01"]:
			return StringName(("guard_polearm" if weapon == &"spear_01" else "guard_weapon") + str(animation_id).trim_prefix("guard"))
	return animation_id

func _selected_weapon_id() -> StringName:
	var option := part_options.get(&"weapon") as OptionButton
	if option == null or option.selected < 0:
		return &"none"
	return StringName(str(option.get_item_metadata(option.selected)))

func _resolve_weapon_attack_animation() -> StringName:
	var weapon_id := _selected_weapon_id()
	if _is_mounted:
		if weapon_id == &"spear_01" and bool(_available_animation_ids.get(&"ride_thrust", false)):
			return &"ride_thrust"
		if bool(_available_animation_ids.get(&"ride_slash", false)):
			return &"ride_slash"
		return &"ride_attack"
	return StringName(str(WEAPON_ATTACK_MAP.get(weapon_id, &"attack_unarmed")))

func _has_available_weapon_attack() -> bool:
	if animation_player == null:
		return false
	for animation_id: StringName in WEAPON_ATTACK_ANIMATIONS:
		if animation_player.has_animation(animation_id):
			return true
	return false

func _is_weapon_attack_animation(animation_id: StringName) -> bool:
	return WEAPON_ATTACK_ANIMATIONS.has(animation_id)

func select_animation_by_id(animation_id: StringName) -> bool:
	var target_id := _normalize_animation_id(animation_id)
	var is_weapon_attack_entry := target_id == &"attack"
	if is_weapon_attack_entry:
		target_id = _resolve_weapon_attack_animation()
	elif target_id == &"ride_attack" and not bool(_available_animation_ids.get(&"ride_attack", false)) and bool(_available_animation_ids.get(&"ride_slash", false)):
		target_id = &"ride_slash"
	elif target_id == &"ride_slash" and not bool(_available_animation_ids.get(&"ride_slash", false)) and bool(_available_animation_ids.get(&"ride_attack", false)):
		target_id = &"ride_attack"
	var index: int = _animation_index(target_id)
	if index < 0 or not bool(_available_animation_ids.get(target_id, false)):
		return false
	animation_option.select(_animation_index(&"attack") if is_weapon_attack_entry else index)
	if target_id in [&"ride_idle", &"ride_walk", &"ride_run", &"ride_attack", &"ride_slash", &"ride_thrust"]:
		if not _is_mounted:
			set_mount_enabled(true)
	else:
		if _is_mounted:
			set_mount_enabled(false)
	_selected_animation = target_id
	visual_state.animation_id = target_id
	_apply_attack_loop_default()
	_play_selected_animation()
	if _is_mounted:
		_calibrate_rider_mount_pose()
	_update_animation_ui()
	_update_status()
	return true

func select_part_by_id(part_id: StringName, option_id: StringName) -> bool:
	if part_id == &"hair":
		option_id = _canonical_hair_id(option_id)
	var option := part_options.get(part_id) as OptionButton
	if option == null:
		return false
	for index: int in range(option.item_count):
		if StringName(str(option.get_item_metadata(index))) != option_id:
			continue
		if option.is_item_disabled(index):
			return false
		option.select(index)
		_on_part_selected(index, part_id)
		return true
	return false

static func default_appearance(body_index: int = 0) -> Dictionary:
	var parts := {}
	for slot: Dictionary in PART_SLOTS:
		var options: Array = HAIR_OPTIONS[body_index] if slot.id == &"hair" else slot.options
		parts[str(slot.id)] = str(options[0].id)
	return {"body": body_index, "parts": parts, "hair_mask": "auto", "hair_dye": "9b775dff", "hair_dyed": false,
		"mounted": false, "coat": "bay", "tack": true}

static func valid_appearance(value: Variant) -> bool:
	if not value is Dictionary or not value.get("parts") is Dictionary:
		return false
	if not (value.get("body") is int or value.get("body") is float) or float(value.body) not in [0.0, 1.0]:
		return false
	if not value.get("mounted") is bool or not value.get("tack") is bool or not value.get("hair_dyed") is bool:
		return false
	if value.get("hair_mask") not in ["auto", "hide", "off"] or value.get("coat") not in ["bay", "black", "chestnut", "white"]:
		return false
	if not value.get("hair_dye") is String or str(value.hair_dye).length() != 8 or not str(value.hair_dye).is_valid_hex_number(false):
		return false
	if value.parts.size() != PART_SLOTS.size():
		return false
	for slot: Dictionary in PART_SLOTS:
		var options: Array = HAIR_OPTIONS[int(value.body)] if slot.id == &"hair" else slot.options
		var found := false
		for option: Dictionary in options:
			if value.parts.get(str(slot.id)) == str(option.id):
				found = true
				break
		if not found:
			return false
	return true

func capture_appearance() -> Dictionary:
	var result := default_appearance(_body_index)
	for slot: Dictionary in PART_SLOTS:
		var option := part_options.get(slot.id) as OptionButton
		result.parts[str(slot.id)] = str(option.get_item_metadata(option.selected))
	result.hair_mask = str(_hair_mask_mode)
	result.hair_dye = _hair_dye_color.to_html(true)
	result.hair_dyed = _hair_dye_enabled
	result.mounted = _is_mounted
	result.coat = str(_current_mount_coat)
	result.tack = _mount_tack_enabled
	return result

func restore_appearance(value: Dictionary) -> bool:
	if not valid_appearance(value):
		return false
	if _body_index != int(value.body):
		_on_body_selected(int(value.body))
	for slot: Dictionary in PART_SLOTS:
		if not select_part_by_id(slot.id, StringName(str(value.parts[str(slot.id)]))):
			return false
	set_hair_mask_mode(StringName(str(value.hair_mask)))
	set_hair_dye(Color.from_string(str(value.hair_dye), Color.WHITE))
	if not bool(value.hair_dyed):
		reset_hair_dye()
	set_mount_coat(StringName(str(value.coat)))
	set_mount_tack_enabled(bool(value.tack))
	set_mount_enabled(bool(value.mounted))
	return true

func _canonical_hair_id(hair_id: StringName) -> StringName:
	# Old preview scripts used one ID for both genders. Keep that input alias,
	# but expose only the explicit gendered IDs in the actual selector.
	if str(hair_id).begins_with("hair_short_"):
		return StringName("hair_%s_%s" % ["female" if _body_index == 1 else "male", str(hair_id).trim_prefix("hair_short_")])
	return hair_id

func set_hair_dye(color: Color) -> void:
	_hair_dye_color = Color(color.r, color.g, color.b, 1.0)
	_hair_dye_enabled = true
	if hair_dye_button != null:
		hair_dye_button.color = _hair_dye_color
		hair_dye_label.text = "髮色 / 已染"
	_update_hair_mask()

func reset_hair_dye() -> void:
	_hair_dye_enabled = false
	if hair_dye_button != null:
		hair_dye_label.text = "髮色 / 原色"
	_update_hair_mask()

func set_hair_mask_mode(mode: StringName) -> void:
	_hair_mask_mode = mode
	if hair_mask_option != null:
		for i in range(hair_mask_option.item_count):
			if StringName(str(hair_mask_option.get_item_metadata(i))) == mode:
				hair_mask_option.select(i)
				break
	_update_hair_mask()

func get_hair_mask_mode() -> StringName:
	return _hair_mask_mode

func _on_hair_mask_mode_selected(index: int) -> void:
	if hair_mask_option == null or index < 0 or index >= hair_mask_option.item_count:
		return
	_hair_mask_mode = StringName(str(hair_mask_option.get_item_metadata(index)))
	_update_hair_mask()

func set_preview_yaw_degrees(degrees: float) -> void:
	_preview_yaw = deg_to_rad(degrees)
	visual_state.yaw_degrees = degrees
	_apply_preview_rotation()

func get_preview_yaw_degrees() -> float:
	return rad_to_deg(_preview_yaw)

func get_preview_zoom() -> float:
	return _preview_zoom

func get_preview_pan() -> Vector2:
	return _preview_pan

func reset_preview_view() -> void:
	_preview_zoom = 1.0
	_preview_pan = Vector2.ZERO
	_preview_yaw = 0.0
	_preview_pitch = 0.0
	visual_state.yaw_degrees = 0.0
	_apply_preview_rotation()
	_update_preview_display()

func _load_combat_props(path: String = COMBAT_PROPS_PATH) -> void:
	if is_instance_valid(combat_props):
		combat_props.free()
	combat_props = null
	if not FileAccess.file_exists(path):
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return
	combat_props = document.generate_scene(state) as Node3D
	preview_pivot.add_child(combat_props)
	_update_combat_props()

func _update_combat_props() -> void:
	if not is_instance_valid(combat_props) or model_root == null or animation_player == null:
		return
	var option := part_options.get(&"weapon") as OptionButton
	var weapon := str(option.get_item_metadata(option.selected)) if option != null else "none"
	var bow := weapon == "bow_01"
	var crossbow := weapon == "crossbow_01"
	var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	if not lazy_combat_visual_bones_enabled:
		skeleton.force_update_all_bone_transforms()
	for node: Node in combat_props.get_children():
		if node is Node3D:
			(node as Node3D).hide()
	if not bow and not crossbow:
		return
	var hips := skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_C_Hips"))
	var quiver := combat_props.get_node("QuiverArrow" if bow else "QuiverBolt") as Node3D
	quiver.show()
	for index in range(quiver.get_child_count()):
		(quiver.get_child(index) as Node3D).visible = combat_ammo_available and index < combat_ammo_count
	quiver.global_transform = skeleton.global_transform * hips * Transform3D(Basis(Vector3.FORWARD, -.15), Vector3(-.28, -.40 if bow else -.21, -.04))
	var clip := _selected_animation
	var is_bow_pose := clip in [&"attack_bow", &"reload_bow"]
	var is_crossbow_pose := clip in [&"attack_crossbow", &"reload_crossbow"]
	if not combat_ammo_available or not (bow and is_bow_pose or crossbow and is_crossbow_pose):
		return
	var time := animation_player.current_animation_position
	if clip in [&"reload_bow", &"reload_crossbow"] and time < .4:
		return
	var release: float = CombatTimings.events(&"attack_bow" if bow else &"attack_crossbow").release
	if clip in [&"attack_bow", &"attack_crossbow"] and time >= release:
		return
	var missile := combat_props.get_node("Arrow" if bow else "Bolt") as Node3D
	missile.show()
	var right := skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_R_Hand"))
	var left := skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_L_Hand"))
	if bow or clip == &"reload_crossbow" and time < 1.1:
		var start := skeleton.global_transform * ((right if bow else left) * Vector3(0, .035, -.01))
		var end := skeleton.global_transform * ((left if bow else right) * Vector3(0, .04, -.01))
		missile.global_position = start
		if start.distance_to(end) > .01:
			missile.look_at(end, skeleton.global_basis.y, true)
	else:
		var rest := skeleton.get_bone_global_rest(skeleton.find_bone("J_Bip_R_Hand"))
		var palm := rest * Vector3(0, .045, -.015)
		var rest_to_pose := skeleton.global_transform * right * rest.affine_inverse()
		missile.global_transform = rest_to_pose * Transform3D(Basis.IDENTITY, palm + Vector3(0, .04, 0))

func set_preview_zoom(value: float, center: Vector2 = Vector2(-1.0, -1.0)) -> void:
	_set_preview_zoom(value, center)

func set_playing(enabled: bool) -> void:
	_set_playing(enabled)

func _build_ui() -> void:
	_ui_font_scale = _calculate_ui_font_scale()
	editor_root = Control.new()
	editor_root.name = "EditorRoot"
	editor_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor_root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("0a101a")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor_root.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 28.0
	margin.offset_top = 24.0
	margin.offset_right = -28.0
	margin.offset_bottom = -24.0
	editor_root.add_child(margin)

	var main_layout := VBoxContainer.new()
	main_layout.name = "MainLayout"
	main_layout.add_theme_constant_override("separation", 14)
	margin.add_child(main_layout)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0.0, 58.0)
	main_layout.add_child(header)
	var title := _new_label("WORLDGOING  /  3D CHARACTER EDITOR", 28, Color("f4ead7"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var subtitle := _new_label("HumanBase preview · fields first", 16, Color("96a8be"))
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(subtitle)
	var close_button := _new_button("關閉  ESC", Vector2(132.0, 42.0))
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var work_area := HBoxContainer.new()
	work_area.name = "WorkArea"
	work_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	work_area.add_theme_constant_override("separation", 14)
	main_layout.add_child(work_area)

	var parts_layout := _make_panel(work_area, Vector2(318.0, 0.0), true)
	parts_layout.add_child(_new_label("部件 Parts", 22, Color("f4ead7")))
	parts_layout.add_child(_new_label("每個欄位接入一組實際 3D 部件。", 16, Color("96a8be")))
	parts_layout.add_child(HSeparator.new())
	body_option = _add_option_row(parts_layout, "Body / 身體")
	part_options[&"body"] = body_option
	for body_model: Dictionary in BODY_MODELS:
		body_option.add_item(str(body_model["label"]))
		body_option.set_item_metadata(body_option.item_count - 1, body_model["id"])
	body_option.select(0)
	body_option.item_selected.connect(_request_body_selected)
	for part: Dictionary in PART_SLOTS:
		var option := _add_option_row(parts_layout, str(part["label"]))
		for component: Dictionary in _part_definition(part["id"])["options"]:
			option.add_item(str(component["label"]))
			option.set_item_metadata(option.item_count - 1, component["id"])
		option.select(0)
		option.item_selected.connect(_request_part_selected.bind(part["id"]))
		part_options[part["id"]] = option
		if part["id"] == &"hair":
			var dye_row := HBoxContainer.new()
			dye_row.custom_minimum_size = Vector2(0,48)
			parts_layout.add_child(dye_row)
			hair_dye_label = _new_label("髮色 / 原色",18,Color("d8e0ea"))
			hair_dye_label.custom_minimum_size = Vector2(122,0)
			dye_row.add_child(hair_dye_label)
			hair_dye_button = ColorPickerButton.new()
			hair_dye_button.custom_minimum_size = Vector2(80,44)
			hair_dye_button.tooltip_text = "髮束統一染色，保留明暗與髮飾原色。"
			hair_dye_button.color = _hair_dye_color
			hair_dye_button.edit_alpha = false
			hair_dye_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hair_dye_button.color_changed.connect(set_hair_dye)
			dye_row.add_child(hair_dye_button)
			var original_color := Button.new()
			original_color.text = "原色"
			original_color.custom_minimum_size = Vector2(70,44)
			original_color.add_theme_font_size_override("font_size",_ui_font_size(18))
			original_color.pressed.connect(reset_hair_dye)
			dye_row.add_child(original_color)
		if part["id"] == &"helmet":
			hair_mask_option = _add_option_row(parts_layout, "Hair Mask / 髮型遮罩")
			hair_mask_option.add_item("Auto / 智慧裁切 (保留瀏海)")
			hair_mask_option.set_item_metadata(0, &"auto")
			hair_mask_option.add_item("Hide / 全隱藏 (戴盔內襯)")
			hair_mask_option.set_item_metadata(1, &"hide")
			hair_mask_option.add_item("Off / 關閉 (無遮罩對比)")
			hair_mask_option.set_item_metadata(2, &"off")
			hair_mask_option.select(0)
			hair_mask_option.item_selected.connect(_on_hair_mask_mode_selected)
	parts_layout.add_spacer(false)
	parts_footer = _new_label("接入狀態  載入中…", 16, Color("d8c49e"))
	parts_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parts_layout.add_child(parts_footer)

	var preview_layout := _make_panel(work_area, Vector2(0.0, 0.0))
	preview_layout.add_child(_new_label("3D Preview", 22, Color("f4ead7")))
	model_label = _new_label("載入素體中…", 16, Color("96a8be"))
	model_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_layout.add_child(model_label)
	var preview_toolbar := HBoxContainer.new()
	preview_toolbar.name = "PreviewToolbar"
	preview_toolbar.add_theme_constant_override("separation", 8)
	var zoom_caption := _new_label("視圖", 16, Color("d8e0ea"))
	zoom_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_toolbar.add_child(zoom_caption)
	preview_zoom_out_button = _new_button("−", Vector2(48.0, 40.0))
	preview_zoom_out_button.tooltip_text = "縮小預覽"
	preview_zoom_out_button.pressed.connect(_on_preview_zoom_out_pressed)
	preview_toolbar.add_child(preview_zoom_out_button)
	preview_zoom_label = _new_label("100%", 17, Color("d8c49e"))
	preview_zoom_label.custom_minimum_size = Vector2(72.0, 40.0)
	preview_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_toolbar.add_child(preview_zoom_label)
	preview_zoom_in_button = _new_button("+", Vector2(48.0, 40.0))
	preview_zoom_in_button.tooltip_text = "放大預覽"
	preview_zoom_in_button.pressed.connect(_on_preview_zoom_in_pressed)
	preview_toolbar.add_child(preview_zoom_in_button)
	preview_reset_view_button = _new_button("重設視圖", Vector2(116.0, 40.0))
	preview_reset_view_button.tooltip_text = "恢復 100%、置中與初始旋轉"
	preview_reset_view_button.pressed.connect(reset_preview_view)
	preview_toolbar.add_child(preview_reset_view_button)
	preview_layout.add_child(preview_toolbar)
	var viewport_panel := PanelContainer.new()
	viewport_panel.name = "PreviewFrame"
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_panel.add_theme_stylebox_override("panel", _panel_style(Color("141e2b"), Color("32445b")))
	preview_layout.add_child(viewport_panel)
	preview_container = SubViewportContainer.new()
	preview_container.name = "PreviewViewportContainer"
	preview_container.stretch = true
	preview_container.texture_filter = CharacterRenderContract.TEXTURE_FILTER
	preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_container.gui_input.connect(_on_preview_gui_input)
	preview_container.resized.connect(_on_preview_resized)
	viewport_panel.add_child(preview_container)
	preview_clip = Control.new()
	preview_clip.name = "PreviewTextureClip"
	preview_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_clip.clip_contents = true
	preview_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_container.add_child(preview_clip)
	preview_texture = TextureRect.new()
	preview_texture.name = "PreviewTexture"
	preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_texture.texture_filter = CharacterRenderContract.TEXTURE_FILTER
	preview_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_clip.add_child(preview_texture)
	var preview_hint := _new_label("滾輪縮放；中鍵平移；左鍵旋轉 360°。地圖角色仍使用原始渲染比例。", 16, Color("7f91a8"))
	preview_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_layout.add_child(preview_hint)

	var animation_layout := _make_panel(work_area, Vector2(332.0, 0.0), true)
	animation_layout.add_child(_new_label("動畫 Animation", 22, Color("f4ead7")))
	var animation_description := _new_label("已完整接入角色動作（基準姿勢、待機、走動、跑步、攻擊、防禦、受擊、倒地）。", 16, Color("96a8be"))
	animation_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	animation_layout.add_child(animation_description)
	animation_layout.add_child(HSeparator.new())
	animation_option = _add_option_row(animation_layout, "Clip / 動作")
	for slot: Dictionary in ANIMATION_SLOTS:
		animation_option.add_item(str(slot["label"]))
		animation_option.set_item_metadata(animation_option.item_count - 1, slot["id"])
		if str(slot["state"]) == "reserved":
			animation_option.set_item_disabled(animation_option.item_count - 1, true)
	animation_option.select(1)
	animation_option.item_selected.connect(_on_animation_selected)

	var playback_row := HBoxContainer.new()
	play_button = _new_button("播放", Vector2(118.0, 42.0))
	play_button.toggle_mode = true
	play_button.pressed.connect(_on_play_pressed)
	playback_row.add_child(play_button)
	reset_button = _new_button("重設動畫", Vector2(112.0, 42.0))
	reset_button.pressed.connect(_reset_animation)
	playback_row.add_child(reset_button)
	animation_layout.add_child(playback_row)

	loop_toggle = CheckBox.new()
	loop_toggle.text = "循環播放 Loop"
	loop_toggle.add_theme_font_size_override("font_size", _ui_font_size(20))
	loop_toggle.button_pressed = true
	loop_toggle.toggled.connect(_on_loop_toggled)
	animation_layout.add_child(loop_toggle)

	var speed_row := HBoxContainer.new()
	speed_row.add_child(_new_label("速度", 17, Color("d8e0ea")))
	speed_slider = HSlider.new()
	speed_slider.min_value = 0.25
	speed_slider.max_value = 2.0
	speed_slider.step = 0.05
	speed_slider.value = 1.0
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_slider.value_changed.connect(_on_speed_changed)
	speed_row.add_child(speed_slider)
	speed_value_label = _new_label("1.00x", 16, Color("d8c49e"))
	speed_value_label.custom_minimum_size = Vector2(48.0, 0.0)
	speed_row.add_child(speed_value_label)
	animation_layout.add_child(speed_row)

	var timeline_title := _new_label("時間軸", 17, Color("d8e0ea"))
	animation_layout.add_child(timeline_title)
	timeline_slider = HSlider.new()
	timeline_slider.min_value = 0.0
	timeline_slider.max_value = 1.0
	timeline_slider.step = 0.01
	timeline_slider.value = 0.0
	timeline_slider.value_changed.connect(_on_timeline_changed)
	animation_layout.add_child(timeline_slider)
	timeline_label = _new_label("0.00 / 1.00 s", 16, Color("96a8be"))
	animation_layout.add_child(timeline_label)
	animation_state_label = _new_label("AnimationPlayer 尚未載入", 16, Color("96a8be"))
	animation_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	animation_layout.add_child(animation_state_label)

	animation_layout.add_child(HSeparator.new())
	var mount_header := _new_label("Mount / 坐騎系統", 20, Color("f4ead7"))
	animation_layout.add_child(mount_header)

	mount_toggle = CheckBox.new()
	mount_toggle.text = "騎乘戰馬 (Mount Horse)"
	mount_toggle.add_theme_font_size_override("font_size", _ui_font_size(20))
	mount_toggle.button_pressed = false
	mount_toggle.toggled.connect(_on_mount_toggled)
	animation_layout.add_child(mount_toggle)

	var coat_row := HBoxContainer.new()
	coat_row.add_child(_new_label("毛色", 17, Color("d8e0ea")))
	mount_coat_option = OptionButton.new()
	mount_coat_option.add_theme_font_size_override("font_size", _ui_font_size(20))
	mount_coat_option.get_popup().add_theme_font_size_override("font_size", _ui_font_size(20))
	mount_coat_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mount_coat_option.add_item("Bay / 棗紅 (鹿毛)")
	mount_coat_option.set_item_metadata(0, &"bay")
	mount_coat_option.add_item("Chestnut / 栗色 (赤兔)")
	mount_coat_option.set_item_metadata(1, &"chestnut")
	mount_coat_option.add_item("Black / 烏騅 (玄曜)")
	mount_coat_option.set_item_metadata(2, &"black")
	mount_coat_option.add_item("White / 照夜白 (白馬)")
	mount_coat_option.set_item_metadata(3, &"white")
	mount_coat_option.item_selected.connect(_on_mount_coat_selected)
	coat_row.add_child(mount_coat_option)
	animation_layout.add_child(coat_row)

	mount_tack_toggle = CheckBox.new()
	mount_tack_toggle.text = "配戴鞍具裝備 (Tack & Reins)"
	mount_tack_toggle.add_theme_font_size_override("font_size", _ui_font_size(20))
	mount_tack_toggle.button_pressed = true
	mount_tack_toggle.toggled.connect(_on_mount_tack_toggled)
	animation_layout.add_child(mount_tack_toggle)

	animation_layout.add_spacer(false)
	var animation_footer := _new_label("全部動作已就緒 · 支援 360° 旋轉、縮放、平移與時間軸拖曳", 16, Color("6f8299"))
	animation_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	animation_layout.add_child(animation_footer)

	status_label = _new_label("Presentation-only preview · 不寫入 GameSession", 16, Color("96a8be"))
	status_label.custom_minimum_size = Vector2(0.0, 42.0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_layout.add_child(status_label)

func _initialize_preview() -> void:
	preview_viewport = SubViewport.new()
	preview_viewport.name = "CharacterPreviewSubViewport"
	# Keep one canonical render target for the editor and the map presenter.
	# UI containers may scale this texture, but the 3D projection itself stays stable.
	preview_viewport.size = CharacterRenderContract.PREVIEW_VIEWPORT_SIZE
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	preview_viewport.transparent_bg = true
	if preview_host != null:
		preview_viewport.own_world_3d = true
		preview_host.add_child(preview_viewport)
	else:
		add_child(preview_viewport)
	if preview_texture != null:
		preview_texture.texture = preview_viewport.get_texture()
		_update_preview_display()

	preview_world = Node3D.new()
	preview_world.name = "CharacterPreviewWorld"
	preview_viewport.add_child(preview_world)
	preview_pivot = Node3D.new()
	preview_pivot.name = "CharacterPreviewPivot"
	preview_world.add_child(preview_pivot)

	mount_horse = MountHorse3D.new()
	mount_horse.name = "CharacterPreviewMount"
	mount_horse.visible = false
	preview_pivot.add_child(mount_horse)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("eef2f5")
	environment.ambient_light_energy = 1.35
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.10
	environment.adjustment_contrast = 1.04
	environment.adjustment_saturation = 1.08
	environment_node.environment = environment
	preview_world.add_child(environment_node)

	var ground := MeshInstance3D.new()
	ground.name = "PreviewGround"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(40.0, 40.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("344354")
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	ground.position.y = -0.015
	ground.visible = false
	preview_world.add_child(ground)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
	key_light.light_color = Color("fff0d5")
	key_light.light_energy = 1.60
	preview_world.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-24.0, 145.0, 0.0)
	fill_light.light_color = Color("9fc5df")
	fill_light.light_energy = 0.65
	preview_world.add_child(fill_light)

	camera = Camera3D.new()
	camera.name = "CharacterPreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(CharacterRenderContract.FOOT_PROFILE["size"])
	camera.near = 0.03
	camera.far = 100.0
	camera.position = Vector3(0.0, float(CharacterRenderContract.FOOT_PROFILE["camera_y"]), float(CharacterRenderContract.FOOT_PROFILE["camera_z"]))
	preview_world.add_child(camera)
	camera.look_at_from_position(camera.position, CharacterRenderContract.FOOT_PROFILE["target"], Vector3.UP)
	camera.current = true
	_load_body_model(visual_state.body_index)

func _update_preview_framing() -> void:
	if camera == null:
		return
	var profile: Dictionary = CharacterRenderContract.camera_profile(_is_mounted)
	camera.size = float(profile["size"])
	camera.position = Vector3(0.0, float(profile["camera_y"]), float(profile["camera_z"]))
	camera.look_at_from_position(camera.position, profile["target"], Vector3.UP)

func _on_preview_resized() -> void:
	_update_preview_display()

func _update_preview_display() -> void:
	if preview_clip == null or preview_texture == null or preview_viewport == null:
		return
	var frame_size := preview_clip.size
	var texture_size := Vector2(preview_viewport.size)
	if frame_size.x <= 1.0 or frame_size.y <= 1.0 or texture_size.x <= 1.0 or texture_size.y <= 1.0:
		return
	var base_scale := minf(frame_size.x / texture_size.x, frame_size.y / texture_size.y)
	var display_scale := base_scale * _preview_zoom
	var scaled_size := texture_size * display_scale
	var max_pan := Vector2(
		maxf(0.0, (scaled_size.x - frame_size.x) * 0.5),
		maxf(0.0, (scaled_size.y - frame_size.y) * 0.5)
	)
	_preview_pan.x = clampf(_preview_pan.x, -max_pan.x, max_pan.x)
	_preview_pan.y = clampf(_preview_pan.y, -max_pan.y, max_pan.y)
	preview_texture.size = texture_size
	preview_texture.scale = Vector2.ONE * display_scale
	preview_texture.position = frame_size * 0.5 + _preview_pan - scaled_size * 0.5
	if preview_zoom_label != null:
		preview_zoom_label.text = "%d%%" % roundi(_preview_zoom * 100.0)

func _set_preview_zoom(value: float, center: Vector2 = Vector2(-1.0, -1.0)) -> void:
	var new_zoom := clampf(value, PREVIEW_MIN_ZOOM, PREVIEW_MAX_ZOOM)
	if is_equal_approx(new_zoom, _preview_zoom):
		return
	if preview_clip != null and center.x >= 0.0 and center.y >= 0.0:
		var frame_size := preview_clip.size
		var texture_size := Vector2(preview_viewport.size) if preview_viewport != null else Vector2.ZERO
		if frame_size.x > 1.0 and frame_size.y > 1.0 and texture_size.x > 1.0 and texture_size.y > 1.0:
			var base_scale := minf(frame_size.x / texture_size.x, frame_size.y / texture_size.y)
			var old_scale := base_scale * _preview_zoom
			var old_size := texture_size * old_scale
			var old_position := frame_size * 0.5 + _preview_pan - old_size * 0.5
			var texture_point := (center - old_position) / old_scale
			var new_scale := base_scale * new_zoom
			var new_size := texture_size * new_scale
			var new_position := center - texture_point * new_scale
			_preview_pan = new_position + new_size * 0.5 - frame_size * 0.5
	_preview_zoom = new_zoom
	_update_preview_display()

func _on_preview_zoom_out_pressed() -> void:
	_set_preview_zoom(_preview_zoom / PREVIEW_ZOOM_STEP)

func _on_preview_zoom_in_pressed() -> void:
	_set_preview_zoom(_preview_zoom * PREVIEW_ZOOM_STEP)

func get_map_sprite_scale() -> float:
	if camera == null or preview_viewport == null:
		return 1.0
	return CharacterRenderContract.sprite_scale(preview_viewport.size, camera.size)

func get_map_ground_offset_pixels() -> Vector2:
	if camera == null or preview_viewport == null or preview_pivot == null:
		return Vector2.ZERO
	var viewport_center := Vector2(preview_viewport.size) * 0.5
	return camera.unproject_position(preview_pivot.global_position) - viewport_center

func _load_body_model(index: int, preview_model_path: String = "") -> void:
	clear_hair_node_lookup_cache()
	if index < 0 or index >= BODY_MODELS.size() or preview_world == null:
		return
	_body_index = index
	visual_state.body_index = index
	_preview_pan = Vector2.ZERO
	if body_option != null and body_option.selected != index:
		body_option.select(index)
	if model_root != null:
		if model_root.get_parent() != null:
			model_root.get_parent().remove_child(model_root)
		model_root.queue_free()
		model_root = null
	animation_player = null
	var model_path: String = str(BODY_MODELS[index]["path"])
	if not preview_model_path.is_empty():
		model_path = preview_model_path
	var absolute_path := ProjectSettings.globalize_path(model_path)
	if not FileAccess.file_exists(absolute_path):
		model_label.text = "找不到素體：%s" % model_path
		return
	var generated: Node3D
	if use_imported_model and preview_model_path.is_empty():
		# Do not reuse mutable preview resources from another editor instance.
		var packed := ResourceLoader.load(model_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed != null:
			generated = packed.instantiate() as Node3D
	else:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var parse_error: Error = document.append_from_file(absolute_path, state)
		if parse_error != OK:
			model_label.text = "GLB 載入失敗：%s" % parse_error
			return
		generated = document.generate_scene(state) as Node3D
	if generated == null:
		model_label.text = "GLB 沒有產生 Node3D"
		return
	model_root = generated
	model_root.name = "HumanBasePreview_%s" % str(BODY_MODELS[index]["id"])
	# The VRM source faces +Z; the preview camera is placed on -Z.
	model_root.rotation_degrees = Vector3.ZERO
	preview_pivot.add_child(model_root)
	_apply_preview_rotation()
	# Preserve the authored skinned spear grip/axis. Lab framing supplies margin;
	# rotating or relocating the weapon to fit a portrait corrupts the thrust.
	var players: Array[Node] = model_root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation_player = players[0] as AnimationPlayer
		if _body_index == 0:
			_ensure_male_full_body()
			_ensure_editor_walk_animation()
		_ensure_editor_jump_attack_animation()
		_refresh_animation_options()
	_apply_face_materials()
	_select_fallback_animation()
	_apply_equipment_style()
	_refresh_part_options()
	_update_model_ui()
	_play_selected_animation()
	if _is_mounted:
		_attach_rider_to_mount()
	_update_preview_framing()
	_update_preview_display()
	_load_combat_props()
	_prepare_rigid_scabbards()
	_prepare_combat_cloth()

func _prepare_combat_cloth() -> void:
	_combat_cloth.clear()
	var shader := load("res://assets/characters/human/q35/combat/combat_cloth_ground.gdshader") as Shader
	for node in model_root.find_children("Cape_*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var bounds := mesh.get_aabb()
		var lowest := INF
		for corner in range(8):
			lowest = minf(lowest, (mesh.global_transform * bounds.get_endpoint(corner)).y - preview_pivot.global_position.y)
		var record := {"node": mesh, "original": [], "ground": [], "outline": mesh.material_overlay, "down": {},
			"floor": lowest, "group": "chinese" if str(mesh.name).begins_with("Cape_Chinese_") else "travel"}
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_surface_override_material(surface)
			var material := mesh.get_active_material(surface)
			var ground := ShaderMaterial.new()
			ground.shader = shader
			if material is BaseMaterial3D:
				ground.set_shader_parameter("base_color", material.albedo_color)
				ground.set_shader_parameter("base_metallic", material.metallic)
				ground.set_shader_parameter("base_roughness", material.roughness)
				ground.set_shader_parameter("has_texture", material.albedo_texture != null)
				ground.set_shader_parameter("albedo_texture", material.albedo_texture)
			elif material is ShaderMaterial:
				for parameter in ["base_color", "base_metallic", "base_roughness"]:
					ground.set_shader_parameter(parameter, material.get_shader_parameter(parameter))
			record.original.append(original)
			record.ground.append(ground)
		if animation_player.has_animation(&"down"):
			var down := animation_player.get_animation(&"down")
			for track in range(down.get_track_count()):
				var path := down.track_get_path(track)
				if down.track_get_type(track) == Animation.TYPE_BLEND_SHAPE and path.get_concatenated_names().get_file() == str(mesh.name):
					var shape := mesh.find_blend_shape_by_name(path.get_concatenated_subnames())
					if shape >= 0:
						record.down[shape] = down.blend_shape_track_interpolate(track, down.length)
		_combat_cloth.append(record)
	# Trim, lining and outer fabric share the same gathering transform.
	var floors := {}
	for record in _combat_cloth:
		floors[record.group] = minf(float(floors.get(record.group, INF)), record.floor)
	for record in _combat_cloth:
		record.floor = floors[record.group]

func _update_combat_cloth() -> void:
	if model_root == null:
		return
	var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if not lazy_combat_visual_bones_enabled:
		skeleton.force_update_all_bone_transforms()
	var hips := skeleton.find_bone("J_Bip_C_Hips")
	var neck := skeleton.find_bone("J_Bip_C_Neck")
	var hip_delta := (skeleton.global_basis * (skeleton.get_bone_global_pose(hips).origin - skeleton.get_bone_global_rest(hips).origin)).y
	var top := (skeleton.global_transform * skeleton.get_bone_global_pose(neck).origin).y
	var low := _selected_animation in [&"get_up", &"rescue"] and top > preview_pivot.global_position.y + .55
	for record in _combat_cloth:
		var mesh := record.node as MeshInstance3D
		if not is_instance_valid(mesh):
			continue
		for surface in range(record.original.size()):
			mesh.set_surface_override_material(surface, record.ground[surface] if low else record.original[surface])
			var material := record.ground[surface] as ShaderMaterial
			material.set_shader_parameter("ground_height", preview_pivot.global_position.y)
			material.set_shader_parameter("source_floor", preview_pivot.global_position.y + float(record.floor) + hip_delta)
			material.set_shader_parameter("cloth_top", top)
		mesh.material_overlay = null if low else record.outline
		if _selected_animation == &"unconscious" or _selected_animation == &"get_up":
			var weight := 1.0 if _selected_animation == &"unconscious" else 1.0 - smoothstep(0.0, .65, animation_player.current_animation_position)
			for shape in record.down:
				mesh.set_blend_shape_value(shape, record.down[shape] * weight)

func _prepare_rigid_scabbards() -> void:
	_rigid_scabbards.clear()
	var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	for node: Node in model_root.find_children("Weapon_Longsword_01_*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not ("_Scabbard_" in str(mesh.name) or "_Sheathed_" in str(mesh.name)):
			continue
		# These existing rigid meshes are hip-weighted. The same hip transform
		# drives them, with a belt swivel so a long scabbard can lie on the ground.
		_rigid_scabbards.append({"node": mesh, "rest": skeleton.global_transform.affine_inverse() * mesh.global_transform})
		mesh.skin = null
		mesh.skeleton = NodePath()
	_update_scabbard_pose()

func _update_scabbard_pose() -> void:
	if _rigid_scabbards.is_empty() or model_root == null:
		return
	var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if not lazy_combat_visual_bones_enabled:
		skeleton.force_update_all_bone_transforms()
	var index := skeleton.find_bone("J_Bip_C_Hips")
	var pose := skeleton.get_bone_global_pose(index)
	var rest := skeleton.get_bone_global_rest(index)
	var hip_transform := pose * rest.affine_inverse()
	var swivel := Transform3D.IDENTITY
	var angle := 0.0
	if _selected_animation == &"get_up":
		# Swing out from the belt while the hips roll up, not through the
		# floor or across the bent knees. Keep the original mesh and hinge.
		var time := animation_player.current_animation_position
		var reach := smoothstep(0.0, .4, time) * (1.0 - smoothstep(1.55, 2.2, time))
		var hinge := hip_transform * (rest.origin + Vector3(.15, 0, 0))
		var original := (hip_transform.basis * Vector3.DOWN).normalized()
		var horizontal := Vector3(original.x, 0, original.z).lerp(Vector3.RIGHT, reach).normalized()
		var downward := maxf(original.y, -clampf((hinge.y - .10) / .78, 0.0, 1.0))
		var target := horizontal * sqrt(maxf(0.0, 1.0 - downward * downward)) + Vector3.UP * downward
		if not target.is_zero_approx():
			var correction := Transform3D(Basis(Quaternion(original, target.normalized())), hinge) * Transform3D(Basis.IDENTITY, -hinge)
			hip_transform = correction * hip_transform
	elif _selected_animation == &"rescue" and pose.basis.y.dot(Vector3.UP) > .4:
		angle = acos(clampf((pose.origin.y - .10) / .74, 0.0, 1.0))
	if not is_zero_approx(angle):
		var pivot := rest.origin + Vector3(.15, .0, .0)
		swivel = Transform3D(Basis(Vector3.RIGHT, angle), pivot) * Transform3D(Basis.IDENTITY, -pivot)
	for item in _rigid_scabbards:
		(item.node as Node3D).global_transform = skeleton.global_transform * hip_transform * swivel * item.rest

func _attach_rider_to_mount() -> void:
	if model_root == null or mount_horse == null:
		return
	var attachment := mount_horse.get_rider_attachment()
	if attachment == null:
		return
	if model_root.get_parent() != attachment:
		model_root.reparent(attachment, false)
	model_root.position = MOUNT_RIDER_OFFSET
	model_root.rotation = Vector3.ZERO
	_calibrate_rider_mount_pose()

func _calibrate_rider_mount_pose() -> void:
	"""Align the rider's pelvis to the horse saddle socket without changing scale.

	The imported riding clips contain an authored vertical offset intended for a
	different horse rig.  The horse asset exposes Socket_Rider as the authority;
	we correct the rider root against that socket once per mount/clip change.
	"""
	if not _is_mounted or model_root == null or mount_horse == null:
		return
	var attachment := mount_horse.get_rider_attachment()
	var horse_skeleton := mount_horse.skeleton
	var rider_skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if attachment == null or horse_skeleton == null or rider_skeleton == null:
		return
	# Apply the newly selected clip before reading its bone pose. AnimationPlayer
	# updates its tracks on the frame tick; advance(0) makes this calibration
	# deterministic when a clip is switched from the UI or a test harness.
	if animation_player != null:
		animation_player.advance(0.0)
	if mount_horse.animation_player != null:
		mount_horse.animation_player.advance(0.0)
	horse_skeleton.force_update_all_bone_transforms()
	rider_skeleton.force_update_all_bone_transforms()
	var socket_index := horse_skeleton.find_bone(MountHorse3D.SOCKET_BONE_NAME)
	if socket_index < 0:
		return
	var hip_index := -1
	for bone_name: StringName in MOUNT_RIDER_HIP_BONES:
		hip_index = rider_skeleton.find_bone(bone_name)
		if hip_index >= 0:
			break
	if hip_index < 0:
		return
	var socket_world := horse_skeleton.global_transform * horse_skeleton.get_bone_global_pose(socket_index).origin
	var hip_world := rider_skeleton.global_transform * rider_skeleton.get_bone_global_pose(hip_index).origin
	# The seat's AABB maximum is the high cantle, not the sitting surface.
	# Socket_Rider is authored at the seat centre and follows the saddle bone.
	var seat_contact := socket_world + Vector3.UP * MOUNT_SEAT_CLEARANCE
	# Keep the rider's authored facing and proportions; only correct global
	# translation. The target is derived from the same saddle every time, so
	# repeated animation changes and mount/unmount cycles are idempotent.
	model_root.global_position += seat_contact - hip_world

func _detach_rider_from_mount() -> void:
	if model_root == null or preview_pivot == null:
		return
	if model_root.get_parent() != preview_pivot:
		model_root.reparent(preview_pivot, false)
	model_root.position = Vector3.ZERO
	model_root.rotation = Vector3.ZERO

func _ensure_editor_walk_animation() -> void:
	if animation_player == null:
		return
	var library := animation_player.get_animation_library(&"")
	if library == null:
		return
	var imported_walk: Animation = library.get_animation(&"walk") if library.has_animation(&"walk") else null
	if imported_walk != null and _walk_animation_has_body_motion(imported_walk):
		return

	var walk := Animation.new()
	walk.resource_name = "walk_editor_fitted"
	walk.length = 1.0
	walk.loop_mode = Animation.LOOP_LINEAR
	var times: Array[float] = [0.0, 0.25, 0.50, 0.75, 1.0]
	var bone_names: Array[String] = [
		"J_Bip_L_UpperLeg", "J_Bip_R_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_R_LowerLeg",
		"J_Bip_L_Foot", "J_Bip_R_Foot", "J_Bip_L_UpperArm", "J_Bip_R_UpperArm",
		"J_Bip_L_LowerArm", "J_Bip_R_LowerArm", "J_Bip_C_Chest", "J_Bip_C_Head",
	]
	var base_rotations: Dictionary = {}
	var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D if model_root != null else null
	if skeleton != null:
		skeleton.reset_bone_poses()
		for bone_name: String in bone_names:
			var bone_index := skeleton.find_bone(bone_name)
			if bone_index >= 0:
				base_rotations[bone_name] = skeleton.get_bone_pose_rotation(bone_index)
	var tpose: Animation = library.get_animation(&"T-Pose") if library.has_animation(&"T-Pose") else null
	if tpose != null:
		for track_index: int in range(tpose.get_track_count()):
			var track_path := str(tpose.track_get_path(track_index))
			for bone_name: String in bone_names:
				if track_path.ends_with(":" + bone_name) and tpose.track_get_key_count(track_index) > 0:
					var key_value: Variant = tpose.track_get_key_value(track_index, 0)
					if key_value is Quaternion:
						base_rotations[bone_name] = key_value
	var track_indices: Dictionary = {}
	for bone_name: String in bone_names:
		var track_index := walk.add_track(Animation.TYPE_ROTATION_3D)
		walk.track_set_path(track_index, NodePath("Armature/Skeleton3D:" + bone_name))
		walk.track_set_interpolation_type(track_index, Animation.INTERPOLATION_LINEAR)
		track_indices[bone_name] = track_index

	for time: float in times:
		var phase := time * TAU
		var stride := sin(phase)
		var knee_left := maxf(0.0, -stride) * 0.22
		var knee_right := maxf(0.0, stride) * 0.22
		var arm_swing := sin(phase + PI) * 0.18
		var poses := {
			"J_Bip_L_UpperLeg": Vector3(stride * 0.36, 0.0, 0.0),
			"J_Bip_R_UpperLeg": Vector3(-stride * 0.36, 0.0, 0.0),
			"J_Bip_L_LowerLeg": Vector3(knee_left, 0.0, 0.0),
			"J_Bip_R_LowerLeg": Vector3(knee_right, 0.0, 0.0),
			"J_Bip_L_Foot": Vector3(-stride * 0.10 - knee_left * 0.18, 0.0, 0.0),
			"J_Bip_R_Foot": Vector3(stride * 0.10 - knee_right * 0.18, 0.0, 0.0),
			"J_Bip_L_UpperArm": Vector3(-1.16, 0.0, arm_swing),
			"J_Bip_R_UpperArm": Vector3(-1.16, 0.0, -arm_swing),
			"J_Bip_L_LowerArm": Vector3(0.12, 0.0, arm_swing * 0.25),
			"J_Bip_R_LowerArm": Vector3(0.12, 0.0, -arm_swing * 0.25),
			"J_Bip_C_Chest": Vector3(0.0, 0.0, stride * 0.035),
			"J_Bip_C_Head": Vector3(0.0, 0.0, -stride * 0.025),
		}
		for bone_name: String in poses:
			var base_rotation: Quaternion = base_rotations.get(bone_name, Quaternion.IDENTITY)
			walk.track_insert_key(int(track_indices[bone_name]), time, base_rotation * Quaternion.from_euler(poses[bone_name]))

	if library.has_animation(&"walk"):
		library.remove_animation(&"walk")
	var add_error := library.add_animation(&"walk", walk)
	if add_error != OK:
		push_error("HumanCharacter3DEditor: failed to install fitted walk animation (%s)" % add_error)

func _ensure_editor_jump_attack_animation() -> void:
	if animation_player == null:
		return
	var library := animation_player.get_animation_library(&"")
	if library == null:
		return
	var source_id: StringName = &"attack_jump_heavy"
	if not library.has_animation(source_id):
		return
	var source := library.get_animation(source_id)
	if source == null:
		return
	var adjusted := source.duplicate(true) as Animation
	if adjusted == null:
		return
	adjusted.resource_name = "attack_jump_heavy_reduced_height"
	var root_tracks: Array[int] = []
	var fallback_tracks: Array[int] = []
	for track_index: int in range(adjusted.get_track_count()):
		if adjusted.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		var track_path := str(adjusted.track_get_path(track_index))
		if not (track_path.contains("Armature") or track_path.contains("Skeleton3D")):
			continue
		fallback_tracks.append(track_index)
		if track_path.contains("J_Bip_C_Hips") or track_path.contains("J_Bip_C_Pelvis") or track_path.contains("J_Bip_C_Root") or track_path.ends_with(":position"):
			root_tracks.append(track_index)
	var tracks_to_adjust: Array[int] = root_tracks if not root_tracks.is_empty() else fallback_tracks
	var adjusted_key_count := 0
	for track_index: int in tracks_to_adjust:
		var base_y := 0.0
		var has_base := false
		for key_index: int in range(adjusted.track_get_key_count(track_index)):
			var key_value: Variant = adjusted.track_get_key_value(track_index, key_index)
			if not key_value is Vector3:
				continue
			var position: Vector3 = key_value
			if not has_base:
				base_y = position.y
				has_base = true
			position.y = base_y + (position.y - base_y) * JUMP_HEAVY_VERTICAL_SCALE
			adjusted.track_set_key_value(track_index, key_index, position)
			adjusted_key_count += 1
	adjusted.set_meta("worldgoing_jump_heavy_adjusted_keys", adjusted_key_count)
	if library.has_animation(&"attack_jump_heavy"):
		library.remove_animation(&"attack_jump_heavy")
	var add_error := library.add_animation(&"attack_jump_heavy", adjusted)
	if add_error != OK:
		push_error("HumanCharacter3DEditor: failed to install reduced jump attack (%s)" % add_error)

func _ensure_male_full_body() -> void:
	if model_root == null or _body_index != 0:
		return
	var full_body := model_root.find_child("Body_Standard_Male_Full", true, false) as MeshInstance3D
	if full_body == null or full_body.mesh == null or full_body.skin == null:
		push_error("HumanCharacter3DEditor: same-pack full male body mesh is incomplete")
		return
	full_body.visible = false
	full_body.set_meta("worldgoing_full_body_base", true)
	_update_full_body_visibility()

func _walk_animation_has_body_motion(animation: Animation) -> bool:
	var changed_tracks := 0
	for track_index: int in range(animation.get_track_count()):
		var path := str(animation.track_get_path(track_index))
		if not (path.contains("J_Bip_L_UpperLeg") or path.contains("J_Bip_R_UpperLeg") or path.contains("J_Bip_L_UpperArm") or path.contains("J_Bip_R_UpperArm")):
			continue
		var key_count := animation.track_get_key_count(track_index)
		if key_count < 3:
			continue
		var first: Variant = animation.track_get_key_value(track_index, 0)
		var middle: Variant = animation.track_get_key_value(
			track_index,
			floori(float(key_count) / 2.0)
		)
		if str(first) != str(middle):
			changed_tracks += 1
	return changed_tracks >= 2

func _apply_face_materials() -> void:
	if model_root == null:
		return
	for node: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var node_name := str(mesh_node.name)
		var is_face := (node_name.begins_with("Face_Standard") or node_name == "Face")
		var is_female_body := (node_name.begins_with("Body_Standard_Female") or node_name == "Body")
		if not (is_face or is_female_body):
			continue
		if mesh_node.mesh == null:
			continue
		for surface_index: int in range(mesh_node.mesh.get_surface_count()):
			var source_material := mesh_node.get_active_material(surface_index) as StandardMaterial3D
			if source_material == null:
				continue
			var face_material := source_material.duplicate() as StandardMaterial3D
			if face_material == null:
				face_material = StandardMaterial3D.new()
			var resource_name := str(source_material.resource_name).to_lower()
			face_material.albedo_color = _face_material_color(resource_name)
			face_material.metallic = 0.0
			face_material.roughness = 0.82
			face_material.emission_enabled = false
			face_material.emission = Color.BLACK
			face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_node.set_surface_override_material(surface_index, face_material)

func _face_material_color(resource_name: String) -> Color:
	if resource_name.contains("skin"):
		return Color("f0b083")
	if resource_name.contains("eyewhite"):
		return Color("fff8ee")
	if resource_name.contains("eyeiris"):
		return Color("4b2d26")
	if resource_name.contains("eyehighlight"):
		return Color("fffaf1")
	if resource_name.contains("eyebrow") or resource_name.contains("facebrow") or resource_name.contains("eyelash") or resource_name.contains("eyeline") or resource_name.contains("eyeextra"):
		return Color("2a1820")
	if resource_name.contains("mouth"):
		return Color("bd7168")
	return Color("f0b083")

func _attach_weapon_to_right_hand() -> void:
	if model_root == null:
		return
	var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var grip := model_root.find_child("Weapon_Longsword_01_Grip", true, false) as MeshInstance3D
	if skeleton == null or grip == null or grip.mesh == null or grip.skin == null:
		return
	var hand_index := skeleton.find_bone(RIGHT_HAND_BONE)
	if hand_index < 0:
		return
	var hand_position := _right_hand_surface_center(skeleton, hand_index)
	if hand_position == Vector3.INF:
		hand_position = skeleton.get_bone_global_pose(hand_index).origin
	var grip_hold_point := grip.mesh.get_aabb().get_center()
	var correction := hand_position - grip_hold_point
	var attachment := skeleton.get_node_or_null("HAND_R_SOCKET_Weapon") as BoneAttachment3D
	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.name = "HAND_R_SOCKET_Weapon"
		attachment.bone_name = RIGHT_HAND_BONE
		attachment.set_meta("worldgoing_weapon_hand_socket", true)
		skeleton.add_child(attachment)
	var weapon_nodes: Array[MeshInstance3D] = []
	for node: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if str(mesh_node.name).begins_with("Weapon_Longsword_01_"):
			weapon_nodes.append(mesh_node)
	for mesh_node: MeshInstance3D in weapon_nodes:
		var source_skin := mesh_node.skin
		if source_skin == null:
			continue
		var bind_index := -1
		for index in range(source_skin.get_bind_count()):
			if source_skin.get_bind_bone(index) == hand_index:
				bind_index = index
				break
		if bind_index < 0:
			continue
		var hand_bind_pose := source_skin.get_bind_pose(bind_index)
		mesh_node.reparent(attachment, false)
		mesh_node.skin = null
		mesh_node.skeleton = NodePath("")
		mesh_node.transform = hand_bind_pose * Transform3D(Basis.IDENTITY, correction)
		mesh_node.set_meta("worldgoing_weapon_hand_aligned", true)
		mesh_node.set_meta("worldgoing_weapon_hand_alignment_offset", correction)


func _right_hand_surface_center(skeleton: Skeleton3D, hand_index: int) -> Vector3:
	var body := model_root.find_child("Body_Standard_Male", true, false) as MeshInstance3D
	if body == null:
		body = model_root.find_child("Body_Standard_Female", true, false) as MeshInstance3D
	if body == null or body.mesh == null or body.skin == null or body.mesh.get_surface_count() == 0:
		return Vector3.INF
	var arrays := body.mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if positions.is_empty() or bones.size() < positions.size() * 4 or weights.size() < positions.size() * 4:
		return Vector3.INF
	var hand_vertices := PackedVector3Array()
	for vertex_index in range(positions.size()):
		var hand_weight := 0.0
		for slot in range(4):
			var bind_slot := int(bones[vertex_index * 4 + slot])
			if bind_slot >= 0 and bind_slot < body.skin.get_bind_count() and body.skin.get_bind_bone(bind_slot) == hand_index:
				hand_weight += float(weights[vertex_index * 4 + slot])
		if hand_weight < 0.50:
			continue
		var skinned_vertex := Vector3.ZERO
		for slot in range(4):
			var bind_slot := int(bones[vertex_index * 4 + slot])
			var weight := float(weights[vertex_index * 4 + slot])
			if weight <= 0.0 or bind_slot < 0 or bind_slot >= body.skin.get_bind_count():
				continue
			var bound_bone := body.skin.get_bind_bone(bind_slot)
			skinned_vertex += (skeleton.get_bone_global_pose(bound_bone) * body.skin.get_bind_pose(bind_slot) * positions[vertex_index]) * weight
		hand_vertices.append(skinned_vertex)
	if hand_vertices.is_empty():
		return Vector3.INF
	var bounds := AABB(hand_vertices[0], Vector3.ZERO)
	for vertex: Vector3 in hand_vertices:
		bounds = bounds.expand(vertex)
	return bounds.get_center()

func _refresh_animation_options() -> void:
	_available_animation_ids.clear()
	for slot: Dictionary in ANIMATION_SLOTS:
		var animation_id: StringName = slot["id"]
		var available: bool = false
		if animation_player != null:
			available = _has_available_weapon_attack() if animation_id == &"attack" else animation_player.has_animation(animation_id)
		_available_animation_ids[animation_id] = available
		var index: int = _animation_index(animation_id)
		if index >= 0:
			animation_option.set_item_disabled(index, str(slot["state"]) == "reserved" or not available)
func _select_fallback_animation() -> void:
	if bool(_available_animation_ids.get(_selected_animation, false)):
		visual_state.animation_id = _selected_animation
		animation_option.select(_animation_index(_selected_animation))
		return
	for slot: Dictionary in ANIMATION_SLOTS:
		var animation_id: StringName = slot["id"]
		if bool(_available_animation_ids.get(animation_id, false)):
			_selected_animation = animation_id
			visual_state.animation_id = animation_id
			animation_option.select(_animation_index(animation_id))
			return
	_selected_animation = &""

func _update_model_ui() -> void:
	if model_label == null:
		return
	var model_data: Dictionary = BODY_MODELS[_body_index]
	var model_kind := "modular equipment pack · 4 face options · 8 hairstyles / 男女獨立"
	model_label.text = "%s   ·   %s" % [str(model_data["label"]), model_kind]
	_update_animation_ui()
	_update_status()

func _update_animation_ui() -> void:
	if animation_state_label == null:
		return
	if animation_player == null:
		animation_state_label.text = "AnimationPlayer：未提供"
		return
	var available: Array[String] = []
	for slot: Dictionary in ANIMATION_SLOTS:
		var animation_id: StringName = slot["id"]
		if bool(_available_animation_ids.get(animation_id, false)):
			available.append(str(animation_id))
	var length: float = _animation_length()
	timeline_slider.max_value = maxf(length, 0.01)
	animation_state_label.text = "AnimationPlayer：已載入\n可用：%s\n目前：%s" % [", ".join(available), str(_selected_animation)]

func _update_status() -> void:
	if status_label == null:
		return
	var body_id: String = str(BODY_MODELS[_body_index]["id"])
	var animation_text: String = str(_selected_animation) if _selected_animation != &"" else "無"
	var total := PART_SLOTS.size() + 1
	status_label.text = "Presentation-only preview · body=%s · animation=%s · parts=%d/%d · 不寫入 GameSession" % [body_id, animation_text, _active_part_count(), total]

func _set_playing(enabled: bool) -> void:
	_is_playing = enabled
	visual_state.playing = enabled
	if play_button != null:
		play_button.set_pressed_no_signal(enabled)
		play_button.text = "暫停" if enabled else "播放"
	_play_selected_animation()

func _play_selected_animation() -> void:
	if animation_player == null or _selected_animation == &"":
		return
	var play_anim: StringName = _selected_animation
	if not animation_player.has_animation(play_anim):
		return
	var animation := animation_player.get_animation(play_anim)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop_toggle == null or loop_toggle.button_pressed else Animation.LOOP_NONE
	animation_player.speed_scale = float(speed_slider.value) if speed_slider != null else 1.0
	visual_state.speed = animation_player.speed_scale
	if animation_player.current_animation != play_anim:
		for node in model_root.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false):
			var armor := node as MeshInstance3D
			for shape in armor.get_blend_shape_count():
				armor.set_blend_shape_value(shape, 0.0)
		for record in _combat_cloth:
			var cloth := record.node as MeshInstance3D
			if is_instance_valid(cloth):
				for shape in cloth.get_blend_shape_count():
					cloth.set_blend_shape_value(shape, 0.0)
		var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D if model_root != null else null
		if skeleton != null:
			skeleton.reset_bone_poses()
		animation_player.play(play_anim)
	if _is_playing:
		animation_player.play(play_anim)
	else:
		animation_player.pause()
	_update_weapon_sheath_state()
	_sync_mount_animation()
	_update_preview_framing()

func _reset_animation() -> void:
	if animation_player == null or _selected_animation == &"":
		return
	var play_anim: StringName = _selected_animation
	if not animation_player.has_animation(play_anim):
		return
	animation_player.play(play_anim)
	animation_player.seek(0.0, true)
	visual_state.animation_time = 0.0
	if mount_horse != null and _is_mounted:
		mount_horse.seek(0.0)
	if not _is_playing:
		animation_player.pause()

func _request_body_selected(index: int) -> void:
	var permitted := int(body_selection_request.call(index)) if body_selection_request.is_valid() else index
	body_option.select(permitted)
	if permitted != _body_index:
		_on_body_selected(permitted)

func _request_part_selected(index: int, part_id: StringName) -> void:
	var option := part_options.get(part_id) as OptionButton
	if option == null or index < 0 or index >= option.item_count:
		return
	if part_selection_request.is_valid():
		var permitted := str(part_selection_request.call(str(part_id), str(option.get_item_metadata(index))))
		for candidate in range(option.item_count):
			if str(option.get_item_metadata(candidate)) == permitted:
				option.select(candidate)
				_on_part_selected(candidate, part_id)
				return
		return
	_on_part_selected(index, part_id)

func _on_body_selected(index: int) -> void:
	_load_body_model(index)

func _on_part_selected(index: int, part_id: StringName) -> void:
	var option := part_options.get(part_id) as OptionButton
	if option == null or index < 0 or index >= option.item_count or option.is_item_disabled(index):
		return
	_apply_part_selection(part_id, index)
	if part_id in [&"weapon", &"shield"] and str(_selected_animation).begins_with("guard"):
		var phase := ""
		for suffix in ["_raise", "_lower", "_break"]:
			if str(_selected_animation).ends_with(suffix):
				phase = suffix
		select_animation_by_id(StringName("guard" + phase))
	if part_id == &"weapon":
		var weapon_opt_id: StringName = StringName(str(option.get_item_metadata(index)))
		if _is_mounted:
			if _selected_animation in [&"ride_attack", &"ride_slash", &"ride_thrust"]:
				var target_ride_anim: StringName = &"ride_thrust" if weapon_opt_id == &"spear_01" else &"ride_slash"
				if _selected_animation != target_ride_anim and bool(_available_animation_ids.get(target_ride_anim, false)):
					select_animation_by_id(target_ride_anim)
		else:
			if _selected_animation != &"attack_jump_heavy" and _is_weapon_attack_animation(_selected_animation):
				var target_anim: StringName = WEAPON_ATTACK_MAP.get(weapon_opt_id, &"attack_unarmed")
				if _selected_animation != target_anim and bool(_available_animation_ids.get(target_anim, false)):
					select_animation_by_id(target_anim)
	_update_parts_footer()
	_update_status()

func _on_animation_selected(index: int) -> void:
	var value: Variant = animation_option.get_item_metadata(index)
	var anim_id := _normalize_animation_id(StringName(str(value)))
	if anim_id == &"attack":
		select_animation_by_id(&"attack")
		return
	if anim_id in [&"ride_idle", &"ride_walk", &"ride_run", &"ride_attack", &"ride_slash", &"ride_thrust"]:
		if not _is_mounted:
			set_mount_enabled(true)
	else:
		if _is_mounted:
			set_mount_enabled(false)
	_selected_animation = anim_id
	visual_state.animation_id = anim_id
	_apply_attack_loop_default()
	_play_selected_animation()
	_update_animation_ui()
	_update_status()

func _on_play_pressed() -> void:
	_set_playing(not _is_playing)

func _on_loop_toggled(_enabled: bool) -> void:
	_play_selected_animation()

func _apply_attack_loop_default() -> void:
	if loop_toggle == null:
		return
	var one_shot := _is_weapon_attack_animation(_selected_animation) or _selected_animation in [
		&"ride_attack", &"ride_slash", &"ride_thrust", &"guard_raise", &"guard_lower",
		&"guard_break", &"get_up", &"rescue", &"reload_bow", &"reload_crossbow", &"down"
	]
	one_shot = one_shot or (str(_selected_animation).begins_with("guard_") and (str(_selected_animation).ends_with("_raise") or str(_selected_animation).ends_with("_lower") or str(_selected_animation).ends_with("_break")))
	if one_shot:
		loop_toggle.set_pressed_no_signal(false)
	elif _selected_animation in [&"idle", &"walk", &"run", &"guard", &"guard_weapon", &"guard_polearm", &"unconscious", &"ride_idle", &"ride_walk", &"ride_run"]:
		# A completed one-shot must not freeze the next sustained pose at its
		# last frame. Otherwise contact geometry depends on prior attack history.
		loop_toggle.set_pressed_no_signal(true)

func _on_speed_changed(value: float) -> void:
	visual_state.speed = value
	if speed_value_label != null:
		speed_value_label.text = "%.2fx" % value
	if animation_player != null:
		animation_player.speed_scale = value
	if mount_horse != null and mount_horse.animation_player != null:
		mount_horse.animation_player.speed_scale = value

func _on_timeline_changed(value: float) -> void:
	if animation_player == null or _selected_animation == &"" or not animation_player.has_animation(_selected_animation):
		return
	animation_player.seek(value, true)
	visual_state.animation_time = value
	if mount_horse != null and _is_mounted:
		var horse_pos := value
		if mount_horse.animation_player != null and mount_horse.animation_player.current_animation != &"":
			var horse_len := mount_horse.animation_player.current_animation_length
			if horse_len > 0.0:
				horse_pos = fposmod(value, horse_len)
		mount_horse.seek(horse_pos)
	if _is_playing:
		animation_player.play(_selected_animation)
	_update_timeline_label(value)
	if _hair_mask_mode == &"auto":
		_update_hair_mask()
	if _is_mounted and mount_horse != null:
		var rider := model_root.find_child("Skeleton3D",true,false) as Skeleton3D
		var boots_option := part_options.get(&"boots") as OptionButton
		var boots_id := StringName(str(boots_option.get_item_metadata(boots_option.selected))) if boots_option != null else &"none"
		mount_horse.update_rider_contacts(rider,_selected_animation in [&"ride_idle",&"ride_walk",&"ride_run"],0.014 if boots_id == &"none" else 0.026)

func set_mount_enabled(enabled: bool) -> void:
	if _is_mounted == enabled:
		return
	_is_mounted = enabled
	visual_state.mounted = enabled
	if mount_toggle != null and mount_toggle.button_pressed != enabled:
		mount_toggle.set_pressed_no_signal(enabled)
	if mount_horse != null:
		mount_horse.visible = enabled
	if enabled:
		_attach_rider_to_mount()
		if not (_selected_animation in [&"ride_walk", &"ride_idle", &"ride_run", &"ride_attack", &"ride_slash", &"ride_thrust"]):
			var target_anim: StringName = &"ride_run" if _selected_animation == &"run" else (&"ride_walk" if _selected_animation == &"walk" else &"ride_idle")
			select_animation_by_id(target_anim)
	else:
		_detach_rider_from_mount()
		if _selected_animation == &"ride_idle":
			select_animation_by_id(&"idle")
		elif _selected_animation == &"ride_walk":
			select_animation_by_id(&"walk")
		elif _selected_animation == &"ride_run":
			select_animation_by_id(&"run")
		elif _selected_animation in [&"ride_attack", &"ride_slash", &"ride_thrust"]:
			select_animation_by_id(&"attack")
	_sync_mount_animation()
	if _is_mounted:
		_calibrate_rider_mount_pose()
	_update_preview_framing()
	_preview_pan = Vector2.ZERO
	_update_preview_display()
	if preview_host != null and preview_host.has_method("_sync_render_projection"):
		preview_host.call("_sync_render_projection")
	_update_status()

func set_mount_coat(coat_id: StringName) -> void:
	_current_mount_coat = coat_id
	if mount_horse != null:
		mount_horse.set_coat(coat_id)
	if mount_coat_option != null:
		for i in range(mount_coat_option.item_count):
			if StringName(str(mount_coat_option.get_item_metadata(i))) == coat_id:
				mount_coat_option.select(i)
				break
	_update_status()

func set_mount_tack_enabled(enabled: bool) -> void:
	_mount_tack_enabled = enabled
	if mount_horse != null:
		mount_horse.set_tack_enabled(enabled)
	if mount_tack_toggle != null and mount_tack_toggle.button_pressed != enabled:
		mount_tack_toggle.set_pressed_no_signal(enabled)

func _on_mount_toggled(enabled: bool) -> void:
	set_mount_enabled(enabled)

func _on_mount_coat_selected(index: int) -> void:
	if mount_coat_option == null or index < 0 or index >= mount_coat_option.item_count:
		return
	var coat_id := StringName(str(mount_coat_option.get_item_metadata(index)))
	set_mount_coat(coat_id)

func _on_mount_tack_toggled(enabled: bool) -> void:
	set_mount_tack_enabled(enabled)

func _sync_mount_animation() -> void:
	if mount_horse == null or not _is_mounted:
		return
	var speed := float(speed_slider.value) if speed_slider != null else 1.0
	if _selected_animation == &"ride_walk":
		mount_horse.play_animation(&"horse_walk", speed)
	elif _selected_animation in [&"ride_run", &"ride_attack", &"ride_slash", &"ride_thrust"]:
		mount_horse.play_animation(&"horse_run", speed)
	else:
		mount_horse.play_animation(&"horse_idle", speed)
	if animation_player != null:
		var pos := animation_player.current_animation_position
		if mount_horse.animation_player != null and mount_horse.animation_player.current_animation != &"":
			var horse_len := mount_horse.animation_player.current_animation_length
			if horse_len > 0.0:
				pos = fposmod(pos, horse_len)
		mount_horse.seek(pos)
		if not _is_playing and mount_horse.animation_player != null:
			mount_horse.animation_player.pause()

func _process(_delta: float) -> void:
	if not visible or animation_player == null or _selected_animation == &"":
		return
	var anim_time: float = animation_player.current_animation_position
	visual_state.animation_time = anim_time
	_update_combat_props()
	_update_scabbard_pose()
	_update_combat_cloth()
	if timeline_slider != null:
		timeline_slider.set_value_no_signal(anim_time)
	_update_timeline_label(anim_time)
	if _hair_mask_mode == &"auto":
		_update_hair_mask()
	if _is_mounted and mount_horse != null:
		var rider := model_root.find_child("Skeleton3D",true,false) as Skeleton3D
		var boots_option := part_options.get(&"boots") as OptionButton
		var boots_id := StringName(str(boots_option.get_item_metadata(boots_option.selected))) if boots_option != null else &"none"
		mount_horse.update_rider_contacts(rider,_selected_animation in [&"ride_idle",&"ride_walk",&"ride_run"],0.014 if boots_id == &"none" else 0.026)

func _update_timeline_label(anim_time: float) -> void:
	if timeline_label == null:
		return
	timeline_label.text = "%.2f / %.2f s" % [anim_time, _animation_length()]

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		var button_index := (event as InputEventMouseButton).button_index
		if button_index == MOUSE_BUTTON_LEFT or button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_preview = false
			_panning_preview = false

func _refresh_part_options() -> void:
	for part: Dictionary in PART_SLOTS:
		var part_id: StringName = part["id"]
		var option := part_options.get(part_id) as OptionButton
		if option == null:
			continue
		if part_id == &"hair":
			option.clear()
			for component: Dictionary in HAIR_OPTIONS[_body_index]:
				option.add_item(str(component["label"]))
				option.set_item_metadata(option.item_count - 1, component["id"])
		option.disabled = false
		var first_available := -1
		for index: int in range(option.item_count):
			var component := _component_definition(part_id, StringName(str(option.get_item_metadata(index))))
			var available := not component.is_empty() and _component_has_nodes(component)
			option.set_item_disabled(index, not available)
			if available and first_available < 0:
				first_available = index
		if first_available < 0:
			option.disabled = true
			continue
		if part_id == &"hair":
			for index in option.item_count:
				if option.get_item_metadata(index) == _hair_selections[_body_index] and not option.is_item_disabled(index):
					first_available = index
					break
		option.select(first_available)
		_apply_part_selection(part_id, first_available)
	_update_parts_footer()

func _apply_part_selection(part_id: StringName, index: int) -> void:
	if model_root == null:
		return
	var option := part_options.get(part_id) as OptionButton
	if option == null or index < 0 or index >= option.item_count:
		return
	var selected_id := StringName(str(option.get_item_metadata(index)))
	if part_id == &"hair":
		_hair_selections[_body_index] = selected_id
	var part := _part_definition(part_id)
	for component: Dictionary in part.get("options", []):
		var selected := StringName(str(component["id"])) == selected_id
		for node in _find_component_nodes(component.get("prefixes", [])):
			(node as Node3D).visible = selected
	_update_weapon_sheath_state()
	_update_full_body_visibility()
	_update_hair_mask()
	_update_lining_fit()

func _update_lining_fit() -> void:
	var outfit_option := part_options.get(&"outfit") as OptionButton
	var armor_option := part_options.get(&"armor") as OptionButton
	if outfit_option == null or armor_option == null or outfit_option.selected < 0 or armor_option.selected < 0:
		return
	var outfit_id := StringName(str(outfit_option.get_item_metadata(outfit_option.selected)))
	var selected := outfit_id == &"outfit_chinese_lining_01"
	var armor_id := StringName(str(armor_option.get_item_metadata(armor_option.selected)))
	var armored := armor_id != &"none"
	var hard_armored := armor_id in [&"armor_iron_01", &"armor_mingguang_01", &"armor_western_iron_01"]
	# The hard-shell morph keeps ease at exposed back gaps; leather retains
	# its original compressed shape. Neither changes the underlying body.
	var compressed := armor_id in [&"armor_light_leather_01", &"armor_chinese_leather_01"]
	for node in model_root.find_children("Outfit_Chinese_Lining_01_*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		for index in mesh.get_blend_shape_count():
			if mesh.mesh.get_blend_shape_name(index) == &"UnderArmor":
				mesh.set_blend_shape_value(index,1.0 if compressed else 0.0)
			elif mesh.mesh.get_blend_shape_name(index) == &"UnderHardArmor":
				mesh.set_blend_shape_value(index,1.0 if hard_armored else 0.0)
		if str(mesh.name).contains("CrossLapel_") or str(mesh.name).ends_with("Hem") or str(mesh.name).ends_with("BackCollar"):
			mesh.visible = selected and not armored
	# These armor choices carry their own cloth sleeves/tunic. The selected
	# lining replaces that layer; restore it when the lining is removed.
	for lining_entry in [
		[&"armor_western_iron_01", "Armor_Western_Iron_01_UnderShirt"],
		[&"armor_iron_01", "Armor_Iron_01_UnderTunic"],
		[&"armor_mingguang_01", "Armor_Mingguang_01_UnderSleeves"],
		[&"armor_mingguang_01", "Armor_Mingguang_01_UnderTunic"],
	]:
		var inner := model_root.find_child(lining_entry[1], true, false) as MeshInstance3D
		if inner != null:
			inner.visible = armor_id == lining_entry[0] and not selected
	# The ordinary female top is entirely covered by these chest plates.
	# Keep its original mesh, restoring it on armor/outfit changes.
	var under_top := model_root.find_child("Outfit_Underlayer_01_Top",true,false) as MeshInstance3D
	if under_top != null:
		under_top.visible = outfit_id == &"outfit_underlayer_01" and not hard_armored
	_update_lining_body_coverage(selected)

func _update_lining_body_coverage(enabled: bool) -> void:
	var body_name := "Body_Standard_Female" if _body_index == 1 else "Body_Standard_Male"
	var body := model_root.find_child(body_name,true,false) as MeshInstance3D
	var shirt := model_root.find_child("Outfit_Chinese_Lining_01_Shirt",true,false) as MeshInstance3D
	var skeleton := model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	if body == null or shirt == null or skeleton == null:
		return
	if not body.has_meta("lining_original_mesh"):
		body.set_meta("lining_original_mesh",body.mesh)
	var original := body.get_meta("lining_original_mesh") as ArrayMesh
	if not enabled:
		body.mesh = original
		return
	if not body.has_meta("lining_covered_mesh"):
		# Only omit faces wholly inside the authored shirt's hem, cuffs and
		# V-neck, with an inward margin. Preserve all vertex/UV/skin data and
		# materials. Undressing restores the exact original mesh resource.
		var covered := ArrayMesh.new()
		var neck := skeleton.get_bone_global_rest(skeleton.find_bone("J_Bip_C_Neck")).origin
		var bounds := shirt.mesh.get_aabb()
		var hem := bounds.position.y + .012
		var cuff := minf(absf(bounds.position.x),absf(bounds.end.x)) - .012
		for surface in original.get_surface_count():
			var arrays := original.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var concealed := PackedByteArray()
			concealed.resize(positions.size())
			for i in positions.size():
				var point := positions[i]
				var top := neck.y - .012
				if point.z > neck.z:
					top = minf(top,neck.y - .090 + absf(point.x)*1.55)
				concealed[i] = int(point.y > hem and point.y < top and absf(point.x) < cuff)
			var visible_indices := PackedInt32Array()
			for i in range(0,indices.size(),3):
				if concealed[indices[i]] != 0 and concealed[indices[i+1]] != 0 and concealed[indices[i+2]] != 0:
					continue
				visible_indices.append_array(indices.slice(i,i+3))
			if visible_indices.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = visible_indices
			covered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			covered.surface_set_material(covered.get_surface_count()-1,original.surface_get_material(surface))
		body.set_meta("lining_covered_mesh",covered)
	body.mesh = body.get_meta("lining_covered_mesh") as ArrayMesh

func _update_weapon_sheath_state() -> void:
	if model_root == null:
		return
	var is_sheathed: bool = _selected_animation in [&"idle", &"walk", &"run", &"ride_idle", &"ride_walk", &"ride_run"]
	is_sheathed = is_sheathed and not combat_ready
	is_sheathed = is_sheathed or _selected_animation == &"rescue"

	# 1. Weapon visibility
	var weapon_opt := part_options.get(&"weapon") as OptionButton
	var weapon_id: StringName = &"none"
	if weapon_opt != null and weapon_opt.selected >= 0:
		weapon_id = StringName(str(weapon_opt.get_item_metadata(weapon_opt.selected)))

	for component: Dictionary in _part_definition(&"weapon").get("options", []):
		var is_selected_weapon := StringName(str(component["id"])) == weapon_id and weapon_id != &"none"
		for node in _find_component_nodes(component.get("prefixes", [])):
			var mesh_node := node as Node3D
			if mesh_node == null:
				continue
			var node_name := str(mesh_node.name)
			if not is_selected_weapon:
				mesh_node.visible = false
				continue

			if node_name.contains("_Scabbard_"):
				mesh_node.visible = true
			elif node_name.contains("_Sheathed_") or node_name.contains("_Holstered_"):
				mesh_node.visible = is_sheathed
			else:
				mesh_node.visible = not is_sheathed

	# 2. Shield visibility
	var shield_opt := part_options.get(&"shield") as OptionButton
	var shield_id: StringName = &"none"
	if shield_opt != null and shield_opt.selected >= 0:
		shield_id = StringName(str(shield_opt.get_item_metadata(shield_opt.selected)))

	var is_ranged_attack := _selected_animation in [&"attack_bow", &"attack_crossbow", &"reload_bow", &"reload_crossbow"]
	# Mounted slash/thrust clips explicitly use the rider's off-hand. Keep the
	# selected shield in that hand; only idle/travel and ranged attacks holster it.
	var shield_is_holstered := is_sheathed or is_ranged_attack

	for component: Dictionary in _part_definition(&"shield").get("options", []):
		var is_selected_shield := StringName(str(component["id"])) == shield_id and shield_id != &"none"
		for node in _find_component_nodes(component.get("prefixes", [])):
			var mesh_node := node as Node3D
			if mesh_node == null:
				continue
			var node_name := str(mesh_node.name)
			if not is_selected_shield:
				mesh_node.visible = false
				continue

			if node_name.contains("_Holstered_"):
				mesh_node.visible = shield_is_holstered
			else:
				mesh_node.visible = not shield_is_holstered

func is_selected_shield_held() -> bool:
	if model_root == null:
		return false
	var shield_opt := part_options.get(&"shield") as OptionButton
	if shield_opt == null or shield_opt.selected < 0:
		return false
	var shield_id := StringName(str(shield_opt.get_item_metadata(shield_opt.selected)))
	if shield_id == &"none":
		return false
	var component := _component_definition(&"shield", shield_id)
	for node in _find_component_nodes(component.get("prefixes", [])):
		var mesh_node := node as Node3D
		if mesh_node != null and mesh_node.is_visible_in_tree() and not str(mesh_node.name).contains("_Holstered_"):
			return true
	return false

func is_selected_weapon_visible() -> bool:
	if model_root == null:
		return false
	var weapon_opt := part_options.get(&"weapon") as OptionButton
	if weapon_opt == null or weapon_opt.selected < 0:
		return false
	var weapon_id := StringName(str(weapon_opt.get_item_metadata(weapon_opt.selected)))
	if weapon_id == &"none":
		return false
	var component := _component_definition(&"weapon", weapon_id)
	for node in _find_component_nodes(component.get("prefixes", [])):
		var mesh_node := node as Node3D
		if mesh_node != null and mesh_node.is_visible_in_tree():
			var node_name := str(mesh_node.name)
			if not node_name.contains("_Holstered_") and not node_name.contains("_Sheathed_"):
				return true
	return false

func _update_full_body_visibility() -> void:
	if model_root == null or _body_index != 0:
		return
	var full_body := model_root.find_child("Body_Standard_Male_Full", true, false) as MeshInstance3D
	if full_body == null:
		return
	for part_id: StringName in [&"outfit", &"armor", &"cape", &"boots"]:
		var option := part_options.get(part_id) as OptionButton
		if option == null or option.selected < 0:
			full_body.visible = false
			return
		var selected_id := StringName(str(option.get_item_metadata(option.selected)))
		if selected_id != &"none":
			full_body.visible = false
			return
	full_body.visible = true

func clear_hair_node_lookup_cache() -> void:
	_hair_nodes.clear()
	_hair_nodes_model_id = 0
	_hair_nodes_id = &""

func _active_hair_nodes(hair_id: StringName) -> Array[MeshInstance3D]:
	var started := Time.get_ticks_usec() if hair_node_lookup_profile_enabled else 0
	var model_id := model_root.get_instance_id()
	var hit := hair_node_lookup_cache_enabled and model_id == _hair_nodes_model_id and hair_id == _hair_nodes_id
	var nodes: Array[MeshInstance3D] = []
	if hit:
		nodes = _hair_nodes
	if not hit:
		var component := _component_definition(&"hair", hair_id)
		for node in _find_component_nodes(component.get("prefixes", [])):
			if node is MeshInstance3D:
				nodes.append(node as MeshInstance3D)
		if hair_node_lookup_cache_enabled:
			_hair_nodes = nodes
			_hair_nodes_model_id = model_id
			_hair_nodes_id = hair_id
	if hair_node_lookup_profile_enabled:
		hair_node_lookup_profile.calls += 1
		hair_node_lookup_profile.hits += int(hit)
		hair_node_lookup_profile.searches += int(not hit)
		hair_node_lookup_profile.lookup_usec += Time.get_ticks_usec() - started
	# Private iteration only. Hair hierarchy is fixed after body loading; an
	# explicit same-root hierarchy edit must clear this list before its next use.
	return nodes

func _update_hair_mask() -> void:
	if model_root == null:
		return
	var helmet_opt := part_options.get(&"helmet") as OptionButton
	var has_helmet: bool = helmet_opt != null and helmet_opt.selected >= 0 and StringName(str(helmet_opt.get_item_metadata(helmet_opt.selected))) != &"none"

	var hair_opt := part_options.get(&"hair") as OptionButton
	var hair_id: StringName = StringName(str(hair_opt.get_item_metadata(hair_opt.selected))) if hair_opt != null and hair_opt.selected >= 0 else &"none"
	var has_hair: bool = hair_id != &"none"

	var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var inv_head := Transform3D.IDENTITY
	if skeleton != null:
		var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
		if head_bone_idx >= 0:
			var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
			inv_head = head_world.affine_inverse()

	var active_hair_nodes := _active_hair_nodes(hair_id)

	if not has_helmet or not has_hair:
		for mesh_node in active_hair_nodes:
			mesh_node.visible = has_hair
			_set_mesh_mask_enabled(mesh_node, false, inv_head)
		return

	var helmet_id: StringName = StringName(str(helmet_opt.get_item_metadata(helmet_opt.selected))) if has_helmet else &"none"

	match _hair_mask_mode:
		&"hide":
			for mesh_node in active_hair_nodes:
				mesh_node.visible = false
				_set_mesh_mask_enabled(mesh_node, false, inv_head, helmet_id)
		&"off":
			for mesh_node in active_hair_nodes:
				mesh_node.visible = true
				_set_mesh_mask_enabled(mesh_node, false, inv_head, helmet_id)
		&"auto":
			for mesh_node in active_hair_nodes:
				mesh_node.visible = true
				_set_mesh_mask_enabled(mesh_node, true, inv_head, helmet_id)

func _set_mesh_mask_enabled(mesh_node: MeshInstance3D, enabled: bool, inv_head: Transform3D, helmet_id: StringName = &"") -> void:
	if mesh_node == null or mesh_node.mesh == null:
		return

	if _hair_mask_shader == null:
		_hair_mask_shader = Shader.new()
		_hair_mask_shader.code = HAIR_CLIP_MASK_SHADER

	# Measured in Head-bone space; current male/female rims share these heights.
	var brow_y := 0.113
	if helmet_id in [&"helmet_iron_01", &"helmet_steel_01"]:
		brow_y = 0.098
	elif helmet_id == &"helmet_western_iron_01":
		brow_y = 0.095
	elif helmet_id == &"helmet_chinese_leather_01":
		brow_y = 0.110
	var node_name := str(mesh_node.name)

	for surface_index in range(mesh_node.mesh.get_surface_count()):
		var existing_override := mesh_node.get_surface_override_material(surface_index) as ShaderMaterial
		if existing_override == null or existing_override.shader != _hair_mask_shader:
			var source_mat := mesh_node.get_active_material(surface_index) as BaseMaterial3D
			var mask_mat := ShaderMaterial.new()
			mask_mat.shader = _hair_mask_shader
			if source_mat != null:
				mask_mat.set_shader_parameter("base_color", source_mat.albedo_color)
				if source_mat.albedo_texture != null:
					mask_mat.set_shader_parameter("albedo_texture", source_mat.albedo_texture)
					mask_mat.set_shader_parameter("has_texture", true)
				else:
					mask_mat.set_shader_parameter("has_texture", false)
			existing_override = mask_mat
			mesh_node.set_surface_override_material(surface_index, mask_mat)

		existing_override.set_shader_parameter("mask_enabled", enabled)
		existing_override.set_shader_parameter("dye_enabled", _hair_dye_enabled and not node_name.ends_with("_Band"))
		existing_override.set_shader_parameter("dye_color", _hair_dye_color)
		existing_override.set_shader_parameter("inv_head_transform", inv_head)
		existing_override.set_shader_parameter("brow_cut_y", brow_y)
		existing_override.set_shader_parameter("tuck_hair_piece", node_name.ends_with("_Buns") or node_name.ends_with("_Loose") or node_name.ends_with("_Band"))

func _apply_equipment_style() -> void:
	if model_root == null:
		return
	if _equipment_outline_material == null:
		var shader := Shader.new()
		shader.code = EQUIPMENT_OUTLINE_SHADER
		_equipment_outline_material = ShaderMaterial.new()
		_equipment_outline_material.shader = shader
	if _equipment_toon_shader == null:
		_equipment_toon_shader = Shader.new()
		_equipment_toon_shader.code = EQUIPMENT_TOON_SHADER
	for node: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var node_name := str(mesh_node.name)
		if node_name.begins_with("Cape_Chinese_01_") or node_name.begins_with("Armor_Chinese_Leather_01_") or node_name.begins_with("Helmet_Mingguang_01_") or node_name.begins_with("Helmet_Chinese_Leather_01_") or node_name.begins_with("Outfit_Chinese_Lining_01_") or node_name.begins_with("Boots_Chinese_Leather_01_"):
			# Preserve authored texture materials and fine engraved/perforated edges.
			mesh_node.material_overlay = null
			continue
		if _is_equipment_node(str(mesh_node.name)):
			# Inverted hulls on thin skin-fitted layers cut black seams through them.
			var fitted_layer := node_name.begins_with("Outfit_Underlayer_01") or node_name.begins_with("Armor_Light_Leather_01") or node_name.contains("_Underlayer_")
			mesh_node.material_overlay = null if fitted_layer else _equipment_outline_material
			_apply_toon_surfaces(mesh_node)

func _apply_toon_surfaces(mesh_node: MeshInstance3D) -> void:
	if mesh_node.mesh == null:
		return
	for surface_index: int in range(mesh_node.mesh.get_surface_count()):
		var source_material := mesh_node.get_active_material(surface_index) as BaseMaterial3D
		if source_material == null:
			continue
		var toon_material := ShaderMaterial.new()
		toon_material.shader = _equipment_toon_shader
		toon_material.set_shader_parameter("base_color", source_material.albedo_color)
		toon_material.set_shader_parameter("base_metallic", source_material.metallic)
		toon_material.set_shader_parameter("base_roughness", source_material.roughness)
		mesh_node.set_surface_override_material(surface_index, toon_material)

func _is_equipment_node(node_name: String) -> bool:
	for token: String in OUTLINE_DETAIL_EXCLUSIONS:
		if node_name.contains(token):
			return false
	for prefix: String in EQUIPMENT_PREFIXES:
		if node_name == prefix or node_name.begins_with(prefix + "_") or node_name.begins_with(prefix + "."):
			return true
	return false

func _update_parts_footer() -> void:
	if parts_footer == null:
		return
	var active := _active_part_count()
	var total := PART_SLOTS.size() + 1
	if active >= total:
		parts_footer.text = "接入狀態  %d / %d\nBody、Face、頭髮、頭盔、內衣、皮革輕甲、披風、武器、盾牌、皮靴皆為實際部件。" % [total, total]
	else:
		parts_footer.text = "接入狀態  %d / %d\n未使用的部件欄位可選 None / 無。" % [active, total]

func _active_part_count() -> int:
	var count := 1
	for part: Dictionary in PART_SLOTS:
		var option := part_options.get(part["id"]) as OptionButton
		if option != null and not option.disabled and option.selected >= 0 and StringName(str(option.get_item_metadata(option.selected))) != &"none":
			count += 1
	return count

func _part_definition(part_id: StringName) -> Dictionary:
	if part_id == &"hair":
		return {"id": &"hair", "label": "Hair / 頭髮", "options": HAIR_OPTIONS[_body_index]}
	for part: Dictionary in PART_SLOTS:
		if StringName(str(part["id"])) == part_id:
			return part
	return {}

func _component_definition(part_id: StringName, component_id: StringName) -> Dictionary:
	if part_id == &"hair":
		component_id = _canonical_hair_id(component_id)
	var part := _part_definition(part_id)
	for component: Dictionary in part.get("options", []):
		if StringName(str(component["id"])) == component_id:
			return component
	return {}

func _component_has_nodes(component: Dictionary) -> bool:
	if StringName(str(component.get("id", ""))) == &"none":
		return true
	return not _find_component_nodes(component.get("prefixes", [])).is_empty()

func _find_component_nodes(prefixes: Array) -> Array:
	var result: Array = []
	if model_root == null:
		return result
	for node: Node in model_root.find_children("*", "Node3D", true, false):
		var node_name := str(node.name)
		for prefix: Variant in prefixes:
			var prefix_text := str(prefix)
			if node_name == prefix_text or node_name.begins_with(prefix_text + "_") or node_name.begins_with(prefix_text + "."):
				result.append(node)
				break
	return result

func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_set_preview_zoom(_preview_zoom * PREVIEW_ZOOM_STEP, button.position)
			get_viewport().set_input_as_handled()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_set_preview_zoom(_preview_zoom / PREVIEW_ZOOM_STEP, button.position)
			get_viewport().set_input_as_handled()
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging_preview = button.pressed
			_panning_preview = false
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning_preview = button.pressed
			_dragging_preview = false
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _dragging_preview:
		var motion := event as InputEventMouseMotion
		_preview_yaw = fmod(_preview_yaw + deg_to_rad(motion.relative.x * 0.55), TAU)
		_preview_pitch = clampf(_preview_pitch + deg_to_rad(motion.relative.y * 0.20), deg_to_rad(-14.0), deg_to_rad(14.0))
		_apply_preview_rotation()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _panning_preview:
		var pan_motion := event as InputEventMouseMotion
		_preview_pan += pan_motion.relative
		_update_preview_display()
		get_viewport().set_input_as_handled()

func _apply_preview_rotation() -> void:
	if preview_pivot == null:
		return
	var requested_rotation := Vector3(_preview_pitch, PI + _preview_yaw, 0.0)
	if not exact_preview_rotation_guard_enabled or preview_pivot.rotation != requested_rotation:
		preview_pivot.rotation = requested_rotation
	if _hair_mask_mode == &"auto":
		_update_hair_mask()

func _animation_length() -> float:
	if animation_player == null or _selected_animation == &"":
		return 0.0
	var play_anim: StringName = _selected_animation
	if not animation_player.has_animation(play_anim):
		return 0.0
	var animation := animation_player.get_animation(play_anim)
	return animation.length if animation != null else 0.0

func _animation_index(animation_id: StringName) -> int:
	var target_id := _normalize_animation_id(animation_id)
	for index: int in range(animation_option.item_count if animation_option != null else 0):
		if StringName(str(animation_option.get_item_metadata(index))) == target_id:
			return index
	return -1

func _add_option_row(parent: VBoxContainer, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 48.0)
	var label := _new_label(label_text, 18, Color("d8e0ea"))
	label.custom_minimum_size = Vector2(122.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var option := OptionButton.new()
	option.add_theme_font_size_override("font_size", _ui_font_size(20))
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(0.0, 44.0)
	option.get_popup().add_theme_font_size_override("font_size", _ui_font_size(20))
	row.add_child(option)
	parent.add_child(row)
	return option

func _make_panel(parent: Control, minimum_size: Vector2, scrollable: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	if minimum_size.x <= 0.0:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("111b28"), Color("2c3e55")))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	if scrollable:
		var scroll := ScrollContainer.new()
		scroll.name = "SidebarScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(scroll)
		scroll.add_child(layout)
	else:
		margin.add_child(layout)
	return layout

func _new_button(button_text: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = minimum_size
	button.add_theme_font_size_override("font_size", _ui_font_size(20))
	return button

func _calculate_ui_font_scale() -> float:
	var design_width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var window_width := float(DisplayServer.window_get_size().x)
	if design_width <= 0.0 or window_width <= 0.0:
		return 1.0
	return clampf(design_width / window_width, 1.0, 1.6)

func _ui_font_size(font_size: int) -> int:
	# Titles keep their authored hierarchy; body controls receive the local
	# compensation needed by the 2560-design to 1600-window presentation.
	return font_size if font_size > 20 else maxi(font_size, roundi(float(font_size) * _ui_font_scale))

func _new_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _ui_font_size(font_size))
	label.add_theme_color_override("font_color", color)
	return label

func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
