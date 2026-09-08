extends AnimatedSprite3D
class_name FacingSprite3D

## Self-contained "billboard direction" sprite.
##
## Splits the 360° around this node (as seen from the camera) into named
## slices (e.g. ["front", "right", "back", "left"], with optional prefix);
## playing the matching animation whenever the slice the camera falls into changes.
##
## angle 0°   = camera directly in front of this node (looking it in the face)
## angle 90°  = camera to this node's right
## angle 180° = camera behind this node
## angle 270° = camera to this node's left
## (angle increases clockwise when viewed from above)

## Names of the directions, in CLOCKWISE order starting at "facing the
## viewer". These are looked up as animation names (with animation_prefix).
@export var direction_names: Array[String] = ["front", "right", "back", "left"]

## Optional: manually control where each direction's zone starts/ends.
## Leave EMPTY to auto-split evenly.
##
## If used, must be the SAME LENGTH as direction_names. Each entry is a
## Vector2(start_degrees, end_degrees) describing that direction's arc,
## going clockwise from start to end. If start > end, the arc wraps through
## 0°/360° (this is how you make "front" straddle the 0° line).
##
## Example: keep "front" playing until the camera is 150° around (i.e. only
## just short of directly behind-ish to the side), instead of handing off to
## "right" at the halfway point of 45°:
##   direction_names  = ["front", "right", "back", "left"]
##   direction_ranges = [
##       Vector2(210, 150),  # front: wraps through 0°, spans 300°
##       Vector2(150, 180),  # right: a thin 30° sliver
##       Vector2(180, 210),  # back
##       Vector2(210, 210),  # (left unused in this example, zero-width)
##   ]
## Zones do not need to be symmetric or equal size just make sure
## start/end values chain together the way you want.
@export var direction_ranges: Array[Vector2] = []

## Prepended to the direction name to build the animation name, e.g. with
## prefix "idle" and direction "front" it looks for animation "idle_front".
@export var animation_prefix: String = ""

## Degrees of "buffer" required past a boundary before switching away from
## the CURRENT direction. Prevents rapid flicker when the camera sits right
## on a zone edge. 0 = no hysteresis (switches exactly at the boundary).
@export_range(0.0, 45.0, 0.5) var hysteresis_degrees: float = 4.0

## How often (seconds) to recompute the direction. 0 = every frame.
@export var update_interval: float = 0.05

var _current_index: int = -1
var _time_since_update: float = 0.0

func _ready() -> void:
	self.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_validate_ranges()

func _process(delta: float) -> void:
	_time_since_update += delta
	if _time_since_update < update_interval:
		return
	_time_since_update = 0.0

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var angle := _get_facing_angle(camera.global_position)
	var index := _resolve_direction_index(angle)

	if index == _current_index:
		return
	_current_index = index

	var dir_name := direction_names[index]
	var anim_name := dir_name if animation_prefix.is_empty() else animation_prefix + "_" + dir_name
	if sprite_frames and sprite_frames.has_animation(anim_name):
		play(anim_name)


## Angle (0-360, clockwise from above) from this node's forward vector to the
## viewer, measured on the XZ plane. 0 = viewer directly in front.
func _get_facing_angle(viewer_position: Vector3) -> float:
	var to_viewer := viewer_position - global_position
	to_viewer.y = 0
	if to_viewer.length_squared() < 0.0001:
		return 0.0
	to_viewer = to_viewer.normalized()

	var forward := -global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	var angle := rad_to_deg(forward.signed_angle_to(to_viewer, Vector3.UP))
	if angle < 0:
		angle += 360.0
	return angle


## Picks a direction index for the given angle, honoring custom ranges (if
## set) and hysteresis (if the camera hasn't moved far enough past the
## current zone's edge yet).
func _resolve_direction_index(angle: float) -> int:
	var candidate := _raw_direction_index(angle)

	if hysteresis_degrees <= 0.0 or _current_index < 0 or candidate == _current_index:
		return candidate

	# Only switch away from the current direction if we're past its edge by
	# at least hysteresis_degrees. Otherwise keep showing the current one.
	var current_range := _get_range(_current_index)
	var expanded_start := fposmod(current_range.x - hysteresis_degrees, 360.0)
	var expanded_end := fposmod(current_range.y + hysteresis_degrees, 360.0)
	if _angle_in_range(angle, expanded_start, expanded_end):
		return _current_index

	return candidate


## Classifies an angle into a direction index using direction_ranges if
## valid, otherwise falling back to an even, centered split.
func _raw_direction_index(angle: float) -> int:
	if _ranges_valid():
		for i in range(direction_ranges.size()):
			var r := direction_ranges[i]
			if _angle_in_range(angle, r.x, r.y):
				return i
		# No range matched (gap in configured ranges) - fall back to nearest
		# center as a safe default rather than doing nothing.
		return _nearest_even_split_index(angle)

	return _nearest_even_split_index(angle)


func _nearest_even_split_index(angle: float) -> int:
	var count := direction_names.size()
	if count <= 0:
		return 0
	var segment := 360.0 / count
	return int(round(angle / segment)) % count


func _get_range(index: int) -> Vector2:
	if _ranges_valid() and index >= 0 and index < direction_ranges.size():
		return direction_ranges[index]
	# Synthesize the even-split range for this index.
	var count := direction_names.size()
	var segment := 360.0 / count
	var center := index * segment
	return Vector2(center - segment * 0.5, center + segment * 0.5)


func _ranges_valid() -> bool:
	return direction_ranges.size() == direction_names.size() and direction_names.size() > 0


## True if `angle` (expected in [0, 360)) falls within [start, end), wrapping
## through 0°/360° automatically when start > end.
func _angle_in_range(angle: float, start: float, end: float) -> bool:
	var a := fposmod(angle, 360.0)
	var s := fposmod(start, 360.0)
	var e := fposmod(end, 360.0)
	if is_equal_approx(s, e):
		# Zero-width or full-circle range; treat as "never matches" (zero-
		# width) unless start/end are both exactly 0, treated as full circle.
		return s == 0.0 and e == 0.0
	if s < e:
		return a >= s and a < e
	else:
		return a >= s or a < e


func _validate_ranges() -> void:
	if direction_ranges.is_empty():
		return
	if direction_ranges.size() != direction_names.size():
		push_warning(
			"FacingSprite3D: direction_ranges size (%d) does not match direction_names size (%d). Falling back to even split." % [
				direction_ranges.size(), direction_names.size()
			]
		)
