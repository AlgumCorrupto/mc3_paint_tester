class_name MC3CarPaintPanel
extends PanelContainer
## Ready-made control panel for an MC3CarPaint node: colour picker + presets, paint type,
## sliders for the main parameters and a view of the generated maps.
##
## Usage:
##     var panel := MC3CarPaintPanel.new()
##     panel.bind($Car/MC3CarPaint)          # or set the `paint` property in the inspector
##     $UI.add_child(panel)
##     panel.content.add_child(my_extra_button)   # extend it if you like
##
## It only reads and writes exported properties of MC3CarPaint, so it also works as a template
## for an in-game garage menu.

const PRESETS := {
	"Orange": Color(1.0, 0.45, 0.10),
	"Red": Color(0.85, 0.05, 0.06),
	"Yellow": Color(1.0, 0.85, 0.10),
	"Green": Color(0.10, 0.65, 0.20),
	"Teal": Color(0.05, 0.60, 0.65),
	"Blue": Color(0.10, 0.25, 0.90),
	"Purple": Color(0.50, 0.15, 0.80),
	"Pink": Color(1.0, 0.35, 0.65),
	"Silver": Color(0.75, 0.77, 0.80),
	"Black": Color(0.10, 0.10, 0.11),
	"White": Color(0.95, 0.95, 0.95),
}

@export var paint: MC3CarPaint
## Show the generated paint / env maps at the bottom.
@export var show_maps := true
## Predefined panoramas for the env map: display name (String) -> Texture2D (equirectangular).
## "Procedural (built-in)" is always offered first.
@export var panorama_presets: Dictionary = {}

## Container holding all controls; add your own controls here.
var content: VBoxContainer

var _base_picker: ColorPickerButton
var _pano_dialog: FileDialog


func _ready() -> void:
	if paint != null:
		_build()


func bind(p: MC3CarPaint) -> void:
	paint = p
	_build()


# ---------------------------------------------------------------------------------------
func _build() -> void:
	for c in get_children():
		c.queue_free()
	custom_minimum_size = Vector2(330, 0)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content = VBoxContainer.new()
	content.custom_minimum_size = Vector2(300, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)

	# ---- paint colour ----------------------------------------------------------------
	_header("Paint")
	_base_picker = ColorPickerButton.new()
	_base_picker.color = paint.base_color
	_base_picker.edit_alpha = false
	_base_picker.custom_minimum_size = Vector2(0, 34)
	_base_picker.text = "Paint colour"
	_base_picker.color_changed.connect(func(c: Color) -> void: paint.base_color = c)
	content.add_child(_base_picker)

	var flow := HFlowContainer.new()
	content.add_child(flow)
	for preset_name in PRESETS:
		var col: Color = PRESETS[preset_name]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(26, 26)
		btn.tooltip_text = preset_name
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.pressed.connect(func() -> void:
			paint.base_color = col
			_base_picker.color = col)
		flow.add_child(btn)

	var type_row := HBoxContainer.new()
	content.add_child(type_row)
	_label(type_row, "Paint type", 13)
	var type_opt := OptionButton.new()
	type_opt.add_item("Metallic", MC3CarPaint.PaintType.METALLIC)
	type_opt.add_item("Pearl", MC3CarPaint.PaintType.PEARL)
	type_opt.add_item("Gloss", MC3CarPaint.PaintType.GLOSS)
	type_opt.selected = type_opt.get_item_index(paint.paint_type)
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_opt.item_selected.connect(func(i: int) -> void: paint.paint_type = type_opt.get_item_id(i))
	type_row.add_child(type_opt)

	_color("Pearl highlight colour (Pearl only)", "pearl_color")
	_slider("Body colour scale (stop 1)", "body_color_scale", 0.05, 1.0, 0.01)
	_slider("Metallic highlight scale", "metallic_scale", 0.5, 3.0, 0.01)
	_slider("Gradient start", "gradient_start", 0.0, 0.9, 0.01)

	# ---- highlights ------------------------------------------------------------------
	_header("Highlights in the paint map")
	_slider("Highlight size", "highlight_size", 0.3, 3.0, 0.01)
	_slider("Highlight intensity", "highlight_intensity", 0.0, 1.5, 0.01)
	_slider("Light fade distance (m)", "light_fade_distance", 5.0, 60.0, 0.5)
	_check("Light attached to the camera", "camera_light")
	_check("Game's non-linear highlight placement (experimental)", "game_placement_formula")

	# ---- environment -----------------------------------------------------------------
	_header("Environment map")
	_slider("Reflection strength (env alpha)", "reflection_alpha", 0.0, 1.0, 0.01)
	_slider("Panorama brightness", "panorama_gain", 0.0, 3.0, 0.01)
	_slider("Light dot intensity", "light_dot_gain", 0.0, 2.0, 0.01)
	_slider("Env camera FOV (garage 100, city 140)", "env_fov", 60.0, 150.0, 1.0)
	_panorama_preset_picker()
	_check("Match Godot sky orientation (reflect what is behind the camera)", "panorama_match_sky")
	_check("Invert panorama scroll (game mode)", "invert_panorama_scroll")
	_check("Flip panorama vertically (game mode)", "panorama_flip_v")
	var pano_row := HBoxContainer.new()
	content.add_child(pano_row)
	var load_btn := Button.new()
	load_btn.text = "Load panorama..."
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(func() -> void: _pano_dialog.popup_centered())
	pano_row.add_child(load_btn)
	var proc_btn := Button.new()
	proc_btn.text = "Procedural"
	proc_btn.pressed.connect(func() -> void: paint.panorama = null)
	pano_row.add_child(proc_btn)

	# ---- shading ---------------------------------------------------------------------
	_header("Car shader")
	_color("Ambient", "ambient")
	_slider("Vertex light intensity", "vertex_light_scale", 0.0, 3.0, 0.01)
	_slider("Reflection gain", "reflection_gain", 0.0, 3.0, 0.01)
	_slider("Paint gain", "paint_gain", 0.0, 3.0, 0.01)
	_slider("Fresnel min", "fresnel_min", 0.0, 1.0, 0.005)
	_slider("Fresnel max", "fresnel_max", 0.0, 1.0, 0.005)
	_slider("Fresnel scale", "fresnel_scale", 0.0, 2.0, 0.005)
	_slider("Env position weight (c146.x)", "fresnel_position", 0.0, 2.0, 0.005)
	_slider("Paint position weight (c117.z)", "paint_position_weight", 0.0, 0.5, 0.005)
	_slider("Normal weight (c116.w)", "normal_weight", 0.0, 1.0, 0.005)
	_check("Lookup scale from camera FOV", "auto_lookup_scale")
	_slider("Lookup scale k", "lookup_scale_k", 0.5, 2.0, 0.01)
	_check("Keep model scale in normals", "keep_model_scale")
	_check("Per-pixel lookup (game is per-vertex)", "per_pixel_lookup")
	_check("sRGB -> linear on output", "gamma_correct")

	# ---- chrome ----------------------------------------------------------------------
	_header("Chrome (groups mc3_chrome / mc3_rim_chrome / mc3_exhaust_chrome)")
	_color("Chrome colour", "chrome_color")
	_color("Rim chrome colour", "rim_chrome_color")
	_color("Exhaust chrome colour", "exhaust_chrome_color")
	_slider("Chrome ambient lift", "chrome_ambient_lift", 0.0, 1.0, 0.01)
	_slider("Chrome position weight", "chrome_position_weight", 0.0, 2.0, 0.005)

	# ---- glass -----------------------------------------------------------------------
	_header("Glass (groups mc3_glass / mc3_headlight_glass / mc3_brakelight_glass)")
	_color("Glass tint", "glass_tint")
	_slider("Glass opacity", "glass_opacity", 0.0, 1.0, 0.005)
	_color("Headlight glass tint", "headlight_glass_tint")
	_slider("Headlight glass opacity", "headlight_glass_opacity", 0.0, 1.0, 0.005)
	_color("Brakelight glass tint", "brakelight_glass_tint")
	_slider("Brakelight glass opacity", "brakelight_glass_opacity", 0.0, 1.0, 0.005)
	_slider("Headlights on", "headlights_on", 0.0, 1.0, 0.01)
	_slider("Brakelights on", "brakelights_on", 0.0, 1.0, 0.01)
	_slider("Glass reflection position weight", "glass_position_weight", 0.0, 2.0, 0.005)
	_slider("Glass Fresnel min", "glass_fresnel_min", 0.0, 1.0, 0.005)
	_slider("Glass Fresnel max", "glass_fresnel_max", 0.0, 1.0, 0.005)
	_slider("Glass Fresnel scale", "glass_fresnel_scale", 0.0, 3.0, 0.005)

	# ---- generated maps --------------------------------------------------------------
	if show_maps:
		_header("Generated maps")
		var row := HBoxContainer.new()
		content.add_child(row)
		row.add_child(_thumb(paint.get_paint_texture(), "paint map"))
		row.add_child(_thumb(paint.get_env_texture(), "env map"))

	_pano_dialog = FileDialog.new()
	_pano_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_pano_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_pano_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.exr, *.hdr ; Images"])
	_pano_dialog.size = Vector2i(800, 520)
	_pano_dialog.file_selected.connect(func(path: String) -> void: paint.set_panorama_from_file(path))
	add_child(_pano_dialog)


func _panorama_preset_picker() -> void:
	var row := HBoxContainer.new()
	content.add_child(row)
	_label(row, "Panorama", 13)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_item("Procedural (built-in)")
	var keys := panorama_presets.keys()
	var selected := 0
	for i in keys.size():
		opt.add_item(str(keys[i]))
		if paint.panorama != null and panorama_presets[keys[i]] == paint.panorama:
			selected = i + 1
	opt.selected = selected
	opt.item_selected.connect(func(i: int) -> void:
		if i == 0:
			paint.panorama = null
		else:
			paint.panorama = panorama_presets[keys[i - 1]])
	row.add_child(opt)


# ---------------------------------------------------------------------------------------
# helpers: everything is bound by property name
# ---------------------------------------------------------------------------------------
func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _header(text: String) -> void:
	content.add_child(HSeparator.new())
	var l := _label(content, text, 15)
	l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))


func _slider(text: String, prop: StringName, min_v: float, max_v: float, step: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	content.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_l := _label(row, text, 12)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_l := _label(row, "%.3f" % float(paint.get(prop)), 12)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = float(paint.get(prop))
	s.custom_minimum_size = Vector2(0, 16)
	s.value_changed.connect(func(x: float) -> void:
		val_l.text = "%.3f" % x
		paint.set(prop, x))
	box.add_child(s)


func _check(text: String, prop: StringName) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = bool(paint.get(prop))
	cb.add_theme_font_size_override("font_size", 12)
	cb.toggled.connect(func(b: bool) -> void: paint.set(prop, b))
	content.add_child(cb)


func _color(text: String, prop: StringName) -> void:
	var cpb := ColorPickerButton.new()
	cpb.color = paint.get(prop)
	cpb.edit_alpha = false
	cpb.custom_minimum_size = Vector2(0, 30)
	cpb.text = text
	cpb.color_changed.connect(func(c: Color) -> void: paint.set(prop, c))
	content.add_child(cpb)


func _thumb(tex: Texture2D, caption: String) -> Control:
	var box := VBoxContainer.new()
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(145, 145)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(tr)
	var l := Label.new()
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box
