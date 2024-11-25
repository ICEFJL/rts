# SimpleClairvoyantAI.gd
extends "res://source/match/players/Player.gd"

# 资源请求优先级枚举
enum ResourceRequestPriority { LOW, MEDIUM, HIGH }

# 进攻结构枚举
enum OffensiveStructure { VEHICLE_FACTORY, AIRCRAFT_FACTORY }

# 导出变量，用于配置AI的行为
@export var expected_number_of_workers = 3
@export var expected_number_of_ccs = 1
@export var expected_number_of_ag_turrets = 1
@export var expected_number_of_aa_turrets = 1
@export var primary_offensive_structure = OffensiveStructure.VEHICLE_FACTORY
@export var secondary_offensive_structure = OffensiveStructure.AIRCRAFT_FACTORY
@export var expected_number_of_battlegroups = 2
@export var expected_number_of_units_in_battlegroup = 4

# 当前是否有正在进行的资源供应
var _provisioning_ongoing = false

# 资源请求队列
var _resource_requests = {
    ResourceRequestPriority.LOW: [],
    ResourceRequestPriority.MEDIUM: [],
    ResourceRequestPriority.HIGH: [],
}

# 延迟执行的任务
var _call_to_perform_during_process = null

# 匹配对象
@onready var _match = find_parent("Match")

# 各个控制器
@onready var _economy_controller = find_child("EconomyController")
@onready var _defense_controller = find_child("DefenseController")
@onready var _offense_controller = find_child("OffenseController")
@onready var _intelligence_controller = find_child("IntelligenceController")
@onready var _construction_works_controller = find_child("ConstructionWorksController")

# 初始化函数
func _ready():
    # 等待匹配准备好
    if not _match.is_node_ready():
        await _match.ready
    # 等待一帧以确保其他玩家已经就位
    await get_tree().physics_frame

    # 连接玩家数据变化信号
    changed.connect(_on_player_data_changed)
    
    # 经济控制器资源请求连接
    _economy_controller.resources_required.connect(
        _on_resource_request.bind(_economy_controller, ResourceRequestPriority.HIGH)
    )
    _economy_controller.setup(self)
    
    # 防御控制器资源请求连接
    _defense_controller.resources_required.connect(
        _on_resource_request.bind(_defense_controller, ResourceRequestPriority.MEDIUM)
    )
    _defense_controller.setup(self)
    
    # 进攻控制器资源请求连接
    _offense_controller.resources_required.connect(
        _on_resource_request.bind(_offense_controller, ResourceRequestPriority.LOW)
    )
    _offense_controller.setup(self)
    
    # 情报控制器初始化
    _intelligence_controller.setup(self)
    
    # 建设工作控制器初始化
    _construction_works_controller.setup(self)

# 每帧处理函数
func _process(_delta):
    if _call_to_perform_during_process != null:
        var call_to_perform = _call_to_perform_during_process
        _call_to_perform_during_process = null
        call_to_perform.call()

# 执行资源供应
func _provision(controller, resources, metadata):
    _provisioning_ongoing = true
    controller.provision(resources, metadata)
    _provisioning_ongoing = false

# 延迟执行资源请求处理
func _try_fulfilling_resource_requests_according_to_priorities_next_frame():
    """此函数延迟调用以避免以下问题：
    1. 从tree_exited信号处理器中调用add_child()的bug
    2. 避免信号触发的高级循环"""
    _call_to_perform_during_process = _try_fulfilling_resource_requests_according_to_priorities

# 处理资源请求
func _try_fulfilling_resource_requests_according_to_priorities():
    if _provisioning_ongoing:
        return
    for priority in [
        ResourceRequestPriority.HIGH, ResourceRequestPriority.MEDIUM, ResourceRequestPriority.LOW
    ]:
        while (
            not _resource_requests[priority].is_empty()
            and has_resources(_resource_requests[priority].front()["resources"])
        ):
            var resource_request = _resource_requests[priority].pop_front()
            _provision(
                resource_request["controller"],
                resource_request["resources"],
                resource_request["metadata"]
            )
        if (
            not _resource_requests[priority].is_empty()
            and not has_resources(_resource_requests[priority].front()["resources"])
        ):
            break

# 处理玩家数据变化
func _on_player_data_changed():
    _try_fulfilling_resource_requests_according_to_priorities_next_frame()

# 处理资源请求
func _on_resource_request(resources, metadata, controller, priority):
    assert(not _provisioning_ongoing, "资源请求在供应过程中收到")
    _resource_requests[priority].append(
        {"controller": controller, "resources": resources, "metadata": metadata}
    )
    _try_fulfilling_resource_requests_according_to_priorities_next_frame()