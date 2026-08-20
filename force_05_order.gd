extends Node3D

# FORCE 05 — Order（秩序）Step 1–4: 门牌系统 + 收集交互 + 假影子 + 427 锁定 + 抹除交互

const PLATE_COUNT := 17

const PLATE_NUMBERS := [
	"83",  "614", "7",   "427", "291", "12",  "48",  "937",
	"5",   "362", "64",  "153", "28",  "741", "96",  "503", "17",
]
const PLAYER_PLATE_INDEX  := 3
const PLAYER_NUMBER_CHARS := ["4", "2", "7"]   # 逐位锁定用

const PLATE_BASE_POS := [
	Vector3(-3.5, 1.80,  2.5),   # 83
	Vector3( 5.5, 1.60, -7.0),   # 614
	Vector3(-1.0, 2.00, -8.5),   # 7
	Vector3( 6.5, 1.70,-36.0),   # 427  ← 最深处
	Vector3(-6.5, 1.90,-13.5),   # 291
	Vector3( 2.5, 1.55,-18.0),   # 12
	Vector3(-4.0, 1.80,-21.5),   # 48
	Vector3( 6.0, 2.00,-10.5),   # 937
	Vector3( 3.0, 1.70,-25.0),   # 5
	Vector3(-7.0, 1.85,-29.0),   # 362
	Vector3(-2.5, 1.90,-33.0),   # 64
	Vector3( 5.5, 2.00,-15.5),   # 153
	Vector3(-5.5, 1.60,-39.0),   # 28
	Vector3( 1.0, 1.75, -5.5),   # 741
	Vector3( 9.0, 1.85,-23.0),   # 96
	Vector3(-8.5, 2.00,-12.5),   # 503
	Vector3( 4.0, 1.65,-31.0),   # 17
]

# ── Step 1 参数 ──────────────────────────────────────────────────
const PLATE_VISUAL_SIZE    := Vector3(1.80, 3.60, 0.04)
const PLATE_COLLISION_SIZE := Vector3(1.80, 3.60, 0.30)
const ROT_Y_RANGE     := 14.0
const ROT_Z_RANGE     :=  4.0
const BOB_AMPLITUDE   := 0.07
const BOB_SPEED       := 0.85
const PULSE_SPEED_MIN := 0.40
const PULSE_SPEED_MAX := 1.10
const PULSE_ALPHA_MIN := 0.62
const PULSE_ALPHA_MAX := 1.00

# ── Step 2 参数 ──────────────────────────────────────────────────
const COLLECT_RADIUS    := 3.2
const STAR_THRESHOLD    := 10
const STAR_FLY_DURATION := 0.55
const JAR_OFFSET        := Vector3(0.38, 0.85, 0.12)

# ── 区域判定（地毯覆盖范围，局部坐标）──────────────────────────────
# 基于 carpet 中心 (0.25, 0, -18.25) ± half-size (12, 0, 24)，留 2m 余量
const AREA_X_MIN := -14.0
const AREA_X_MAX :=  15.0
const AREA_Z_MIN := -45.0
const AREA_Z_MAX :=   8.0

# ── Step 3 参数 ──────────────────────────────────────────────────
const SHADOW_STRETCH_DIST := 35.0   # 此距离内开始拉伸（米）
const SHADOW_MAX_STRETCH  :=  2.20  # 最大拉伸倍数
# 427 锁定距离
const LOCK_RANGE_START :=  20.0  # 进入此距离开始闪烁
const LOCK_DIST_FULL   :=   4.0  # 完全锁定 → 停止闪烁，显示 F 键
# 427 闪烁间隔（远端极稀，近端仍保持缓慢，严守人眼可感知下限）
const FLICKER_INTERVAL_FAR_MIN  := 14.0   # 远端最短间隔（秒）
const FLICKER_INTERVAL_FAR_MAX  := 28.0
const FLICKER_INTERVAL_NEAR_MIN :=  7.0   # 人眼可感知下限（绝不低于此值）
const FLICKER_INTERVAL_NEAR_MAX := 14.0
# 非 427 门牌近距离闪烁
const OTHER_FLICKER_DIST    := 10.0
const OTHER_FLICKER_INT_MIN := 10.0   # 人眼可感知最低阈值
const OTHER_FLICKER_INT_MAX := 22.0
# 距离亮度系统
const BRIGHTNESS_MAX_DIST := 35.0    # 超过此距离降至最低亮度
const BRIGHTNESS_MIN      :=  0.20   # 远处最低亮度
const BRIGHTNESS_427      :=  2.80   # 427 固定超亮（HDR）

# ── Step 1 变量 ──────────────────────────────────────────────────
var _plates       : Array = []
var _labels       : Array = []
var _bob_phases   : Array = []
var _pulse_speeds : Array = []
var _pulse_phases : Array = []
var _plate_mat    : ShaderMaterial

# ── Step 2 变量 ──────────────────────────────────────────────────
var _areas      : Array = []
var _hints      : Array = []
var _collected  : Array = []
var _near_plate : int   = -1
var star_count  : int   = 0
var _player     : Node3D
var _jar_root   : Node3D
var _jar_label  : Label3D

# ── Step 3 变量 ──────────────────────────────────────────────────
var _shadow_mesh   : MeshInstance3D
# 427 锁定状态：0=IDLE  1=FLICKERING  2=LOCKED
var _lock_state    : int = 0
var _f_hint        : Label3D
# per-plate 闪烁状态
var _flicker_next_t : Array = []  # Array[float]  距下次闪烁的倒计时
var _is_flickering  : Array = []  # Array[bool]   当前是否处于闪烁动画中

# ── Step 4 变量 ──────────────────────────────────────────────────
var _shadow_label   : Label3D        # 地面影子上的 427 数字
var _shadow_hint    : Label3D        # [Q] 抹除提示
var _erase_attempts : int   = 0      # 0 / 1 / 2，上限 2 次
var _vignette_layer : CanvasLayer
var _vignette_rect  : ColorRect
var _vignette_mat   : ShaderMaterial
var _ending_triggered : bool = false  # 防止结局重复触发


func _ready() -> void:
	_setup_plate_material()
	_spawn_plates()
	_create_carpet()
	await get_tree().process_frame
	_find_player()
	_create_jar()
	_create_shadow()
	_create_vignette()
	_register_keys()


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		push_warning("[order] player not found")


func _register_keys() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("interact", ev)
	if not InputMap.has_action("follow"):
		InputMap.add_action("follow")
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_F
		InputMap.action_add_event("follow", ev2)
	if not InputMap.has_action("erase"):
		InputMap.add_action("erase")
		var ev3 := InputEventKey.new()
		ev3.keycode = KEY_Q
		InputMap.action_add_event("erase", ev3)


# =========================
# 罐子
# =========================

func _create_jar() -> void:
	_jar_root = Node3D.new()
	_jar_root.name = "StarJar"

	var body := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = 0.10
	cyl.bottom_radius = 0.12
	cyl.height        = 0.22
	body.mesh = cyl
	var jar_mat := StandardMaterial3D.new()
	jar_mat.albedo_color = Color(0.85, 0.95, 1.00, 0.35)
	jar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jar_mat.roughness    = 0.10
	body.material_override = jar_mat
	_jar_root.add_child(body)

	var lid   := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.07
	torus.outer_radius = 0.13
	lid.mesh = torus
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.75, 0.88, 0.95, 0.55)
	lid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lid_mat.roughness    = 0.15
	lid.material_override = lid_mat
	lid.position.y = 0.12
	_jar_root.add_child(lid)

	_jar_label = Label3D.new()
	_jar_label.text      = "0"
	_jar_label.font_size = 36
	_jar_label.modulate  = Color(1.0, 0.90, 0.20, 0.85)
	_jar_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_jar_label.position  = Vector3(0.0, 0.28, 0.0)
	_jar_root.add_child(_jar_label)

	add_child(_jar_root)


# =========================
# 假影子（Step 3）
# =========================

func _create_shadow() -> void:
	_shadow_mesh = MeshInstance3D.new()
	_shadow_mesh.name = "FakeShadow"

	var plane     := PlaneMesh.new()
	plane.size     = Vector2(1.20, 0.90)   # 宽 X，深 Z（拉伸方向）
	_shadow_mesh.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness    = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mesh.material_override = mat

	# 独立图层，避免参与全局阴影计算
	_shadow_mesh.set_layer_mask_value(1, true)
	_shadow_mesh.set_layer_mask_value(2, false)

	add_child(_shadow_mesh)
	_create_shadow_label()


func _create_shadow_label() -> void:
	var gothic_font: Font = load("res://fonts/UnifrakturMaguntia.ttf") if \
		ResourceLoader.exists("res://fonts/UnifrakturMaguntia.ttf") else null

	_shadow_label = Label3D.new()
	_shadow_label.name = "ShadowNumber427"
	_shadow_label.text = "427"
	_shadow_label.font_size = 120
	_shadow_label.modulate  = Color(0.62, 0.38, 0.10, 0.92)   # 琥珀褐，在暗影上可见
	_shadow_label.rotation_degrees.x = -90.0                   # 平铺于地面
	if gothic_font:
		_shadow_label.font = gothic_font
	add_child(_shadow_label)

	_shadow_hint = Label3D.new()
	_shadow_hint.name = "ShadowHint"
	_shadow_hint.text = "[Q] 擦除"
	_shadow_hint.font_size = 72
	_shadow_hint.modulate        = Color(0.92, 0.60, 0.18, 0.90)  # 褐金
	_shadow_hint.outline_size    = 6
	_shadow_hint.outline_modulate = Color(0.15, 0.08, 0.02, 0.95) # 深褐描边，提升可读性
	_shadow_hint.billboard       = BaseMaterial3D.BILLBOARD_ENABLED
	_shadow_hint.no_depth_test   = true
	_shadow_hint.font            = _make_cjk_font()
	add_child(_shadow_hint)


func _update_shadow() -> void:
	if _player == null or not is_instance_valid(_shadow_mesh):
		return
	if _collected[PLAYER_PLATE_INDEX]:
		_shadow_mesh.visible = false
		if is_instance_valid(_shadow_label): _shadow_label.visible = false
		if is_instance_valid(_shadow_hint):  _shadow_hint.visible  = false
		return

	if not _player_in_area():
		_shadow_mesh.visible = false
		if is_instance_valid(_shadow_label): _shadow_label.visible = false
		if is_instance_valid(_shadow_hint):  _shadow_hint.visible  = false
		return

	var p    : Vector3 = _player.global_position
	var p427 : Vector3 = (_plates[PLAYER_PLATE_INDEX] as Node3D).global_position
	var to_427 := Vector3(p427.x - p.x, 0.0, p427.z - p.z)
	var dist   := to_427.length()

	_shadow_mesh.global_position = Vector3(p.x, 0.02, p.z)

	if dist > 0.5:
		# 朝向 427
		_shadow_mesh.rotation.y = atan2(to_427.x, to_427.z)
		# 距离越近，拉伸越明显
		var t: float = 1.0 - clamp(dist / SHADOW_STRETCH_DIST, 0.0, 1.0)
		var stretch: float = lerp(1.0, SHADOW_MAX_STRETCH, t)
		_shadow_mesh.scale = Vector3(1.0, 1.0, stretch)
	else:
		_shadow_mesh.scale = Vector3(1.0, 1.0, 1.0)

	# 影子编号 / [Q] 提示随玩家移动
	if is_instance_valid(_shadow_label):
		_shadow_label.global_position = Vector3(p.x, 0.04, p.z)
	if is_instance_valid(_shadow_hint):
		_shadow_hint.global_position = Vector3(p.x, 1.20, p.z)
		_shadow_hint.visible         = _erase_attempts < 2


# =========================
# 闪烁核心（Step 3）
# =========================

# 触发一次"老灯管"式闪烁：快速暗下，短暂停留，缓慢恢复
func _trigger_flicker(idx: int) -> void:
	if _is_flickering[idx] or _collected[idx]:
		return
	if not is_instance_valid(_labels[idx]):
		return
	_is_flickering[idx] = true
	var label := _labels[idx] as Label3D
	var dim_to  : float = randf_range(0.02, 0.18)   # 几乎熄灭
	var dim_dur : float = randf_range(0.90, 1.40)    # 暗下去的速度
	var hold    : float = randf_range(0.40, 0.80)    # 停在暗处
	var recover : float = randf_range(1.80, 3.00)    # 缓慢恢复
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", dim_to, dim_dur)
	tw.tween_interval(hold)
	tw.tween_property(label, "modulate:a", 1.0, recover).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _is_flickering[idx] = false)


# =========================
# 427 锁定逻辑（Step 3）
# =========================

func _update_427_lock(delta: float) -> void:
	if _collected[PLAYER_PLATE_INDEX] or _lock_state == 2:
		return

	var p    : Vector3 = _player.global_position
	var p427 : Vector3 = (_plates[PLAYER_PLATE_INDEX] as Node3D).global_position
	var dist := p.distance_to(p427)

	if dist > LOCK_RANGE_START:
		if _lock_state != 0:
			_lock_state = 0
		return

	# 完全锁定
	if dist <= LOCK_DIST_FULL:
		_lock_state = 2
		(_labels[PLAYER_PLATE_INDEX] as Label3D).modulate.a = 1.0
		_f_hint.modulate.a = 0.90
		print("[order] 427 fully locked — F key available")
		return

	# 闪烁中：根据距离插值计算本次间隔
	_lock_state = 1
	var t: float = 1.0 - clamp(dist / LOCK_RANGE_START, 0.0, 1.0)
	var int_min: float = lerp(FLICKER_INTERVAL_FAR_MIN, FLICKER_INTERVAL_NEAR_MIN, t)
	var int_max: float = lerp(FLICKER_INTERVAL_FAR_MAX, FLICKER_INTERVAL_NEAR_MAX, t)

	_flicker_next_t[PLAYER_PLATE_INDEX] -= delta
	if _flicker_next_t[PLAYER_PLATE_INDEX] <= 0.0:
		_trigger_flicker(PLAYER_PLATE_INDEX)
		_flicker_next_t[PLAYER_PLATE_INDEX] = randf_range(int_min, int_max)


# =========================
# 非 427 门牌近距离闪烁（Step 3）
# =========================

func _update_other_flicker(delta: float) -> void:
	if _player == null:
		return
	for i in PLATE_COUNT:
		if i == PLAYER_PLATE_INDEX or _collected[i]:
			continue
		var dist := _player.global_position.distance_to((_plates[i] as Node3D).global_position)
		if dist > OTHER_FLICKER_DIST:
			continue
		_flicker_next_t[i] -= delta
		if _flicker_next_t[i] <= 0.0:
			_trigger_flicker(i)
			_flicker_next_t[i] = randf_range(OTHER_FLICKER_INT_MIN, OTHER_FLICKER_INT_MAX)


# =========================
# 地毯（装饰）
# =========================

func _create_carpet() -> void:
	var carpet := MeshInstance3D.new()
	carpet.name = "Carpet"

	# 覆盖所有门牌：X -8.5~9.0 → 宽 24，Z -39.0~2.5 → 深 48，各留 3 单位边距
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 48.0)
	carpet.mesh = plane

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled,
            diffuse_lambert, specular_disabled;

uniform vec4  color_a    : source_color = vec4(0.88, 0.72, 0.12, 1.0); // 暖黄格
uniform vec4  color_b    : source_color = vec4(0.30, 0.14, 0.04, 1.0); // 深褐格
uniform vec4  color_edge : source_color = vec4(0.52, 0.28, 0.06, 1.0); // 边框金褐
uniform float border     = 0.025; // 边框宽度（UV 比例）

void fragment() {
	float b = border;
	bool in_border = UV.x < b || UV.x > 1.0 - b ||
	                 UV.y < b || UV.y > 1.0 - b;

	// 用世界比例保证格子接近正方形：宽 24 格 / 深 48 格 → 每格 1m
	vec2 uv_inner = (UV - b) / (1.0 - 2.0 * b);
	vec2 t        = floor(uv_inner * vec2(24.0, 48.0));
	float checker = mod(t.x + t.y, 2.0);

	vec3 col = in_border
		? color_edge.rgb
		: mix(color_b.rgb, color_a.rgb, checker);

	float noise = fract(sin(dot(UV * 120.0, vec2(12.9898, 78.233))) * 43758.5);
	col = mix(col, col * 0.88, noise * 0.18);

	ALBEDO    = col;
	ROUGHNESS = 0.92;
	METALLIC  = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	carpet.material_override = mat

	# 中心对齐门牌群（X≈0.25, Z≈-18.25），Y=0.008 低于影子（0.02）
	carpet.position = Vector3(0.25, 0.008, -18.25)
	add_child(carpet)


# =========================
# 工具
# =========================

# 玩家是否在地毯区域内（局部坐标矩形判定）
func _player_in_area() -> bool:
	if _player == null:
		return false
	var lp := to_local(_player.global_position)
	return lp.x > AREA_X_MIN and lp.x < AREA_X_MAX \
		and lp.z > AREA_Z_MIN and lp.z < AREA_Z_MAX


# 返回能渲染中文的 SystemFont（Windows 优先微软雅黑）
func _make_cjk_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei", "SimHei", "PingFang SC",
		"WenQuanYi Micro Hei", "Noto Sans CJK SC", "Arial Unicode MS"
	])
	return f


# =========================
# 门牌生成
# =========================

func _setup_plate_material() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4  plate_color    : source_color = vec4(0.28, 0.16, 0.08, 0.92);
uniform vec4  glow_color     : source_color = vec4(0.42, 0.24, 0.10, 1.00);
uniform float glow_width     = 0.10;
uniform float glow_intensity = 1.6;

float hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.35));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i),                  hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float glow = 1.0 - smoothstep(0.0, glow_width, edge);

	float wear = noise(UV * 6.0) * 0.55 + noise(UV * 14.0) * 0.25;
	vec3 worn  = plate_color.rgb * (1.0 - wear * 0.30);

	float crack = smoothstep(0.72, 0.76, noise(UV * 22.0));
	worn = mix(worn, worn * 0.55, crack * 0.5);

	ALBEDO    = mix(worn, glow_color.rgb, glow * glow_intensity);
	ALPHA     = mix(plate_color.a - wear * 0.06, 0.92, glow);
	EMISSION  = glow_color.rgb * glow * 0.38;
	ROUGHNESS = mix(0.85, 0.50, glow) + wear * 0.10;
	METALLIC  = 0.04;
}
"""
	_plate_mat = ShaderMaterial.new()
	_plate_mat.shader = shader


func _spawn_plates() -> void:
	_collected.resize(PLATE_COUNT)
	_collected.fill(false)
	_flicker_next_t.resize(PLATE_COUNT)
	_is_flickering.resize(PLATE_COUNT)
	_is_flickering.fill(false)
	# 错开各门牌的第一次闪烁，避免同时亮灭
	for _fi in PLATE_COUNT:
		_flicker_next_t[_fi] = randf_range(0.8, 4.0)

	var gothic_font: Font = load("res://fonts/UnifrakturMaguntia.ttf") if \
		ResourceLoader.exists("res://fonts/UnifrakturMaguntia.ttf") else null

	for i in PLATE_COUNT:
		var root := Node3D.new()
		root.name     = "Plate_" + PLATE_NUMBERS[i]
		root.position = PLATE_BASE_POS[i]
		root.rotation_degrees.y = randf_range(-ROT_Y_RANGE, ROT_Y_RANGE)
		root.rotation_degrees.z = randf_range(-ROT_Z_RANGE, ROT_Z_RANGE)
		add_child(root)

		var mesh := MeshInstance3D.new()
		var box  := BoxMesh.new()
		box.size               = PLATE_VISUAL_SIZE
		mesh.mesh              = box
		mesh.material_override = _plate_mat
		root.add_child(mesh)

		var body  := StaticBody3D.new()
		var col   := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = PLATE_COLLISION_SIZE
		col.shape  = shape
		body.add_child(col)
		root.add_child(body)

		var label := Label3D.new()
		label.text             = PLATE_NUMBERS[i]
		label.font_size        = 200
		label.modulate         = Color(1.00, 0.92, 0.15, 1.00)
		label.outline_size     = 10
		label.outline_modulate = Color(1.00, 0.55, 0.00, 0.90)
		if gothic_font:
			label.font = gothic_font
		label.position      = Vector3(0.0, 0.0, 0.03)
		label.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		root.add_child(label)

		var area   := Area3D.new()
		var acol   := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = COLLECT_RADIUS
		acol.shape    = sphere
		area.add_child(acol)
		root.add_child(area)
		area.body_entered.connect(_on_plate_entered.bind(i))
		area.body_exited.connect(_on_plate_exited.bind(i))

		var cjk_font := _make_cjk_font()
		var hint := Label3D.new()
		hint.text      = "[E] 摘除" if i == 0 else "[E]"
		hint.font_size = 100
		hint.modulate  = Color(1.0, 1.0, 1.0, 0.0)
		hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hint.position  = Vector3(0.0, 2.10, 0.0)
		hint.font      = cjk_font
		root.add_child(hint)

		# 427 专属：[F] 提示（初始不可见，锁定后显示）
		if i == PLAYER_PLATE_INDEX:
			_f_hint = Label3D.new()
			_f_hint.text      = "[F] 认同"
			_f_hint.font_size = 100
			_f_hint.modulate  = Color(0.80, 1.00, 0.80, 0.0)   # 绿白，与 [E] 区分
			_f_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_f_hint.position  = Vector3(0.0, 2.60, 0.0)
			_f_hint.font      = cjk_font
			root.add_child(_f_hint)

		_plates.append(root)
		_labels.append(label)
		_areas.append(area)
		_hints.append(hint)
		_bob_phases.append(randf() * TAU)
		_pulse_speeds.append(randf_range(PULSE_SPEED_MIN, PULSE_SPEED_MAX))
		_pulse_phases.append(randf() * TAU)


# =========================
# 感应区信号
# =========================

func _on_plate_entered(body: Node3D, idx: int) -> void:
	if not body.is_in_group("player") or _collected[idx]:
		return
	_near_plate = idx
	# 427 已锁定时不显示 [E]（避免误操作时玩家意识到有 E 可按）
	if idx == PLAYER_PLATE_INDEX and _lock_state == 2:
		return
	_hints[idx].modulate.a = 0.90


func _on_plate_exited(body: Node3D, idx: int) -> void:
	if not body.is_in_group("player"):
		return
	if _near_plate == idx:
		_near_plate = -1
	_hints[idx].modulate.a = 0.0


# =========================
# 收集逻辑
# =========================

func _collect_plate(idx: int) -> void:
	if _collected[idx]:
		return
	_collected[idx] = true
	_near_plate     = -1

	_hints[idx].modulate.a = 0.0
	_labels[idx].visible   = false

	# 427 被收集时清除 F 提示和锁定状态
	if idx == PLAYER_PLATE_INDEX:
		if is_instance_valid(_f_hint):
			_f_hint.modulate.a = 0.0
		_lock_state = 0

	_spawn_flying_star(idx)

	star_count += 1
	if _jar_label:
		_jar_label.text = str(star_count)

	print("[order] collected '", PLATE_NUMBERS[idx], "'  stars=", star_count, "/", STAR_THRESHOLD)

	if star_count >= STAR_THRESHOLD:
		_trigger_path1_ending()


func _spawn_flying_star(idx: int) -> void:
	var star := MeshInstance3D.new()
	var sph  := SphereMesh.new()
	sph.radius = 0.08
	sph.height = 0.16
	star.mesh  = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color     = Color(1.00, 0.92, 0.20)
	mat.emission_enabled = true
	mat.emission         = Color(1.00, 0.85, 0.10) * 1.5
	star.material_override = mat

	star.global_position = _plates[idx].global_position + Vector3(0.0, 0.5, 0.0)
	get_tree().root.add_child(star)

	var target: Vector3 = _jar_root.global_position + Vector3(0.0, 0.10, 0.0) \
		if is_instance_valid(_jar_root) else star.global_position
	var tw := create_tween()
	tw.tween_property(star, "global_position", target, STAR_FLY_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(star.queue_free)


# =========================
# 结局演出（Step 5）
# =========================

# 通用：通过 CostumeManager 触发标准白屏字幕（与其他 Force 一致）
func _show_ending_text(event_name: String) -> void:
	var mgr := get_tree().root.find_child("CostumeManager", true, false)
	if mgr:
		mgr.call("on_order_ending", event_name)


# ── Path 1 — 编目者 ────────────────────────────────────────────
func _trigger_path1_ending() -> void:
	if _ending_triggered: return
	_ending_triggered = true
	print("[order] Path 1 — 编目者")

	# 罐盖焊死：压下 + 扁平化
	if is_instance_valid(_jar_root) and _jar_root.get_child_count() >= 2:
		var lid := _jar_root.get_child(1) as Node3D
		var tw_lid := create_tween()
		tw_lid.tween_property(lid, "position:y", 0.04, 0.40).set_trans(Tween.TRANS_BOUNCE)
		tw_lid.tween_property(lid, "scale", Vector3(1.18, 0.55, 1.18), 0.20)

	# 罐身刻痕：换材质，炽金发光
	if is_instance_valid(_jar_root) and _jar_root.get_child_count() >= 1:
		var body := _jar_root.get_child(0) as MeshInstance3D
		var new_mat              := StandardMaterial3D.new()
		new_mat.albedo_color      = Color(0.78, 0.62, 0.18, 0.80)
		new_mat.emission_enabled  = true
		new_mat.emission          = Color(1.00, 0.72, 0.10) * 0.9
		new_mat.metallic          = 0.75
		new_mat.roughness         = 0.45
		new_mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
		var tw_body := create_tween()
		tw_body.tween_interval(0.6)
		tw_body.tween_callback(func(): body.material_override = new_mat)

	# 暗角渐入
	if _vignette_mat:
		var tw_v := create_tween()
		tw_v.tween_method(
			func(v: float) -> void: _vignette_mat.set_shader_parameter("intensity", v),
			0.0, 0.72, 2.0
		)

	await get_tree().create_timer(2.5).timeout
	_show_ending_text("order_path1")


# ── Path 2 — 幻灭 ─────────────────────────────────────────────
func _trigger_path2_ending() -> void:
	if _ending_triggered: return
	_ending_triggered = true
	print("[order] Path 2 — 幻灭")

	# Stage 1：427 锁定顶点——金光脉冲（满足感的顶峰，0.5s）
	var lbl_427 := _labels[PLAYER_PLATE_INDEX] as Label3D
	var tw_peak := create_tween()
	tw_peak.tween_property(lbl_427, "modulate",
		Color(BRIGHTNESS_427 * 2.2, BRIGHTNESS_427 * 2.0, BRIGHTNESS_427 * 0.35, 1.0), 0.20)
	tw_peak.tween_property(lbl_427, "modulate",
		Color(BRIGHTNESS_427, BRIGHTNESS_427 * 0.93, BRIGHTNESS_427 * 0.10, 1.0), 0.30)

	await get_tree().create_timer(0.5).timeout

	# Stage 2：涟漪扩散——以 427 为圆心，按距离依次将其余门牌变成 "427"
	var p427 : Vector3 = (_plates[PLAYER_PLATE_INDEX] as Node3D).global_position
	for i in PLATE_COUNT:
		if i == PLAYER_PLATE_INDEX or _collected[i] or not is_instance_valid(_labels[i]):
			continue
		var dist  : float = p427.distance_to((_plates[i] as Node3D).global_position)
		var delay : float = minf(dist * 0.045, 1.80)   # 最远不超过 1.8s
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(_flash_plate_to_427.bind(i))

	await get_tree().create_timer(2.8).timeout   # 等涟漪扩散完毕 + 短暂压迫停顿

	# Stage 3：白屏接字幕（由 costume_ui 标准流程处理）
	_show_ending_text("order_path2")


# 涟漪扩散辅助：单块门牌白闪后稳定为 "427" 亮度
func _flash_plate_to_427(i: int) -> void:
	if not is_instance_valid(_labels[i]): return
	var lbl := _labels[i] as Label3D
	lbl.text = "427"
	var tw := create_tween()
	# 白闪瞬间
	tw.tween_property(lbl, "modulate", Color(4.2, 4.0, 3.8, 1.0), 0.10)
	# 缓落至与 427 相同的暖金亮度
	tw.tween_property(lbl, "modulate",
		Color(BRIGHTNESS_427, BRIGHTNESS_427 * 0.93, BRIGHTNESS_427 * 0.10, 1.0), 0.55) \
		.set_ease(Tween.EASE_OUT)


# =========================
# 晕眩暗角（Step 4）
# =========================

func _create_vignette() -> void:
	_vignette_layer = CanvasLayer.new()
	_vignette_layer.layer = 100
	add_child(_vignette_layer)

	_vignette_rect = ColorRect.new()
	_vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
    vec2 uv   = UV - vec2(0.5);
    float dist = length(uv);
    float v    = smoothstep(0.25, 0.72, dist) * intensity;
    COLOR = vec4(0.0, 0.0, 0.0, v);
}
"""
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = shader
	_vignette_mat.set_shader_parameter("intensity", 0.0)
	_vignette_rect.material = _vignette_mat
	_vignette_layer.add_child(_vignette_rect)


func _play_vignette(peak: float, sustain: float) -> void:
	if _vignette_mat == null:
		return
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: _vignette_mat.set_shader_parameter("intensity", v),
		0.0, peak, 0.6
	)
	tw.tween_interval(sustain)
	tw.tween_method(
		func(v: float) -> void: _vignette_mat.set_shader_parameter("intensity", v),
		peak, 0.0, 1.4
	)


func _try_erase() -> void:
	if _erase_attempts >= 2:
		return
	_erase_attempts += 1
	print("[order] 抹除尝试 ", _erase_attempts, "/2")

	if _erase_attempts == 1:
		# 第 1 次：中等暗角，短暂眩晕感
		_play_vignette(0.62, 2.0)
	else:
		# 第 2 次：深度暗角，持续更久，触发 Path 3
		_play_vignette(0.90, 4.0)
		if is_instance_valid(_shadow_hint): _shadow_hint.visible = false
		_trigger_path3_ending()


# ── Path 3 — 隐士 ─────────────────────────────────────────────
func _trigger_path3_ending() -> void:
	if _ending_triggered: return
	_ending_triggered = true
	print("[order] Path 3 — 隐士")

	# Phase 1：全场门牌疯狂抖动（约 2 秒）
	for i in PLATE_COUNT:
		if _collected[i] or not is_instance_valid(_plates[i]):
			continue
		var plate := _plates[i] as Node3D
		var base  : Vector3 = PLATE_BASE_POS[i]
		var tw    := create_tween()
		for _s in 18:   # 18 帧抖动，每帧 0.08~0.14 s
			tw.tween_property(plate, "position",
				base + Vector3(randf_range(-0.48, 0.48),
							   randf_range(-0.32, 0.32),
							   randf_range(-0.48, 0.48)),
				randf_range(0.08, 0.14)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(plate, "position", base, 0.10)

	await get_tree().create_timer(2.4).timeout

	# Phase 2：坍缩——所有门牌缩至 0（随机先后顺序）
	for i in PLATE_COUNT:
		if not is_instance_valid(_plates[i]):
			continue
		var cw := create_tween()
		cw.tween_interval(randf_range(0.0, 0.35))   # 随机错开，避免整齐
		cw.tween_property(_plates[i] as Node3D, "scale", Vector3.ZERO,
			randf_range(0.45, 0.80)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(1.2).timeout

	# Phase 3：编号消失（从未存在过）
	if is_instance_valid(_shadow_label): _shadow_label.visible = false
	if is_instance_valid(_shadow_hint):  _shadow_hint.visible  = false
	if is_instance_valid(_labels[PLAYER_PLATE_INDEX]):
		var tw_num := create_tween()
		tw_num.tween_property(_labels[PLAYER_PLATE_INDEX] as Label3D,
			"modulate:a", 0.0, 0.8).set_ease(Tween.EASE_OUT)

	# 暗角渐入
	if _vignette_mat:
		var tw_v := create_tween()
		tw_v.tween_method(
			func(v: float) -> void: _vignette_mat.set_shader_parameter("intensity", v),
			0.0, 0.80, 1.8
		)

	await get_tree().create_timer(2.0).timeout
	_show_ending_text("order_path3")


# =========================
# 每帧更新
# =========================

func _process(delta: float) -> void:
	if _ending_triggered: return   # 结局触发后冻结所有交互

	var t := Time.get_ticks_msec() * 0.001

	# 罐子跟随玩家（仅在地毯区域内显示）
	if _player and is_instance_valid(_jar_root):
		_jar_root.global_position = _player.global_position + \
			_player.global_transform.basis * JAR_OFFSET
		_jar_root.visible = _player_in_area()

	# 假影子
	_update_shadow()

	# 427 锁定
	if _player:
		_update_427_lock(delta)
		_update_other_flicker(delta)

	# E 键收集
	if Input.is_action_just_pressed("interact") and _near_plate >= 0:
		_collect_plate(_near_plate)

	# F 键跟随（仅 427 完全锁定后有效）
	if Input.is_action_just_pressed("follow") and _lock_state == 2:
		_trigger_path2_ending()

	# Q 键抹除（影子编号，最多两次）
	if Input.is_action_just_pressed("erase") and _erase_attempts < 2:
		_try_erase()

	# 距离亮度系统 + Bobbing + 脉冲发光
	for i in _plates.size():
		if not is_instance_valid(_plates[i]) or _collected[i]:
			continue

		# ── 距离亮度 ──────────────────────────────────────────
		if _player and is_instance_valid(_labels[i]):
			var label := _labels[i] as Label3D
			if i == PLAYER_PLATE_INDEX:
				# 427 始终超亮
				label.modulate.r = BRIGHTNESS_427
				label.modulate.g = BRIGHTNESS_427 * 0.93
				label.modulate.b = BRIGHTNESS_427 * 0.10
			else:
				var dist_b := _player.global_position.distance_to(
					(_plates[i] as Node3D).global_position)
				var b: float = lerp(BRIGHTNESS_MIN, 1.0,
					1.0 - clamp(dist_b / BRIGHTNESS_MAX_DIST, 0.0, 1.0))
				label.modulate.r = b
				label.modulate.g = b * 0.92
				label.modulate.b = b * 0.15

		# ── Bobbing ───────────────────────────────────────────
		if i == PLAYER_PLATE_INDEX and _lock_state == 2:
			_plates[i].position.y = PLATE_BASE_POS[i].y
			continue

		_plates[i].position.y = PLATE_BASE_POS[i].y \
			+ sin(t * BOB_SPEED + _bob_phases[i]) * BOB_AMPLITUDE

		# ── 脉冲（alpha）─────────────────────────────────────
		if i == PLAYER_PLATE_INDEX and _lock_state >= 1:
			continue   # 427 闪烁/锁定期间由 _trigger_flicker 控制 alpha

		if is_instance_valid(_labels[i]):
			var pulse := (sin(t * _pulse_speeds[i] + _pulse_phases[i]) + 1.0) * 0.5
			var a: float = lerp(PULSE_ALPHA_MIN, PULSE_ALPHA_MAX, pulse)
			(_labels[i] as Label3D).modulate.a = a
