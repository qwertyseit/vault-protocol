# vault_3d.gd
# -----------------------------------------------------------------------------
# The 3D vault: a metal cube the Operator can spin in any direction.
# Every side of the cube shows a 2D panel (a module, the timer display, the
# Vault ID plate...). Each panel is drawn into its own SubViewport and that
# picture is put on the cube face as a texture.
#
# Touch controls:
#   * drag             -> rotate the vault (with a little inertia)
#   * tap / press+hold -> the touch is sent to the panel under the finger,
#                         so buttons, wires and keys work like normal UI
#   * two fingers      -> pinch to zoom (mouse wheel on a PC)
# After a spin the vault turns so the nearest side faces the screen, upright.
# -----------------------------------------------------------------------------
extends Node3D

const UI = preload("res://scripts/ui_factory.gd")

enum Face { FRONT, RIGHT, BACK, LEFT, TOP, BOTTOM }
enum Touch { NONE, PENDING, ROTATE, PANEL }

const BOX := 2.0 # cube size (meters)
const PANEL := 1.36 # size of the screen on each face
const FACE_PX := 1024 # pixels of each face screen
const DRAG_THRESHOLD := 22.0 # finger movement (px) that turns a touch into a spin
const HOLD_DELAY := 0.12 # a finger kept still this long is "pressing the panel"
const CANCEL_WINDOW := 0.45 # moving the finger soon after that cancels the press and spins instead
const ROTATE_SPEED := 0.005 # radians per pixel of dragging
const MIN_DISTANCE := 3.0
const MAX_DISTANCE := 7.5
const GAME_DISTANCE := 4.15
const GAME_V_OFFSET := -0.25 # shows the vault a bit higher, between the HUD bars
const SHOWCASE_DISTANCE := 6.8
const SHOWCASE_V_OFFSET := -1.45 # menu: the vault floats above the mission cards
# After a spin the vault stops slightly turned, so it still looks 3D.
const SNAP_TILT := Vector2(-0.15, 0.11) # (yaw, pitch) in radians

# Normal and "up" direction of every face, in the cube's own space.
const FACE_DIRS := [
	[Vector3(0, 0, 1), Vector3(0, 1, 0)], # FRONT
	[Vector3(1, 0, 0), Vector3(0, 1, 0)], # RIGHT
	[Vector3(0, 0, -1), Vector3(0, 1, 0)], # BACK
	[Vector3(-1, 0, 0), Vector3(0, 1, 0)], # LEFT
	[Vector3(0, 1, 0), Vector3(0, 0, -1)], # TOP
	[Vector3(0, -1, 0), Vector3(0, 0, 1)], # BOTTOM
]

## Turn off while the result screen / menu is shown.
var interactive := false

var camera: Camera3D
var box: Node3D
var faces: Array = [] # one Dictionary per Face

var _distance := GAME_DISTANCE
var _v_offset := GAME_V_OFFSET
var _v_offset_now := GAME_V_OFFSET
var _showcase := false # menu mode: slowly spins by itself, ignores touches
var _spin := 0.0
var _shake := 0.0
var _fingers := {} # touch index -> screen position
var _pinching := false
var _pinch_span := 0.0
var _touch: Touch = Touch.NONE
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _press_time := 0.0
var _panel_face := -1
var _panel_pixel := Vector2.ZERO
var _panel_time := 0.0
var _last_move_time := 0.0
var _velocity := Vector2.ZERO
var _snapping := false
var _snap_target := Quaternion.IDENTITY

var _metal: StandardMaterial3D
var _dark_metal: StandardMaterial3D
var _rubber: StandardMaterial3D
var _glass: StandardMaterial3D
var _rivet_mesh: CylinderMesh


func _ready() -> void:
	_make_materials()
	_build_scene()
	reset_view()


# =============================================================================
# Public API (used by main.gd)
# =============================================================================

## Returns an empty full-size Control on the given face (old content is removed).
func face_holder(face: int) -> Control:
	var holder: Control = faces[face]["holder"]
	UI.clear_children(holder)
	return holder


func clear_faces() -> void:
	for f in faces:
		if f["holder"] != null:
			UI.clear_children(f["holder"])
		set_led(f["index"], false, UI.LED_OFF)


## Redraw the face screens every frame (during a mission). false = keep the
## last picture and stop redrawing (menu / result screen, saves battery).
func set_active(active: bool) -> void:
	for f in faces:
		var vp: SubViewport = f["viewport"]
		if vp != null and not f["static"]:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_ONCE


## Menu mode: the vault floats higher, smaller, and slowly turns by itself.
func set_showcase(on: bool) -> void:
	_showcase = on
	_touch = Touch.NONE
	_fingers.clear()
	_pinching = false
	_velocity = Vector2.ZERO
	_snapping = false
	if on:
		_distance = SHOWCASE_DISTANCE
		_v_offset = SHOWCASE_V_OFFSET
	else:
		_distance = GAME_DISTANCE
		_v_offset = GAME_V_OFFSET
		box.position = Vector3.ZERO


## Short camera shake (used on a strike).
func shake(strength := 1.0) -> void:
	_shake = maxf(_shake, strength)


## Small "bump" of the vault (used when a module is disarmed).
func pop() -> void:
	var tw := create_tween()
	tw.tween_property(box, "scale", Vector3.ONE * 1.05, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Small status light next to a face's screen (like the module LEDs in KTANE).
func set_led(face: int, visible_led: bool, color: Color) -> void:
	var led: MeshInstance3D = faces[face]["led"]
	led.visible = visible_led
	var mat: StandardMaterial3D = led.material_override
	mat.albedo_color = color
	mat.emission = color


## Starting angle: front, right side and top are visible.
func reset_view() -> void:
	_velocity = Vector2.ZERO
	_snapping = false
	_touch = Touch.NONE
	box.quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(26.0)) * Quaternion(Vector3.UP, deg_to_rad(-30.0))
	box.position = Vector3.ZERO
	_distance = SHOWCASE_DISTANCE if _showcase else GAME_DISTANCE


# =============================================================================
# Input
# =============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _showcase:
		return

	# Real touchscreen: Godot also sends the FIRST finger as mouse events
	# ("emulate mouse from touch", on by default), so one finger is handled
	# below as a mouse. Here we only track all fingers for the 2-finger pinch.
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_fingers[st.index] = st.position
		else:
			_fingers.erase(st.index)
		if _fingers.size() >= 2:
			_start_pinch()
		elif _pinching:
			_pinching = false
			_start_snap()
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_fingers[sd.index] = sd.position
		if _pinching and _fingers.size() >= 2:
			_update_pinch()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				_on_release(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.3, MIN_DISTANCE, MAX_DISTANCE)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.3, MIN_DISTANCE, MAX_DISTANCE)
	elif event is InputEventMouseMotion:
		if _touch != Touch.NONE:
			_on_move((event as InputEventMouseMotion).position)
	elif event is InputEventMagnifyGesture and not _pinching:
		# laptop touchpad pinch
		_distance = clampf(_distance / (event as InputEventMagnifyGesture).factor, MIN_DISTANCE, MAX_DISTANCE)


## Second finger down: stop spinning / pressing and zoom instead.
func _start_pinch() -> void:
	if _touch == Touch.PANEL:
		_cancel_panel_press()
	_touch = Touch.NONE
	_velocity = Vector2.ZERO
	_snapping = false
	_pinching = true
	_pinch_span = maxf(_finger_span(), 1.0)


func _update_pinch() -> void:
	var span := maxf(_finger_span(), 1.0)
	_distance = clampf(_distance * _pinch_span / span, MIN_DISTANCE, MAX_DISTANCE)
	_pinch_span = span


func _finger_span() -> float:
	var points := _fingers.values()
	return (points[0] as Vector2).distance_to(points[1])


func _on_press(pos: Vector2) -> void:
	if _pinching:
		return
	_touch = Touch.PENDING
	_press_pos = pos
	_last_pos = pos
	_press_time = _now()
	_last_move_time = _press_time
	_velocity = Vector2.ZERO
	_snapping = false


func _on_move(pos: Vector2) -> void:
	if _touch == Touch.PENDING and pos.distance_to(_press_pos) > DRAG_THRESHOLD:
		_touch = Touch.ROTATE
	elif _touch == Touch.PANEL and pos.distance_to(_press_pos) > DRAG_THRESHOLD \
			and _now() - _panel_time < CANCEL_WINDOW:
		# The player wanted to spin, not to press: cancel the press first.
		_cancel_panel_press()
		_touch = Touch.ROTATE
	if _touch == Touch.ROTATE:
		var rel := pos - _last_pos
		_rotate_by(rel)
		# speed in pixels per second, measured with real time (works at any FPS)
		var dt := maxf(_now() - _last_move_time, 1.0 / 120.0)
		_velocity = _velocity.lerp(rel / dt, 0.6).limit_length(2500.0)
		_last_move_time = _now()
	_last_pos = pos


func _on_release(pos: Vector2) -> void:
	match _touch:
		Touch.PENDING:
			# A quick tap: press + release on the panel under the finger.
			var hit := _pick(pos)
			if not hit.is_empty() and interactive:
				_send_click(hit["face"], hit["pixel"], true)
				_send_click(hit["face"], hit["pixel"], false)
		Touch.PANEL:
			var hit := _pick(pos)
			var pixel: Vector2 = _panel_pixel
			if not hit.is_empty() and hit["face"] == _panel_face:
				pixel = hit["pixel"]
			_send_click(_panel_face, pixel, false)
		Touch.ROTATE:
			if _now() - _last_move_time > 0.1:
				_velocity = Vector2.ZERO # the finger stopped before letting go
			if _velocity.length() < 120.0:
				_start_snap()
	_touch = Touch.NONE


func _process(delta: float) -> void:
	_update_camera(delta)

	if _showcase:
		# Menu: turn slowly and float up and down a little.
		_spin += delta * 0.45
		box.quaternion = Quaternion(Vector3.RIGHT, 0.36) * Quaternion(Vector3.UP, _spin)
		box.position.y = sin(_spin * 2.2) * 0.06
		return

	# Finger kept still on a panel -> start pressing it (needed for HOLD).
	if _touch == Touch.PENDING and _now() - _press_time >= HOLD_DELAY:
		var hit := _pick(_press_pos)
		if not hit.is_empty() and interactive:
			_touch = Touch.PANEL
			_panel_face = hit["face"]
			_panel_pixel = hit["pixel"]
			_panel_time = _now()
			_send_click(_panel_face, _panel_pixel, true)
		else:
			_touch = Touch.ROTATE # pressed on the metal case: just spin

	# Inertia after a fast swipe, then snap to the nearest side.
	if _touch == Touch.NONE and not _snapping and _velocity.length() > 0.0:
		_rotate_by(_velocity * delta)
		_velocity *= exp(-5.0 * delta)
		if _velocity.length() < 120.0:
			_velocity = Vector2.ZERO
			_start_snap()

	if _snapping:
		box.quaternion = box.quaternion.slerp(_snap_target, 1.0 - exp(-12.0 * delta))
		if box.quaternion.angle_to(_snap_target) < 0.002:
			box.quaternion = _snap_target
			_snapping = false


## Smooth zoom / height changes + the strike shake.
func _update_camera(delta: float) -> void:
	var k := 1.0 - exp(-8.0 * delta)
	camera.position.z = lerpf(camera.position.z, _distance, k)
	_v_offset_now = lerpf(_v_offset_now, _v_offset, k)
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.09
	camera.v_offset = _v_offset_now + randf_range(-1.0, 1.0) * _shake * 0.06


func _rotate_by(rel: Vector2) -> void:
	var yaw := Quaternion(Vector3.UP, rel.x * ROTATE_SPEED)
	var pitch := Quaternion(Vector3.RIGHT, rel.y * ROTATE_SPEED)
	box.quaternion = (yaw * pitch * box.quaternion).normalized()


func _start_snap() -> void:
	_snap_target = Quaternion(_snapped_basis(box.basis.orthonormalized())).normalized()
	_snapping = true


## The rotation that shows the side most turned to the camera straight on
## AND upright (its text reads normally, never sideways or upside down).
func _snapped_basis(b: Basis) -> Basis:
	var best_face := 0
	var best_dot := -INF
	for i in FACE_DIRS.size():
		var normal_now: Vector3 = b * (FACE_DIRS[i][0] as Vector3)
		if normal_now.z > best_dot: # +Z points to the camera
			best_dot = normal_now.z
			best_face = i
	var n: Vector3 = FACE_DIRS[best_face][0]
	var up: Vector3 = FACE_DIRS[best_face][1]
	# Face frame (right, up, normal) must become (screen right, screen up, to camera),
	# so the cube rotation is the inverse of that frame.
	var straight := Basis(up.cross(n), up, n).transposed()
	# ...then turned a tiny bit, so the sides stay visible.
	var tilt := Basis(Quaternion(Vector3.RIGHT, SNAP_TILT.y) * Quaternion(Vector3.UP, SNAP_TILT.x))
	return tilt * straight


## Which face screen is under this screen position, and which pixel of it.
func _pick(screen_pos: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best_t := INF
	var result := {}
	for f in faces:
		if f["viewport"] == null or f["static"]:
			continue # nothing to press there (the bottom sticker)
		var xf: Transform3D = (f["node"] as Node3D).global_transform
		var normal := xf.basis.z.normalized()
		var denom := dir.dot(normal)
		if denom > -0.0001:
			continue # this side looks away from the camera
		var t := (xf.origin - origin).dot(normal) / denom
		if t <= 0.0 or t >= best_t:
			continue
		var local := xf.affine_inverse() * (origin + dir * t)
		var uv := Vector2(local.x / PANEL + 0.5, 0.5 - local.y / PANEL)
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			continue
		best_t = t
		result = {"face": f["index"], "pixel": uv * FACE_PX}
	return result


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Releases a press "far away" so no button fires, and tells the panel
## (e.g. the Override Button) to forget the press.
func _cancel_panel_press() -> void:
	var holder: Control = faces[_panel_face]["holder"]
	for child in holder.get_children():
		if child.has_method("cancel_touch"):
			child.cancel_touch()
	_send_click(_panel_face, Vector2(-10000, -10000), false)


## Sends a left mouse press/release to the face's 2D screen.
func _send_click(face: int, pixel: Vector2, pressed: bool) -> void:
	var vp: SubViewport = faces[face]["viewport"]
	if vp == null:
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.pressed = pressed
	ev.position = pixel
	ev.global_position = pixel
	vp.push_input(ev, true)


# =============================================================================
# Building the scene (all from code)
# =============================================================================
func _make_materials() -> void:
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.80, 0.84, 0.90)
	_metal.albedo_texture = _brushed_texture()
	_metal.uv1_triplanar = true # the texture wraps every side of the box
	_metal.uv1_scale = Vector3.ONE * 0.9
	_metal.metallic = 0.55
	_metal.roughness = 0.40

	_dark_metal = StandardMaterial3D.new()
	_dark_metal.albedo_color = Color(0.22, 0.24, 0.27)
	_dark_metal.metallic = 0.5
	_dark_metal.roughness = 0.5

	_rubber = StandardMaterial3D.new()
	_rubber.albedo_color = Color(0.10, 0.10, 0.11)
	_rubber.roughness = 0.9


## "Brushed steel": thin horizontal streaks, made in code (no image files).
func _brushed_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 2401
	for y in size:
		var row := r.randf_range(-0.035, 0.035)
		for x in size:
			var v := 0.82 + row + r.randf_range(-0.02, 0.02)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A soft light reflection for the face screens (looks like glass).
func _glass_material() -> StandardMaterial3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.025)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	return m


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.095, 0.115, 0.145) # the 2D vignette darkens the edges
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.74)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42, -28, 0)
	key_light.light_energy = 1.15
	add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(25, 150, 0)
	fill_light.light_energy = 0.45
	add_child(fill_light)
	var rim_light := DirectionalLight3D.new() # from behind: bright edges
	rim_light.rotation_degrees = Vector3(-15, 160, 0)
	rim_light.light_energy = 0.7
	rim_light.light_color = Color(0.75, 0.85, 1.0)
	add_child(rim_light)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH # portrait phone: fit the width
	camera.fov = 46.0
	camera.v_offset = _v_offset
	camera.position = Vector3(0, 0, _distance)
	add_child(camera)
	camera.current = true

	box = Node3D.new()
	box.name = "Vault"
	add_child(box)

	# Metal body
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3.ONE * BOX
	body.mesh = body_mesh
	body.material_override = _metal
	box.add_child(body)

	# Rubber corner bumpers
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var c := MeshInstance3D.new()
				var cm := BoxMesh.new()
				cm.size = Vector3.ONE * 0.36
				c.mesh = cm
				c.material_override = _rubber
				c.position = Vector3(sx, sy, sz) * (BOX * 0.5 - 0.13)
				box.add_child(c)

	# The six faces
	_glass = _glass_material()
	_rivet_mesh = CylinderMesh.new()
	_rivet_mesh.top_radius = 0.035
	_rivet_mesh.bottom_radius = 0.042
	_rivet_mesh.height = 0.03
	_rivet_mesh.radial_segments = 12
	_rivet_mesh.rings = 1
	for i in FACE_DIRS.size():
		faces.append(_build_face(i))


func _build_face(index: int) -> Dictionary:
	var n: Vector3 = FACE_DIRS[index][0]
	var up: Vector3 = FACE_DIRS[index][1]
	var right := up.cross(n)

	var node := Node3D.new()
	node.name = "Face%d" % index
	node.transform = Transform3D(Basis(right, up, n), n * (BOX * 0.5 + 0.004))
	box.add_child(node)

	# Frame around the screen
	var t := 0.06
	var half := PANEL * 0.5
	for side in [[0.0, half + t * 0.5, PANEL + 2 * t, t], [0.0, -half - t * 0.5, PANEL + 2 * t, t],
			[half + t * 0.5, 0.0, t, PANEL], [-half - t * 0.5, 0.0, t, PANEL]]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(side[2], side[3], 0.05)
		bar.mesh = bm
		bar.material_override = _dark_metal
		bar.position = Vector3(side[0], side[1], 0.02)
		node.add_child(bar)

	# Status LED (top-right, outside the screen)
	var led := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	led.mesh = sm
	var led_mat := StandardMaterial3D.new()
	led_mat.emission_enabled = true
	led_mat.emission_energy_multiplier = 1.5
	led.material_override = led_mat
	led.position = Vector3(half - 0.08, half + 0.13, 0.04)
	led.visible = false
	node.add_child(led)

	# Rivets in the middle of each edge of the metal side
	var rivet_pos := BOX * 0.5 - 0.11
	for p in [Vector2(0, rivet_pos), Vector2(0, -rivet_pos), Vector2(rivet_pos, 0), Vector2(-rivet_pos, 0)]:
		var rivet := MeshInstance3D.new()
		rivet.mesh = _rivet_mesh
		rivet.material_override = _dark_metal
		rivet.position = Vector3(p.x, p.y, 0.01)
		rivet.rotation_degrees = Vector3(90, 0, 0) # cylinder points out of the side
		node.add_child(rivet)

	var face := {"index": index, "node": node, "viewport": null, "holder": null, "led": led, "static": false}

	# 2D screen rendered into a SubViewport
	var vp := SubViewport.new()
	vp.name = "Screen%d" % index
	vp.size = Vector2i(FACE_PX, FACE_PX)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var background := ColorRect.new()
	background.color = UI.PANEL
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(vp, background, 0, 0, 1, 1)

	var holder: Control = null
	if index == Face.BOTTOM:
		# The bottom has no module, only a factory sticker. It never changes,
		# so it is drawn once and the vault can be spun by touching it.
		_build_sticker(vp)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		face["static"] = true
	else:
		# Thin bezel + a screw in every corner of the panel
		UI.panel(vp, "Bezel", UI.CLEAR, 0.006, 0.006, 0.994, 0.994, 26, UI.PANEL_LIGHT, 5)
		for c in [Vector2(0.018, 0.018), Vector2(0.946, 0.018), Vector2(0.018, 0.946), Vector2(0.946, 0.946)]:
			var screw := UI.circle(vp, "Screw", UI.SOCKET, c.x, c.y, c.x + 0.036, c.y + 0.036)
			screw.set_border_width_all(4)
			screw.border_color = Color(0, 0, 0, 0.5)
		holder = UI.area(vp, "Holder", 0.015, 0.015, 0.985, 0.985)

	var screen := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(PANEL, PANEL)
	screen.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = vp.get_texture()
	screen.material_override = mat
	screen.position = Vector3(0, 0, 0.006)
	node.add_child(screen)

	var glass := MeshInstance3D.new()
	glass.mesh = qm
	glass.material_override = _glass
	glass.position = Vector3(0, 0, 0.009)
	node.add_child(glass)

	face["viewport"] = vp
	face["holder"] = holder
	return face


## Bottom side: a paper "factory sticker" (pure decoration + a hint for players
## who look for the Vault ID in the wrong place).
func _build_sticker(vp: SubViewport) -> void:
	var paper_color := Color(0.85, 0.82, 0.73)
	var ink := Color(0.13, 0.13, 0.15)
	var paper := UI.rect(vp, "Paper", paper_color, 0.03, 0.03, 0.97, 0.97)

	# Dark title band
	var band := UI.rect(paper, "TitleBand", ink, 0, 0.80, 1, 1)
	UI.text(band, "Title", "VAULT PROTOCOL", 92, paper_color, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0, 0.97, 1, true)

	UI.text(paper, "Model", "MODEL MT-2401   •   REV 1.1", 48, ink, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.68, 0.96, 0.77, true)
	UI.rect(paper, "Line1", ink, 0.08, 0.655, 0.92, 0.662)
	UI.text(paper, "Hint", "VAULT ID IS ON THE TOP PANEL", 44, ink, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.55, 0.96, 0.64)

	# Fake barcode
	var widths := [3, 1, 2, 1, 1, 3, 2, 1, 3, 1, 2, 2, 1, 3, 1, 1, 2, 3, 1, 2, 1, 3, 2, 1, 1, 2, 3, 1, 2, 1, 1, 3, 2]
	var total := 0
	for w in widths:
		total += w + 1
	var x := 0.18
	var unit := 0.64 / float(total)
	for i in widths.size():
		var w: float = widths[i] * unit
		UI.rect(paper, "Bar%d" % i, ink, x, 0.33, x + w, 0.50)
		x += w + unit
	UI.text(paper, "BarcodeText", "0  2401  57  31  8", 34, ink, HORIZONTAL_ALIGNMENT_CENTER, 0.1, 0.27, 0.9, 0.33)

	UI.text(paper, "Care", "HANDLE WITH CARE", 60, ink, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.155, 0.96, 0.25, true)

	# Hazard stripes along the bottom (clipped diagonal bars)
	var stripes := UI.area(paper, "Stripes", 0, 0, 1, 0.12)
	stripes.clip_contents = true
	UI.rect(stripes, "StripeBase", UI.AMBER, 0, 0, 1, 1)
	var strip_w := (0.94 * FACE_PX)
	var strip_h := 0.12 * 0.94 * FACE_PX
	var i_bar := 0
	var bx := -strip_h
	while bx < strip_w + strip_h:
		var bar := ColorRect.new()
		bar.color = ink
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = Vector2(46, strip_h * 2.0)
		bar.position = Vector2(bx, -strip_h * 0.5)
		bar.rotation = deg_to_rad(35.0)
		bar.name = "Stripe%d" % i_bar
		stripes.add_child(bar)
		bx += 110.0
		i_bar += 1
