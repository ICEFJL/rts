extends Node

# 当资源需求发生变化时发出信号
signal resources_required(resources, metadata)

# 预加载单位和场景
const Worker = preload("res://source/match/units/Worker.gd")
const CommandCenter = preload("res://source/match/units/CommandCenter.gd")
const AGTurret = preload("res://source/match/units/AntiGroundTurret.gd")
const AGTurretScene = preload("res://source/match/units/AntiGroundTurret.tscn")
const AATurret = preload("res://source/match/units/AntiAirTurret.gd")
const AATurretScene = preload("res://source/match/units/AntiAirTurret.tscn")

# 刷新间隔时间
const REFRESH_INTERVAL_S = 1.0 / 60.0 * 30.0

# 当前玩家
var _player = null
# 待处理的地对地炮塔资源请求数量
var _number_of_pending_ag_turret_resource_requests = 0
# 待处理的地对空炮塔资源请求数量
var _number_of_pending_aa_turret_resource_requests = 0

# 获取父节点 AI
@onready var _ai = get_parent()

# 初始化设置
func setup(player):
    _setup_refresh_timer()
    _player = player
    _attach_current_turrets()
    MatchSignals.unit_spawned.connect(_on_unit_spawned)
    _enforce_number_of_ag_turrets()
    _enforce_number_of_aa_turrets()

# 处理资源供应
func provision(resources, metadata):
    var workers = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit is Worker and unit.player == _player
    )
    var ccs = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit is CommandCenter and unit.player == _player
    )
    if metadata == "ag_turret":
        assert(
            resources == Constants.Match.Units.CONSTRUCTION_COSTS[AGTurretScene.resource_path],
            "unexpected amount of resources"
        )
        _number_of_pending_ag_turret_resource_requests -= 1
        if workers.is_empty() or ccs.is_empty():
            return
        _construct_turret(AGTurretScene)
    elif metadata == "aa_turret":
        assert(
            resources == Constants.Match.Units.CONSTRUCTION_COSTS[AATurretScene.resource_path],
            "unexpected amount of resources"
        )
        _number_of_pending_aa_turret_resource_requests -= 1
        if workers.is_empty() or ccs.is_empty():
            return
        _construct_turret(AATurretScene)
    else:
        assert(false, "unexpected flow")

# 设置刷新计时器
func _setup_refresh_timer():
    var timer = Timer.new()
    add_child(timer)
    timer.timeout.connect(_on_refresh_timer_timeout)
    timer.start(REFRESH_INTERVAL_S)

# 附加当前存在的炮塔
func _attach_current_turrets():
    var turrets = get_tree().get_nodes_in_group("units").filter(
        func(unit): return (unit is AGTurret or unit is AATurret) and unit.player == _player
    )
    for turret in turrets:
        _attach_turret(turret)

# 附加炮塔并监听其退出树事件
func _attach_turret(turret):
    turret.tree_exited.connect(_on_unit_died.bind(turret))

# 确保地对地炮塔的数量符合预期
func _enforce_number_of_ag_turrets():
    var ag_turrets = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit is AGTurret and unit.player == _player
    )
    if (
        ag_turrets.size() + _number_of_pending_ag_turret_resource_requests
        >= _ai.expected_number_of_ag_turrets
    ):
        return
    var number_of_extra_ag_turrets_required = (
        _ai.expected_number_of_ag_turrets
        - (ag_turrets.size() + _number_of_pending_ag_turret_resource_requests)
    )
    for _i in range(number_of_extra_ag_turrets_required):
        resources_required.emit(
            Constants.Match.Units.CONSTRUCTION_COSTS[AGTurretScene.resource_path], "ag_turret"
        )
        _number_of_pending_ag_turret_resource_requests += 1

# 确保地对空炮塔的数量符合预期
func _enforce_number_of_aa_turrets():
    var aa_turrets = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit is AATurret and unit.player == _player
    )
    if (
        aa_turrets.size() + _number_of_pending_aa_turret_resource_requests
        >= _ai.expected_number_of_aa_turrets
    ):
        return
    var number_of_extra_aa_turrets_required = (
        _ai.expected_number_of_aa_turrets
        - (aa_turrets.size() + _number_of_pending_aa_turret_resource_requests)
    )
    for _i in range(number_of_extra_aa_turrets_required):
        resources_required.emit(
            Constants.Match.Units.CONSTRUCTION_COSTS[AATurretScene.resource_path], "aa_turret"
        )
        _number_of_pending_aa_turret_resource_requests += 1

# 构建炮塔
func _construct_turret(turret_scene):
    var construction_cost = Constants.Match.Units.CONSTRUCTION_COSTS[turret_scene.resource_path]
    assert(
        _player.has_resources(construction_cost),
        "player should have enough resources at this point"
    )
    var ccs = get_tree().get_nodes_in_group("units").filter(
        func(unit): return unit is CommandCenter and unit.player == _player
    )
    var unit_to_spawn = turret_scene.instantiate()
    # TODO: 引入实际算法以考虑敌方位置
    var placement_position = Utils.Match.Unit.Placement.find_valid_position_radially(
        ccs[0].global_position,
        unit_to_spawn.radius + Constants.Match.Units.EMPTY_SPACE_RADIUS_SURROUNDING_STRUCTURE_M,
        find_parent("Match").navigation.get_navigation_map_rid_by_domain(
            unit_to_spawn.movement_domain
        ),
        get_tree()
    )
    var target_transform = Transform3D(Basis(), placement_position).looking_at(
        placement_position + Vector3(0, 0, 1), Vector3.UP
    )
    _player.subtract_resources(construction_cost)
    MatchSignals.setup_and_spawn_unit.emit(unit_to_spawn, target_transform, _player)

# 单位死亡时的处理
func _on_unit_died(unit):
    if not is_inside_tree():
        return
    if unit is AGTurret:
        _enforce_number_of_ag_turrets()
    elif unit is AATurret:
        _enforce_number_of_aa_turrets()
    else:
        assert(false, "unexpected flow")

# 单位生成时的处理
func _on_unit_spawned(unit):
    if unit.player != _player:
        return
    if unit is AGTurret or unit is AATurret:
        _attach_turret(unit)

# 刷新计时器超时时的处理
func _on_refresh_timer_timeout():
    _enforce_number_of_ag_turrets()
    _enforce_number_of_aa_turrets()
