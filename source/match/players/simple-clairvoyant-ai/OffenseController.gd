# OffenseController.gd
extends Node

# 当资源需求满足时发出信号
signal resources_required(resources, metadata)

# 预加载各种单位和建筑场景
const Worker = preload("res://source/match/units/Worker.gd")
const CommandCenter = preload("res://source/match/units/CommandCenter.gd")
const VehicleFactory = preload("res://source/match/units/VehicleFactory.gd")
const VehicleFactoryScene = preload("res://source/match/units/VehicleFactory.tscn")
const Tank = preload("res://source/match/units/Tank.gd")
const TankScene = preload("res://source/match/units/Tank.tscn")
const AircraftFactory = preload("res://source/match/units/AircraftFactory.gd")
const AircraftFactoryScene = preload("res://source/match/units/AircraftFactory.tscn")
const Helicopter = preload("res://source/match/units/Helicopter.gd")
const HelicopterScene = preload("res://source/match/units/Helicopter.tscn")
const AutoAttackingBattlegroup = preload(
    "res://source/match/players/simple-clairvoyant-ai/AutoAttackingBattlegroup.gd"
)

# 刷新间隔时间
const REFRESH_INTERVAL_S = 1.0 / 60.0 * 30.0

# 玩家实例
var _player = null

# 主要和次要建筑场景
var _primary_structure_scene = null
var _secondary_structure_scene = null

# 待处理的建筑资源请求数量
var _number_of_pending_structure_resource_requests = {}

# 主要和次要单位场景
var _primary_unit_scene = null
var _secondary_unit_scene = null

# 待处理的单位资源请求数量
var _number_of_pending_unit_resource_requests = {}

# 正在形成的战斗群
var _battlegroup_under_forming = null

# 已存在的战斗群列表
var _battlegroups = []

# AI实例
@onready var _ai = get_parent()

# 初始化控制器
func setup(player):
    _player = player
    # 根据AI配置选择主要和次要建筑场景
    _primary_structure_scene = (
        VehicleFactoryScene
        if _ai.primary_offensive_structure == _ai.OffensiveStructure.VEHICLE_FACTORY
        else AircraftFactoryScene
    )
    _secondary_structure_scene = (
        VehicleFactoryScene
        if _ai.secondary_offensive_structure == _ai.OffensiveStructure.VEHICLE_FACTORY
        else AircraftFactoryScene
    )
    # 根据AI配置选择主要和次要单位场景
    _primary_unit_scene = (
        TankScene
        if _ai.primary_offensive_structure == _ai.OffensiveStructure.VEHICLE_FACTORY
        else HelicopterScene
    )
    _secondary_unit_scene = (
        TankScene
        if _ai.secondary_offensive_structure == _ai.OffensiveStructure.VEHICLE_FACTORY
        else HelicopterScene
    )
    # 设置刷新计时器
    _setup_refresh_timer()
    # 尝试创建新的战斗群
    _try_creating_new_battlegroup()
    # 附加当前战斗中的单位
    _attach_current_battle_units()
    # 连接单位生成信号
    MatchSignals.unit_spawned.connect(_on_unit_spawned)
    # 确保主要建筑存在
    _enforce_primary_structure_existence()

# 提供资源
func provision(resources, metadata):
    if metadata == "primary_structure":
        _provision_structure(_primary_structure_scene, resources, metadata)
    elif metadata == "secondary_structure":
        _provision_structure(_secondary_structure_scene, resources, metadata)
    elif metadata == "primary_unit":
        _provision_unit(_primary_unit_scene, _primary_structure(), resources, metadata)
    elif metadata == "secondary_unit":
        _provision_unit(_secondary_unit_scene, _secondary_structure(), resources, metadata)
    else:
        assert(false, "unexpected flow")

# 设置刷新计时器
func _setup_refresh_timer():
    var timer = Timer.new()
    add_child(timer)
    timer.timeout.connect(_on_refresh_timer_timeout)
    timer.start(REFRESH_INTERVAL_S)

# 提供建筑
func _provision_structure(structure_scene, resources, metadata):
    assert(
        resources == Constants.Match.Units.CONSTRUCTION_COSTS[structure_scene.resource_path],
        "unexpected amount of resources"
    )
    # 获取可用的工人
    var workers = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit is Worker and unit.player == _player
    )
    # 减少待处理的资源请求数量
    _number_of_pending_structure_resource_requests[metadata] -= 1
    if workers.is_empty():
        return
    # 构建建筑
    _construct_structure(structure_scene)

# 提供单位
func _provision_unit(unit_scene, structure_producing_unit, resources, metadata):
    assert(
        resources == Constants.Match.Units.PRODUCTION_COSTS[unit_scene.resource_path],
        "unexpected amount of resources"
    )
    if structure_producing_unit == null:
        return
    # 减少待处理的资源请求数量
    _number_of_pending_unit_resource_requests[metadata] -= 1
    # 生产单位
    structure_producing_unit.production_queue.produce(unit_scene, true)

# 尝试创建新的战斗群
func _try_creating_new_battlegroup():
    if not _battlegroups.is_empty():
        _enforce_secondary_structure_existence()
    if _battlegroups.size() == _ai.expected_number_of_battlegroups:
        var primary_structure = _primary_structure()
        if primary_structure != null:
            primary_structure.production_queue.cancel_all()
        _battlegroup_under_forming = null
        return false
    # 获取敌方玩家
    var adversary_players = get_tree().get_nodes_in_group("players").filter(
        func(player): return player != _player
    )
    adversary_players.shuffle()
    # 创建新的战斗群
    var battlegroup = AutoAttackingBattlegroup.new(
        _ai.expected_number_of_units_in_battlegroup, adversary_players
    )
    _battlegroups.append(battlegroup)
    battlegroup.tree_exited.connect(_on_battlegroup_died.bind(battlegroup))
    add_child(battlegroup)
    _battlegroup_under_forming = battlegroup
    return true

# 附加当前战斗中的单位
func _attach_current_battle_units():
    var battle_units = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit.player == _player and (unit is Tank or unit is Helicopter)
    )
    for battle_unit in battle_units:
        _on_unit_spawned(battle_unit)

# 构建建筑
func _construct_structure(structure_scene):
    var construction_cost = Constants.Match.Units.CONSTRUCTION_COSTS[structure_scene.resource_path]
    assert(
        _player.has_resources(construction_cost),
        "player should have enough resources at this point"
    )
    # 获取指挥中心和工人
    var ccs = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit is CommandCenter and unit.player == _player
    )
    var workers = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit is Worker and unit.player == _player
    )
    var unit_to_spawn = structure_scene.instantiate()
    var reference_position_for_placement = (
        ccs[0].global_position if not ccs.is_empty() else workers[0].global_position
    )
    var placement_position = Utils.Match.Unit.Placement.find_valid_position_radially(
        reference_position_for_placement,
        unit_to_spawn.radius + Constants.Match.Units.EMPTY_SPACE_RADIUS_SURROUNDING_STRUCTURE_M,
        find_parent("Match").navigation.get_navigation_map_rid_by_domain(
            unit_to_spawn.movement_domain
        ),
        get_tree()
    )
    var target_transform = Transform3D(Basis(), placement_position).looking_at(
        placement_position + Vector3(-1, 0, 1), Vector3.UP
    )
    _player.subtract_resources(construction_cost)
    MatchSignals.setup_and_spawn_unit.emit(unit_to_spawn, target_transform, _player)
    _enforce_primary_units_production.call_deferred()

# 确保主要建筑存在
func _enforce_primary_structure_existence():
    _enforce_structure_existence(
        _primary_structure(), _primary_structure_scene, "primary_structure"
    )

# 确保次要建筑存在
func _enforce_secondary_structure_existence():
    _enforce_structure_existence(
        _secondary_structure(), _secondary_structure_scene, "secondary_structure"
    )

# 确保建筑存在
func _enforce_structure_existence(structure, structure_scene, type):
    if structure == null and _number_of_pending_structure_resource_requests.get(type, 0) == 0:
        _number_of_pending_structure_resource_requests[type] = (
            _number_of_pending_structure_resource_requests.get(type, 0) + 1
        )
        resources_required.emit(
            Constants.Match.Units.CONSTRUCTION_COSTS[structure_scene.resource_path], type
        )

# 确保主要单位生产
func _enforce_primary_units_production():
    _enforce_units_production(_primary_structure(), _primary_unit_scene, "primary_unit")

# 确保次要单位生产
func _enforce_secondary_units_production():
    _enforce_units_production(_secondary_structure(), _secondary_unit_scene, "secondary_unit")

# 确保单位生产
func _enforce_units_production(structure, unit_scene, type):
    if structure == null or not structure.is_constructed() or not _is_units_production_allowed():
        return
    var number_of_pending_units = structure.production_queue.size()
    if number_of_pending_units + _number_of_pending_unit_resource_requests.get(type, 0) == 0:
        _number_of_pending_unit_resource_requests[type] = (
            _number_of_pending_unit_resource_requests.get(type, 0) + 1
        )
        resources_required.emit(
            Constants.Match.Units.PRODUCTION_COSTS[unit_scene.resource_path], type
        )

# 获取主要建筑
func _primary_structure():
    var primary_structures = get_tree().get_nodes_in_group("units").filter(
        func(unit):
            return (
                (
                    unit is VehicleFactory
                    if _ai.primary_offensive_structure == _ai.OffensiveStructure.VEHICLE_FACTORY
                    else unit is AircraftFactory
                )
                and unit.player == _player
            )
    )
    return primary_structures[0] if not primary_structures.is_empty() else null

# 获取次要建筑
func _secondary_structure():
    var secondary_structures = get_tree().get_nodes_in_group("units").filter(
        func(unit):
            return (
                (
                    unit is VehicleFactory
                    if _ai.secondary_offensive_structure == _ai.OffensiveStructure.VEHICLE_FACTORY
                    else unit is AircraftFactory
                )
                and unit.player == _player
            )
    )
    return secondary_structures[0] if not secondary_structures.is_empty() else null

# 检查是否允许生产单位
func _is_units_production_allowed():
    var primary_structure = _primary_structure()
    var secondary_structure = _secondary_structure()
    return (
        _number_of_additional_units_required()
        > (
            Utils.Arr.sum(_number_of_pending_unit_resource_requests.values())
            + (
                primary_structure.production_queue.size()
                if primary_structure != null and primary_structure.is_constructed()
                else 0
            )
            + (
                secondary_structure.production_queue.size()
                if secondary_structure != null and secondary_structure.is_constructed()
                else 0
            )
        )
    )

# 计算需要的额外单位数量
func _number_of_additional_units_required():
    if _battlegroup_under_forming == null:
        return 0
    return (
        _ai.expected_number_of_battlegroups * _ai.expected_number_of_units_in_battlegroup
        - (_battlegroups.size() - 1) * _ai.expected_number_of_units_in_battlegroup
        - _battlegroup_under_forming.size()
    )

# 处理单位生成事件
func _on_unit_spawned(unit):
    if unit.player != _player:
        return
    if unit is Tank or unit is Helicopter:
        if _battlegroup_under_forming == null:
            return
        _battlegroup_under_forming.attach_unit(unit)
        if _battlegroup_under_forming.size() == _ai.expected_number_of_units_in_battlegroup:
            _try_creating_new_battlegroup()
        _enforce_primary_units_production()
        _enforce_secondary_units_production()

# 处理战斗群死亡事件
func _on_battlegroup_died(battlegroup):
    if not is_inside_tree():
        return
    _battlegroups.erase(battlegroup)

# 处理刷新计时器超时事件
func _on_refresh_timer_timeout():
    _enforce_primary_structure_existence()
    # 次要建筑存在仅在战斗群形成时强制执行
    _enforce_primary_units_production()
    _enforce_secondary_units_production()