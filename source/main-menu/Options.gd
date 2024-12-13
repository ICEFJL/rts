extends Control

@onready var _screen = find_child("Screen")
@onready var _mouse_movement_restricted = find_child("MouseMovementRestricted")
@onready var _spin_box_drone = find_child("SpinBox_Drone")
@onready var _spin_box_worker = find_child("SpinBox_Worker")
@onready var _spin_box_helicopter = find_child("SpinBox_Helicopter")
@onready var _spin_box_tank = find_child("SpinBox_Tank")


func _ready():
	_mouse_movement_restricted.button_pressed = Globals.options.mouse_restricted
	_screen.selected = Globals.options.screen
	_spin_box_drone.value = Globals.options.drone_nums
	_spin_box_worker.value = Globals.options.worker_nums
	_spin_box_helicopter.value = Globals.options.helicopter_nums
	_spin_box_tank.value = Globals.options.tank_nums


func _on_mouse_movement_restricted_pressed():
	Globals.options.mouse_restricted = _mouse_movement_restricted.button_pressed
	_save_options()


func _on_screen_item_selected(index):
	Globals.options.screen = {
		0: Globals.options.Screen.FULL,
		1: Globals.options.Screen.WINDOW,
	}[index]
	_save_options()


func _on_back_button_pressed():
	_save_options()
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")


func _save_options():
	Globals.options.drone_nums = _spin_box_drone.value
	Globals.options.worker_nums = _spin_box_worker.value
	Globals.options.helicopter_nums = _spin_box_helicopter.value
	Globals.options.tank_nums = _spin_box_tank.value
	ResourceSaver.save(Globals.options, Constants.OPTIONS_FILE_PATH)
