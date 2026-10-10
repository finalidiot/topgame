extends SceneTree
## Actual menu controls/font geometry; no save, physics or power-state changes.
const UI = preload("res://scripts/menus.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Styles = preload("res://scripts/ability_card_style.gd")
const Front = preload("res://scripts/front_end.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
const Inspector = preload("res://scripts/ability_inspection.gd")
var checks: int = 0
var failures: Array[String] = []
var roster: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var report: String = ""
var ui: Control

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func settle(frames: int = 3) -> void:
	for tick: int in range(frames): await process_frame
func cards() -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in ui._content.get_children():
		if child is Button and child.has_meta("ability_tier"): result.append(child)
	return result
func key(code: Key) -> void:
	var event := InputEventKey.new(); event.physical_keycode = code; event.keycode = code
	event.pressed = true; Input.parse_input_event(event); await settle()
	event.pressed = false; Input.parse_input_event(event); await settle()
func motion(card: Button) -> void:
	var event := InputEventMouseMotion.new(); event.position = card.get_global_rect().get_center(); event.global_position = event.position
	Input.parse_input_event(event); await settle()
func click(card: Button) -> void:
	await motion(card)
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
	event.position = card.get_global_rect().get_center(); event.global_position = event.position
	event.pressed = true; Input.parse_input_event(event); await settle()
	event.pressed = false; Input.parse_input_event(event); await settle()
func tap(card: Button) -> void:
	var old_emulation: bool=Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch=true
	var event := InputEventScreenTouch.new();event.index=0;event.position=card.get_global_rect().get_center()
	event.pressed=true;Input.parse_input_event(event);await settle()
	event.pressed=false;Input.parse_input_event(event);await settle()
	Input.emulate_mouse_from_touch=old_emulation
func fits(label: Label, context: String) -> void:
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	check(label.get_line_count() * font.get_height(size) <= label.size.y + 0.1, context + " has no clipped text height: " + label.text)
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		check(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x + 0.1, context + " fits its width: " + label.text)
func verify_card(card: Button, power: Dictionary, context: String) -> Dictionary:
	var style: Dictionary = Styles.get_card_tier_style(int(power.rank), str(power.get("mutation", "")))
	var badge: Label = card.get_node("AbilityTierBadge")
	var title: Label = card.get_node("AbilityCardTitle")
	var body: Label = card.get_node("AbilityCardBody")
	var prompt: Label = card.get_node("AbilityCardConfirm")
	check(card.get_meta("ability_tier") == power.card_tier and card.get_meta("ability_badge") == power.card_badge, context + " actual control uses catalogue semantics")
	check(badge.text == style.badge and badge.get_theme_color("font_color") == style.accent_color, context + " explicit badge survives without relying on colour")
	check(title.get_theme_color("font_color") == style.title_color, context + " title is determined by investment, not family")
	check(body.get_theme_color("font_color") == Styles.BODY and body.modulate == Color.WHITE, context + " body is neutral in every tier")
	for label: Label in [badge,title,body,prompt]: fits(label, context)
	card.release_focus(); ui._animate_cards()
	var frame: StyleBoxFlat = (card.get_node("SemanticCardFrame") as Panel).get_theme_stylebox("panel")
	check(frame.border_color == style.border_color and frame.border_width_left == style.border_width and not frame.draw_center, context + " unfocused semantic frame preserves the authored body")
	card.grab_focus(); ui._animate_cards()
	frame = (card.get_node("SemanticCardFrame") as Panel).get_theme_stylebox("panel")
	check(frame.border_color == style.accent_color and frame.border_width_left == style.focus_width, context + " focus keeps the same semantic accent")
	var art: TextureRect
	for child: Node in card.get_children():
		if child is TextureRect: art = child; break
	check(art != null and art.texture is AtlasTexture and art.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, context + " uses its existing native atlas with nearest filtering")
	check(art.modulate == Color.WHITE and art.self_modulate == Color.WHITE, context + " art has no semantic colour wash")
	var atlas: AtlasTexture = art.texture
	check(atlas.atlas.resource_path == str(power.card_texture), context + " preserves exact power-specific illustration source")
	check(ui._content.get_global_rect().encloses(card.get_global_rect()), context + " remains inside the native menu surface")
	return {"id":str(power.get("mutation", "")) if int(power.rank) == 3 else str(power.power_id), "name":str(power.name), "rank":int(power.rank),
		"tier":style.tier, "badge":style.badge, "title_colour":style.title_color.to_html(false), "accent_colour":style.accent_color.to_html(false),
		"body_colour":Styles.BODY.to_html(false), "title_font_size":title.get_theme_font_size("font_size"),
		"art":str(power.card_texture), "art_sha256":FileAccess.get_sha256(ProjectSettings.globalize_path(str(power.card_texture))), "body":body.text}

func audit_roster() -> void:
	check(Powers.ACTIVE_IDS.size() == 16 and Powers.MUTATIONS.size() == 14, "The audit covers the actual sixteen families and fourteen mutation choices")
	for id: String in Powers.ACTIVE_IDS:
		for rank: int in [0,1]:
			var power: Dictionary = Powers.get_offer(id,rank)
			check(power.rank == rank + 1 and power.power_id == id and not power.has("rarity"), id + " keeps real investment and family metadata without fake rarity")
			ui.show_reward([id], [id] if rank > 0 else [], 1,"audit",421,"",{"power_ranks":{id:rank}})
			await settle()
			roster.append(verify_card(cards()[0],power,id + " " + str(rank + 1)))
		if Powers.max_rank(id) == 3:
			var parent_offer: Dictionary = Powers.get_offer(id,2)
			ui.show_reward([id],[id],1,"audit",421,"",{"power_ranks":{id:2}})
			await settle()
			verify_card(cards()[0],parent_offer,id + " mutation-entry offer")
		for branch: String in Powers.mutation_choices(id):
			var power: Dictionary = Powers.get_mutation(branch)
			check(power.power_id == id and power.rank == 3 and power.mutation == branch and not power.has("rarity"), branch + " keeps correct original family and mutation ownership")
			ui.show_mutation(id,Powers.mutation_choices(id),"audit",421,branch)
			await settle()
			var card: Button
			for candidate: Button in cards():
				if candidate.get_meta("power_id") == branch: card = candidate
			roster.append(verify_card(card,power,branch))
	check(roster.size() == 46,"Every active base, Rank II and mutation is actually rendered and audited")
	for row: Dictionary in roster:
		check(row.body_colour == "e3e8dc",row.name + " body stays neutral")
		check(row.accent_colour == {1:"bdcbd3",2:"64d8ef",3:"d49bf1"}[row.rank],row.name + " uses the same tier accent as unrelated families")
	var ghost: Dictionary = Powers.get_mutation("ghost_circuit")
	check("hostile" in str(ghost.description) and "physically" in str(ghost.description) and "paid" in str(ghost.description) and "live" in str(ghost.description),"Ghost explains real owned/hostile paid physical closure")
	check("closer" in str(ghost.description) and "consumed" in str(ghost.description) and "3.5" in str(ghost.description),"Ghost explains hostile effect ownership, finite sections and closer cooldown")
	for rank: int in [1,2]:
		var chain: Dictionary = Powers.get_owned_power("chain_impact",rank)
		check("hard hit" in str(chain.description).to_lower() and "physical" in str(chain.description) and "cooldown" in str(chain.description),"Chain rank %d explains accepted physical hard hits and owner cooldown"%rank)
		check("knockouts alone do not" in str(chain.description) and not "credited knockout" in str(chain.description).to_lower(),"Chain rank %d no longer promises knockout-triggered chains"%rank)
		var orbit: Dictionary = Powers.get_owned_power("orbit_drive",rank)
		check("100%" in str(orbit.description) and "active carving" in str(orbit.description) and "capped RPM recovery" in str(orbit.description),"Orbit rank %d explains full-charge active capped recovery"%rank)
		check("idle movement earns nothing" in str(orbit.description),"Orbit rank %d does not promise passive recovery"%rank)
	check("same rate" in str(Powers.get_owned_power("orbit_drive",2).description),"Orbit II preserves the real unchanged charge-growth rate")
	check("hard hit" in str(Powers.CONDITIONS.chain_impact).to_lower() and "100% DRIVE" in str(Powers.CONDITIONS.orbit_drive),"Compact conditions match the new actual mechanics")

func inspector_hierarchy() -> void:
	var inspector := Inspector.new();inspector.size=Vector2(188,242);root.add_child(inspector)
	for row: Dictionary in roster:
		var branch: String=row.id if row.rank==3 else ""
		var id: String=str(Powers.get_mutation(branch).power_id) if row.rank==3 else row.id
		inspector.inspect(id,row.rank,branch)
		await settle()
		var header: Label=inspector._body.get_node("AbilityInspectorHeader")
		check(header.get_theme_color("font_color")==Styles.get_card_tier_style(row.rank,branch).title_color,row.name+" inspector header uses its actual investment tier")
		for child: Node in inspector._body.get_children():
			if child is Label:fits(child,row.name+" inspector")
	inspector.inspect("afterimage",1,"ghost_circuit",false)
	check(inspector._body.get_node("AbilityInspectorHeader").get_theme_color("font_color")==Styles.BODY,"A locked or malformed mutation argument cannot colour a Rank I inspector purple")
	check(inspector.breakdown.name=="Afterimage","A locked mutation argument preserves the real Rank I identity")
	inspector.inspect("afterimage",2,"ghost_circuit",true)
	check(inspector._body.get_node("AbilityInspectorHeader").text.ends_with("MUTATION / PREVIEW"),"A real branch preview is explicitly labelled")
	check(inspector._body.get_node("AbilityInspectorHeader").get_theme_color("font_color")==Styles.MUTATION_ACCENT,"A real branch preview uses the shared mutation colour")
	inspector.inspect("afterimage",2,"missing_branch",true)
	check(not inspector.breakdown.branch_preview and inspector.breakdown.name=="Afterimage II","An invalid branch ID cannot manufacture a mutation preview")
	check(inspector._body.get_node("AbilityInspectorHeader").get_theme_color("font_color")==Styles.UPGRADE_ACCENT,"An invalid mutation preview retains the actual Rank II colour")
	inspector.free()

func input_hierarchy() -> void:
	ui.show_reward(["redline","dead_centre","afterimage"],["dead_centre","afterimage"],1,"input",421,"",{"power_ranks":{"dead_centre":1,"afterimage":2}})
	await settle(); var row: Array[Button] = cards()
	check(row[0].get_meta("ability_badge") == "POWER" and row[1].get_meta("ability_badge") == "RANK II" and row[2].get_meta("ability_badge") == "MUTATION", "One mixed draft exposes all three investment meanings")
	row[0].grab_focus(); await settle(); await key(KEY_RIGHT)
	check(row[1].has_focus(), "Real keyboard focus reaches the Rank II card")
	await motion(row[2]); check(ui._ability_inspector.power_id == "afterimage","Hover reads another card without replacing the focused tier")
	check(row[1].get_node("AbilityTierBadge").text == "RANK II" and row[2].get_node("AbilityTierBadge").text == "MUTATION","Focused and hovered cards retain explicit badges")
	await click(row[0]);check(not actions.is_empty() and actions.back().name == "choose_power" and actions.back().value.power_id == "redline","Actual mouse selection emits the original power intent and payload")
	var previous: String = Bindings.layout
	for profile: String in ["xbox","nintendo","playstation"]:
		Bindings.configure(profile); ui._note_input_profile(profile); row[1].grab_focus(); await settle()
		var prompt: Label = row[1].get_node("AbilityCardConfirm")
		check(prompt.text.begins_with(Front.prompt(profile,"confirm")),profile + " prints the correct confirmation glyph while keeping the cyan badge")
		var event := InputEventJoypadButton.new();event.device=0;event.button_index=Bindings.confirm_button(profile)
		event.pressed=true;Input.parse_input_event(event);await settle();event.pressed=false;Input.parse_input_event(event);await settle()
		check(actions.back().name == "choose_power" and actions.back().value.power_id == "dead_centre",profile + " actual mapped confirmation selects the focused upgrade")
	Bindings.configure(previous)
	ui._note_input_profile("touch")
	for card: Button in row: card.touch_targets=true
	check(row[0].get_node("AbilityCardConfirm").text.begins_with("TAP"), "Touch presentation remains explicit without colour-only meaning")
	check(row[0]._has_point(row[0].size*0.5),"Native touch target includes the visible centre of the semantic card")
	var count: int=actions.size();await tap(row[0])
	# The isolated menu intentionally leaves selected controls alive. Touch and
	# engine mouse emulation can both emit intents; Main owns exactly-once claims.
	check(actions.size()>count and actions.slice(count).all(func(item: Dictionary)->bool:return item.name=="choose_power" and item.value.power_id=="redline"),"Synthetic ScreenTouch reaches the visible card and preserves its exact payload")
	ui.show_mutation("afterimage",Powers.mutation_choices("afterimage"),"input",421,"ghost_circuit")
	await settle();var branch: Button=cards()[0]
	await click(branch)
	check(actions.back().name == "choose_mutation" and actions.back().value.branch_id == "ghost_circuit","Actual mutation click keeps the correct branch payload")

func reduced_flashing_hierarchy() -> void:
	ui.reduced_flashing=true
	for rank: int in [1,2,3]:
		ui.show_acquisition("redline","RETURN TO COMBAT",rank,"breakneck" if rank==3 else "")
		var initial: float=ui._acquisition_flash.color.a
		var previous: float=initial
		for tick: int in range(15):
			# A normal headless run may process many frames in a millisecond.
			# Sample real presentation time, rather than assuming 15 frames=.25s.
			await create_timer(0.02).timeout
			await settle(1)
			var alpha: float=ui._acquisition_flash.color.a
			check(alpha<=previous+0.0001,"Reduced Flashing tier %d reveal fades once without a brightness pulse"%rank)
			previous=alpha
		check(previous==0.0 and initial<=0.180001,"Reduced Flashing tier %d resolves its restrained existing reveal"%rank)
	ui.reduced_flashing=false

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
	if not report.is_empty() and (not report.is_absolute_path() or FileAccess.file_exists(report) or not report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/")):
		push_error("Fresh external QA report required");quit(2);return
	root.size=Vector2i(800,480);root.content_scale_size=Vector2i(800,480)
	Input.use_accumulated_input=false
	ui=UI.new();root.add_child(ui);ui.action.connect(func(name: String,value: Variant)->void:actions.append({"name":name,"value":value}))
	await settle();await audit_roster();await inspector_hierarchy();await input_hierarchy();await reduced_flashing_hierarchy()
	if not report.is_empty():
		var file=FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"card_count":roster.size(),"roster":roster,"inputs":actions,"scope":"Actual production menu nodes, font/layout and mapped events; no save opened, no physical controller/phone acceptance. Authored art remains unmodified and untinted. Roster contains16base+16RankII+14mutations; future power rarity is not implemented."},"\t"));file.close()
	print("ABILITY_CARD_HIERARCHY_003A1_%s checks=%d failures=%d cards=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),roster.size()])
	ui.free();quit(0 if failures.is_empty() else 1)
