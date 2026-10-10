extends RefCounted
## Read-only packaged resource inspection. Does not create gameplay/save state.
const MANIFEST: String = "res://assets/powers/ecology003a2/manifest.json"
const FAMILIES: Dictionary = {
	"iron_comet":["wallbreaker","ricochet_engine"],
	"orbit_drive":["centrifuge","perpetual_orbit"],
	"momentum_bank":["flywheel_release","countersteer"],
	"crash_guard":["reactive_plating","sacrificial_damper"]}

static func digest(bytes: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	return hash.finish().hex_encode()

static func pair(value: Variant, x: int, y: int) -> bool:
	return value is Array and value.size()==2 and float(value[0])==x and float(value[1])==y

static func inspect() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(MANIFEST)
	var parsed: Variant = JSON.parse_string(text)
	var rows: Array[Dictionary] = [];var failures: Array[String] = []
	if not parsed is Dictionary or int(parsed.get("version",0)) != 1 or parsed.get("task","") != "003A.2" or parsed.get("filter","") != "nearest" or parsed.get("native_pixels",false) != true:
		return {"json":text,"textures":rows,"failures":[MANIFEST]}
	if not parsed.get("families",{}) is Dictionary or parsed.families.size()!=4 or not parsed.get("art",{}) is Dictionary or parsed.art.size()!=8:
		return {"json":text,"textures":rows,"failures":[MANIFEST]}
	for family: String in FAMILIES:
		for group: String in ["cards","icons"]:
			var meta: Dictionary = parsed.families.get(family,{}).get(group,{})
			var side: int = 64 if group=="cards" else 16
			var columns: int = 6 if group=="cards" else 2
			var count: int = 12 if group=="cards" else 2
			var path: String = "res://assets/powers/ecology003a2/"+family+"_"+group+".png"
			var source: String = "assets/source-art/ecology003a2/"+family+"_"+group+".aseprite"
			var tags: Variant = meta.get("tags",{})
			var valid: bool = pair(meta.get("cell",[]),side,side) and pair(meta.get("pivot",[]),side/2,side/2) and int(meta.get("columns",0))==columns and int(meta.get("frame_count",0))==count
			valid = valid and meta.get("texture","")==path and meta.get("source","")==source and meta.get("native_runtime_rgba_exact",false)==true
			valid = valid and meta.get("layers",[]).size()==(5 if group=="cards" else 2) and meta.get("durations_ms",[]).size()==count and tags is Dictionary and tags.size()==2
			for duration: Variant in meta.get("durations_ms",[]):valid=valid and int(duration)>0
			for index: int in range(2):
				var branch: String = FAMILIES[family][index]
				var span: Dictionary = tags.get(branch,{}) if tags is Dictionary else {}
				var frames: int = 6 if group=="cards" else 1
				valid=valid and int(span.get("from",-1))==index*frames and int(span.get("to",-1))==(index+1)*frames-1
				var art: Dictionary=parsed.art.get(branch,{})
				valid=valid and art.get("family","")==family and art.get("art_id","")==branch and art.get("source_tag","")==branch
				if group=="cards":valid=valid and art.get("card_texture","")==path and int(art.get("card_row",-1))==index and int(art.get("card_frames",0))==6 and int(art.get("card_cell",0))==64 and int(art.get("card_static_frame",-1)) in range(6)
				else:valid=valid and art.get("icon","")==path and int(art.get("icon_frame",-1))==index
			var texture: Texture2D=(load(path) as Texture2D) if ResourceLoader.exists(path) else null
			var pixels: Image=texture.get_image() if texture!=null else null
			var size: Vector2i=Vector2i(texture.get_size()) if texture!=null else Vector2i.ZERO
			var visible: bool=pixels!=null and not pixels.is_empty() and not pixels.is_invisible()
			valid=valid and visible and size==Vector2i(side*columns,side*ceili(float(count)/columns))
			var rgba: String="";var visible_rgba: String=""
			if visible:
				pixels.convert(Image.FORMAT_RGBA8)
				var decoded: PackedByteArray=pixels.get_data();rgba=digest(decoded)
				for offset: int in range(0,decoded.size(),4):
					if decoded[offset+3]==0:
						for channel: int in range(3):decoded[offset+channel]=0
				visible_rgba=digest(decoded)
			var row: Dictionary={"kind":family+"/"+group,"family":family,"group":group,"path":path,"metadata_path":MANIFEST,
				"size":[size.x,size.y],"visible_pixels":visible,"valid":valid,"rgba_sha256":rgba,"visible_rgba_sha256":visible_rgba,"transparent_rgb_normalized":true,
				"packaged_native_master_present":FileAccess.file_exists("res://"+source)}
			for key: String in ["cell","pivot","layers","tags","durations_ms","columns","frame_count","source","source_sha256","texture_sha256","native_runtime_rgba_exact"]:row[key]=meta.get(key)
			rows.append(row)
			if not valid:failures.append(path)
	return {"json":text,"textures":rows,"failures":failures}
