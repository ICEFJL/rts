# 继承自 Node3D，用于处理玩家放置建筑的逻辑
extends Node3D

# 定义蓝图位置的有效性枚举
enum BlueprintPositionValidity {
	VALID,
	COLLIDES_WITH_OBJECT,
	NOT_NAVIGABLE,
	NOT_ENOUGH_RESOURCES,
	OUT_OF_MAP,
}

# 常量定义
const ROTATION_BY_KEY_STEP = 45.0  # 每次旋转的角度步长
const ROTATION_DEAD_ZONE_DISTANCE = 0.1  # 旋转死区距离
const MATERIALS_ROOT = "res://source/match/resources/materials/"  # 材质资源根路径
const BLUEPRINT_VALID_PATH = MATERIALS_ROOT + "blueprint_valid.material.tres"  # 有效蓝图材质路径
const BLUEPRINT_INVALID_PATH = MATERIALS_ROOT + "blueprint_invalid.material.tres"  # 无效蓝图材质路径

# 变量定义
var _active_blueprint_node = null  # 当前激活的蓝图节点
var _pending_structure_radius = null  # 待放置建筑的半径
var _pending_structure_navmap_rid = null  # 待放置建筑的导航图 RID
var _pending_structure_prototype = null  # 待放置建筑的原型
var _blueprint_rotating = false  # 是否正在旋转蓝图

# 初始化变量
@onready var _player = get_parent()  # 获取父节点（玩家）
@onready var _match = find_parent("Match")  # 获取 Match 节点
@onready var _feedback_label = find_child("FeedbackLabel3D")  # 获取反馈标签节点


# 初始化方法
func _ready():
	_feedback_label.hide()  # 隐藏反馈标签
	MatchSignals.place_structure.connect(_on_structure_placement_request)  # 连接放置建筑信号


# 处理未处理的输入事件
func _unhandled_input(event):
	if not _structure_placement_started():  # 如果没有开始放置建筑，则返回
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_lmb_down_event(event)  # 处理鼠标左键按下事件
	if event.is_action_pressed("rotate_structure"):
		_try_rotating_blueprint_by(ROTATION_BY_KEY_STEP)  # 尝试旋转蓝图
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		_handle_lmb_up_event(event)  # 处理鼠标左键释放事件
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_rmb_event(event)  # 处理鼠标右键事件
	if event is InputEventMouseMotion:
		_handle_mouse_motion_event(event)  # 处理鼠标移动事件


# 处理鼠标左键按下事件
func _handle_lmb_down_event(_event):
	get_viewport().set_input_as_handled()  # 标记输入已处理
	_start_blueprint_rotation()  # 开始蓝图旋转


# 处理鼠标左键释放事件
func _handle_lmb_up_event(_event):
	get_viewport().set_input_as_handled()  # 标记输入已处理
	if _blueprint_position_is_valid():  # 如果蓝图位置有效
		_finish_structure_placement()  # 完成建筑放置
	_finish_blueprint_rotation()  # 结束蓝图旋转


# 处理鼠标右键事件
func _handle_rmb_event(event):
	get_viewport().set_input_as_handled()  # 标记输入已处理
	if event.pressed:
		_finish_blueprint_rotation()  # 结束蓝图旋转
		_cancel_structure_placement()  # 取消建筑放置


# 处理鼠标移动事件
func _handle_mouse_motion_event(_event):
	get_viewport().set_input_as_handled()  # 标记输入已处理
	if _blueprint_rotation_started():  # 如果蓝图旋转已开始
		_rotate_blueprint_towards_mouse_pos()  # 旋转蓝图朝向鼠标位置
	else:
		_set_blueprint_position_based_on_mouse_pos()  # 设置蓝图位置基于鼠标位置
	var blueprint_position_validity = _calculate_blueprint_position_validity()  # 计算蓝图位置有效性
	_update_feedback_label(blueprint_position_validity)  # 更新反馈标签
	_update_blueprint_color(blueprint_position_validity == BlueprintPositionValidity.VALID)  # 更新蓝图颜色


# 检查是否已经开始放置建筑
func _structure_placement_started():
	return _active_blueprint_node != null


# 检查蓝图位置是否有效
func _blueprint_position_is_valid():
	return _calculate_blueprint_position_validity() == BlueprintPositionValidity.VALID


# 检查是否已经开始蓝图旋转
func _blueprint_rotation_started():
	return _blueprint_rotating == true


# 计算蓝图位置的有效性
func _calculate_blueprint_position_validity():
	if _active_bluprint_out_of_map():  # 如果蓝图超出地图范围
		return BlueprintPositionValidity.OUT_OF_MAP
	if not _player_has_enough_resources():  # 如果玩家资源不足
		return BlueprintPositionValidity.NOT_ENOUGH_RESOURCES
	var placement_validity = Utils.Match.Unit.Placement.validate_agent_placement_position(
		_active_blueprint_node.global_position,
		_pending_structure_radius,
		get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("resource_units"),
		_pending_structure_navmap_rid
	)
	if placement_validity == Utils.Match.Unit.Placement.COLLIDES_WITH_AGENT:  # 如果蓝图与现有单位碰撞
		return BlueprintPositionValidity.COLLIDES_WITH_OBJECT
	if placement_validity == Utils.Match.Unit.Placement.NOT_NAVIGABLE:  # 如果蓝图位置不可导航
		return BlueprintPositionValidity.NOT_NAVIGABLE
	return BlueprintPositionValidity.VALID


# 检查玩家是否有足够的资源
func _player_has_enough_resources():
	var construction_cost = Constants.Match.Units.CONSTRUCTION_COSTS[
		_pending_structure_prototype.resource_path
	]
	return _player.has_resources(construction_cost)


# 检查蓝图是否超出地图范围
func _active_bluprint_out_of_map():
	return not Geometry2D.is_point_in_polygon(
		Vector2(
			_active_blueprint_node.global_transform.origin.x,
			_active_blueprint_node.global_transform.origin.z
		),
		_match.map.get_topdown_polygon_2d()
	)


# 更新反馈标签
func _update_feedback_label(blueprint_position_validity):
	_feedback_label.visible = (blueprint_position_validity != BlueprintPositionValidity.VALID)
	match blueprint_position_validity:
		BlueprintPositionValidity.COLLIDES_WITH_OBJECT:
			_feedback_label.text = tr("BLUEPRINT_COLLIDES_WITH_OBJECT")
		BlueprintPositionValidity.NOT_NAVIGABLE:
			_feedback_label.text = tr("BLUEPRINT_NOT_NAVIGABLE")
		BlueprintPositionValidity.NOT_ENOUGH_RESOURCES:
			_feedback_label.text = tr("BLUEPRINT_NOT_ENOUGH_RESOURCES")
		BlueprintPositionValidity.OUT_OF_MAP:
			_feedback_label.text = tr("BLUEPRINT_OUT_OF_MAP")


# 开始建筑放置
func _start_structure_placement(structure_prototype):
	if _structure_placement_started():  # 如果已经开始了建筑放置，则返回
		return
	_pending_structure_prototype = structure_prototype  # 设置待放置建筑的原型
	_active_blueprint_node = (
		load(Constants.Match.Units.STRUCTURE_BLUEPRINTS[structure_prototype.resource_path])
		. instantiate()
	)  # 实例化蓝图节点
	var blueprint_origin = Vector3(-999, 0, -999)  # 设置蓝图初始位置
	var camera_direction_yless = (
		(get_viewport().get_camera_3d().project_ray_normal(Vector2(0, 0)) * Vector3(1, 0, 1))
		. normalized()
	)  # 获取相机方向（忽略 Y 轴）
	var rotate_towards = blueprint_origin + camera_direction_yless.rotated(Vector3.UP, PI * 0.75)  # 计算旋转目标
	_active_blueprint_node.global_transform = Transform3D(Basis(), blueprint_origin).looking_at(
		rotate_towards, Vector3.UP
	)  # 设置蓝图的初始变换
	add_child(_active_blueprint_node)  # 添加蓝图节点到场景
	var temporary_structure_instance = _pending_structure_prototype.instantiate()  # 实例化临时建筑
	_pending_structure_radius = temporary_structure_instance.radius  # 设置待放置建筑的半径
	_pending_structure_navmap_rid = (
		find_parent("Match")
		. navigation
		. get_navigation_map_rid_by_domain(temporary_structure_instance.movement_domain)
	)  # 获取待放置建筑的导航图 RID
	temporary_structure_instance.free()  # 释放临时建筑实例


# 设置蓝图位置基于鼠标位置
func _set_blueprint_position_based_on_mouse_pos():
	var mouse_pos_2d = get_viewport().get_mouse_position()  # 获取鼠标位置
	var mouse_pos_3d = get_viewport().get_camera_3d().get_ray_intersection(mouse_pos_2d)  # 获取鼠标在 3D 空间的位置
	if mouse_pos_3d == null:  # 如果鼠标位置无效，则返回
		return
	_active_blueprint_node.global_transform.origin = mouse_pos_3d  # 设置蓝图位置
	_feedback_label.global_transform.origin = mouse_pos_3d  # 设置反馈标签位置


# 更新蓝图颜色
func _update_blueprint_color(blueprint_position_is_valid):
	var material_to_set = (
		preload(BLUEPRINT_VALID_PATH)
		if blueprint_position_is_valid
		else preload(BLUEPRINT_INVALID_PATH)
	)  # 选择合适的材质
	for child in _active_blueprint_node.find_children("*"):  # 遍历蓝图的所有子节点
		if "material_override" in child:  # 如果子节点有材质覆盖属性
			child.material_override = material_to_set  # 设置材质


# 取消建筑放置
func _cancel_structure_placement():
	if _structure_placement_started():  # 如果已经开始放置建筑
		_feedback_label.hide()  # 隐藏反馈标签
		_active_blueprint_node.queue_free()  # 释放蓝图节点
		_active_blueprint_node = null  # 重置蓝图节点


# 完成建筑放置
func _finish_structure_placement():
	if _player_has_enough_resources():  # 如果玩家有足够的资源
		var construction_cost = Constants.Match.Units.CONSTRUCTION_COSTS[
			_pending_structure_prototype.resource_path
		]  # 获取建筑的建造成本
		_player.subtract_resources(construction_cost)  # 扣除玩家资源
		MatchSignals.setup_and_spawn_unit.emit(
			_pending_structure_prototype.instantiate(),
			_active_blueprint_node.global_transform,
			_player
		)  # 发送信号以创建并放置建筑
	_cancel_structure_placement()  # 取消建筑放置


# 开始蓝图旋转
func _start_blueprint_rotation():
	_blueprint_rotating = true


# 尝试旋转蓝图
func _try_rotating_blueprint_by(degrees):
	if not _structure_placement_started():  # 如果没有开始放置建筑，则返回
		return
	_active_blueprint_node.global_transform.basis = (
		_active_blueprint_node.global_transform.basis.rotated(Vector3.UP, deg_to_rad(degrees))
	)  # 旋转蓝图


# 旋转蓝图朝向鼠标位置
func _rotate_blueprint_towards_mouse_pos():
	var mouse_pos_2d = get_viewport().get_mouse_position()  # 获取鼠标位置
	var mouse_pos_3d = get_viewport().get_camera_3d().get_ray_intersection(mouse_pos_2d)  # 获取鼠标在 3D 空间的位置
	if mouse_pos_3d == null:  # 如果鼠标位置无效，则返回
		return
	var mouse_pos_yless = mouse_pos_3d * Vector3(1, 0, 1)  # 忽略 Y 轴
	var blueprint_pos_3d = _active_blueprint_node.global_transform.origin  # 获取蓝图位置
	var blueprint_pos_yless = blueprint_pos_3d * Vector3(-999, 0, -999)  # 忽略 Y 轴
	if mouse_pos_yless.distance_to(blueprint_pos_yless) < ROTATION_DEAD_ZONE_DISTANCE:  # 如果鼠标位置在死区内，则返回
		return
	var rotation_target = Vector3(mouse_pos_yless.x, blueprint_pos_3d.y, mouse_pos_yless.z)  # 计算旋转目标
	if rotation_target.is_equal_approx(_active_blueprint_node.global_transform.origin):  # 如果旋转目标与当前位置相同，则返回
		return
	_active_blueprint_node.global_transform = _active_blueprint_node.global_transform.looking_at(
		rotation_target, Vector3.UP
	)  # 设置蓝图的变换


# 结束蓝图旋转
func _finish_blueprint_rotation():
	_blueprint_rotating = false


# 处理放置建筑请求
func _on_structure_placement_request(structure_prototype):
	_start_structure_placement(structure_prototype)  # 开始建筑放置
