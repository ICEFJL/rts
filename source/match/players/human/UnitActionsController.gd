# 导入预加载的脚本
extends Node

const Structure = preload("res://source/match/units/Structure.gd")


# 定义动作类
class Actions:
	const Moving = preload("res://source/match/units/actions/Moving.gd")
	const MovingToUnit = preload("res://source/match/units/actions/MovingToUnit.gd")
	const Following = preload("res://source/match/units/actions/Following.gd")
	const CollectingResourcesSequentially = preload("res://source/match/units/actions/CollectingResourcesSequentially.gd")
	const AutoAttacking = preload("res://source/match/units/actions/AutoAttacking.gd")
	const Constructing = preload("res://source/match/units/actions/Constructing.gd")


# 初始化函数
func _ready():
	MatchSignals.terrain_targeted.connect(_on_terrain_targeted)  # 连接地形目标信号
	MatchSignals.unit_targeted.connect(_on_unit_targeted)  # 连接单位目标信号
	MatchSignals.unit_spawned.connect(_on_unit_spawned)  # 连接单位生成信号

# 尝试将选中的单位导航到指定位置
func _try_navigating_selected_units_towards_position(target_point):
	var terrain_units_to_move = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return (
				unit.is_in_group("controlled_units")  # 单位是否在控制组
				and unit.movement_domain == Constants.Match.Navigation.Domain.TERRAIN  # 单位是否在地形域
				and Actions.Moving.is_applicable(unit)  # 移动动作是否适用
			)
	)
	var air_units_to_move = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return (
				unit.is_in_group("controlled_units")  # 单位是否在控制组
				and unit.movement_domain == Constants.Match.Navigation.Domain.AIR  # 单位是否在空中域
				and Actions.Moving.is_applicable(unit)  # 移动动作是否适用
			)
	)
	var new_unit_targets = Utils.Match.Unit.Movement.crowd_moved_to_new_pivot(
		terrain_units_to_move, target_point  # 计算地形单位的新目标位置
	)
	new_unit_targets += Utils.Match.Unit.Movement.crowd_moved_to_new_pivot(
		air_units_to_move, target_point  # 计算空中单位的新目标位置
	)
	for tuple in new_unit_targets:
		var unit = tuple[0]
		var new_target = tuple[1]
		unit.action = Actions.Moving.new(new_target)  # 设置单位的移动动作

# 尝试设置选中建筑的集结点
func _try_setting_rally_points(target_point: Vector3):
	var controlled_structures = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return unit.is_in_group("controlled_units") and unit.find_child("RallyPoint") != null  # 建筑是否有集结点
	)
	for structure in controlled_structures:
		var rally_point = structure.find_child("RallyPoint")
		if rally_point != null:
			rally_point.global_position = target_point  # 设置集结点位置

# 尝试命令选中的工人建造建筑
func _try_ordering_selected_workers_to_construct_structure(potential_structure):
	if not potential_structure is Structure or potential_structure.is_constructed():  # 检查是否为建筑且未建造完成
		return
	var structure = potential_structure
	var selected_constructors = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return (
				unit.is_in_group("controlled_units")  # 单位是否在控制组
				and Actions.Constructing.is_applicable(unit, structure)  # 建造动作是否适用
			)
	)
	for unit in selected_constructors:
		unit.action = Actions.Constructing.new(structure)  # 设置单位的建造动作

# 尝试将选中的单位导航到指定单位
func _navigate_selected_units_towards_unit(target_unit):
	var units_navigated = 0
	for unit in get_tree().get_nodes_in_group("selected_units"):
		if not unit.is_in_group("controlled_units"):  # 单位是否在控制组
			continue
		if Actions.CollectingResourcesSequentially.is_applicable(unit, target_unit):  # 收集资源动作是否适用
			unit.action = Actions.CollectingResourcesSequentially.new(target_unit)
			units_navigated += 1
		elif Actions.AutoAttacking.is_applicable(unit, target_unit):  # 自动攻击动作是否适用
			unit.action = Actions.AutoAttacking.new(target_unit)
			units_navigated += 1
		elif Actions.Constructing.is_applicable(unit, target_unit):  # 建造动作是否适用
			unit.action = Actions.Constructing.new(target_unit)
			units_navigated += 1
		elif (
			(
				target_unit.is_in_group("adversary_units")  # 目标单位是否为敌方单位
				or target_unit.is_in_group("controlled_units")  # 目标单位是否为己方单位
			)
			and Actions.Following.is_applicable(unit)  # 跟随动作是否适用
		):
			unit.action = Actions.Following.new(target_unit)
			units_navigated += 1
		elif Actions.MovingToUnit.is_applicable(unit):  # 移动到单位动作是否适用
			unit.action = Actions.MovingToUnit.new(target_unit)
			units_navigated += 1
	return units_navigated > 0  # 返回是否有单位被导航

# 处理地形目标信号
func _on_terrain_targeted(position):
	_try_navigating_selected_units_towards_position(position)  # 尝试将选中的单位导航到指定位置
	_try_setting_rally_points(position)  # 尝试设置选中建筑的集结点

# 处理单位目标信号
func _on_unit_targeted(unit):
	if _navigate_selected_units_towards_unit(unit):  # 尝试将选中的单位导航到指定单位
		var targetability = unit.find_child("Targetability")
		if targetability != null:
			targetability.animate()  # 动画化目标单位

# 处理单位生成信号
func _on_unit_spawned(unit):
	_try_ordering_selected_workers_to_construct_structure(unit)  # 尝试命令选中的工人建造新生成的建筑