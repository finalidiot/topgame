extends RefCounted
## Read-only catalogue/texture inspection for exported release QA. Main validates
## the external report destination before calling; existing files are refused.
const Catalog = preload("res://scripts/parts.gd")
const EcologyProbe = preload("res://scripts/ecology_package_probe.gd")
const FEEDBACK_MANIFEST: String = "res://assets/powers/feedback_002c5_2/manifest.json"
const PICKUP_FLAIR_MANIFEST: String = "res://assets/powers/pickup_003a1/manifest.json"
const PICKUP_COLLECT_AUDIO: String = "res://assets/audio/pickup_collect.wav"
const BEAST_MANIFEST: String = "res://assets/powers/beasts_002c5_2/manifest.json"
const MUSIC_MANIFEST: String = "res://assets/audio/music/manifest.json"
const Music = preload("res://scripts/music.gd")
const COMBAT_ART_MANIFEST: String = "res://assets/powers/combat_003a1/manifest.json"
const COMBAT_IDENTITY_MANIFEST: String = "res://assets/powers/identity_manifest.json"
const COMBAT_SPARK_MANIFEST: String = "res://assets/powers/impact_003a1/manifest.json"
const COMBAT_CRACK_MANIFEST: String = "res://assets/powers/impact_003a1/crack_manifest.json"
const COMBAT_AUDIO_MANIFEST: String = "res://assets/audio/impact_003a1/manifest.json"
const MUSIC_VARIATION_MANIFEST: String = "res://assets/audio/music/run_arrangement_003a1_manifest.json"
const MUSIC_VARIATION_SCORE: String = "res://assets/audio/music/run_arrangement_003a1.json"
const COMBAT_AUDIO_IDS: Array[String] = ["metal_light","metal_normal","metal_clang","metal_edge","metal_scrape","metal_massive","metal_extreme","metal_crack","metal_grind","metal_wall","metal_takedown"]
const COMBAT_CARD_IDS: Array[String] = ["redline","afterimage","orbit_drive","predator_line"]
const PacketEconomyModel = preload("res://scripts/packet_economy.gd")
const PACKET_ART_ROOT: String = "res://assets/ui/shop_003a/"
const PACKET_AUDIO_ROOT: String = "res://assets/audio/shop_003a/"
const PACKET_AUDIO_MANIFEST: String = PACKET_AUDIO_ROOT + "manifest.json"
const UI_POLISH_ROOT: String = "res://assets/ui/human_feedback003a/"
const DEFENCE_MANIFEST: String = "res://assets/powers/defence003a/manifest.json"
const DEFENCE_VARIANTS: Dictionary = {
	"gyro_lock":["gyro_lock", "gyro_lock_ii", "keel", "flywheel"],
	"impact_sink":["impact_sink", "impact_sink_ii", "shock_bleed", "return_spring"],
	"anchor_exchange":["anchor_exchange", "anchor_exchange_ii", "deep_footing", "slip_anchor"]
}
const ARENA_ROOT: String = "res://assets/arena/escalation003a/"
const ARENA_LAYOUT: Dictionary = {
	"display_panel":{"cell":[40,24],"pivot":[20,22],"frames":8,"layers":3,"tags":["IDLE","LOAD"]},
	"machinery":{"cell":[64,40],"pivot":[32,38],"frames":12,"layers":4,"tags":["IDLE","DRIVE","OVERDRIVE"]},
	"perimeter":{"cell":[32,16],"pivot":[16,8],"frames":8,"layers":2,"tags":["LEFT","RIGHT"]},
	"sparks":{"cell":[24,24],"pivot":[12,19],"frames":6,"layers":2,"tags":["SPARK"]},
	"vent":{"cell":[32,32],"pivot":[16,30],"frames":8,"layers":3,"tags":["IDLE","HOT"]},
	"warning_bank":{"cell":[48,16],"pivot":[24,12],"frames":16,"layers":3,"tags":["SAFE","BUILDING","WARNING","ALARM"]}
}
const UI_POLISH_LAYOUT: Dictionary = {
	"metal_plate":{"cell":[32, 32], "frames":3},
	"inspection_frame":{"cell":[32, 32], "frames":1},
	"button_caps":{"cell":[24, 24], "frames":6},
	"merchant":{"cell":[48, 64], "frames":14},
	"merchant_fixture":{"cell":[192, 64], "frames":1},
	"credit_chip":{"cell":[16, 16], "frames":4},
	"preview_station":{"cell":[160, 56], "frames":1}
}

static func inspect(output: String) -> Dictionary:
	if output.is_empty() or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output):
		return {"ok":false, "error":"Package asset report already exists or has no destination."}
	var catalogue_json: String = FileAccess.get_file_as_string(Catalog.DATA_PATH)
	var data: Variant = JSON.parse_string(catalogue_json)
	if not data is Dictionary or int(data.get("schema_version", 0)) != 1:
		return {"ok":false, "error":"The package does not contain the expected catalogue JSON."}
	var records: Array[Dictionary] = []
	var failures: Array[String] = []
	for category: String in ["blade", "ratchet", "bit"]:
		for id: String in Catalog.PARTS[category]:
			var part: Dictionary = Catalog.PARTS[category][id]
			var paths: Array[String] = [str(part.visual.sprite)]
			if category == "blade": paths.append(str(part.visual.spin))
			for path: String in paths:
				var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
				var spin: bool = path == str(part.visual.get("spin", ""))
				var expected: Vector2i = Vector2i(384 if spin else 48, 48)
				var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
				var visible: bool = false
				if texture != null:
					var pixels: Image = texture.get_image()
					visible = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
				var valid: bool = texture != null and size == expected and visible
				records.append({"part_id":category + ":" + id, "path":path, "size":[size.x, size.y], "visible_pixels":visible, "valid":valid})
				if not valid: failures.append(path)
	# Inspect the new floor sheets through the compiled release probe as well:
	# the editor loading them does not prove a fresh Windows package contains them.
	var feedback_json: String = FileAccess.get_file_as_string(FEEDBACK_MANIFEST)
	var feedback: Variant = JSON.parse_string(feedback_json)
	var feedback_records: Array[Dictionary] = []
	if not feedback is Dictionary or not feedback.get("effects", {}) is Dictionary:
		failures.append(FEEDBACK_MANIFEST)
	else:
		for kind: String in ["centre", "impact", "pickup"]:
			var meta: Dictionary = feedback.effects.get(kind, {})
			var path: String = str(meta.get("texture", ""))
			var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
			var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
			var pixels: Image = texture.get_image() if texture != null else null
			var valid: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
			var fingerprint: String = ""
			var visible_fingerprint: String = ""
			if valid:
				pixels.convert(Image.FORMAT_RGBA8)
				var decoded: PackedByteArray = pixels.get_data()
				var hash: HashingContext = HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(decoded)
				fingerprint = hash.finish().hex_encode()
				# Godot pads RGB behind fully transparent pixels at import. Those
				# bytes never render; every alpha and every visible RGB must match.
				for offset: int in range(0,decoded.size(),4):
					if decoded[offset+3] == 0:
						for channel: int in range(3): decoded[offset+channel] = 0
				hash.start(HashingContext.HASH_SHA256)
				hash.update(decoded)
				visible_fingerprint = hash.finish().hex_encode()
			feedback_records.append({"kind":kind,"path":path,"size":[size.x,size.y],"visible_pixels":valid,"valid":valid,
				"rgba_sha256":fingerprint,"visible_rgba_sha256":visible_fingerprint,"transparent_rgb_normalized":true})
			if not valid: failures.append(path)
	var pickup_flair_json: String = FileAccess.get_file_as_string(PICKUP_FLAIR_MANIFEST)
	var pickup_meta: Variant = JSON.parse_string(pickup_flair_json)
	var pickup_flair_record: Dictionary = _inspect_pickup_flair(pickup_meta if pickup_meta is Dictionary else {})
	if not bool(pickup_flair_record.valid): failures.append(PICKUP_FLAIR_MANIFEST)
	var pickup_audio_record: Dictionary = _inspect_pickup_audio()
	if not bool(pickup_audio_record.valid): failures.append(PICKUP_COLLECT_AUDIO)
	var beast_json: String = FileAccess.get_file_as_string(BEAST_MANIFEST)
	var beasts: Variant = JSON.parse_string(beast_json)
	var beast_records: Array[Dictionary] = []
	if not beasts is Dictionary or not beasts.get("effects", {}) is Dictionary:
		failures.append(BEAST_MANIFEST)
	else:
		for kind: String in ["black_arrow", "iron_bull", "stone_tortoise", "coil_dragon"]:
			var record: Dictionary = _inspect_beast_sheet(kind, beasts.effects.get(kind, {}))
			beast_records.append(record)
			if not bool(record.valid): failures.append(str(record.path))
	var music_json: String = FileAccess.get_file_as_string(MUSIC_MANIFEST)
	var music: Variant = JSON.parse_string(music_json)
	var music_records: Array[Dictionary] = []
	if not music is Dictionary or not music.get("stems", {}) is Dictionary:
		failures.append(MUSIC_MANIFEST)
	else:
		for kind: String in ["title", "workshop", "run_base", "run_pressure", "run_boss"]:
			var path: String = "res://assets/audio/music/" + kind + ".wav"
			var sample: AudioStreamWAV = (load(path) as AudioStreamWAV) if ResourceLoader.exists(path) else null
			var valid: bool = sample != null and sample.format == AudioStreamWAV.FORMAT_16_BITS and sample.stereo and sample.mix_rate == 32000
			var pcm_data: PackedByteArray = sample.data if sample != null else PackedByteArray()
			valid = valid and pcm_data.size() == int(music.grid.frames) * 4
			var hash: HashingContext = HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(pcm_data)
			music_records.append({"kind":kind,"path":path,"valid":valid,"pcm_frames":pcm_data.size() / 4,"mix_rate":sample.mix_rate if sample != null else 0,"pcm_sha256":hash.finish().hex_encode()})
			if not valid: failures.append(path)
	# These are actual compiled/imported resources, not a receipt/UI fixture.
	# Exact source parity is checked by the external verifier from these hashes.
	var packet_json: Dictionary = {}
	var packet_records: Array[Dictionary] = []
	for kind: String in ["packet", "reclaimed_packet", "reveal_mat"]:
		var metadata_path: String = PACKET_ART_ROOT + kind + ".json"
		var source_json: String = FileAccess.get_file_as_string(metadata_path)
		packet_json[kind] = source_json
		var parsed: Variant = JSON.parse_string(source_json)
		var record: Dictionary = _inspect_packet_sheet(kind, parsed if parsed is Dictionary else {})
		packet_records.append(record)
		if not bool(record.valid): failures.append(str(record.path))
	var packet_audio_json: String = FileAccess.get_file_as_string(PACKET_AUDIO_MANIFEST)
	var packet_audio_manifest: Variant = JSON.parse_string(packet_audio_json)
	var packet_audio_records: Array[Dictionary] = []
	if not packet_audio_manifest is Dictionary or not packet_audio_manifest.get("cues", {}) is Dictionary:
		failures.append(PACKET_AUDIO_MANIFEST)
	else:
		for kind: String in ["packet_land", "packet_crinkle", "packet_tear", "packet_spill", "packet_clink", "packet_new", "packet_rare", "packet_recycle"]:
			var record: Dictionary = _inspect_packet_audio(kind, packet_audio_manifest.cues.get(kind, {}))
			packet_audio_records.append(record)
			if not bool(record.valid): failures.append(str(record.path))
	var economy_json: String = FileAccess.get_file_as_string(PacketEconomyModel.DATA_PATH)
	var economy_validation_errors: Array[String] = PacketEconomyModel.validate_config()
	var economy_odds: Dictionary = PacketEconomyModel.rarity_odds("standard")
	if not economy_validation_errors.is_empty() or economy_odds.is_empty(): failures.append(PacketEconomyModel.DATA_PATH)
	var ui_polish_json: Dictionary = {}
	var ui_polish_records: Array[Dictionary] = []
	for kind: String in UI_POLISH_LAYOUT:
		var source_json: String = FileAccess.get_file_as_string(UI_POLISH_ROOT + kind + ".json")
		ui_polish_json[kind] = source_json
		var parsed: Variant = JSON.parse_string(source_json)
		var record: Dictionary = _inspect_ui_polish_sheet(kind, parsed if parsed is Dictionary else {})
		ui_polish_records.append(record)
		if not bool(record.valid): failures.append(str(record.path))
	var defence_json: String = FileAccess.get_file_as_string(DEFENCE_MANIFEST)
	var defence: Variant = JSON.parse_string(defence_json)
	var defence_records: Array[Dictionary] = []
	if not defence is Dictionary or not defence.get("families", {}) is Dictionary:
		failures.append(DEFENCE_MANIFEST)
	else:
		for family: String in DEFENCE_VARIANTS:
			var family_meta: Dictionary = defence.families.get(family, {})
			for group: String in ["cards", "icons", "fx"]:
				var record: Dictionary = _inspect_defence_sheet(family, group, family_meta.get(group, {}))
				defence_records.append(record)
				if not bool(record.valid): failures.append(str(record.path))
	var arena_json: Dictionary = {}
	var arena_records: Array[Dictionary] = []
	for kind: String in ARENA_LAYOUT:
		var text: String = FileAccess.get_file_as_string(ARENA_ROOT + kind + ".json")
		arena_json[kind] = text
		var parsed: Variant = JSON.parse_string(text)
		var record: Dictionary = _inspect_arena_sheet(kind, parsed if parsed is Dictionary else {})
		arena_records.append(record)
		if not bool(record.valid): failures.append(str(record.path))
	var combat_art_json: String = FileAccess.get_file_as_string(COMBAT_ART_MANIFEST)
	var combat_identity_json: String = FileAccess.get_file_as_string(COMBAT_IDENTITY_MANIFEST)
	var combat_spark_json: String = FileAccess.get_file_as_string(COMBAT_SPARK_MANIFEST)
	var combat_crack_json: String = FileAccess.get_file_as_string(COMBAT_CRACK_MANIFEST)
	var combat_art: Variant = JSON.parse_string(combat_art_json)
	var combat_identity: Variant = JSON.parse_string(combat_identity_json)
	var combat_spark: Variant = JSON.parse_string(combat_spark_json)
	var combat_crack: Variant = JSON.parse_string(combat_crack_json)
	var combat_records: Array[Dictionary] = _inspect_combat_art(combat_art if combat_art is Dictionary else {},combat_identity if combat_identity is Dictionary else {},combat_spark if combat_spark is Dictionary else {},combat_crack if combat_crack is Dictionary else {})
	for record: Dictionary in combat_records:
		if not bool(record.valid): failures.append(str(record.path))
	var combat_audio_json: String = FileAccess.get_file_as_string(COMBAT_AUDIO_MANIFEST)
	var combat_audio: Variant = JSON.parse_string(combat_audio_json)
	var combat_audio_records: Array[Dictionary] = []
	for kind: String in COMBAT_AUDIO_IDS:
		var meta: Dictionary = combat_audio.get("sounds",{}).get(kind,{}) if combat_audio is Dictionary else {}
		var record: Dictionary = _inspect_combat_pcm(kind,"res://assets/audio/impact_003a1/"+kind+".wav",int(meta.get("frames",0)),false,false)
		record.valid = bool(record.valid) and str(meta.get("file",""))==kind+".wav" and record.pcm_sha256==str(meta.get("pcm_sha256",""))
		combat_audio_records.append(record)
		if not bool(record.valid): failures.append(str(record.path))
	var variation_json: String = FileAccess.get_file_as_string(MUSIC_VARIATION_MANIFEST)
	var variation: Variant = JSON.parse_string(variation_json)
	var variation_records: Array[Dictionary] = []
	for kind: String in ["run_opening","run_motion"]:
		var meta: Dictionary = variation.get("stems",{}).get(kind,{}) if variation is Dictionary else {}
		# WAV imports are unlooped PCM. Music duplicates those resources and sets
		# exact synchronized runtime loop bounds; this probe reports the import.
		var record: Dictionary = _inspect_combat_pcm(kind,"res://assets/audio/music/"+kind+".wav",int(meta.get("frames",0)),true,false)
		variation_records.append(record)
		if not bool(record.valid): failures.append(str(record.path))
	var ecology: Dictionary = EcologyProbe.inspect()
	for failure: String in ecology.failures: failures.append(failure)
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null: return {"ok":false, "error":"Cannot write the external package asset report."}
	file.store_string(JSON.stringify({"catalogue_sha256":FileAccess.get_sha256(Catalog.DATA_PATH), "catalogue_json":catalogue_json,
		"textures":records, "feedback_json":feedback_json, "feedback_textures":feedback_records,
		"pickup_flair_json":pickup_flair_json,"pickup_flair_texture":pickup_flair_record,"pickup_collect_audio":pickup_audio_record,
		"beast_json":beast_json, "beast_textures":beast_records,
		"music_json":music_json, "music_stems":music_records,
		"packet_json":packet_json, "packet_textures":packet_records,
		"packet_audio_json":packet_audio_json, "packet_audio":packet_audio_records,
		"economy_json":economy_json, "economy_config":PacketEconomyModel.config(),
		"economy_odds":economy_odds, "economy_validation_errors":economy_validation_errors,
		"ui_polish_json":ui_polish_json, "ui_polish_textures":ui_polish_records,
		"defence_json":defence_json,"defence_textures":defence_records,
		"arena_json":arena_json,"arena_textures":arena_records,
		"combat_art_json":combat_art_json,"combat_identity_json":combat_identity_json,"combat_spark_json":combat_spark_json,"combat_crack_json":combat_crack_json,"combat_art_textures":combat_records,"combat_arena_geometry_json":FileAccess.get_file_as_string("res://assets/arena/manifest.json"),
		"combat_audio_json":combat_audio_json,"combat_audio":combat_audio_records,
		"music_variation_json":variation_json,"music_variation_score_json":FileAccess.get_file_as_string(MUSIC_VARIATION_SCORE),"music_variation_stems":variation_records,"music_asset_metadata":Music.asset_metadata(),
		"ecology_json":ecology.json,"ecology_textures":ecology.textures,
		"failures":failures, "read_only_asset_inspection":true}, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK: return {"ok":false, "error":"The external package asset report could not be written completely."}
	if not failures.is_empty(): return {"ok":false, "error":"Packaged textures failed validation: " + str(failures)}
	return {"ok":true, "textures":records.size(), "report":output}

static func _inspect_combat_art(art: Dictionary, identity: Dictionary, sparks: Dictionary, cracks: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var base: Dictionary = art.get("base_arena",{})
	for name: String in ["backdrop","structure","surface","markings","rear_rim","front_rim"]:
		var path: String = "res://assets/arena/"+name+".png"
		var meta: Dictionary = base.duplicate(true);meta["texture"]=str(base.get("textures",{}).get(name,""))
		var expected: Dictionary = {"path":path,"source":"assets/source-art/arena_foundry_eight.aseprite","cell":[640,360],"pivot":[320,180],"frames":1,"columns":1,"layers":6,"tags":[],"allow_empty_tags":true}
		var record: Dictionary = _inspect_final_sheet("arena_base/"+name,meta,expected)
		record["metadata_path"]=COMBAT_ART_MANIFEST;record["native_layer"]=name;records.append(record)
	for name: String in ["venue_lights","power_motion","redline_ring"]:
		var meta: Dictionary = art.get("families",{}).get(name,{})
		var tags: Array = ["IGNITE"] if name=="redline_ring" else (["EARLY","BUILDING","MID","LATE","EXTREME"] if name=="venue_lights" else ["REDLINE_ROTATION","PREDATOR_FLOW_e","PREDATOR_FLOW_se","PREDATOR_FLOW_s","PREDATOR_FLOW_sw","PREDATOR_FLOW_w","PREDATOR_FLOW_nw","PREDATOR_FLOW_n","PREDATOR_FLOW_ne","CIRCUIT_CURRENT","CIRCUIT_LATCH"])
		var expected: Dictionary = {"path":"res://assets/powers/combat_003a1/"+name+".png","source":"assets/source-art/combat_003a1/"+name+".aseprite","cell":[640,360] if name=="venue_lights" else ([128,128] if name=="redline_ring" else [48,32]),"pivot":[0,0] if name=="venue_lights" else ([64,64] if name=="redline_ring" else [24,16]),"frames":5 if name=="venue_lights" else (8 if name=="redline_ring" else 88),"columns":5 if name=="venue_lights" else 8,"layers":3,"tags":tags}
		var record: Dictionary = _inspect_final_sheet("combat/"+name,meta,expected);record["metadata_path"]=COMBAT_ART_MANIFEST;records.append(record)
	for family: String in COMBAT_CARD_IDS:
		var meta: Dictionary = identity.get("families",{}).get(family,{}).get("cards",{})
		var tags: Array[String] = [family,family+"_ii"]
		if family=="redline":tags.append_array(["runaway","breakneck"])
		if family=="afterimage":tags.append_array(["ghost_circuit","slipstream"])
		var expected: Dictionary = {"path":"res://assets/powers/identity/"+family+"_cards.png","source":"assets/source-art/power_identity_002c5/"+family+"_cards.aseprite","cell":[64,64],"pivot":[32,32],"frames":tags.size()*12,"columns":12,"layers":6 if family=="afterimage" else 5,"tags":tags}
		var record: Dictionary = _inspect_final_sheet("card/"+family,meta,expected);record["metadata_path"]=COMBAT_IDENTITY_MANIFEST;records.append(record)
	var spark_tags: Array[String] = []
	for tier: String in ["light","strong","hard","extreme"]:
		for direction: int in range(8):spark_tags.append(tier+"_"+str(direction))
	var expected: Dictionary = {"path":"res://assets/powers/impact_003a1/contact_sparks.png","source":"assets/source-art/impact_003a1/contact_sparks.aseprite","cell":[64,48],"pivot":[32,24],"frames":128,"columns":16,"layers":3,"tags":spark_tags}
	var record: Dictionary = _inspect_final_sheet("combat/contact_sparks",sparks,expected);record["metadata_path"]=COMBAT_SPARK_MANIFEST;records.append(record)
	var crack_tags: Array[String] = []
	for tier: String in ["hard","extreme"]:
		for direction: int in range(8):crack_tags.append(tier+"_"+str(direction))
	var crack_expected: Dictionary = {"path":"res://assets/powers/impact_003a1/contact_crack.png","source":"assets/source-art/impact_003a1/contact_crack.aseprite","cell":[64,48],"pivot":[32,24],"frames":64,"columns":16,"layers":3,"tags":crack_tags}
	var crack_record: Dictionary = _inspect_final_sheet("combat/contact_crack",cracks,crack_expected)
	crack_record["metadata_path"]=COMBAT_CRACK_MANIFEST
	crack_record.valid=bool(crack_record.valid) and cracks.get("filter","")=="nearest" and cracks.get("native_runtime_rgba_exact",false)==true and cracks.get("loop",true)==false and int(cracks.get("segments",{}).get("hard",0))==3 and int(cracks.get("segments",{}).get("extreme",0))==5 and float(cracks.get("maximum_lifetime_seconds",1.0))<.2 and int(cracks.get("physical_work_threshold",0))==500000
	records.append(crack_record)
	return records

static func _inspect_combat_pcm(kind: String, path: String, frames: int, stereo: bool, looping: bool) -> Dictionary:
	var sample: AudioStreamWAV = (load(path) as AudioStreamWAV) if ResourceLoader.exists(path) else null
	var pcm: PackedByteArray = sample.data if sample!=null else PackedByteArray()
	var channels: int = 2 if stereo else 1
	var valid: bool = sample!=null and frames>0 and sample.format==AudioStreamWAV.FORMAT_16_BITS and sample.stereo==stereo and sample.mix_rate==32000
	valid = valid and pcm.size()==frames*channels*2
	if sample!=null:valid=valid and sample.loop_mode==(AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED) and (not looping or (sample.loop_begin==0 and sample.loop_end==frames))
	return {"kind":kind,"path":path,"valid":valid,"format":sample.format if sample!=null else -1,"stereo":sample.stereo if sample!=null else false,"channels":(2 if sample.stereo else 1) if sample!=null else 0,"mix_rate":sample.mix_rate if sample!=null else 0,"loop_mode":sample.loop_mode if sample!=null else -1,"loop_begin":sample.loop_begin if sample!=null else -1,"loop_end":sample.loop_end if sample!=null else -1,"pcm_frames":pcm.size()/(channels*2),"duration_seconds":sample.get_length() if sample!=null else 0.0,"pcm_sha256":_digest(pcm)}

static func _inspect_pickup_flair(meta: Dictionary) -> Dictionary:
	var expected: Dictionary = {"path":"res://assets/powers/pickup_003a1/collection.png",
		"source":"assets/source-art/pickup_003a1/collection.aseprite","cell":[40,24],"pivot":[20,12],
		"frames":6,"columns":6,"layers":3,"tags":["collect"]}
	var record: Dictionary = _inspect_final_sheet("collect",meta,expected)
	record.metadata_path=PICKUP_FLAIR_MANIFEST
	record.valid = bool(record.valid) and str(meta.get("filter",""))=="nearest" and bool(meta.get("floor_only",false)) and not bool(meta.get("loop",true))
	record.valid = bool(record.valid) and bool(meta.get("native_runtime_rgba_exact",false)) and int(meta.get("duration_ms",0))==310
	var timings: Array[int] = [30,35,45,55,65,80]
	if record.valid:
		for index: int in range(timings.size()): record.valid = bool(record.valid) and float(record.durations_ms[index])==float(timings[index])
	return record

static func _inspect_pickup_audio(path: String = PICKUP_COLLECT_AUDIO) -> Dictionary:
	var sample: AudioStreamWAV = (load(path) as AudioStreamWAV) if ResourceLoader.exists(path) else null
	var pcm: PackedByteArray = sample.data if sample != null else PackedByteArray()
	var valid: bool = path==PICKUP_COLLECT_AUDIO and sample != null and sample.format==AudioStreamWAV.FORMAT_16_BITS and not sample.stereo and sample.mix_rate==48000 and sample.loop_mode==AudioStreamWAV.LOOP_DISABLED
	valid = valid and pcm.size()==8640*2
	return {"kind":"pickup_collect","path":path,"valid":valid,"mix_rate":sample.mix_rate if sample != null else 0,
		"channels":(2 if sample.stereo else 1) if sample != null else 0,"stereo":sample.stereo if sample != null else false,
		"format":sample.format if sample != null else -1,"loop_mode":sample.loop_mode if sample != null else -1,
		"pcm_frames":pcm.size()/2,"duration_seconds":sample.get_length() if sample != null else 0.0,"pcm_sha256":_digest(pcm)}

static func _inspect_defence_sheet(family: String, group: String, meta: Dictionary) -> Dictionary:
	var expected: Dictionary = {"path":"res://assets/powers/defence003a/" + family + "_" + group + ".png",
		"source":"assets/source-art/defence003a/" + family + "_" + group + ".aseprite"}
	var required: Array = DEFENCE_VARIANTS.get(family, [])
	if group == "cards": expected.merge({"cell":[64,64],"pivot":[32,32],"frames":48,"columns":12,"layers":5,"tags":required})
	elif group == "icons": expected.merge({"cell":[16,16],"pivot":[8,8],"frames":4,"columns":4,"layers":3,"tags":required})
	elif group == "fx":
		var tags: Array = ["stored", "engage", "vent", "return"] if family == "impact_sink" else (["lock", "engage", "release"] if family == "gyro_lock" else ["brace", "engage", "release"])
		expected.merge({"cell":[96,80],"pivot":[48,48],"frames":tags.size()*8,"columns":8,"layers":4,"tags":tags})
	var record: Dictionary = _inspect_final_sheet(family + "/" + group, meta, expected)
	record["family"] = family; record["group"] = group
	record["metadata_path"] = DEFENCE_MANIFEST
	if required.is_empty(): record.valid = false
	return record

static func _inspect_arena_sheet(kind: String, meta: Dictionary) -> Dictionary:
	var expected: Dictionary = ARENA_LAYOUT.get(kind, {}).duplicate(true)
	expected["path"] = ARENA_ROOT + kind + ".png"
	expected["source"] = "assets/source-art/arena_escalation003a/" + kind + ".aseprite"
	expected["columns"] = expected.get("frames", 0)
	var record: Dictionary = _inspect_final_sheet(kind, meta, expected)
	record["metadata_path"] = ARENA_ROOT + kind + ".json"
	if not bool(meta.get("native_pixels", false)) or not bool(meta.get("presentation_only", false)) or str(meta.get("filter", "")) != "nearest": record.valid = false
	return record

static func _inspect_final_sheet(kind: String, meta: Dictionary, expected: Dictionary) -> Dictionary:
	var path: String = str(expected.get("path", ""))
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
	var pixels: Image = texture.get_image() if texture != null else null
	var visible: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
	var count: int = int(meta.get("frame_count", 0))
	var columns: int = int(meta.get("columns", 0))
	var durations: Array = meta.get("durations_ms", [])
	var tags: Dictionary = meta.get("tags", {})
	var layers: Array = meta.get("layers", [])
	var cell: Array = meta.get("cell", [])
	var pivot: Array = meta.get("pivot", [])
	var expected_cell: Array = expected.get("cell", [])
	var expected_pivot: Array = expected.get("pivot", [])
	var valid: bool = visible and cell.size() == 2 and pivot.size() == 2 and expected_cell.size() == 2 and expected_pivot.size() == 2
	if valid:
		valid = Vector2i(int(cell[0]), int(cell[1])) == Vector2i(int(expected_cell[0]), int(expected_cell[1])) and Vector2i(int(pivot[0]), int(pivot[1])) == Vector2i(int(expected_pivot[0]), int(expected_pivot[1]))
	valid = valid and count > 0 and count == int(expected.get("frames", -1)) and columns > 0 and columns == int(expected.get("columns", -1))
	if valid: valid = size == Vector2i(int(cell[0]) * columns, int(cell[1]) * ceili(float(count) / columns))
	valid = valid and str(meta.get("texture", "")) == path and str(meta.get("source", "")) == str(expected.get("source", "invalid"))
	valid = valid and durations.size() == count and layers.size() == int(expected.get("layers", -1))
	var names: Dictionary = {}
	for name: Variant in layers:
		valid = valid and name is String and not str(name).is_empty() and not names.has(name)
		names[name] = true
	for duration: Variant in durations: valid = valid and is_finite(float(duration)) and float(duration) > 0.0 and float(duration) <= 10000.0
	var required: Array = expected.get("tags", [])
	valid = valid and (not required.is_empty() or bool(expected.get("allow_empty_tags",false))) and tags.size() == required.size()
	for tag: String in required: valid = valid and tags.has(tag)
	for span: Dictionary in tags.values():
		valid = valid and int(span.get("from", -1)) >= 0 and int(span.get("to", -1)) >= int(span.get("from", -1)) and int(span.get("to", -1)) < count
	var fingerprint: String = ""
	if visible:
		if pixels.is_compressed(): pixels.decompress()
		pixels.convert(Image.FORMAT_RGBA8)
		var decoded: PackedByteArray = pixels.get_data()
		for offset: int in range(0, decoded.size(), 4):
			if decoded[offset+3] == 0:
				for channel: int in range(3): decoded[offset+channel] = 0
		fingerprint = _digest(decoded)
	var source: String = "res://" + str(expected.get("source", ""))
	var source_available: bool = FileAccess.file_exists(source)
	var native_hash: String = FileAccess.get_sha256(source) if source_available else ""
	if source_available and meta.has("source_sha256"): valid = valid and native_hash == str(meta.source_sha256)
	return {"kind":kind,"path":path,"valid":valid,"visible_pixels":visible,"size":[size.x,size.y],
		"cell":cell,"pivot":pivot,"columns":columns,"frame_count":count,"durations_ms":durations,"tags":tags,"layers":layers,
		"visible_rgba_sha256":fingerprint,"transparent_rgb_normalized":true,"source":meta.get("source", ""),
		"native_source_available":source_available,"native_source_sha256":native_hash}

static func _inspect_ui_polish_sheet(kind: String, meta: Dictionary) -> Dictionary:
	var path: String = UI_POLISH_ROOT + kind + ".png"
	var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
	var pixels: Image = texture.get_image() if texture != null else null
	var visible: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
	var cell: Array = meta.get("cell", [])
	var pivot: Array = meta.get("pivot", [])
	var durations: Array = meta.get("durations_ms", [])
	var layers: Array = meta.get("layers", [])
	var tags: Dictionary = meta.get("tags", {})
	var expected: Dictionary = UI_POLISH_LAYOUT.get(kind, {})
	var columns: int = int(meta.get("columns", 0))
	var count: int = int(meta.get("frame_count", 0))
	var expected_cell: Array = expected.get("cell", [])
	var valid: bool = visible and cell.size() == 2 and expected_cell.size() == 2 and pivot.size() == 2
	if valid: valid = Vector2i(int(cell[0]), int(cell[1])) == Vector2i(int(expected_cell[0]), int(expected_cell[1]))
	valid = valid and count == int(expected.get("frames", 0)) and columns == count
	if valid:
		valid = size == Vector2i(int(cell[0]) * count, int(cell[1]))
		valid = valid and int(pivot[0]) >= 0 and int(pivot[0]) <= int(cell[0]) and int(pivot[1]) >= 0 and int(pivot[1]) <= int(cell[1])
	valid = valid and str(meta.get("texture", "")) == kind + ".png" and str(meta.get("filter", "")) == "nearest" and bool(meta.get("native_pixels", false))
	valid = valid and durations.size() == count and not layers.is_empty() and not tags.is_empty()
	for duration: Variant in durations: valid = valid and float(duration) > 0.0
	for tag: String in tags:
		var bounds: Dictionary = tags[tag]
		valid = valid and int(bounds.get("from", -1)) >= 0 and int(bounds.get("to", -1)) >= int(bounds.get("from", -1)) and int(bounds.get("to", -1)) < count
	var fingerprint: String = ""
	if visible:
		if pixels.is_compressed(): pixels.decompress()
		pixels.convert(Image.FORMAT_RGBA8)
		var decoded: PackedByteArray = pixels.get_data()
		for offset: int in range(0, decoded.size(), 4):
			if decoded[offset + 3] == 0:
				for channel: int in range(3): decoded[offset + channel] = 0
		fingerprint = _digest(decoded)
	return {"kind":kind, "path":path, "metadata_path":UI_POLISH_ROOT + kind + ".json",
		"valid":valid, "visible_pixels":visible, "size":[size.x, size.y], "cell":cell,
		"pivot":pivot, "tags":tags, "durations_ms":durations, "layers":layers,
		"columns":columns, "frame_count":count, "visible_rgba_sha256":fingerprint,
		"transparent_rgb_normalized":true}

static func _inspect_beast_sheet(kind: String, meta: Dictionary) -> Dictionary:
	var path: String = str(meta.get("texture", ""))
	var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
	var pixels: Image = texture.get_image() if texture != null else null
	var cell: Array = meta.get("cell", [])
	var columns: int = int(meta.get("columns", 0))
	var frames: int = int(meta.get("frame_count", 0))
	var valid: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
	valid = valid and cell.size() == 2 and int(cell[0]) == 128 and int(cell[1]) == 128 and columns > 0 and frames >= 20
	if valid: valid = size == Vector2i(columns * 128, ceili(float(frames) / float(columns)) * 128)
	var fingerprint: String = ""
	if valid:
		pixels.convert(Image.FORMAT_RGBA8)
		var decoded: PackedByteArray = pixels.get_data()
		for offset: int in range(0, decoded.size(), 4):
			if decoded[offset + 3] == 0:
				for channel: int in range(3): decoded[offset + channel] = 0
		var hash: HashingContext = HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(decoded)
		fingerprint = hash.finish().hex_encode()
	return {"kind":kind, "path":path, "size":[size.x, size.y], "visible_pixels":valid, "valid":valid,
		"visible_rgba_sha256":fingerprint, "transparent_rgb_normalized":true}

static func _digest(bytes: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func _inspect_packet_sheet(kind: String, meta: Dictionary) -> Dictionary:
	var path: String = PACKET_ART_ROOT + kind + ".png"
	var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
	var pixels: Image = texture.get_image() if texture != null else null
	var visible: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
	var cell: Array = meta.get("cell", [])
	var pivot: Array = meta.get("pivot", [])
	var durations: Array = meta.get("durations_ms", [])
	var layers: Array = meta.get("layers", [])
	var tags: Dictionary = meta.get("tags", {})
	var expected_cell: Vector2i = Vector2i(272, 134) if kind == "reveal_mat" else Vector2i(96, 96)
	var expected_pivot: Vector2i = Vector2i(136, 124) if kind == "reveal_mat" else Vector2i(48, 86)
	var expected_frames: int = 1 if kind == "reveal_mat" else 13
	var columns: int = int(meta.get("columns", 0))
	var count: int = int(meta.get("frame_count", 0))
	var valid: bool = visible and cell.size() == 2 and pivot.size() == 2
	if valid:
		valid = Vector2i(int(cell[0]), int(cell[1])) == expected_cell and Vector2i(int(pivot[0]), int(pivot[1])) == expected_pivot
	valid = valid and count == expected_frames and columns == expected_frames and size == Vector2i(expected_cell.x * expected_frames, expected_cell.y)
	valid = valid and str(meta.get("texture", "")) == kind + ".png" and str(meta.get("filter", "")) == "nearest" and bool(meta.get("native_pixels", false))
	valid = valid and durations.size() == expected_frames and layers.size() == (3 if kind == "reveal_mat" else 6)
	var required_tags: Array = ["REVEAL_MAT"] if kind == "reveal_mat" else ["SEALED", "CRINKLE", "TEAR_START", "TEAR_OPEN", "SPILL", "EMPTY_PACKET"]
	valid = valid and tags.size() == required_tags.size()
	for tag: String in required_tags:
		valid = valid and tags.has(tag)
	for duration: Variant in durations:
		valid = valid and float(duration) > 0.0
	var rgba_fingerprint: String = ""
	var visible_fingerprint: String = ""
	if visible:
		if pixels.is_compressed(): pixels.decompress()
		pixels.convert(Image.FORMAT_RGBA8)
		var decoded: PackedByteArray = pixels.get_data()
		rgba_fingerprint = _digest(decoded)
		# Normalize only RGB behind alpha-zero pixels, matching beast/feedback
		# package verification while preserving every alpha and visible RGB byte.
		for offset: int in range(0, decoded.size(), 4):
			if decoded[offset + 3] == 0:
				for channel: int in range(3): decoded[offset + channel] = 0
		visible_fingerprint = _digest(decoded)
	return {"kind":kind, "path":path, "metadata_path":PACKET_ART_ROOT + kind + ".json",
		"valid":valid, "visible_pixels":visible, "size":[size.x, size.y],
		"cell":cell, "pivot":pivot, "tags":tags, "durations_ms":durations, "columns":columns, "frame_count":count,
		"rgba_sha256":rgba_fingerprint, "visible_rgba_sha256":visible_fingerprint, "transparent_rgb_normalized":true}

static func _inspect_packet_audio(kind: String, meta: Dictionary) -> Dictionary:
	var path: String = PACKET_AUDIO_ROOT + kind + ".wav"
	var sample: AudioStreamWAV = (load(path) as AudioStreamWAV) if ResourceLoader.exists(path) else null
	var pcm: PackedByteArray = sample.data if sample != null else PackedByteArray()
	var fingerprint: String = _digest(pcm)
	var valid: bool = sample != null and sample.format == AudioStreamWAV.FORMAT_16_BITS and not sample.stereo and sample.mix_rate == 32000 and sample.loop_mode == AudioStreamWAV.LOOP_DISABLED
	valid = valid and str(meta.get("file", "")) == kind + ".wav" and int(meta.get("pcm_frames", 0)) > 0
	valid = valid and pcm.size() == int(meta.get("pcm_frames", 0)) * 2 and fingerprint == str(meta.get("pcm_sha256", ""))
	return {"kind":kind, "path":path, "valid":valid, "mix_rate":sample.mix_rate if sample != null else 0,
		"channels":(2 if sample.stereo else 1) if sample != null else 0, "stereo":sample.stereo if sample != null else false,
		"format":sample.format if sample != null else -1, "loop_mode":sample.loop_mode if sample != null else -1,
		"pcm_frames":pcm.size() / 2, "pcm_sha256":fingerprint}
