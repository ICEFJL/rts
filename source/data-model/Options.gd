extends Resource

enum Screen { FULL = 0, WINDOW = 1 }

@export var screen: Screen = Screen.FULL:
	set = _set_screen
@export var mouse_restricted = false:
	set = _set_mouse_restricted
@export var drone_nums = 0:
	set = _set_drone_nums
@export var worker_nums = 0:
	set = _set_worker_nums
@export var tank_nums = 0:
	set = _set_tank_nums
@export var helicopter_nums = 0:
	set = _set_helicopter_nums


func _init():
	_apply_stored_options()


func _set_screen(value):
	screen = value
	_apply_screen()


func _set_mouse_restricted(value):
	mouse_restricted = value
	_apply_mouse_restricted()


func _set_drone_nums(value):
	drone_nums = value


func _set_worker_nums(value):
	worker_nums = value


func _set_tank_nums(value):
	tank_nums = value


func _set_helicopter_nums(value):
	helicopter_nums = value


func _apply_stored_options():
	_apply_screen()
	_apply_mouse_restricted()


func _apply_screen():
	DisplayServer.window_set_mode(
		(
			DisplayServer.WINDOW_MODE_FULLSCREEN
			if screen == Screen.FULL
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)


func _apply_mouse_restricted():
	if mouse_restricted:
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
