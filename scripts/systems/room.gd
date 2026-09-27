class_name Room
extends Node2D
## M3 房间基类：统一处理"跨房间出生点定位"与"相机边界注入"。
## 房间场景结构约定：
## - Player：玩家实例（节点名必须为 Player）
## - SpawnPoints/<名字>：Marker2D 出生点集合（无跨房间进入时使用 default_spawn）
## - 门：scenes/interactables/room_door.tscn 的实例，配置目标房间与目标出生点

## 相机可移动边界（世界坐标矩形）
@export var camera_bounds := Rect2(0, 0, 3840, 1728)
## 初始进入 / 单个调试（F6）时使用的出生点名
@export var default_spawn := &"Default"


func _ready() -> void:
	var spawn_name := RoomManager.consume_pending_spawn()
	if spawn_name == &"":
		spawn_name = default_spawn
	_place_player(spawn_name)
	_setup_camera()


## 把玩家放到指定出生点（找不到出生点时保留场景摆放位置并告警）
func _place_player(spawn_name: StringName) -> void:
	var player := get_node_or_null("Player") as CharacterBody2D
	if player == null:
		return
	var marker := get_node_or_null("SpawnPoints/%s" % spawn_name) as Marker2D
	if marker == null:
		push_warning("Room '%s': spawn point '%s' not found" % [name, spawn_name])
		return
	player.global_position = marker.global_position
	player.velocity = Vector2.ZERO


## 把房间的相机边界注入玩家相机，并重置平滑（避免切房间后镜头长距离滑动）
func _setup_camera() -> void:
	var cam := get_node_or_null("Player/Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = int(camera_bounds.position.x)
	cam.limit_top = int(camera_bounds.position.y)
	cam.limit_right = int(camera_bounds.end.x)
	cam.limit_bottom = int(camera_bounds.end.y)
	cam.reset_smoothing()
