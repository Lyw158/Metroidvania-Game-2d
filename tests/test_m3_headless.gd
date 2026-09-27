extends Node2D
## M3 无头冒烟测试（独立测试场景：驱动器常驻 root，不被房间切换销毁）。
## 用法：godot --headless --path <项目目录> res://tests/test_m3_headless.tscn
## 覆盖：过渡进入出生房 / 门触发切换与出生点定位 / 能力房拾取与能力跨房间保留 / 终点房与回程。
## 输出使用英文，避免 Windows PowerShell 下的编码乱码。

const M1_ROOM := "res://scenes/rooms/m1_playground.tscn"
const ABILITY_ROOM := "res://scenes/rooms/m3_ability_room.tscn"
const FINAL_ROOM := "res://scenes/rooms/m3_final_room.tscn"
## 出生点断言容差（玩家出生后可能下落一小段距离）
const SPAWN_TOLERANCE := 120.0

var _failures := 0


func _ready() -> void:
	_detach_and_run.call_deferred()


## 让测试驱动器脱离 current_scene：change_scene_to_file 只替换 current_scene，
## 这样房间切换不会销毁本节点，测试可以贯穿多个房间。
func _detach_and_run() -> void:
	get_tree().current_scene = null
	_run()


func _check(ok: bool, message: String) -> void:
	if ok:
		print("[PASS] ", message)
	else:
		_failures += 1
		print("[FAIL] ", message)


func _finish() -> void:
	print("M3 smoke test finished: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	await get_tree().process_frame

	# 0) 进入出生房（走正式过渡路径；spawn 为空 → 使用房间 default_spawn = Default）
	RoomManager.change_room(M1_ROOM, &"")
	var room := await _wait_room(&"M1Playground")
	_check(room != null, "enter M1Playground via transition")
	if room == null:
		_finish()
		return
	var player: Player = room.get_node("Player")
	var default_marker := room.get_node("SpawnPoints/Default") as Marker2D
	_check(player.global_position.distance_to(default_marker.global_position) < SPAWN_TOLERANCE,
			"default spawn at Default marker")

	# 1) 右下角门 → 能力房，并在 FromBirthRoom 出生
	player.global_position = (room.get_node("M3Doors/Door_ToAbilityRoom") as Area2D).global_position
	room = await _wait_room(&"M3AbilityRoom")
	_check(room != null, "door triggers transition to ability room")
	if room == null:
		_finish()
		return
	player = room.get_node("Player")
	var spawn1 := room.get_node("SpawnPoints/FromBirthRoom") as Marker2D
	_check(player.global_position.distance_to(spawn1.global_position) < SPAWN_TOLERANCE,
			"spawn at FromBirthRoom")
	# 出生点不应位于门区内：等一段时间不应被再次传走
	var scene_before_name := String(get_tree().current_scene.name)
	for i in 30:
		await get_tree().physics_frame
	_check(get_tree().current_scene != null
			and String(get_tree().current_scene.name) == scene_before_name,
			"no immediate re-transition after spawn")

	# 2) 拾取光球 → 解锁二段跳
	var pickup := room.get_node("Pickup_Ability") as Area2D
	player.global_position = pickup.global_position
	var waited := 0
	while not GameManager.is_pickup_collected(&"ability_double_jump") and waited < 300:
		await get_tree().physics_frame
		waited += 1
	_check(GameManager.is_pickup_collected(&"ability_double_jump"), "pickup collected and recorded")
	_check(player.has_ability(PlayerAbilities.DOUBLE_JUMP), "double jump unlocked in ability room")

	# 3) 走回入口门 → 回出生房，在 FromAbilityRoom 出生；能力跨房间保留
	player.global_position = (room.get_node("M3Doors/Door_Back") as Area2D).global_position
	room = await _wait_room(&"M1Playground")
	_check(room != null, "back to birth room")
	if room == null:
		_finish()
		return
	player = room.get_node("Player")
	var spawn2 := room.get_node("SpawnPoints/FromAbilityRoom") as Marker2D
	_check(player.global_position.distance_to(spawn2.global_position) < SPAWN_TOLERANCE,
			"spawn at FromAbilityRoom")
	_check(player.has_ability(PlayerAbilities.DOUBLE_JUMP), "ability kept across rooms")

	# 4) 高台出口门 → 终点房（游戏内需二段跳跳上高台；此处直接传送验证门与出生点）
	player.global_position = (room.get_node("M3Doors/Door_ToFinalRoom") as Area2D).global_position
	room = await _wait_room(&"M3FinalRoom")
	_check(room != null, "final room entered")
	if room == null:
		_finish()
		return
	player = room.get_node("Player")
	var spawn3 := room.get_node("SpawnPoints/FromPerch") as Marker2D
	_check(player.global_position.distance_to(spawn3.global_position) < SPAWN_TOLERANCE,
			"spawn at FromPerch")

	# 5) 终点房回程门 → 回出生房高台的 FromFinishRoom
	player.global_position = (room.get_node("M3Doors/Door_Back") as Area2D).global_position
	room = await _wait_room(&"M1Playground")
	_check(room != null, "back from final room")
	if room == null:
		_finish()
		return
	player = room.get_node("Player")
	var spawn4 := room.get_node("SpawnPoints/FromFinishRoom") as Marker2D
	_check(player.global_position.distance_to(spawn4.global_position) < SPAWN_TOLERANCE,
			"spawn at FromFinishRoom")

	_finish()


## 等待 current_scene 变为指定房间名，并等待过渡（淡入淡出）完成
func _wait_room(room_name: StringName) -> Node:
	var waited := 0
	while (get_tree().current_scene == null or get_tree().current_scene.name != room_name) and waited < 400:
		await get_tree().physics_frame
		waited += 1
	waited = 0
	while RoomManager.is_transitioning() and waited < 400:
		await get_tree().physics_frame
		waited += 1
	if get_tree().current_scene == null or get_tree().current_scene.name != room_name:
		return null
	return get_tree().current_scene
