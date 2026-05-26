class_name PlayerAnimBinding extends AnimationTree


@onready var _player: CharacterBody3D = get_parent()


var _prev_rotation_y: float = 0.0
var _is_pivoting_pulse: bool = false
var _is_hit_pulse: bool = false  # wired when damage system exists

# Change-guard caches — avoid invalidating the parameter cache by re-writing
# the same value every frame.
var _cached_move_blend: Vector2 = Vector2.INF
var _cached_drift_blend: float = INF
var _cached_is_steering: bool = false
var _cached_is_slow: bool = false


func _ready() -> void:
	active = true
	_prev_rotation_y = _player.rotation.y
	_player.dash_fired.connect(_on_dash_fired)
	_player.pivot_started.connect(_on_pivot_started)
	# Future: _player.hit_received.connect(_on_hit_received)


func _physics_process(delta: float) -> void:
	# One-frame pulses always write — the explicit true→false transition is
	# how the StateMachine catches the single-frame `true` window.
	set("parameters/Top/Locomotion/conditions/is_pivoting", _is_pivoting_pulse)
	_is_pivoting_pulse = false
	set("parameters/Top/conditions/is_hit", _is_hit_pulse)
	_is_hit_pulse = false

	var steering := _player.is_steering()
	if steering != _cached_is_steering:
		set("parameters/Top/Locomotion/conditions/is_steering", steering)
		_cached_is_steering = steering

	var speed := _player.velocity.length()
	var slow := speed < _player.idle_threshold
	if slow != _cached_is_slow:
		set("parameters/Top/Locomotion/conditions/is_slow", slow)
		_cached_is_slow = slow

	var normalized_speed := clampf(speed / _player.max_speed, 0.0, 1.0)
	var rotation_delta := (_player.rotation.y - _prev_rotation_y) / delta
	var turn_rate := clampf(
		rotation_delta / deg_to_rad(_player.turn_rate_deg), -1.0, 1.0
	)
	_prev_rotation_y = _player.rotation.y

	var move_blend := Vector2(turn_rate, normalized_speed)
	if move_blend != _cached_move_blend:
		set("parameters/Top/Locomotion/Move/blend_position", move_blend)
		_cached_move_blend = move_blend

	if normalized_speed != _cached_drift_blend:
		set("parameters/Top/Locomotion/Drift/blend_position", normalized_speed)
		_cached_drift_blend = normalized_speed


func _on_dash_fired() -> void:
	set("parameters/DashShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _on_pivot_started() -> void:
	_is_pivoting_pulse = true
