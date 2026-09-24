extends Node2D
## M1 测试场：长跑区 / 阶梯 / 断崖 / 跳跃高度塔 / 窄柱 / 单向平台塔
## 相机可移动边界由房间定义并注入玩家相机（M3 房间系统接管前，先用这个最小方案）

@export var camera_bounds := Rect2(0, 0, 3840, 1728)


func _ready() -> void:
	var cam: Camera2D = $Player/Camera2D
	cam.limit_left = int(camera_bounds.position.x)
	cam.limit_top = int(camera_bounds.position.y)
	cam.limit_right = int(camera_bounds.end.x)
	cam.limit_bottom = int(camera_bounds.end.y)
