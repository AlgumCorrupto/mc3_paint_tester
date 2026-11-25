@icon("res://addons/mc3_car_paint/icon.svg")
class_name MC3CarPaint
extends Node3D
## Midnight Club 3 style car paint and chrome.
##
## Add this node as a child of a car (or set [member target]). Every MeshInstance3D below it is painted
## with the MC3 car paint pipeline, except meshes in one of the chrome groups, which get the chrome material:
##   group "mc3_chrome"          -> [member chrome_color]
##   group "mc3_rim_chrome"      -> [member rim_chrome_color]
##   group "mc3_exhaust_chrome"  -> [member exhaust_chrome_color]
##   group "mc3_glass"           -> alpha blended coloured glass, [member glass_tint] / [member glass_opacity]
##   group "mc3_headlight_glass" -> glass that lights up with [member headlights_on]
##   group "mc3_brakelight_glass"-> glass that lights up with [member headlights_on] + [member brakelights_on]
##   group "mc3_paint_ignore"    -> skipped
## (a group on a parent node applies to all meshes below it)
##
## Car paint:  paint map (256x256, one glow sprite per light) + env map (256x256, panorama + light glows),
##             combined by a shader that does normal indexed (matcap style) lookups.
## Chrome:     the same env map, modulated by vertex lighting and a tint.
## Glass:      flat tint + Fresnel weighted env map reflection, alpha blended.
## Paint and chrome were verified against an Xbox capture, glass was rebuilt from one (see README).
##
## Lights: every OmniLight3D / SpotLight3D in the scene is used automatically (the game uses the 10 closest
## lights), plus [member light_sources] and an optional light attached to the camera.
## Works at run time only (it needs the active camera).

enum PaintType { METALLIC, PEARL, GLOSS }

const MAX_LIGHTS := 12
const PAINT_MAP_SHADER := preload("shaders/paint_map.gdshader")
const ENV_MAP_SHADER := preload("shaders/env_map.gdshader")
const CAR_SHADER := preload("shaders/car_paint.gdshader")
const CHROME_SHADER := preload("shaders/chrome.gdshader")
const GLASS_SHADER := preload("shaders/glass.gdshader")
const SKY_SHADER := preload("shaders/pano_sky.gdshader")
const IGNORE_GROUP := &"mc3_paint_ignore"
const CHROME_GROUPS := [&"mc3_chrome", &"mc3_rim_chrome", &"mc3_exhaust_chrome"]
const GLASS_GROUPS := [&"mc3_glass", &"mc3_headlight_glass", &"mc3_brakelight_glass"]
## chrome groups first (kinds 0-2), then glass groups (kinds 3-5)
const SPECIAL_GROUPS := [&"mc3_chrome", &"mc3_rim_chrome", &"mc3_exhaust_chrome", &"mc3_glass", &"mc3_headlight_glass", &"mc3_brakelight_glass"]

## Used when the scene has no lights and use_fallback_rig is on (metres, relative to the car).
const FALLBACK_RIG := [
	Vector3(-6.0, 5.0, -6.0), Vector3(6.0, 5.0, -6.0),
	Vector3(-6.0, 5.0, 6.0), Vector3(6.0, 5.0, 6.0),
	Vector3(0.0, 8.0, 0.0),
	Vector3(-9.0, 1.5, 0.0), Vector3(9.0, 1.5, 0.0),
	Vector3(0.0, 1.5, 9.0), Vector3(0.0, 1.5, -9.0),
]

# ---------------------------------------------------------------------------------------
@export_group("Target")
## Node whose MeshInstance3D descendants get painted. Empty = the parent of this node.
@export var target: Node
## Camera used for the view dependent parts. Empty = the viewport's current camera.
@export var camera: Camera3D
## Use the bounds of the painted meshes as the car position. Off = this node's position.
@export var auto_center := true

# ---------------------------------------------------------------------------------------
@export_group("Paint")
@export_color_no_alpha var base_color := Color(1.0, 0.45, 0.10)
@export var paint_type: PaintType = PaintType.METALLIC
## Second colour of the Pearl paint type (gradient stop 0).
@export_color_no_alpha var pearl_color := Color(0.45, 0.85, 1.0)
## Picker colour -> gradient stop 1. The game stores dark colours (capture: ~0.25 of the visible colour).
@export_range(0.05, 1.0, 0.01) var body_color_scale := 0.25
## SetupMetallicGradient scale; stop 0 = clamp(normalize(stop 1) * scale). The capture matches 1.5.
@export_range(0.5, 3.0, 0.01) var metallic_scale := 1.5
@export_range(0.0, 0.9, 0.01) var gradient_start := 0.0

# ---------------------------------------------------------------------------------------
@export_group("Highlights")
## Sprite half-size is size * 0.3 in the game's -1..1 ortho space (capture: about 1.2).
@export_range(0.3, 3.0, 0.01) var highlight_size := 1.2
@export_range(0.0, 1.5, 0.01) var highlight_intensity := 0.8
## DrawHilight fades a light out linearly over 25 m.
@export_range(5.0, 60.0, 0.5) var light_fade_distance := 25.0
## The game only draws the 10 closest lights.
@export_range(1, 12) var max_lights := 10
## Light attached to the camera (keeps the centre of the map lit).
@export var camera_light := true
## Additional light positions (any Node3D).
@export var light_sources: Array[Node3D] = []
## Also use every OmniLight3D / SpotLight3D in the scene.
@export var auto_collect_lights := true
## When there are no lights at all, use a built-in garage-like rig.
@export var use_fallback_rig := true
@export var fallback_rig_scale := 1.0
## Degrees per second.
@export var fallback_rig_rotation := 0.0
## Use the (non-linear) placement formula from the disassembly instead of "highlight where normal = half vector".
## Unverified, kept for comparison.
@export var game_placement_formula := false

# ---------------------------------------------------------------------------------------
@export_group("Environment")
## Flat reflection strength written to the env map alpha (capture: 92/255).
@export_range(0.0, 1.0, 0.01) var reflection_alpha := 0.361
## 360 degree panorama (lat/long). Empty = procedural garage-like panorama.
@export var panorama: Texture2D:
	set(value):
		panorama = value
		_apply_panorama()
@export_range(0.0, 3.0, 0.01) var panorama_gain := 2.0
@export var invert_panorama_scroll := false
## Up-facing normals read the LOWER half of the env map (verified in the capture), so a physically
## upright panorama shows its floor on roofs. Turn this on to flip it.
@export var panorama_flip_v := false
## Physically oriented panorama: the reflection shows what is behind the camera and follows its yaw AND pitch,
## using the same equirectangular convention as Godot's PanoramaSkyMaterial, so the same image can be the
## scene background. Off = the game's behaviour (a flat blit scrolled by the heading only).
@export var panorama_match_sky := false
@export_range(0.0, 2.0, 0.01) var light_dot_gain := 1.0
## Garage 100, default city 140.
@export_range(60.0, 150.0, 1.0) var env_fov := 100.0
## The env camera sits at the car position plus this height (game: 1 m).
@export var env_camera_height := 1.0

# ---------------------------------------------------------------------------------------
@export_group("Vertex lighting")
## Capture: 0.065.
@export_color_no_alpha var ambient := Color(0.065, 0.065, 0.065)
## Capture: material colour (c107) = white.
@export_range(0.0, 3.0, 0.01) var vertex_light_scale := 1.0
## Direction the light travels, world space. Capture values (garage).
@export var light0_direction := Vector3(0.63797, -0.50528, -0.58111)
@export_color_no_alpha var light0_color := Color(0.34036, 0.34036, 0.34036)
@export var light1_direction := Vector3(0.0, -0.95783, -0.28735)
@export_color_no_alpha var light1_color := Color(0.25, 0.25, 0.25)
@export var light2_direction := Vector3(-0.57735, -0.57735, -0.57735)
@export_color_no_alpha var light2_color := Color(0.0, 0.0, 0.0)

# ---------------------------------------------------------------------------------------
@export_group("Lookup and reflection")
## uv = (a * clip.xy + s * nclip.xy) * scale + 0.5. Capture: scale 0.64248 at 43 degrees FOV (k = 1).
@export var auto_lookup_scale := true
## scale = k * (0.35 + 0.65 * (fov - 25) / 40), fov = vertical FOV in degrees (FixupTexMatrices).
@export_range(0.5, 2.0, 0.01) var lookup_scale_k := 1.0
## Used when auto_lookup_scale is off.
@export_range(0.05, 3.0, 0.001) var lookup_scale := 0.64248
## s (c116.w).
@export_range(0.0, 1.0, 0.001) var normal_weight := 0.25
## a for the paint map (c117.z).
@export_range(0.0, 0.5, 0.001) var paint_position_weight := 0.05
## a for the env map = fresnel_position * normal_weight (c146.x * c116.w). Capture: 0.44.
@export_range(0.0, 2.0, 0.001) var fresnel_position := 0.44
## COLOR0.a = clamp((1 - n.z) * scale, min, max). Capture: 0.275 / 1.0 / 0.675.
@export_range(0.0, 1.0, 0.001) var fresnel_min := 0.275
@export_range(0.0, 1.0, 0.001) var fresnel_max := 1.0
@export_range(0.0, 2.0, 0.001) var fresnel_scale := 0.675
@export_range(0.0, 3.0, 0.01) var reflection_gain := 1.0
@export_range(0.0, 3.0, 0.01) var paint_gain := 1.0
## The game does not renormalise the transformed normal, so the lookup depends on the model scale.
## Off = always use unit normals.
@export var keep_model_scale := false
## The game does the lookups per vertex; per pixel is smoother.
@export var per_pixel_lookup := false
## Convert the display-referred result to linear (needed for Godot's sRGB output).
@export var gamma_correct := true

# ---------------------------------------------------------------------------------------
@export_group("Chrome")
@export_color_no_alpha var rim_chrome_color := Color.from_string("#fff987", Color.WHITE)
@export_color_no_alpha var chrome_color := Color(1.0, 1.0, 1.0)
@export_color_no_alpha var exhaust_chrome_color := Color.from_string("#434cb0", Color.WHITE)
## chrome_color_a: ambient light is lifted toward white by this much (default 0.2).
@export_range(0.0, 1.0, 0.01) var chrome_ambient_lift := 0.2
## a = chrome_position_weight * normal_weight. SetFresnelParamsChrome uploads 0.8.
@export_range(0.0, 2.0, 0.001) var chrome_position_weight := 0.8
## k of FixupTexMatrices for chrome (wheel 1.0, others 1.2).
@export_range(0.5, 2.0, 0.01) var chrome_lookup_k := 1.0

# ---------------------------------------------------------------------------------------
@export_group("Glass")
## Plain glass (group mc3_glass). Capture: tint 22/255 grey, opacity 115/255.
@export_color_no_alpha var glass_tint := Color(0.0863, 0.0863, 0.0863)
@export_range(0.0, 1.0, 0.001) var glass_opacity := 0.451
## Headlight glass (group mc3_headlight_glass). Not in the capture: a pale tint to be adjusted.
@export_color_no_alpha var headlight_glass_tint := Color(0.55, 0.58, 0.62)
@export_range(0.0, 1.0, 0.001) var headlight_glass_opacity := 0.45
## Brakelight glass (group mc3_brakelight_glass). Not in the capture: a red tint to be adjusted.
@export_color_no_alpha var brakelight_glass_tint := Color(0.55, 0.04, 0.04)
@export_range(0.0, 1.0, 0.001) var brakelight_glass_opacity := 0.55
## coloredglass_headlightval: lifts the ambient light of headlight glass by 0.5 * this.
@export_range(0.0, 1.0, 0.01) var headlights_on := 0.0
## coloredglass_brakelightval: brakelight glass is lifted by 0.5 * headlights_on + 0.5 * this.
@export_range(0.0, 1.0, 0.01) var brakelights_on := 0.0
## glassFresnelParams = (0.9, 0.124, 1.0, 1.5): a = glass_position_weight * normal_weight,
## COLOR0.a = clamp((1 - n.z) * scale, min, max).
@export_range(0.0, 2.0, 0.001) var glass_position_weight := 0.9
@export_range(0.0, 1.0, 0.001) var glass_fresnel_min := 0.124
@export_range(0.0, 1.0, 0.001) var glass_fresnel_max := 1.0
@export_range(0.0, 3.0, 0.001) var glass_fresnel_scale := 1.5
@export_range(0.5, 2.0, 0.01) var glass_lookup_k := 1.0

# ---------------------------------------------------------------------------------------
# internals
# ---------------------------------------------------------------------------------------
var _paint_vp: SubViewport
var _env_vp: SubViewport
var _paint_mat: ShaderMaterial
var _env_mat: ShaderMaterial
var _car_mat: ShaderMaterial
var _chrome_mats: Array = []
var _glass_mats: Array = []
var _sky_mat: ShaderMaterial
var _sky: Sky
var _paint_img: Image
var _paint_tex: ImageTexture
var _dot_img: Image
var _dot_tex: ImageTexture
var _meshes: Array = []
var _chrome_meshes: Array = [[], [], [], [], [], []]   # kinds 0-2 chrome, 3-5 glass
var _scene_lights: Array = []
var _lights_dirty := true
var _bounds := AABB(Vector3.ZERO, Vector3.ONE)
var _center := Vector3.ZERO
var _rig_angle := 0.0
var _lookup_scale_now := 0.64248


func _ready() -> void:
	_build_maps()
	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)
	refresh_targets()


func _process(delta: float) -> void:
	var cam := _get_camera()
	if cam == null:
		return
	_rig_angle += deg_to_rad(fallback_rig_rotation) * delta
	if _lights_dirty:
		_rescan_lights()
	_update_bounds()
	_update_lights(cam)
	_update_uniforms(cam)


# ---------------------------------------------------------------------------------------
# public API
# ---------------------------------------------------------------------------------------
## The car paint material (assign it to extra meshes if you like).
func get_material() -> ShaderMaterial:
	return _car_mat


## kind: 0 = chrome, 1 = rim chrome, 2 = exhaust chrome.
func get_chrome_material(kind: int = 0) -> ShaderMaterial:
	return _chrome_mats[clampi(kind, 0, 2)]


## kind: 0 = glass, 1 = headlight glass, 2 = brakelight glass.
func get_glass_material(kind: int = 0) -> ShaderMaterial:
	return _glass_mats[clampi(kind, 0, 2)]


## 256x256 paint ("diffuse") map, useful for debugging.
func get_paint_texture() -> Texture2D:
	return _paint_vp.get_texture()


## 256x256 environment map (rgb = reflection colour, a = reflection strength).
func get_env_texture() -> Texture2D:
	return _env_vp.get_texture()


func get_center() -> Vector3:
	return _center


func get_bounds() -> AABB:
	return _bounds


## Current lookup scale (depends on the camera FOV when auto_lookup_scale is on).
func get_lookup_scale() -> float:
	return _lookup_scale_now


## Re-scan the target for meshes. Call it after adding or removing meshes below the target.
func refresh_targets() -> void:
	_meshes.clear()
	for i in SPECIAL_GROUPS.size():
		_chrome_meshes[i].clear()
	var root: Node = target if target != null else get_parent()
	if root != null:
		_collect(root, -1, _meshes, _chrome_meshes)
	_assign_materials(_meshes, _chrome_meshes)
	_update_bounds()


## Paint another node (and its MeshInstance3D descendants) with the same materials.
func apply_to(root: Node) -> void:
	var paint: Array = []
	var chrome: Array = [[], [], [], [], [], []]
	_collect(root, -1, paint, chrome)
	_assign_materials(paint, chrome)


## Re-scan the scene for OmniLight3D / SpotLight3D nodes. Happens automatically when lights are added or removed.
func refresh_lights() -> void:
	_lights_dirty = true


## A Sky that shows the current panorama with the same orientation as the reflections
## (see panorama_match_sky). It follows [member panorama] automatically:
##     environment.background_mode = Environment.BG_SKY
##     environment.sky = paint.get_sky()
func get_sky() -> Sky:
	if _sky == null:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = SKY_SHADER
		_sky = Sky.new()
		_sky.sky_material = _sky_mat
		_apply_panorama()
	return _sky


func set_panorama_from_file(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		push_warning("MC3CarPaint: could not load panorama '%s'." % path)
		return false
	panorama = ImageTexture.create_from_image(img)
	return true


# ---------------------------------------------------------------------------------------
# set up
# ---------------------------------------------------------------------------------------
func _build_maps() -> void:
	_paint_vp = _make_viewport()
	_env_vp = _make_viewport()
	_paint_mat = _add_map_rect(_paint_vp, PAINT_MAP_SHADER)
	_env_mat = _add_map_rect(_env_vp, ENV_MAP_SHADER)

	_paint_img = Image.create(MAX_LIGHTS, 1, false, Image.FORMAT_RGBAF)
	_paint_tex = ImageTexture.create_from_image(_paint_img)
	_paint_mat.set_shader_parameter("light_data", _paint_tex)
	_dot_img = Image.create(MAX_LIGHTS, 1, false, Image.FORMAT_RGBAF)
	_dot_tex = ImageTexture.create_from_image(_dot_img)
	_env_mat.set_shader_parameter("dot_data", _dot_tex)

	_car_mat = ShaderMaterial.new()
	_car_mat.shader = CAR_SHADER
	_car_mat.set_shader_parameter("paint_map", _paint_vp.get_texture())
	_car_mat.set_shader_parameter("env_map", _env_vp.get_texture())

	_chrome_mats.clear()
	for i in 3:
		var m := ShaderMaterial.new()
		m.shader = CHROME_SHADER
		m.set_shader_parameter("env_map", _env_vp.get_texture())
		_chrome_mats.append(m)
	_glass_mats.clear()
	for i in 3:
		var gm := ShaderMaterial.new()
		gm.shader = GLASS_SHADER
		gm.set_shader_parameter("env_map", _env_vp.get_texture())
		_glass_mats.append(gm)
	_apply_panorama()


func _make_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp, false, Node.INTERNAL_MODE_FRONT)
	return vp


func _add_map_rect(vp: SubViewport, shader: Shader) -> ShaderMaterial:
	var rect := ColorRect.new()
	rect.size = Vector2(256, 256)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	vp.add_child(rect)
	return mat


func _apply_panorama() -> void:
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("use_pano", panorama != null)
		if panorama != null:
			_sky_mat.set_shader_parameter("pano", panorama)
	if _env_mat == null:
		return
	_env_mat.set_shader_parameter("use_custom_pano", panorama != null)
	if panorama != null:
		_env_mat.set_shader_parameter("pano_tex", _prepare_panorama(panorama))


## The env map is only 256x256, so the panorama is sampled with mipmaps. Imported 2D textures usually have
## none, so a mipmapped copy (at most 2048 wide) is made here.
func _prepare_panorama(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	if img.is_compressed() and img.decompress() != OK:
		return tex
	if img.get_width() > 2048:
		img.resize(2048, maxi(img.get_height() * 2048 / img.get_width(), 1), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _collect(n: Node, inherited: int, paint_out: Array, chrome_out: Array) -> void:
	if n.is_in_group(IGNORE_GROUP):
		return
	var kind := inherited
	for i in SPECIAL_GROUPS.size():
		if n.is_in_group(SPECIAL_GROUPS[i]):
			kind = i
	if n is MeshInstance3D:
		if kind >= 0:
			chrome_out[kind].append(n)
		else:
			paint_out.append(n)
	for c in n.get_children():
		_collect(c, kind, paint_out, chrome_out)


func _assign_materials(paint: Array, chrome: Array) -> void:
	for mi in paint:
		mi.material_override = _car_mat
	for i in 3:
		for mi in chrome[i]:
			mi.material_override = _chrome_mats[i]
		for mi in chrome[i + 3]:
			mi.material_override = _glass_mats[i]


func _get_camera() -> Camera3D:
	return camera if camera != null else get_viewport().get_camera_3d()


func _on_tree_changed(n: Node) -> void:
	if n is Light3D:
		_lights_dirty = true


func _rescan_lights() -> void:
	_lights_dirty = false
	_scene_lights.clear()
	if not auto_collect_lights:
		return
	var root := get_tree().root
	for type_name in ["OmniLight3D", "SpotLight3D"]:
		for n in root.find_children("*", type_name, true, false):
			_scene_lights.append(n)


func _update_bounds() -> void:
	# the bounds come from the painted meshes; chrome and glass only count when there is nothing else
	var found := _merge_bounds(_meshes)
	if not found:
		for i in SPECIAL_GROUPS.size():
			if _merge_bounds(_chrome_meshes[i]):
				found = true
				break
	_center = _bounds.get_center() if (auto_center and found) else global_position


func _merge_bounds(list: Array) -> bool:
	var found := false
	var box := AABB()
	for mi in list:
		if not is_instance_valid(mi) or not mi.is_inside_tree() or not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if found:
			box = box.merge(b)
		else:
			box = b
			found = true
	if found:
		_bounds = box
	return found


# ---------------------------------------------------------------------------------------
# camera helpers
# ---------------------------------------------------------------------------------------
func _vertical_fov(cam: Camera3D) -> float:
	if cam.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return 43.0
	var fov := cam.fov
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) / _aspect()))
	return fov


func _aspect() -> float:
	var size := get_viewport().get_visible_rect().size
	return maxf(size.x, 1.0) / maxf(size.y, 1.0)


## FixupTexMatrices: k * (0.35 + 0.65 * (fov - 25) / 40)
func _scale_for_fov(k: float, fov_deg: float) -> float:
	return clampf(k * (0.35 + 0.65 * (fov_deg - 25.0) / 40.0), 0.05, 3.0)


# ---------------------------------------------------------------------------------------
# lights -> paint map sprites and env map dots
# ---------------------------------------------------------------------------------------
func _light_positions(cam: Camera3D) -> Array:
	var pts: Array = []
	for n in light_sources:
		if n != null and is_instance_valid(n) and n.is_inside_tree():
			pts.append(n.global_position)
	if auto_collect_lights:
		for n in _scene_lights:
			if is_instance_valid(n) and n.is_inside_tree() and n.is_visible_in_tree() and not (n in light_sources):
				pts.append(n.global_position)
	if pts.is_empty() and use_fallback_rig:
		var rot := Basis(Vector3.UP, _rig_angle)
		for off in FALLBACK_RIG:
			pts.append(_center + rot * (off * fallback_rig_scale))

	# the game draws the closest lights only
	var c := _center
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(c) < b.distance_squared_to(c))
	var budget := clampi(max_lights, 1, MAX_LIGHTS)
	if camera_light:
		budget -= 1
	if pts.size() > budget:
		pts.resize(maxi(budget, 0))
	if camera_light:
		var cb := cam.global_transform.basis
		var to_cam := (cam.global_position - c).normalized()
		pts.append(c + to_cam * 10.0 + cb.y * 2.5 + cb.x * 1.5)
	return pts


func _update_lights(cam: Camera3D) -> void:
	var c := _center
	var b_hat := (cam.global_position - c).normalized()
	var to_view := cam.global_transform.basis.transposed()   # world -> view (x right, y up, z towards viewer)
	var env_origin := c + Vector3.UP * env_camera_height
	var tan_half := tan(deg_to_rad(env_fov * 0.5))

	# projection scales of the main camera (what the vertex shader sees as PROJECTION_MATRIX)
	var fov := _vertical_fov(cam)
	var fy := 1.0 / tan(deg_to_rad(fov) * 0.5)
	var fx := fy / _aspect()
	var lscale := _lookup_scale_now
	var cv: Vector3 = to_view * (c - cam.global_position)     # car centre in view space

	var count := 0
	var dcount := 0
	for light_pos in _light_positions(cam):
		if count >= MAX_LIGHTS:
			break
		var lw: Vector3 = light_pos
		var d := (lw - c).length()
		var a_hat: Vector3 = (lw - c) / maxf(d, 0.0001)

		# DrawHilight: the normal that reflects the light to the camera is the half vector
		var h := a_hat + b_hat
		if h.length() > 0.0001:
			var w: Vector3 = to_view * h.normalized()
			var mx: float
			var my: float
			if game_placement_formula:
				mx = 0.5 + 0.5 * (-2.0 * w.x * (1.0 - absf(w.x)))
				my = 0.5 + 0.5 * (2.0 * w.y * (1.0 - absf(w.z)))
			else:
				# same mapping as the car shader's paint lookup, so the highlight lands where normal = H
				mx = 0.5 + lscale * (normal_weight * fx * w.x + paint_position_weight * fx * cv.x)
				my = 0.5 + lscale * (normal_weight * fy * w.y + paint_position_weight * fy * cv.y)
			var alpha := highlight_intensity * (1.0 - clampf(d / light_fade_distance, 0.0, 1.0))
			_paint_img.set_pixel(count, 0, Color(mx, my, highlight_size * 0.15, alpha))
			count += 1

		# env map light glow: perspective projection from the car towards the viewer; the game's
		# 180 degree roll makes the image axes line up with the lookup (u right, v towards "up").
		if dcount < MAX_LIGHTS:
			var dv: Vector3 = to_view * (lw - env_origin).normalized()
			if dv.z > 0.05:
				var ex := dv.x / (dv.z * tan_half)
				var ey := dv.y / (dv.z * tan_half)
				if absf(ex) < 1.3 and absf(ey) < 1.3:
					_dot_img.set_pixel(dcount, 0, Color(0.5 + 0.5 * ex, 0.5 + 0.5 * ey, 0.045, 0.85))
					dcount += 1

	_paint_tex.update(_paint_img)
	_dot_tex.update(_dot_img)
	_paint_mat.set_shader_parameter("light_count", count)
	_env_mat.set_shader_parameter("dot_count", dcount)


# ---------------------------------------------------------------------------------------
# uniforms
# ---------------------------------------------------------------------------------------
func _gradient_colors() -> Array:
	# SetupMetallicGradient / SetupPearlGradient / SetupGlossGradient
	var b := Vector3(base_color.r, base_color.g, base_color.b) * body_color_scale
	var a := Vector3.ZERO
	match paint_type:
		PaintType.METALLIC:
			a = (b.normalized() * metallic_scale).clamp(Vector3.ZERO, Vector3.ONE)
		PaintType.PEARL:
			a = Vector3(pearl_color.r, pearl_color.g, pearl_color.b)
		PaintType.GLOSS:
			a = b * 0.85
	return [Color(a.x, a.y, a.z, 1.0), Color(b.x, b.y, b.z, 1.0)]


func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _update_uniforms(cam: Camera3D) -> void:
	var fov := _vertical_fov(cam)
	_lookup_scale_now = _scale_for_fov(lookup_scale_k, fov) if auto_lookup_scale else lookup_scale

	var g := _gradient_colors()
	_paint_mat.set_shader_parameter("color_a", g[0])
	_paint_mat.set_shader_parameter("color_b", g[1])
	_paint_mat.set_shader_parameter("gradient_start", gradient_start)

	# DrawSky: u offset = atan2(...) / 2pi of the camera heading
	var fwd := -cam.global_transform.basis.z
	var heading := atan2(fwd.x, fwd.z) / TAU
	if invert_panorama_scroll and not panorama_match_sky:
		heading = -heading
	_env_mat.set_shader_parameter("heading", heading)
	_env_mat.set_shader_parameter("match_sky", panorama_match_sky)
	_env_mat.set_shader_parameter("pano_v_offset", asin(clampf(fwd.y, -1.0, 1.0)) / PI)
	_env_mat.set_shader_parameter("pano_gain", panorama_gain)
	_env_mat.set_shader_parameter("flip_pano_v", panorama_flip_v)
	_env_mat.set_shader_parameter("dot_gain", light_dot_gain)
	_env_mat.set_shader_parameter("reflect_alpha", reflection_alpha)

	var m := _car_mat
	m.set_shader_parameter("light_dir0", light0_direction)
	m.set_shader_parameter("light_dir1", light1_direction)
	m.set_shader_parameter("light_dir2", light2_direction)
	m.set_shader_parameter("light_col0", _v3(light0_color))
	m.set_shader_parameter("light_col1", _v3(light1_color))
	m.set_shader_parameter("light_col2", _v3(light2_color))
	m.set_shader_parameter("ambient", _v3(ambient))
	m.set_shader_parameter("material_mul", vertex_light_scale)
	m.set_shader_parameter("lookup_scale", _lookup_scale_now)
	m.set_shader_parameter("normal_weight", normal_weight)
	m.set_shader_parameter("paint_pos_weight", paint_position_weight)
	m.set_shader_parameter("env_pos_weight", fresnel_position * normal_weight)
	m.set_shader_parameter("keep_model_scale", keep_model_scale)
	m.set_shader_parameter("per_pixel_lookup", per_pixel_lookup)
	m.set_shader_parameter("fres_min", fresnel_min)
	m.set_shader_parameter("fres_max", fresnel_max)
	m.set_shader_parameter("fres_scale", fresnel_scale)
	m.set_shader_parameter("reflect_gain", reflection_gain)
	m.set_shader_parameter("paint_gain", paint_gain)
	m.set_shader_parameter("gamma_correct", gamma_correct)

	var chrome_scale := _scale_for_fov(chrome_lookup_k, fov) if auto_lookup_scale else lookup_scale
	var colors := [chrome_color, rim_chrome_color, exhaust_chrome_color]
	for i in 3:
		var cm: ShaderMaterial = _chrome_mats[i]
		cm.set_shader_parameter("chrome_color", _v3(colors[i]))
		cm.set_shader_parameter("chrome_ambient_lift", chrome_ambient_lift)
		cm.set_shader_parameter("light_dir0", light0_direction)
		cm.set_shader_parameter("light_dir1", light1_direction)
		cm.set_shader_parameter("light_dir2", light2_direction)
		cm.set_shader_parameter("light_col0", _v3(light0_color))
		cm.set_shader_parameter("light_col1", _v3(light1_color))
		cm.set_shader_parameter("light_col2", _v3(light2_color))
		cm.set_shader_parameter("ambient", _v3(ambient))
		cm.set_shader_parameter("lookup_scale", chrome_scale)
		cm.set_shader_parameter("normal_weight", normal_weight)
		cm.set_shader_parameter("env_pos_weight", chrome_position_weight * normal_weight)
		cm.set_shader_parameter("keep_model_scale", keep_model_scale)
		cm.set_shader_parameter("per_pixel_lookup", per_pixel_lookup)
		cm.set_shader_parameter("reflect_gain", reflection_gain)
		cm.set_shader_parameter("gamma_correct", gamma_correct)

	# glass: tint + opacity per kind, ambient lift from the headlight / brakelight values (Bind)
	var glass_scale := _scale_for_fov(glass_lookup_k, fov) if auto_lookup_scale else lookup_scale
	var glass_tints := [glass_tint, headlight_glass_tint, brakelight_glass_tint]
	var glass_opacities := [glass_opacity, headlight_glass_opacity, brakelight_glass_opacity]
	var lifts := [0.0, 0.5 * headlights_on, 0.5 * headlights_on + 0.5 * brakelights_on]
	for i in 3:
		var gm: ShaderMaterial = _glass_mats[i]
		gm.set_shader_parameter("glass_tint", _v3(glass_tints[i]))
		gm.set_shader_parameter("glass_opacity", glass_opacities[i])
		gm.set_shader_parameter("light_lift", clampf(lifts[i], 0.0, 1.0))
		gm.set_shader_parameter("light_dir0", light0_direction)
		gm.set_shader_parameter("light_dir1", light1_direction)
		gm.set_shader_parameter("light_dir2", light2_direction)
		gm.set_shader_parameter("light_col0", _v3(light0_color))
		gm.set_shader_parameter("light_col1", _v3(light1_color))
		gm.set_shader_parameter("light_col2", _v3(light2_color))
		gm.set_shader_parameter("ambient", _v3(ambient))
		gm.set_shader_parameter("lookup_scale", glass_scale)
		gm.set_shader_parameter("normal_weight", normal_weight)
		gm.set_shader_parameter("env_pos_weight", glass_position_weight * normal_weight)
		gm.set_shader_parameter("keep_model_scale", keep_model_scale)
		gm.set_shader_parameter("per_pixel_lookup", per_pixel_lookup)
		gm.set_shader_parameter("fres_min", glass_fresnel_min)
		gm.set_shader_parameter("fres_max", glass_fresnel_max)
		gm.set_shader_parameter("fres_scale", glass_fresnel_scale)
		gm.set_shader_parameter("reflect_gain", reflection_gain)
		gm.set_shader_parameter("gamma_correct", gamma_correct)
