# Player.gd
extends Node3D

# 定义一个信号，当玩家数据发生变化时发出
signal changed

# 导出变量，用于表示资源A的数量
@export var resource_a = 0:
	set(value):
		resource_a = value
		# 当资源A的数量发生变化时，发出changed信号
		emit_changed()

# 导出变量，用于表示资源B的数量
@export var resource_b = 0:
	set(value):
		resource_b = value
		# 当资源B的数量发生变化时，发出changed信号
		emit_changed()

# 导出变量，用于表示玩家的颜色
@export var color = Color.WHITE

# 存储颜色材质的变量
var _color_material = null


# 添加资源
func add_resources(resources):
	for resource in resources:
		# 更新资源数量
		set(resource, get(resource) + resources[resource])


# 检查是否拥有足够的资源
func has_resources(resources):
	if FeatureFlags.allow_resources_deficit_spending:
		# 如果允许赤字支出，则总是返回True
		return true
	for resource in resources:
		# 检查每种资源的数量是否足够
		if get(resource) < resources[resource]:
			return false
	return true


# 减少资源
func subtract_resources(resources):
	for resource in resources:
		# 更新资源数量
		set(resource, get(resource) - resources[resource])


# 获取颜色材质
func get_color_material():
	if _color_material == null:
		# 如果颜色材质尚未创建，则创建一个新的StandardMaterial3D
		_color_material = StandardMaterial3D.new()
		_color_material.vertex_color_use_as_albedo = true
		_color_material.albedo_color = color
		_color_material.metallic = 1
	return _color_material


# 发出changed信号
func emit_changed():
	changed.emit()