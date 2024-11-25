extends Node

# 预加载 MatchUtils 脚本
const Match = preload("res://source/match/MatchUtils.gd")


# 定义一个 Set 类，继承自外部预加载的 Set 脚本
class Set:
	extends "res://source/utils/Set.gd"

	# 从数组创建一个新的 Set 实例
	static func from_array(array):
		var a_set = Set.new()
		for item in array:
			a_set.add(item)
		return a_set

	# 计算两个集合的差集
	static func subtracted(minuend, subtrahend):
		var difference = Set.new()
		for item in minuend.iterate():
			if not subtrahend.has(item):
				difference.add(item)
		return difference


# 定义一个 Dict 类，包含静态方法
class Dict:
	# 获取字典的所有键值对
	static func items(dict):
		var pairs = []
		for key in dict:
			pairs.append([key, dict[key]])
		return pairs


# 定义一个 Float 类，包含静态方法
class Float:
	# 检查两个浮点数是否在给定的误差范围内相等
	static func is_equal_approx_with_epsilon(a: float, b: float, epsilon):
		return abs(a - b) <= epsilon


# 定义一个 Colour 类，包含静态方法
class Colour:
	# 检查两个颜色是否在给定的误差范围内相等
	static func is_equal_approx_with_epsilon(a: Color, b: Color, epsilon: float):
		return (
			Float.is_equal_approx_with_epsilon(a.r, b.r, epsilon)
			and Float.is_equal_approx_with_epsilon(a.g, b.g, epsilon)
			and Float.is_equal_approx_with_epsilon(a.b, b.b, epsilon)
		)


# 定义一个 NodeEx 类，包含静态方法
class NodeEx:
	# 查找节点的父节点，该父节点属于指定的组
	static func find_parent_with_group(node, group_for_parent_to_be_in):
		var ancestor = node.get_parent()
		while ancestor != null:
			if ancestor.is_in_group(group_for_parent_to_be_in):
				return ancestor
			ancestor = ancestor.get_parent()
		return null


# 定义一个 Arr 类，包含静态方法
class Arr:
	# 计算数组的总和
	static func sum(array):
		var total = 0
		for item in array:
			total += item
		return total


# 定义一个 RouletteWheel 类，用于实现轮盘赌选择算法
class RouletteWheel:
	var _values_w_sorted_normalized_shares = []

	# 初始化轮盘赌选择器，传入值及其对应的权重映射
	func _init(value_to_share_mapping):
		var total_share = Arr.sum(value_to_share_mapping.values())
		for value in value_to_share_mapping:
			var share = value_to_share_mapping[value]
			var normalized_share = share / total_share
			_values_w_sorted_normalized_shares.append([value, normalized_share])
		for i in range(1, _values_w_sorted_normalized_shares.size()):
			_values_w_sorted_normalized_shares[i][1] += _values_w_sorted_normalized_shares[i - 1][1]

	# 根据给定的概率选择一个值
	func get_value(probability):
		for tuple in _values_w_sorted_normalized_shares:
			var value = tuple[0]
			var accumulated_share = tuple[1]
			if probability <= accumulated_share:
				return value
		assert(false, "unexpected flow")
		return -1
