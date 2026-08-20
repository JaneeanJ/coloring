extends Node

# 服装视觉层：程序化几何体挂到玩家骨骼上
# 三件服装初始隐藏，由 costume_manager 的信号触发显示

var _ribbon: BoneAttachment3D   # 金色斜织带 → Follow
var _eye:    BoneAttachment3D   # 眼睛刺绣   → Gaze
var _antler: BoneAttachment3D   # 鹿角发饰   → Overtake

# Identity 配饰
var _mirror:   BoneAttachment3D   # 镜面碎片 → Observe
var _feather:  BoneAttachment3D   # 倒置羽饰 → Accept
var _fragment: BoneAttachment3D   # 碎片饰   → Destroy

# Connection 配饰
var _frame_skirt:      BoneAttachment3D   # 画框裙摆 → connection_frame
var _water_gauze:      BoneAttachment3D   # 流动薄纱 → connection_water
var _scissors_shards:  BoneAttachment3D   # 拼接碎片 → connection_scissors
# Eros 配饰
var _eros_island_shawl: BoneAttachment3D  # 暖白披肩 → eros_island
var _eros_ship_collar:  BoneAttachment3D  # 雾青灰立领 → eros_ship
# Creation 配饰
var _creation_collar:   BoneAttachment3D  # 领口别针（雾紫）→ creation_0 Promise
var _creation_sleeve:   BoneAttachment3D  # 袖口泪滴吊坠（琥珀）→ creation_1 Lemon
var _creation_hairpin:  BoneAttachment3D  # 发夹羽纹（珊瑚）→ creation_2 我心翱翔
var _creation_necklace: BoneAttachment3D  # 项链坠（玫瑰粉）→ creation_3 大教堂时代
var _creation_emission_mats: Array = []   # 供 _flash_all_creation 用
# Constants 配饰
var _constants_bead: BoneAttachment3D     # 右手灰银珠饰 → constants


func setup(skeleton: Skeleton3D) -> void:
	_ribbon   = _create_ribbon(skeleton)
	_eye      = _create_eye(skeleton)
	_antler   = _create_antler(skeleton)
	_mirror   = _create_mirror(skeleton)
	_feather  = _create_feather(skeleton)
	_fragment = _create_fragment(skeleton)
	# Connection
	_frame_skirt     = _create_frame_skirt(skeleton)
	_water_gauze     = _create_water_gauze(skeleton)
	_scissors_shards = _create_scissors_shards(skeleton)
	_eros_island_shawl = _create_eros_island_shawl(skeleton)
	_eros_ship_collar  = _create_eros_ship_collar(skeleton)
	# Creation
	_creation_collar   = _create_creation_collar(skeleton)
	_creation_sleeve   = _create_creation_sleeve(skeleton)
	_creation_hairpin  = _create_creation_hairpin(skeleton)
	_creation_necklace = _create_creation_necklace(skeleton)
	# Constants
	_constants_bead = _create_constants_bead(skeleton)


# 由 world.gd 连接到 costume_manager 的 costume_triggered 信号
func on_costume_triggered(event_name: String) -> void:
	match event_name:
		"follow":            _show(_ribbon)
		"gaze":              _show(_eye)
		"overtake":          _show(_antler)
		"observe_identity":  _show(_mirror)
		"accept_identity":   _show(_feather)
		"destroy_identity":  _show(_fragment)
		"connection_frame":    _show(_frame_skirt)
		"connection_water":    _show(_water_gauze)
		"connection_scissors": _show(_scissors_shards)
		"eros_island":         _show(_eros_island_shawl)
		"eros_ship":           _show(_eros_ship_collar)
		"creation_0":          _show(_creation_collar)
		"creation_1":          _show(_creation_sleeve)
		"creation_2":          _show(_creation_hairpin)
		"creation_3":
			_show(_creation_necklace)
			_flash_all_creation()   # 四件配饰共鸣发光
		"constants": _show(_constants_bead)


# 显示节点，带 scale 0→1 出现动画
func _show(node: BoneAttachment3D) -> void:
	if node == null or node.visible:
		return
	node.visible = true
	node.scale = Vector3.ZERO
	var tween = node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 创建 BoneAttachment3D 并挂到 Skeleton3D
func _make_attachment(skeleton: Skeleton3D, bone_name: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.bone_name = bone_name
	att.visible = false
	skeleton.add_child(att)
	return att


# ── 金色斜织带（Spine2，胸前 + 背后各一份）──────────────────────
func _create_ribbon(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.84, 0.0)
	mat.metallic     = 0.6
	mat.roughness    = 0.3

	var box := BoxMesh.new()
	box.size = Vector3(0.38, 0.04, 0.04)

	for z_side in [0.08, -0.08]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.material_override = mat
		mesh.rotation_degrees.z = 45.0
		mesh.position = Vector3(0.0, 0.05, z_side)
		att.add_child(mesh)

	return att


# ── 眼睛刺绣（Spine2，胸前 + 背后各一份）────────────────────────
func _create_eye(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	var mat_w := StandardMaterial3D.new()
	mat_w.albedo_color = Color(0.95, 0.93, 0.88)

	var mat_p := StandardMaterial3D.new()
	mat_p.albedo_color = Color(0.1, 0.05, 0.02)

	var sph_w := SphereMesh.new()
	sph_w.radius = 0.06
	sph_w.height = 0.12

	var sph_p := SphereMesh.new()
	sph_p.radius = 0.032
	sph_p.height = 0.064

	for z_side in [0.10, -0.10]:
		# 眼白
		var eye_white := MeshInstance3D.new()
		eye_white.mesh = sph_w
		eye_white.material_override = mat_w
		eye_white.scale    = Vector3(1.0, 0.35, 0.75)
		eye_white.position = Vector3(0.0, 0.08, z_side)
		att.add_child(eye_white)

		# 瞳孔（稍微更靠外）
		var pupil := MeshInstance3D.new()
		pupil.mesh = sph_p
		pupil.material_override = mat_p
		pupil.scale    = Vector3(1.0, 0.35, 0.75)
		pupil.position = Vector3(0.0, 0.08, z_side * 1.2)
		att.add_child(pupil)

	return att


# ── 鹿角发饰（Head，左右对称两根角）─────────────────────────────
func _create_antler(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Head")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.77, 0.64, 0.35)
	mat.roughness    = 0.9

	for side in [-1, 1]:
		# 主干
		var stem     := MeshInstance3D.new()
		var cyl_s    := CylinderMesh.new()
		cyl_s.top_radius    = 0.012
		cyl_s.bottom_radius = 0.022
		cyl_s.height        = 0.16
		stem.mesh = cyl_s
		stem.material_override = mat
		stem.position          = Vector3(side * 0.07, 0.16, 0.0)
		stem.rotation_degrees.z = side * -18.0
		att.add_child(stem)

		# 分叉
		var branch  := MeshInstance3D.new()
		var cyl_b   := CylinderMesh.new()
		cyl_b.top_radius    = 0.008
		cyl_b.bottom_radius = 0.013
		cyl_b.height        = 0.10
		branch.mesh = cyl_b
		branch.material_override = mat
		branch.position          = Vector3(side * 0.10, 0.24, 0.0)
		branch.rotation_degrees.z = side * -38.0
		att.add_child(branch)

	return att


# ── 镜面碎片（Spine2，胸前 + 背后，银色扁片）────────────────────
func _create_mirror(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.90, 0.92)
	mat.metallic     = 0.85
	mat.roughness    = 0.15

	# 3 片错落碎片，前后各一组
	var pieces := [
		{"pos": Vector3( 0.00,  0.14,  0.0), "rot": Vector3(0, 0,  15), "size": Vector3(0.28, 0.03, 0.18)},
		{"pos": Vector3( 0.13,  0.04,  0.0), "rot": Vector3(0, 0, -25), "size": Vector3(0.20, 0.03, 0.14)},
		{"pos": Vector3(-0.11, -0.08,  0.0), "rot": Vector3(0, 0,  40), "size": Vector3(0.16, 0.03, 0.12)},
	]

	for z_side in [0.12, -0.12]:
		for p in pieces:
			var mesh := MeshInstance3D.new()
			var box  := BoxMesh.new()
			box.size = p["size"]
			mesh.mesh = box
			mesh.material_override = mat
			mesh.position = Vector3(p["pos"].x, p["pos"].y, z_side)
			mesh.rotation_degrees = p["rot"]
			att.add_child(mesh)

	return att


# ── 倒置羽饰（Spine2，肩背部，尖端朝下）────────────────────────
func _create_feather(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.86, 0.88)
	mat.metallic     = 0.0
	mat.roughness    = 0.85

	for side in [-1, 1]:
		# 主羽：细长锥形，尖端朝下（top_radius 小）
		var feather  := MeshInstance3D.new()
		var cyl      := CylinderMesh.new()
		cyl.top_radius    = 0.012
		cyl.bottom_radius = 0.045
		cyl.height        = 0.36
		feather.mesh = cyl
		feather.material_override = mat
		feather.position          = Vector3(side * 0.16, 0.06, -0.10)
		feather.rotation_degrees.z = side * 12.0
		att.add_child(feather)

		# 副羽：更短更细
		var feather2  := MeshInstance3D.new()
		var cyl2      := CylinderMesh.new()
		cyl2.top_radius    = 0.008
		cyl2.bottom_radius = 0.028
		cyl2.height        = 0.24
		feather2.mesh = cyl2
		feather2.material_override = mat
		feather2.position          = Vector3(side * 0.24, 0.04, -0.10)
		feather2.rotation_degrees.z = side * 22.0
		att.add_child(feather2)

	return att


# ── 碎片饰（Spine2，身体周围漂浮灰色碎块）──────────────────────
func _create_fragment(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.28, 0.27)
	mat.roughness    = 0.95

	# 6 块碎片，围绕身体散布在不同位置和角度
	var shards := [
		{"pos": Vector3( 0.32,  0.18,  0.10), "rot": Vector3( 15,  30,  20), "size": Vector3(0.13, 0.03, 0.10)},
		{"pos": Vector3(-0.28,  0.12, -0.08), "rot": Vector3(-10, -25,  35), "size": Vector3(0.14, 0.03, 0.09)},
		{"pos": Vector3( 0.22, -0.10,  0.14), "rot": Vector3( 25,  15, -18), "size": Vector3(0.11, 0.03, 0.12)},
		{"pos": Vector3(-0.18,  0.24,  0.12), "rot": Vector3(-20,  40,  10), "size": Vector3(0.12, 0.03, 0.10)},
		{"pos": Vector3( 0.15, -0.22, -0.13), "rot": Vector3( 10, -35, -28), "size": Vector3(0.09, 0.03, 0.09)},
		{"pos": Vector3(-0.26, -0.15,  0.06), "rot": Vector3(-30,  20,  45), "size": Vector3(0.10, 0.03, 0.07)},
	]

	for s in shards:
		var mesh := MeshInstance3D.new()
		var box  := BoxMesh.new()
		box.size = s["size"]
		mesh.mesh = box
		mesh.material_override = mat
		mesh.position        = s["pos"]
		mesh.rotation_degrees = s["rot"]
		att.add_child(mesh)

	return att


# ── 画框裙摆（Spine2，四条细矩形围成画框，原木褐色，低透明度）──────
func _create_frame_skirt(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.32, 0.14, 0.50)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness    = 0.85

	var t  := 0.022   # 条厚度
	var w  := 0.34    # 框宽
	var h  := 0.40    # 框高
	var cy := -0.20   # 框中心 Y（腰部以下）

	var bars: Array = [
		[Vector3(0.0,      cy + h * 0.5, 0.0), Vector3(w, t,  t)],   # 上横
		[Vector3(0.0,      cy - h * 0.5, 0.0), Vector3(w, t,  t)],   # 下横
		[Vector3(-w * 0.5, cy,           0.0), Vector3(t, h,  t)],   # 左竖
		[Vector3( w * 0.5, cy,           0.0), Vector3(t, h,  t)],   # 右竖
	]

	for b: Array in bars:
		var mesh := MeshInstance3D.new()
		var box  := BoxMesh.new()
		box.size = b[1]
		mesh.mesh              = box
		mesh.material_override = mat
		mesh.position          = b[0]
		att.add_child(mesh)

	return att


# ── 流动薄纱（Spine2，三层扁平圆盘，蓝色半透明，错落倾斜）──────────
func _create_water_gauze(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	var mat := StandardMaterial3D.new()
	mat.albedo_color             = Color(0.38, 0.70, 0.96, 0.38)
	mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness                = 0.60
	mat.emission_enabled         = true
	mat.emission                 = Color(0.20, 0.50, 0.90)
	mat.emission_energy_multiplier = 0.18

	# 三层圆盘，高度和倾斜角各不相同，形成流动薄纱感
	var layers: Array = [
		{"y": -0.10, "rx":  5.0, "rz":  0.0, "r": 0.22},
		{"y": -0.20, "rx":  9.0, "rz": 14.0, "r": 0.26},
		{"y": -0.31, "rx": 13.0, "rz":-10.0, "r": 0.23},
	]

	for l: Dictionary in layers:
		var mesh := MeshInstance3D.new()
		var cyl  := CylinderMesh.new()
		cyl.top_radius    = l["r"]
		cyl.bottom_radius = l["r"]
		cyl.height        = 0.018
		cyl.radial_segments = 24
		mesh.mesh              = cyl
		mesh.material_override = mat
		mesh.position          = Vector3(0.0, l["y"], 0.0)
		mesh.rotation_degrees  = Vector3(l["rx"], 0.0, l["rz"])
		att.add_child(mesh)

	return att


# ── 拼接裙摆碎片（Spine2，各块拼图原色，错落分布）──────────────────
func _create_scissors_shards(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	# 颜色对应七块拼图（取前六块旅人色）
	var shards: Array = [
		{"pos": Vector3( 0.18, -0.14,  0.06), "rot": Vector3( 10,  25, -15), "size": Vector3(0.12, 0.025, 0.09), "col": Color(0.36, 0.49, 0.60)},  # 黛蓝
		{"pos": Vector3(-0.20, -0.18, -0.05), "rot": Vector3( -8, -20,  20), "size": Vector3(0.14, 0.025, 0.10), "col": Color(0.71, 0.42, 0.36)},  # 赭红
		{"pos": Vector3( 0.10, -0.28,  0.08), "rot": Vector3( 15,  10, -30), "size": Vector3(0.10, 0.025, 0.08), "col": Color(0.83, 0.64, 0.30)},  # 藤黄
		{"pos": Vector3(-0.13, -0.10,  0.07), "rot": Vector3( -5,  35,  12), "size": Vector3(0.11, 0.025, 0.09), "col": Color(0.50, 0.66, 0.55)},  # 竹青
		{"pos": Vector3( 0.22, -0.24, -0.06), "rot": Vector3( 20, -15,  25), "size": Vector3(0.09, 0.025, 0.10), "col": Color(0.66, 0.61, 0.69)},  # 雾紫
		{"pos": Vector3(-0.08, -0.33,  0.03), "rot": Vector3(-12,  40, -18), "size": Vector3(0.13, 0.025, 0.08), "col": Color(0.77, 0.82, 0.83)},  # 月白
	]

	for s: Dictionary in shards:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = s["col"]
		mat.roughness    = 0.75

		var mesh := MeshInstance3D.new()
		var box  := BoxMesh.new()
		box.size = s["size"]
		mesh.mesh              = box
		mesh.material_override = mat
		mesh.position          = s["pos"]
		mesh.rotation_degrees  = s["rot"]
		att.add_child(mesh)

	return att


# ── 暖白披肩（Spine2，肩部两侧宽扁条，暖白色）── eros_island ──────
func _create_eros_ship_collar(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Neck")

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.18, 0.72, 0.42)   # 雾青灰
	mat.roughness                  = 0.6
	mat.emission_enabled           = true
	mat.emission                   = Color(0.18, 0.72, 0.42)
	mat.emission_energy_multiplier = 0.2

	# 立领：环绕颈部的薄圈
	var mesh := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = 0.10
	cyl.bottom_radius = 0.12
	cyl.height        = 0.08
	cyl.rings         = 1
	mesh.mesh              = cyl
	mesh.material_override = mat
	mesh.position          = Vector3(0.0, 0.05, 0.0)
	att.add_child(mesh)

	return att


func _create_eros_island_shawl(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Spine2")

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.96, 0.92, 0.85)
	mat.roughness                  = 0.75
	mat.emission_enabled           = true
	mat.emission                   = Color(0.96, 0.92, 0.85)
	mat.emission_energy_multiplier = 0.15

	for side in [-1, 1]:
		var mesh := MeshInstance3D.new()
		var box  := BoxMesh.new()
		box.size  = Vector3(0.22, 0.04, 0.18)
		mesh.mesh = box
		mesh.material_override  = mat
		mesh.position           = Vector3(side * 0.20, 0.18, 0.0)
		mesh.rotation_degrees.z = side * -12.0
		att.add_child(mesh)

	return att


# ═══════════════════════════════════════════════════════
# Creation 配饰（Force 06）
# ═══════════════════════════════════════════════════════

# ── 领口别针（Promise）—— 雾紫水彩晕染感半透明圆片 ──────────────────
func _create_creation_collar(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Neck")

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.78, 0.65, 0.92, 0.70)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = Color(0.78, 0.65, 0.92)
	mat.emission_energy_multiplier = 0.40
	mat.roughness                  = 0.80
	_creation_emission_mats.append(mat)

	# 圆形别针主体
	var disc := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = 0.030
	cyl.bottom_radius = 0.030
	cyl.height        = 0.006
	cyl.radial_segments = 20
	disc.mesh              = cyl
	disc.material_override = mat
	disc.position          = Vector3(0.02, -0.04, 0.06)   # 颈前偏下
	att.add_child(disc)

	return att


# ── 袖口泪滴吊坠（Lemon）—— 琥珀色水滴形 ───────────────────────────
func _create_creation_sleeve(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_RightForeArm")

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.90, 0.65, 0.12, 0.90)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = Color(0.88, 0.60, 0.08)
	mat.emission_energy_multiplier = 0.35
	mat.roughness                  = 0.30
	mat.metallic                   = 0.20
	_creation_emission_mats.append(mat)

	# 泪滴：顶收尖（top_radius=0），底圆，180° 翻转使圆端朝下
	var drop := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = 0.0
	cyl.bottom_radius = 0.018
	cyl.height        = 0.055
	drop.mesh              = cyl
	drop.material_override = mat
	drop.position          = Vector3(0.0, -0.08, 0.0)
	drop.rotation_degrees.x = 180.0   # 尖端朝上、圆端朝下垂挂
	att.add_child(drop)

	return att


# ── 发夹羽纹（我心翱翔）—— 两道细珊瑚色羽状线条 ─────────────────────
func _create_creation_hairpin(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Head")

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.96, 0.52, 0.42)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.94, 0.48, 0.38)
	mat.emission_energy_multiplier = 0.45
	mat.roughness                  = 0.60
	_creation_emission_mats.append(mat)

	# 两道细羽纹，左右对称，有轻微旋转以模拟羽毛走向
	for i in 2:
		var side := float(i) * 2.0 - 1.0   # -1 或 +1
		var feather  := MeshInstance3D.new()
		var cyl      := CylinderMesh.new()
		cyl.top_radius    = 0.004
		cyl.bottom_radius = 0.010
		cyl.height        = 0.078
		feather.mesh              = cyl
		feather.material_override = mat
		feather.position          = Vector3(side * 0.045, 0.10, -0.04)
		feather.rotation_degrees  = Vector3(12.0, 0.0, side * 22.0)
		att.add_child(feather)

	return att


# ── 项链坠（大教堂时代）—— 玫瑰粉细圈 + 中心圆球 ────────────────────
func _create_creation_necklace(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_Neck")

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.95, 0.60, 0.72)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.93, 0.55, 0.68)
	mat.emission_energy_multiplier = 0.45
	mat.roughness                  = 0.35
	mat.metallic                   = 0.15
	_creation_emission_mats.append(mat)

	var base_pos := Vector3(0.0, -0.08, 0.06)

	# 中心圆球（坠心）
	var center := MeshInstance3D.new()
	var sph    := SphereMesh.new()
	sph.radius = 0.018
	sph.height = 0.036
	center.mesh              = sph
	center.material_override = mat
	center.position          = base_pos
	att.add_child(center)

	# 外圈纹样（极细环，模拟玫瑰花窗镶边）
	var ring := MeshInstance3D.new()
	var ring_cyl := CylinderMesh.new()
	ring_cyl.top_radius    = 0.032
	ring_cyl.bottom_radius = 0.032
	ring_cyl.height        = 0.004
	ring_cyl.radial_segments = 24
	ring.mesh              = ring_cyl
	ring.material_override = mat
	ring.position          = base_pos
	att.add_child(ring)

	return att


# ── Constants — 右手灰银珠饰（占位，后续统一整理） ───────────────────
func _create_constants_bead(skeleton: Skeleton3D) -> BoneAttachment3D:
	var att := _make_attachment(skeleton, "mixamorig_RightHand")

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.78, 0.78, 0.82)   # 灰银
	mat.metallic                   = 0.60
	mat.roughness                  = 0.30
	mat.emission_enabled           = true
	mat.emission                   = Color(0.78, 0.78, 0.82)
	mat.emission_energy_multiplier = 0.25

	var mi  := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.012
	sph.height = 0.024
	mi.mesh              = sph
	mi.material_override = mat
	mi.position          = Vector3(0.0, 0.02, 0.0)
	att.add_child(mi)

	att.visible = false
	return att


# ── 大教堂时代完成时：四件 Creation 配饰共鸣发光 ────────────────────
func _flash_all_creation() -> void:
	for mat: StandardMaterial3D in _creation_emission_mats:
		if mat == null:
			continue
		var base_e: float = mat.emission_energy_multiplier
		var tw := create_tween()
		tw.tween_method(
			func(v: float) -> void: mat.emission_energy_multiplier = v,
			base_e, base_e * 4.5, 0.30
		)
		tw.tween_method(
			func(v: float) -> void: mat.emission_energy_multiplier = v,
			base_e * 4.5, base_e, 1.00
		).set_ease(Tween.EASE_OUT)
