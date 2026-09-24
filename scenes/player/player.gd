class_name Player
extends CharacterBody2D
## M1 玩家控制器：水平移动 / 跳跃 / 手感辅助 / 状态机 / 动画 / 摄像机前瞻。
##
## 素材锚点规范（M6 替换素材时依赖，务必保持）：
## - 动画帧画布 256×320，角色视觉高约 260px，水平居中（中轴 x=128）
## - 脚底统一落在画布 y=300（相对节点原点 +140px），碰撞盒底部与之对齐
## - 替换正式素材后：AnimatedSprite2D 的 scale 恢复为 1、offset 恢复为 (0, 0)
##
## 状态机说明：验证期用 enum 四态（Idle/Run/Jump/Fall）足够；
## 后续（M5 战斗）如需扩展，再评估节点式状态机。
##
## 能力系统（M2）：解锁状态存放在子节点 PlayerAbilities（player_abilities.gd）；
## 本脚本只负责查询能力并执行对应行为（当前仅二段跳）；F1 可切换二段跳状态用于对比调试。

enum State { IDLE, RUN, JUMP, FALL }

## 单向平台所在物理层（对应 project.godot 中 layer 2 "OneWayPlatform"）
const ONE_WAY_LAYER := 2

@export_group("水平移动")
## 最大水平速度（px/s）
@export var max_speed := 520.0
## 地面加速度（px/s²）
@export var ground_acceleration := 3200.0
## 地面减速度：松开方向键后的制动（大于加速度，停得干脆）
@export var ground_deceleration := 4200.0
## 空中加速度（小于地面，空中控制略钝）
@export var air_acceleration := 1800.0
## 空中减速度（较小，保留空中惯性）
@export var air_deceleration := 900.0

@export_group("跳跃与重力")
## 起跳初速度（负值向上）
@export var jump_velocity := -1500.0
## 上升段重力（小于下落段 → 起跳轻盈）
@export var gravity_rise := 3400.0
## 下落段重力（大于上升段 → 落地干脆）
@export var gravity_fall := 4100.0
## 最大下落速度
@export var max_fall_speed := 2300.0
## 短按跳跃的最低高度比例（松开跳键时对上升速度截断的系数）
@export_range(0.0, 1.0) var min_jump_ratio := 0.45

@export_group("手感辅助")
## Coyote Time：离开地面后仍可起跳的宽限时间（秒）
@export var coyote_time := 0.10
## Jump Buffer：落地前提前按跳的预输入窗口（秒）
@export var jump_buffer_time := 0.12
## 下穿单向平台后忽略其碰撞的时间（秒）
@export var drop_through_time := 0.20

@export_group("能力：二段跳")
## 二段跳初速度（负值向上，略弱于首跳 → 第二跳更"轻"）
@export var double_jump_velocity := -1250.0
## 空中最多可追加的跳跃次数（解锁二段跳后生效）
@export var max_air_jumps := 1

@export_group("摄像机")
## 朝移动方向的前瞻偏移距离（px），0 为关闭
@export var look_ahead_distance := 130.0
## 前瞻偏移的平滑速度（越大跟得越紧）
@export var look_ahead_speed := 3.5

@export_group("调试")
## 在角色上方显示实时状态 / 速度 / 计时器（调参用，验收后可关）
@export var show_debug := true

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D
@onready var abilities: PlayerAbilities = $PlayerAbilities

var state: State = State.IDLE

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _drop_through_timer := 0.0
var _air_jumps_used := 0
var _debug_label: Label


func _ready() -> void:
	if show_debug:
		_debug_label = Label.new()
		_debug_label.position = Vector2(-170.0, -290.0)
		var settings := LabelSettings.new()
		settings.font_size = 30
		settings.outline_size = 8
		settings.outline_color = Color(0.0, 0.0, 0.0, 0.85)
		_debug_label.label_settings = settings
		add_child(_debug_label)
	animated_sprite.play("idle")


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	var jump_pressed := Input.is_action_just_pressed("jump")

	_update_timers(delta, jump_pressed)
	_try_drop_through(jump_pressed)
	_apply_horizontal_movement(direction, delta)
	_apply_gravity(delta)
	_try_jump()
	_apply_jump_cut()

	move_and_slide()

	_update_state()
	_update_animation(direction)
	_update_camera_lookahead(direction, delta)
	_update_debug()


## 维护 Coyote / Jump Buffer / 下穿计时器
func _update_timers(delta: float, jump_pressed: bool) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
		_air_jumps_used = 0
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if jump_pressed:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	if _drop_through_timer > 0.0:
		_drop_through_timer -= delta
		if _drop_through_timer <= 0.0:
			set_collision_mask_value(ONE_WAY_LAYER, true)


## 按住 下 + 跳：站在单向平台上时下穿
func _try_drop_through(jump_pressed: bool) -> void:
	if not jump_pressed:
		return
	if not Input.is_action_pressed("move_down"):
		return
	if not is_on_floor() or not _standing_on_one_way():
		return
	# 清掉本帧跳跃预输入，避免下穿后立刻弹跳
	_jump_buffer_timer = 0.0
	_drop_through_timer = drop_through_time
	set_collision_mask_value(ONE_WAY_LAYER, false)
	velocity.y = 40.0


## 检测脚下是否有单向平台（读取上一帧 move_and_slide 的滑动碰撞结果）
func _standing_on_one_way() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().dot(Vector2.UP) < 0.5:
			continue
		var body := collision.get_collider() as CollisionObject2D
		if body != null and body.collision_layer & ONE_WAY_LAYER:
			return true
	return false


## 水平移动：加速 / 减速按地面与空中分开配置
func _apply_horizontal_movement(direction: float, delta: float) -> void:
	var target_speed := direction * max_speed
	var rate: float
	if is_on_floor():
		rate = ground_acceleration if not is_zero_approx(direction) else ground_deceleration
	else:
		rate = air_acceleration if not is_zero_approx(direction) else air_deceleration
	velocity.x = move_toward(velocity.x, target_speed, rate * delta)


## 重力：上升 / 下落分段，并限制最大下落速度
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity := gravity_rise if velocity.y < 0.0 else gravity_fall
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


## 跳跃：Jump Buffer + Coyote Time 决定地面起跳；空中按跳则尝试二段跳
func _try_jump() -> void:
	if _jump_buffer_timer <= 0.0 or _drop_through_timer > 0.0:
		return
	# 地面起跳（含 Coyote 宽限）
	if _coyote_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		velocity.y = jump_velocity
		return
	# 二段跳（M2）：解锁后在空中再按一次跳跃键追加一段
	if abilities.has_ability(PlayerAbilities.DOUBLE_JUMP) and _air_jumps_used < max_air_jumps:
		_jump_buffer_timer = 0.0
		_air_jumps_used += 1
		velocity.y = double_jump_velocity


## 可变跳跃高度：上升途中松开跳键，则截断上升速度
func _apply_jump_cut() -> void:
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y = maxf(velocity.y, jump_velocity * min_jump_ratio)


## 状态机：落地看水平速度分 Idle/Run，空中看纵向速度分 Jump/Fall
func _update_state() -> void:
	if is_on_floor():
		state = State.RUN if absf(velocity.x) > 10.0 else State.IDLE
	else:
		state = State.JUMP if velocity.y < 0.0 else State.FALL


## 动画与状态联动；run 的播放速度随实际移速缩放
func _update_animation(direction: float) -> void:
	var anim := "idle"
	match state:
		State.IDLE:
			anim = "idle"
		State.RUN:
			anim = "run"
		State.JUMP:
			anim = "jump"
		State.FALL:
			anim = "fall"
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)
	if state == State.RUN:
		animated_sprite.speed_scale = clampf(absf(velocity.x) / max_speed, 0.6, 1.4)
	else:
		animated_sprite.speed_scale = 1.0
	if not is_zero_approx(direction):
		animated_sprite.flip_h = direction < 0.0


## 摄像机前瞻：镜头朝移动方向平滑偏移，无输入时回中
func _update_camera_lookahead(direction: float, delta: float) -> void:
	var target := direction * look_ahead_distance
	camera.offset.x = lerpf(camera.offset.x, target, look_ahead_speed * delta)


func _update_debug() -> void:
	if _debug_label == null:
		return
	_debug_label.text = "state: %s\nvel: (%.0f, %.0f)\ncoyote: %.2f  buffer: %.2f\ndouble_jump: %s  air_jumps: %d/%d" % [
		State.keys()[state],
		velocity.x,
		velocity.y,
		_coyote_timer,
		_jump_buffer_timer,
		"ON" if abilities.has_ability(PlayerAbilities.DOUBLE_JUMP) else "OFF",
		_air_jumps_used,
		max_air_jumps,
	]


## 调试快捷键（F1）：切换二段跳解锁状态，方便解锁前后对比验证
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle_double_jump"):
		var unlocked := abilities.toggle_ability(PlayerAbilities.DOUBLE_JUMP)
		_show_toast("二段跳调试切换：" + ("已解锁" if unlocked else "已锁定"))


## 能力门面方法：供能力拾取物等外部对象调用（内部转发给 PlayerAbilities 节点）
func unlock_ability(id: StringName) -> bool:
	return abilities.unlock_ability(id)


func has_ability(id: StringName) -> bool:
	return abilities.has_ability(id)


## 临时屏幕提示（上浮淡出）；M6 接入正式 UI 前的调试反馈
func _show_toast(text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.z_index = 10
	var settings := LabelSettings.new()
	settings.font_size = 34
	settings.font_color = Color(1.0, 0.86, 0.4)
	settings.outline_size = 8
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.85)
	toast.label_settings = settings
	toast.size = Vector2(600.0, 60.0)
	toast.position = Vector2(-300.0, -330.0)
	add_child(toast)
	var tween := toast.create_tween()
	tween.set_parallel(true)
	tween.tween_property(toast, "position:y", toast.position.y - 80.0, 1.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "modulate:a", 0.0, 1.2).set_delay(0.2)
	tween.chain().tween_callback(toast.queue_free)
