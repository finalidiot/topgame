extends SceneTree
## Actual imported venue/power/spark RGBA and original metal/music PCM. This
## editor contract is also checked from the compiled candidate by the verifier.
const Probe = preload("res://scripts/parts_package_probe.gd")
var checks: int = 0
var failures: Array[String] = []
var before: Dictionary = {}

func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)

func fingerprints(folder: String) -> Dictionary:
	var result: Dictionary = {}
	for name: String in ["collection.json","collection.json.bak","prototype.cfg"]:
		var path: String = folder.path_join(name)
		if FileAccess.file_exists(path):result[path]=FileAccess.get_sha256(path)
	var pending: Array[String] = [folder.path_join("collection-backups")]
	while not pending.is_empty():
		var parent: String = pending.pop_back()
		var directory: DirAccess = DirAccess.open(parent)
		if directory==null:continue
		for file: String in directory.get_files():result[parent.path_join(file)]=FileAccess.get_sha256(parent.path_join(file))
		for child: String in directory.get_directories():pending.append(parent.path_join(child))
	return result

func visible_rgba(path: String) -> String:
	var image: Image = Image.new()
	check(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK,"Native exported PNG decodes: "+path)
	image.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = image.get_data()
	for offset: int in range(0,bytes.size(),4):
		if bytes[offset+3]==0:
			for channel: int in range(3):bytes[offset+channel]=0
	return Probe._digest(bytes)

func source_pcm(path: String) -> PackedByteArray:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var at: int = 12
	while at+8<=bytes.size():
		var size: int = bytes.decode_u32(at+4)
		if bytes.slice(at,at+4).get_string_from_ascii()=="data":return bytes.slice(at+8,at+8+size)
		at+=8+size+size%2
	return PackedByteArray()

func run() -> void:
	var qa_task: String = "003A.1"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-task="): qa_task = argument.trim_prefix("--qa-task=")
	if qa_task not in ["003A.1","003A.2"]: quit(2); return
	var profile: String = OS.get_user_data_dir();before=fingerprints(profile)
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Probe.COMBAT_ART_MANIFEST))
	var identity: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Probe.COMBAT_IDENTITY_MANIFEST))
	var sparks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Probe.COMBAT_SPARK_MANIFEST))
	var cracks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Probe.COMBAT_CRACK_MANIFEST))
	var rows: Array[Dictionary] = Probe._inspect_combat_art(art,identity,sparks,cracks)
	check(rows.size()==15,"Compiled probe covers six venue layers, three accents, four card atlases, sparks and crack")
	var found: Dictionary = {}
	for row: Dictionary in rows:
		check(not found.has(row.kind),"Imported art identity is unique: "+row.kind);found[row.kind]=true
		check(row.valid and row.visible_pixels,"Actual imported native sheet is valid: "+row.kind)
		check(row.visible_rgba_sha256==visible_rgba(row.path),"Actual imported alpha/visible RGBA agrees exactly: "+row.kind)
		check(row.native_source_available and row.native_source_sha256==FileAccess.get_sha256("res://"+str(row.source)),"Editor native source evidence is an actual file digest: "+row.kind)
	for key: String in ["cell","pivot","frame_count","columns","durations_ms","tags","layers","source"]:
		var bad: Dictionary = sparks.duplicate(true)
		match key:
			"cell","pivot":bad[key]=[1,1]
			"frame_count","columns":bad[key]=1
			"durations_ms","layers":bad[key]=[]
			"tags":bad[key]={}
			"source":bad[key]="assets/wrong.aseprite"
		var altered: Array[Dictionary] = Probe._inspect_combat_art(art,identity,bad,cracks)
		check(not altered[altered.size()-2].valid,"Contact spark native topology drift is rejected: "+key)
		bad=cracks.duplicate(true)
		# Independently corrupt the crack topology using the same explicit value.
		match key:
			"cell","pivot":bad[key]=[1,1]
			"frame_count","columns":bad[key]=1
			"durations_ms","layers":bad[key]=[]
			"tags":bad[key]={}
			"source":bad[key]="assets/wrong.aseprite"
		altered=Probe._inspect_combat_art(art,identity,sparks,bad)
		check(not altered.back().valid,"Contact crack native topology drift is rejected: "+key)
	var cue_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Probe.COMBAT_AUDIO_MANIFEST))
	for kind: String in Probe.COMBAT_AUDIO_IDS:
		var path: String = "res://assets/audio/impact_003a1/"+kind+".wav"
		var meta: Dictionary = cue_manifest.sounds[kind]
		var row: Dictionary = Probe._inspect_combat_pcm(kind,path,int(meta.frames),false,false)
		check(row.valid and row.format==AudioStreamWAV.FORMAT_16_BITS and row.channels==1 and row.mix_rate==32000,"Actual metal cue import has authored PCM format: "+kind)
		check(row.pcm_sha256==Probe._digest(source_pcm(path)) and row.pcm_sha256==meta.pcm_sha256,"Actual imported metal PCM is source-exact: "+kind)
		check(absf(float(row.duration_seconds)-float(meta.duration_seconds))<0.000001 and row.loop_mode==AudioStreamWAV.LOOP_DISABLED,"Metal cue retains authored short one-way duration: "+kind)
		check(not Probe._inspect_combat_pcm(kind,path,int(meta.frames)+1,false,false).valid,"Truncated/wrong-length metal PCM cannot pass: "+kind)
	var variation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Probe.MUSIC_VARIATION_MANIFEST))
	for kind: String in ["run_opening","run_motion"]:
		var path: String = "res://assets/audio/music/"+kind+".wav"
		var meta: Dictionary = variation.stems[kind]
		var row: Dictionary = Probe._inspect_combat_pcm(kind,path,int(meta.frames),true,false)
		check(row.valid and row.channels==2 and row.mix_rate==32000,"Actual new Run stem import shares accepted PCM grid: "+kind)
		check(row.pcm_sha256==Probe._digest(source_pcm(path)),"Actual new Run stem PCM is source-exact: "+kind)
		check(absf(float(row.duration_seconds)-float(variation.grid.seconds))<0.000001,"New Run stem retains exact synchronized duration: "+kind)
		check(not Probe._inspect_combat_pcm(kind,path,int(meta.frames),false,false).valid,"Mono substitution for stereo synchronized stem is rejected: "+kind)
	var qa_root: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa_root.is_empty():qa_root=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var folder: String = qa_root.path_join(qa_task+"/manifests");DirAccess.make_dir_recursive_absolute(folder)
	var output: String = folder.path_join("003a1_combat_actual_imports_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	var status: Dictionary = Probe.inspect(output)
	check(status.get("ok",false),"Full additive production package probe preserves all earlier asset/economy guards")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output))
	check(report.failures.is_empty() and report.read_only_asset_inspection,"Actual full asset report is read-only and complete")
	check(report.combat_art_textures.size()==15 and report.combat_audio.size()==11 and report.music_variation_stems.size()==2,"Actual report contains every new native resource once")
	check(report.music_stems.size()==5 and report.music_asset_metadata.stems.size()==7,"Original five PCM receipts remain separate from seven-stem runtime asset metadata")
	check(report.combat_arena_geometry_json==FileAccess.get_file_as_string("res://assets/arena/manifest.json"),"Compiled proof includes the canonical fixed projection/gate metadata")
	check(before==fingerprints(profile),"Actual player profile and every recovery backup remain byte-identical")
	print("COMBAT_ACCEPTANCE_PACKAGE003A1_%s checks=%d failures=%d assets=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),output])
	quit(0 if failures.is_empty() else 1)
