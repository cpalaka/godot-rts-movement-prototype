extends CharacterBody3D


# Signals for the animation binding (player_anim.gd, future session).
@warning_ignore("unused_signal")
signal dash_fired


# Tunable exports — see spec for rationale
@export var max_speed: float = 7.0
@export var accel: float = 24.0
@export var friction: float = 14.0
@export var turn_rate_deg: float = 540.0
@export var walk_threshold: float = 2.0
@export var dash_strength: float = 16.0
@export var dash_cooldown: float = 1.0
@export var impulse_decay: float = 50.0
# Tuning exports for the animation interface (see animation state machine spec)
@export var pivot_reversal_threshold: float = -0.5  # dot product cutoff (~120° reversal)
@export var pivot_min_speed: float = 2.0            # below this speed, reversal too soft to register
@export var idle_threshold: float = 0.1             # below this speed, future Drift→Idle transition fires

# Internal velocity channels
var input_velocity: Vector3 = Vector3.ZERO
var impulse_velocity: Vector3 = Vector3.ZERO

# Steering state
var _steering: bool = false
var _cursor_world: Vector3 = Vector3.ZERO
var _dash_ready_at: float = 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_steering = mb.pressed
	if event.is_action_pressed("dash"):
		_try_dash()


func _physics_process(delta: float) -> void:
	# 1. Compute target input_velocity from steering signal
	var target_v := Vector3.ZERO
	if _steering and _refresh_cursor_world():
		var to_cursor := _cursor_world - global_position
		to_cursor.y = 0.0
		var distance := to_cursor.length()
		if distance > 0.0001:
			var dir := to_cursor / distance
			var magnitude := clampf(distance / walk_threshold, 0.0, 1.0)
			target_v = dir * max_speed * magnitude

	# 2. Integrate input_velocity (accel toward target, friction toward zero)
	if target_v != Vector3.ZERO:
		input_velocity = input_velocity.move_toward(target_v, accel * delta)
	else:
		input_velocity = input_velocity.move_toward(Vector3.ZERO, friction * delta)

	# 3. Decay impulse_velocity toward zero
	impulse_velocity = impulse_velocity.move_toward(Vector3.ZERO, impulse_decay * delta)

	# 4. Combine channels and apply
	velocity = input_velocity + impulse_velocity

	# 5. Facing follows velocity heading (smoothed)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() > 0.01:
		var target_yaw := atan2(horizontal.x, horizontal.z)
		var max_step := deg_to_rad(turn_rate_deg) * delta
		rotation.y = _step_angle(rotation.y, target_yaw, max_step)

	move_and_slide()


# Projects current mouse position onto the y=0 plane and stores hit in _cursor_world.
# Returns true if projection succeeded (camera exists, ray not parallel to plane,
# intersection is forward of camera).
func _refresh_cursor_world() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if absf(ray_dir.y) < 0.0001:
		return false
	var t := -ray_origin.y / ray_dir.y
	if t < 0.0:
		return false
	_cursor_world = ray_origin + ray_dir * t
	return true


func _try_dash() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _dash_ready_at:
		return
	var dir := _resolve_dash_dir()
	if dir == Vector3.ZERO:
		return
	impulse_velocity = dir * dash_strength
	_dash_ready_at = now + dash_cooldown
	dash_fired.emit()


func _resolve_dash_dir() -> Vector3:
	# Priority: active steering → current velocity → current facing
	if _steering and _refresh_cursor_world():
		var to_cursor := _cursor_world - global_position
		to_cursor.y = 0.0
		if to_cursor.length_squared() > 0.0001:
			return to_cursor.normalized()
	var v := Vector3(velocity.x, 0.0, velocity.z)
	if v.length_squared() > 0.01:
		return v.normalized()
	# Fall back to facing. The Facing cone in player.tscn is oriented along
	# local +Z, so transform.basis.z is where the player visually points.
	# (Godot's canonical forward is -basis.z; we override for visual consistency.)
	return transform.basis.z


# Public API for external systems to push the player.
# Knockback callers should pass a 3D impulse; only XZ components are used.
# Note: this is ADDITIVE (unlike dash, which OVERWRITES). See spec asymmetry note.
func apply_impulse(impulse: Vector3) -> void:
	impulse_velocity += Vector3(impulse.x, 0.0, impulse.z)


# Public accessor for animation binding (player_anim.gd in future session).
func is_steering() -> bool:
	return _steering


static func _step_angle(from: float, to: float, max_delta: float) -> float:
	# Shortest-arc step from `from` to `to`, clamped to `max_delta`.
	var diff := wrapf(to - from, -PI, PI)
	if absf(diff) <= max_delta:
		return to
	return from + signf(diff) * max_delta
