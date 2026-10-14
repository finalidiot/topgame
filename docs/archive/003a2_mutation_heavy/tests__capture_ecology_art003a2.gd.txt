extends SceneTree
## Actual catalogue and menu cards in declared sibling-choice fixtures.
## No save, combat, XP, acquisition or natural gameplay outcome is claimed.
const Menus = preload("res://scripts/menus.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Styles = preload("res://scripts/ability_card_style.gd")
var output_dir: String = ""
var report: String = ""
var checks: int = 0
var failures: Array[String] = []
var images: Array[Dictionary] = []
var ui: Menus

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func settle(count: int = 3) -> void:
	for tick: int in range(count): await process_frame
func fits(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	check(label.get_line_count() * font.get_height(size) <= label.size.y + 0.1, "Text height fits: " + label.text)
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		check(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x + 0.1, "Text width fits: " + label.text)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	for path: String in [output_dir, report]:
		if not path.is_absolute_path() or not path.replace("\\", "/").to_lower().contains("gyrobrothers-qa/003a.2/"):
			push_error("Fresh external003A.2 evidence paths required"); quit(2); return
	if FileAccess.file_exists(report) or DirAccess.dir_exists_absolute(output_dir):
		push_error("Existing art evidence must remain untouched"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(800, 480)
	root.content_scale_size = Vector2i(800, 480)
	DisplayServer.window_set_title("Spinning Metal — MUTATION ART ISOLATED QA")
	ui = Menus.new(); root.add_child(ui); await settle()
	check(Powers.ACTIVE_IDS.size() == 16, "Sixteen active families preserved")
	check(Powers.VERTICAL_IDS.size() == 11 and Powers.MUTATIONS.size() == 22, "Eleven vertical families / twenty-two mutations")
	var forms: int = 0
	for family: String in Powers.ACTIVE_IDS:
		for rank: int in [1, 2]:
			var metadata: Dictionary = Powers.get_owned_power(family, rank)
			check(not metadata.is_empty() and metadata.power_id == family and metadata.rank == rank, "Existing legal family/rank: " + family)
			check(metadata.card_badge == ("POWER" if rank == 1 else "RANK II"), "Existing investment semantic badge: " + family)
			forms += 1
	for branch: String in Powers.MUTATIONS:
		var mutation: Dictionary = Powers.get_mutation(branch)
		check(mutation.card_badge == "MUTATION" and mutation.card_tier == "mutation", "Mutation semantics: " + branch)
		forms += 1
	check(forms == 54, "Actual catalogue has fifty-four semantic forms")
	for family: String in ["iron_comet", "orbit_drive", "momentum_bank", "crash_guard"]:
		var branches: Array[String] = Powers.mutation_choices(family)
		check(branches.size() == 2 and Powers.max_rank(family) == 3, "Two legal mutually exclusive siblings: " + family)
		ui.show_mutation(family, branches, "art_fixture/" + family, 421, branches[0])
		await settle(4)
		var controls: Array[Button] = []
		for child: Node in ui._content.get_children():
			if child is Button and child.has_meta("ability_tier"): controls.append(child)
		check(controls.size() == 2, "Actual two-card choice rendered: " + family)
		var rows: Array[Dictionary] = []
		for index: int in range(controls.size()):
			var card: Button = controls[index]
			var id: String = str(card.get_meta("power_id"))
			var metadata: Dictionary = Powers.get_mutation(id)
			check(id == branches[index] and metadata.power_id == family, "Rendered choice has correct parent/identity: " + id)
			check(card.get_meta("ability_badge") == "MUTATION", "Actual semantic card badge: " + id)
			check(Powers.get_owned_power(family, 3, id).mutation == id, "Legal branch ownership metadata: " + id)
			check(Powers.get_owned_power(family, 3, "runaway").is_empty(), "Foreign branch rejected: " + id)
			for label_name: String in ["AbilityTierBadge", "AbilityCardTitle", "AbilityCardBody", "AbilityCardConfirm"]:
				fits(card.get_node(label_name) as Label)
			var body: Label = card.get_node("AbilityCardBody")
			check(body.get_theme_color("font_color") == Styles.BODY, "Neutral body text: " + id)
			var image: TextureRect
			for child: Node in card.get_children():
				if child is TextureRect: image = child; break
			check(image != null and image.texture is AtlasTexture, "Actual atlas illustration: " + id)
			if image == null: continue
			check(image.modulate == Color.WHITE and image.self_modulate == Color.WHITE, "Untinted art: " + id)
			check(image.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Nearest native art: " + id)
			var atlas: AtlasTexture = image.texture
			check(atlas.atlas.resource_path == metadata.card_texture and metadata.card_frames == 6, "New six-pose catalogue source: " + id)
			rows.append({"id":id,"name":metadata.name,"badge":"MUTATION","texture":metadata.card_texture,"art_sha256":FileAccess.get_sha256(ProjectSettings.globalize_path(metadata.card_texture)),"card_rect":[card.get_global_rect().position.x,card.get_global_rect().position.y,card.size.x,card.size.y]})
		# Let the focused card reach its authored action beat through the actual
		# menu timeline. The sibling uses its ordinary source-defined static pose.
		var first: Dictionary = Powers.get_mutation(branches[0])
		var elapsed: float = 0.015
		for index: int in range(int(first.card_static_frame)): elapsed += float(first.card_durations_ms[index]) / 1000.0
		await create_timer(elapsed).timeout
		await RenderingServer.frame_post_draw
		var path: String = output_dir.path_join(family + ".png")
		check(root.get_texture().get_image().save_png(path) == OK, "Real native menu pixels saved: " + family)
		var area: Rect2 = ui._content.get_global_rect()
		images.append({"family":family,"path":path,"sha256":FileAccess.get_sha256(path),"menu_rect":[area.position.x,area.position.y,area.size.x,area.size.y],"cards":rows})
	var result: Dictionary = {"checks":checks,"failures":failures,"images":images,"forms":forms,
		"scope":"Actual catalogue and normal Menus rendering. Declared legal sibling-choice fixtures; no XP, acquisition, combat, save or human hardware acceptance. Native art and UI pixels are captured without recolouring."}
	var file := FileAccess.open(report, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t")); file.close()
	ui.free()
	print("ECOLOGY_ART_CAPTURE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
