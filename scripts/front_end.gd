extends Control
## Presentation-only skin and input context. No collection, Run or physics state.

const INK: Color = Color("10151f")
const PANEL: Color = Color("1c2933")
const BORDER: Color = Color("44535b")
const TEXT: Color = Color("e3e8dc")
const MUTED: Color = Color("9aa9a8")
const BLUE: Color = Color("79bed0")
const ORANGE: Color = Color("df9b58")
const FONT_PATH: String = "res://assets/ui/foundry_small.fnt"
const BACKGROUND_PATH: String = "res://assets/ui/frontend_background.png"
const GLYPH_PATH: String = "res://assets/ui/input_glyphs.png"
const SCREEN_REGISTRY: Dictionary = {
	"title_gate":{"scope":"menu", "background":0},
	"collection_title":{"scope":"menu", "background":1},
	"title":{"scope":"menu", "background":1},
	"play_modes":{"scope":"menu", "background":1},
	"collection_workshop":{"scope":"menu", "background":1},
	"garage":{"scope":"menu", "background":1},
	"settings":{"scope":"menu", "background":1},
	"save_tools":{"scope":"menu", "background":1},
	"reset_confirmation":{"scope":"menu", "background":1},
	"help":{"scope":"menu", "background":1},
	"starter_ceremony":{"scope":"menu", "background":1},
	"starter_confirm":{"scope":"menu", "background":1},
	"starter_owned":{"scope":"menu", "background":1},
	"collection_error":{"scope":"menu", "background":1},
	"starters":{"scope":"menu", "background":1},
	"reward":{"scope":"run_choice", "background":1},
	"mutation":{"scope":"run_choice", "background":1},
	"acquisition":{"scope":"run_choice", "background":1},
	"level_up":{"scope":"run_choice", "background":1},
	"pause":{"scope":"run_choice", "background":1},
	"result":{"scope":"menu", "background":1},
	"hud":{"scope":"combat", "background":-1},
}

var screen_id: String = "collection_title"
var _background: Texture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(BACKGROUND_PATH): _background = load(BACKGROUND_PATH)
	queue_redraw()

func _draw() -> void:
	var frame: int = int(SCREEN_REGISTRY.get(screen_id, {}).get("background", 1))
	if frame < 0: return
	if _background != null:
		frame = mini(frame, maxi(0, _background.get_width() / 640 - 1))
		draw_texture_rect_region(_background, Rect2(0, 0, 640, 360), Rect2(frame * 640, 0, 640, 360))
	else:
		draw_rect(Rect2(0, 0, 640, 360), INK)
	draw_rect(Rect2(16, 356, 608, 1), BORDER)

static func font_size(requested: int) -> int:
	# The authored face is 6x10. Whole multiples preserve its native clusters.
	return maxi(10, roundi(float(requested) / 10.0) * 10)

static func pixel_font() -> Font:
	return load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) else null

static func plate(fill: Color, outline: Color, width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(width)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.anti_aliasing = false
	return style

static func make_theme() -> Theme:
	var value: Theme = Theme.new()
	value.default_font_size = 10
	var font: Font = pixel_font()
	if font != null: value.default_font = font
	for kind: String in ["Label", "Button"]: value.set_color("font_color", kind, TEXT)
	value.set_color("font_hover_color", "Button", Color.WHITE)
	value.set_color("font_focus_color", "Button", Color.WHITE)
	value.set_color("font_pressed_color", "Button", INK)
	value.set_stylebox("normal", "Button", plate(Color("263640"), BORDER))
	value.set_stylebox("hover", "Button", plate(Color("344853"), BLUE))
	value.set_stylebox("pressed", "Button", plate(ORANGE, ORANGE))
	value.set_stylebox("focus", "Button", plate(Color(0, 0, 0, 0), ORANGE, 2))
	value.set_stylebox("disabled", "Button", plate(Color("172129"), Color("344047")))
	value.set_stylebox("background", "ProgressBar", plate(INK, BORDER))
	value.set_stylebox("fill", "ProgressBar", plate(BLUE, BLUE, 0))
	value.set_stylebox("slider", "HSlider", plate(BORDER, BORDER, 0))
	value.set_stylebox("grabber_area", "HSlider", plate(BLUE, BLUE, 0))
	value.set_stylebox("focus", "HSlider", plate(Color(0, 0, 0, 0), ORANGE, 2))
	return value

static func controller_profile(device: int) -> String:
	var name: String = Input.get_joy_name(device).to_lower()
	if "playstation" in name or "dualshock" in name or "dualsense" in name: return "playstation"
	if "nintendo" in name or "switch" in name: return "nintendo"
	if "xbox" in name or "xinput" in name: return "xbox"
	return "gamepad"

static func prompt(profile: String, action: String) -> String:
	if profile == "keyboard":
		return {"confirm":"ENTER / CLICK", "back":"ESC", "choose":"ARROWS / TAB", "pause":"ESC", "steer":"WASD / ARROWS", "burst":"SPACE", "brake":"SHIFT"}.get(action, action.to_upper())
	var south: String = {"playstation":"CROSS", "nintendo":"B", "xbox":"A"}.get(profile, "SOUTH BUTTON")
	var east: String = {"playstation":"CIRCLE", "nintendo":"A", "xbox":"B"}.get(profile, "EAST BUTTON")
	return {"confirm":south, "back":east, "choose":"D-PAD / STICK", "pause":"MENU", "steer":"LEFT STICK", "burst":south, "brake":"SHOULDER / TRIGGER"}.get(action, action.to_upper())

static func glyph(profile: String, action: String) -> AtlasTexture:
	if not ResourceLoader.exists(GLYPH_PATH): return null
	var tag: String = "key_enter" if action == "confirm" else "key_escape"
	if profile != "keyboard":
		tag = ("pad_cross" if profile == "playstation" else "pad_south") if action == "confirm" else (("pad_circle" if profile == "playstation" else "pad_east") if action == "back" else "dpad")
		# The atlas A/B tags describe Xbox positions; mapped Nintendo pads put
		# B on the physical south button and A on east. Keep letter and prompt true.
		if profile == "nintendo" and action in ["confirm", "back"]: tag = "pad_east" if action == "confirm" else "pad_south"
	var names: Array[String] = ["key_enter", "key_escape", "pad_south", "pad_east", "dpad", "pad_back", "pad_start", "pad_cross", "pad_circle"]
	var frame: int = names.find(tag)
	var texture: AtlasTexture = AtlasTexture.new()
	texture.atlas = load(GLYPH_PATH)
	texture.region = Rect2(maxi(0, frame) * 16, 0, 16, 16)
	return texture
