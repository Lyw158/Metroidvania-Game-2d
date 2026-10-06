extends Node
## M4 存档管理器（autoload）：
## - save_game()：存档点调用，把「房间 / 玩家位置 / 已解锁能力 / 已拾取物 / 存档点 ID」写入 save_path（JSON）。
## - 读档：_ready 时从磁盘恢复记录并灌入 GameManager；延迟两帧后 boot_restore_check()，
##   仅当当前场景是项目主场景（正常启动游戏）时回到存档房间与位置；F6 单场景调试不受影响。
## - respawn_player()：死亡后回到存档点（M5 战斗调用；M4 由玩家调试键 F2 触发验证）。
## 恢复位置传递：request_restore() 设置请求 → change_room() 进入目标房间后由 Room 基类消费。
##
## 存档文件结构（user://save.json，JSON）：
## { "version": 1, "room_path": "res://...", "position": {"x": , "y": },
##   "save_point_id": "...", "abilities": [...], "pickups": [...] }

const SAVE_VERSION := 1

## 存档文件路径；测试可覆盖为独立路径隔离，避免污染正式存档
var save_path := "user://save.json"

## 存档写入完成（存档点演出反馈用）
signal game_saved(room_path: String, save_point_id: StringName)
## 读档完成（has_save 表示磁盘上是否存在有效存档）
signal game_loaded(has_save: bool)

var _data: Dictionary = {}
var _loaded_room_path := ""
var _loaded_position := Vector2.ZERO
var _loaded_save_point: StringName = &""
var _restore_requested := false
var _respawning := false
var _main_scene_path := ""


func _ready() -> void:
	_main_scene_path = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_read_from_disk()
	# autoload 的 _ready 早于主场景实例化，等两帧后再做启动恢复判断
	_boot_restore.call_deferred()


func _boot_restore() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	boot_restore_check()


## 启动读档：仅当当前场景为项目主场景（正常启动游戏）时生效，回到存档房间并恢复位置。
## F6 单场景调试不会触发；独立测试可手动调用以模拟"重开游戏"。
func boot_restore_check() -> void:
	if not has_save():
		return
	var current := get_tree().current_scene
	if current == null or current.scene_file_path != _main_scene_path:
		return
	request_restore()
	await RoomManager.change_room(_loaded_room_path, &"")


## 写入一次存档（存档点调用）；返回是否成功
func save_game(room_path: String, position: Vector2, save_point_id: StringName) -> bool:
	var data := {
		"version": SAVE_VERSION,
		"room_path": room_path,
		"position": {"x": position.x, "y": position.y},
		"save_point_id": String(save_point_id),
		"abilities": _as_string_array(GameManager.get_recorded_abilities()),
		"pickups": _as_string_array(GameManager.get_recorded_pickups()),
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: 无法写入存档 '%s'（err %d）" % [save_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_apply_data(data)
	game_saved.emit(room_path, save_point_id)
	return true


## 删除磁盘存档并清空内存状态（新游戏 / 测试清理）
func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	_clear_state()
	game_loaded.emit(false)


## 从磁盘重新读取（测试模拟"重开游戏"；不清理 GameManager 中已有的记录）
func reload() -> void:
	_read_from_disk()


func has_save() -> bool:
	return not _data.is_empty()


func get_saved_room_path() -> String:
	return _loaded_room_path


func get_saved_position() -> Vector2:
	return _loaded_position


func get_saved_save_point_id() -> StringName:
	return _loaded_save_point


func get_saved_abilities() -> Array:
	return _as_string_array(_data.get("abilities", []))


func get_saved_pickups() -> Array:
	return _as_string_array(_data.get("pickups", []))


## 指定存档点是否为当前激活的（已记录的）存档点（SavePoint 视觉状态用）
func is_save_point_active(save_point_id: StringName) -> bool:
	return has_save() and _loaded_save_point == save_point_id


## 请求下一次进入存档房间时把玩家放到存档位置（启动读档 / 死亡重生发起）
func request_restore() -> void:
	_restore_requested = true


## Room 基类在 _ready 时调用：本次进入的房间是否应使用存档位置摆放玩家（消费式，只生效一次）
func try_consume_restore(room_path: String) -> bool:
	if not _restore_requested:
		return false
	_restore_requested = false
	return has_save() and room_path == _loaded_room_path


## 死亡重生：回到存档点（无存档时重载当前房间回到默认出生点）。
## M5 战斗在玩家死亡时调用；M4 由玩家调试键（F2）触发验证。
func respawn_player() -> void:
	if _respawning or RoomManager.is_transitioning():
		return
	_respawning = true
	var current := get_tree().current_scene
	var current_path := "" if current == null else current.scene_file_path
	if has_save():
		request_restore()
		await RoomManager.change_room(_loaded_room_path, &"")
	elif not current_path.is_empty():
		await RoomManager.change_room(current_path, &"")
	_respawning = false
	await get_tree().process_frame
	_show_respawn_toast()


func is_respawning() -> bool:
	return _respawning


func _read_from_disk() -> void:
	_clear_state()
	if not FileAccess.file_exists(save_path):
		game_loaded.emit(false)
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: 无法读取存档 '%s'" % save_path)
		game_loaded.emit(false)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("SaveManager: 存档 JSON 解析失败（%s）" % save_path)
		game_loaded.emit(false)
		return
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveManager: 存档版本不符，忽略（%s）" % str(data.get("version", "?")))
		game_loaded.emit(false)
		return
	_apply_data(data)
	# 记录灌入 GameManager：重开时能力 / 拾取物立即恢复（PlayerAbilities 随后从这里读取）
	for id in data.get("abilities", []):
		GameManager.record_ability(StringName(str(id)))
	for uid in data.get("pickups", []):
		GameManager.record_pickup(StringName(str(uid)))
	game_loaded.emit(true)


func _apply_data(data: Dictionary) -> void:
	_data = data
	_loaded_room_path = str(data.get("room_path", ""))
	var position: Dictionary = data.get("position", {})
	_loaded_position = Vector2(float(position.get("x", 0.0)), float(position.get("y", 0.0)))
	_loaded_save_point = StringName(str(data.get("save_point_id", "")))


func _clear_state() -> void:
	_data = {}
	_loaded_room_path = ""
	_loaded_position = Vector2.ZERO
	_loaded_save_point = &""
	_restore_requested = false


func _as_string_array(source: Array) -> Array:
	var result: Array = []
	for item in source:
		result.append(String(item))
	return result


## 重生提示（占位 UI，M6 接入正式 HUD 前的反馈）
func _show_respawn_toast() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var anchor := Vector2.ZERO
	var player := scene.get_node_or_null("Player") as Node2D
	if player != null:
		anchor = player.global_position
	var toast := Label.new()
	toast.text = "已在存档点重生"
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.z_index = 20
	var settings := LabelSettings.new()
	settings.font_size = 40
	settings.font_color = Color(1.0, 0.9, 0.6)
	settings.outline_size = 10
	settings.outline_color = Color(0.05, 0.03, 0.0, 0.9)
	toast.label_settings = settings
	toast.size = Vector2(640.0, 60.0)
	scene.add_child(toast)
	toast.global_position = anchor + Vector2(-320.0, -360.0)
	var tween := toast.create_tween()
	tween.set_parallel(true)
	tween.tween_property(toast, "position:y", toast.position.y - 70.0, 1.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "modulate:a", 0.0, 1.4).set_delay(0.4)
	tween.chain().tween_callback(toast.queue_free)
