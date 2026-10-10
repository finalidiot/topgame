"""Matched real-physics smart-top/paid-route load on immutable before/after source."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[2]
for family in ("tools/build","tools/workspace","tools/presentation"):
    sys.path.insert(0,str(ROOT/family))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source,profile

BASELINE="68669556b253a67212e32c0cbf18d56f0df43f6f"
DRIVERS=("observe_power_routes_performance_003a1.gd","measured_power_routes_003a1.gd","measured_presentation_battle.gd")

def now():return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
def driver_hashes(project):return {name:pipeline.sha256(project/"tests"/name) for name in DRIVERS}
def import_preserving_bytes(engine,project,logs):
    originals={p:p.read_bytes() for p in (project/"assets").rglob("*.import")}
    result=pipeline.import_source([engine,"--headless","--path",str(project),"--editor","--import"],logs,900)
    normalisations={}
    for path,raw in originals.items():
        imported=path.read_bytes()
        if imported==raw:continue
        assert imported.replace(b"\r\n",b"\n")==raw.replace(b"\r\n",b"\n"),"Importer altered semantics: "+str(path)
        normalisations[path.relative_to(project).as_posix()]={"importer_sha256":pipeline.sha256(path),"difference":"CRLF/LF only; exact original metadata restored after completed import"}
        path.write_bytes(raw)
        normalisations[path.relative_to(project).as_posix()]["restored_sha256"]=pipeline.sha256(path)
    return {**result,"import_metadata_newline_normalisations":normalisations}

def prepare_baseline(args):
    """Import immutable old production while final new mechanics are validated."""
    qa=workspace.create_task_workspace("003A.1",args.qa_root)
    stem="003a1_power_routes_baseline_"+now();guard=profile()
    archive=qa/"temp"/(stem+".zip");project=qa/"temp"/(stem+"_source");project.mkdir()
    subprocess.run(["git","archive","--format=zip","--output",str(archive),BASELINE],cwd=ROOT,check=True)
    with zipfile.ZipFile(archive) as handle:
        for item in handle.infolist():
            relative=Path(item.filename)
            assert not relative.is_absolute() and ".." not in relative.parts
            target=(project/relative).resolve();assert target.is_relative_to(project.resolve())
            if relative.parts[0] not in ("scripts","assets","project.godot","main.tscn"):continue
            if item.is_dir():target.mkdir(parents=True,exist_ok=True);continue
            target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(handle.read(item))
    (project/"tests").mkdir()
    for name in DRIVERS:shutil.copy2(ROOT/"tests"/name,project/"tests"/name)
    expected=source(project);drivers=driver_hashes(project)
    imported=import_preserving_bytes(workspace.find_tool("godot",args.engine),project,qa/"logs"/stem)
    observed=source(project);assert observed==expected and driver_hashes(project)==drivers and profile()==guard
    manifest=qa/"manifests"/(stem+".json")
    record={"baseline_sha":BASELINE,"baseline_archive":str(archive),"baseline_archive_sha256":pipeline.sha256(archive),"stages":{"before":{"project":str(project),"production_hashes":observed,"driver_hashes":drivers,"import":imported}},"player_unchanged":True,"scope":"Immutable686git archive; same read-only observer. Completed isolated cold import, awaiting final after-source boundary."}
    pipeline.write_json(manifest,record);print(json.dumps({"baseline_prepared":str(manifest)},indent=2),flush=True)
    return manifest

def freeze(args):
    qa=workspace.create_task_workspace("003A.1",args.qa_root)
    stem="003a1_power_routes_frozen_"+now()
    guard=profile();current=source(ROOT);drivers=driver_hashes(ROOT)
    stages={}
    cached=json.loads(args.baseline_cache.read_text()) if args.baseline_cache else None
    if cached:
        assert cached["baseline_sha"]==BASELINE
        archive=Path(cached["baseline_archive"]);assert pipeline.sha256(archive)==cached["baseline_archive_sha256"]
    else:
        archive=qa/"temp"/(stem+"_baseline.zip")
        subprocess.run(["git","archive","--format=zip","--output",str(archive),BASELINE],cwd=ROOT,check=True)
    for label in ("before","after"):
        if label=="before" and cached:
            item=cached["stages"]["before"];project=Path(item["project"])
            assert source(project)==item["production_hashes"] and driver_hashes(project)==item["driver_hashes"]
            # Keep even preliminary observer stages immutable. A fresh clone
            # reuses imported old production, with the final identical observer.
            cloned=qa/"temp"/(stem+"_before");assert not cloned.exists();shutil.copytree(project,cloned)
            for name in DRIVERS:shutil.copy2(ROOT/"tests"/name,cloned/"tests"/name)
            assert source(cloned)==item["production_hashes"] and driver_hashes(cloned)==drivers
            stages[label]={**item,"project":str(cloned),"driver_hashes":drivers,"reused_completed_baseline_import":str(args.baseline_cache),"baseline_import_manifest_sha256":pipeline.sha256(args.baseline_cache),"final_observer_copied_into_fresh_clone":True}
            continue
        stage=qa/"temp"/(stem+"_"+label);assert not stage.exists();stage.mkdir()
        if label=="before":
            with zipfile.ZipFile(archive) as handle:
                for item in handle.infolist():
                    relative=Path(item.filename)
                    assert not relative.is_absolute() and ".." not in relative.parts
                    target=(stage/relative).resolve();assert target.is_relative_to(stage.resolve())
                    # Only production resource families, plus explicit observer.
                    if relative.parts[0] not in ("scripts","assets","project.godot","main.tscn"):continue
                    if item.is_dir():target.mkdir(parents=True,exist_ok=True);continue
                    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(handle.read(item))
        else:
            for name in ("project.godot","main.tscn"):shutil.copy2(ROOT/name,stage/name)
            for family in ("scripts","assets"):shutil.copytree(ROOT/family,stage/family)
            assert source(stage)==current,"Source changed during final after snapshot; preserve stage and retry"
        (stage/"tests").mkdir()
        for name in DRIVERS:shutil.copy2(ROOT/"tests"/name,stage/"tests"/name)
        assert driver_hashes(stage)==drivers
        stages[label]={"project":str(stage),"production_hashes":source(stage),"driver_hashes":drivers}
    assert source(ROOT)==current and profile()==guard
    manifest=qa/"manifests"/(stem+".json")
    data={"created_utc":datetime.now(timezone.utc).isoformat(),"baseline_sha":BASELINE,"working_head":pipeline.git(ROOT,"rev-parse","HEAD"),"baseline_archive":str(archive),"baseline_archive_sha256":pipeline.sha256(archive),"stages":stages,"original_production":current,"real_player_guard":guard,"scope":"Exact git archive baseline and coherent current production; same read-only observer/instrumentation. Fresh isolated cold imports; no save identity/config dimensions modified."}
    pipeline.write_json(manifest,data)
    engine=workspace.find_tool("godot",args.engine)
    for label in ("before","after"):
        if stages[label].get("reused_completed_baseline_import"):continue
        print("COLD_IMPORT "+label,flush=True)
        project=Path(stages[label]["project"])
        logs=qa/"logs"/(stem+"_"+label+"_import")
        stages[label]["import"]=import_preserving_bytes(engine,project,logs)
        imported=source(project);expected=stages[label]["production_hashes"]
        # A cold editor import may assign a UID sidecar to a newly authored
        # script. Preserve and declare that metadata; runtime bytes stay exact.
        added={key:value for key,value in imported.items() if key not in expected}
        assert all(key.startswith("scripts/") and key.endswith(".uid") for key in added)
        assert {key:imported[key] for key in expected}==expected and driver_hashes(project)==drivers
        stages[label]["before_import_production_hashes"]=expected
        stages[label]["cold_import_added_uid_metadata"]=added
        stages[label]["production_hashes"]=imported
        pipeline.write_json(manifest,data)
    assert profile()==guard
    print(json.dumps({"frozen":str(manifest),"player_unchanged":True,"before_sha":BASELINE,"after_power_sha":current["scripts/power_runtime.gd"]}),flush=True)
    return manifest

def stats(values):
    if not values:return {"samples":0}
    values=sorted(values)
    return {"samples":len(values),"median_ms":statistics.median(values),"p95_ms":values[min(len(values)-1,int((len(values)*.95)+.999999)-1)],"max_ms":max(values),"mean_ms":statistics.mean(values)}

def summary(cases):
    result={}
    for count in (4,5,6):
        selected=[case for case in cases if case["full_enemies_fixture"]==count]
        metrics={key:stats([v for case in selected for v in case["samples_ms"][key]]) for key in selected[0]["samples_ms"]}
        peaks={key:max(case["peaks"].get(key,0) for case in selected) for key in {key for case in selected for key in case["peaks"]}}
        result[str(count)]={"cases":len(selected),"measurements":metrics,"peaks":peaks,"physics_frames":sum(case["physics_frames"] for case in selected),"simulation_advancing_frames":sum(case["simulation_advancing_frames"] for case in selected),"real_impact_hold_frames":sum(case["real_impact_hold_frames"] for case in selected),"requested_density_frames":sum(case["full_density_frames"] for case in selected),"multiple_owner_routes_frames":sum(case["multiple_owner_route_frames"] for case in selected),"joint_density_routes_frames":sum(case["full_density_with_multiple_routes_frames"] for case in selected),"current_npc_advice_frames":sum(case["current_npc_advice_frames"] for case in selected),"safe_position_advice_opportunity_frames":sum(case["safe_position_advice_opportunity_frames"] for case in selected),"clocks_synchronized":all(case["clocks_synchronized"] for case in selected),"max_index_builds_per_tick":max(case["max_index_builds_per_tick"] for case in selected),"max_owner_searches_per_tick":max(case["max_owner_searches_per_tick"] for case in selected)}
    return result

def measure(args,manifest):
    qa=workspace.create_task_workspace("003A.1",args.qa_root)
    boundary=json.loads(manifest.read_text(encoding="utf-8"));guard=profile()
    suffix="_"+args.revision if args.revision else ""
    rendered=args.mode=="native";stem="003a1_power_routes_"+args.mode+suffix+"_"+now()
    engine=workspace.find_tool("godot",args.engine);results={}
    # Serial engine measurements avoid mutual contention. Other host activity
    # remains possible and is disclosed; wall times are not Android claims.
    for label in ("before","after"):
        item=boundary["stages"][label];project=Path(item["project"])
        assert source(project)==item["production_hashes"] and driver_hashes(project)==item["driver_hashes"]
        report=qa/"benchmarks"/(stem+"_"+label+".json")
        command=[engine,"--path",str(project),"--script","res://tests/"+DRIVERS[0]]
        command += ["--resolution","640x360","--disable-vsync","--audio-driver","Dummy"] if rendered else ["--headless"]
        command += ["--","--report="+str(report),"--label="+label,"--ticks="+str(args.ticks)]
        if rendered:command.append("--rendered")
        print("MEASURE "+args.mode+" "+label,flush=True)
        process=pipeline.run_logged(command,qa/"logs"/(stem+"_"+label+".log"),900)
        data=json.loads(report.read_text(encoding="utf-8"))
        assert not data["failures"] and len(data["cases"])==9
        assert data["seeds"]==[421,7341,2026] and data["rendered"]==rendered
        assert not data["main_created"] and not data["collection_opened"]
        for case in data["cases"]:
            assert case["full_density_frames"]>=120 and case["multiple_owner_route_frames"]>=30
            assert case["clocks_synchronized"]
            assert case["peaks"]["live_routes"]<=72 and case["peaks"]["circuit_points_peak"]<=224
            if rendered:assert case["frame_wall_ms"]["samples"]>0 and case["draw_submission_ms"]["samples"]>0
        assert source(project)==item["production_hashes"] and driver_hashes(project)==item["driver_hashes"]
        results[label]={"report":str(report),"sha256":pipeline.sha256(report),"process":process,"data":data}
    assert profile()==guard
    for before,after in zip(results["before"]["data"]["cases"],results["after"]["data"]["cases"]):
        assert (before["seed"],before["full_enemies_fixture"],before["initial_clock_fixture"],before["initial"])==(after["seed"],after["full_enemies_fixture"],after["initial_clock_fixture"],after["initial"]),"Matched initial physics/ownership changed"
    replay=None
    if rendered:
        simulation=qa/"benchmarks"/("003a1_power_routes_simulation_performance"+suffix+".json")
        if simulation.is_file():
            previous=json.loads(simulation.read_text())
            assert previous["boundary_sha256"]==pipeline.sha256(manifest)
            for label in ("before","after"):
                path=Path(previous["observations"][label]["report"])
                assert pipeline.sha256(path)==previous["observations"][label]["sha256"]
                old=json.loads(path.read_text())
                for old_case,new_case in zip(old["cases"],results[label]["data"]["cases"]):
                    for key in ("seed","full_enemies_fixture","initial","physics_frames","simulation_advancing_frames","real_impact_hold_frames","full_density_frames","multiple_owner_route_frames","current_npc_advice_frames","safe_position_advice_opportunity_frames","final_powers","final","battle_status"):
                        assert old_case[key]==new_case[key],"Native/headless physical replay differs: "+label+"/"+key
                    fields=("tick","elapsed","control","player_rpm","hits","powers")
                    assert [[row[key] for key in fields] for row in old_case["trace"]]==[[row[key] for key in fields] for row in new_case["trace"]],"Native/headless sampled controls differ"
            replay={"simulation_report":str(simulation),"sha256":pipeline.sha256(simulation),"cases":18,"physics_controls_positions_velocities_RPM_outcomes_and_power_events_exact":True}
    output=qa/"benchmarks"/("003a1_power_routes_"+args.mode+"_performance"+suffix+".json")
    canonical=qa/"manifests"/output.name
    assert not output.exists() and not canonical.exists(),"Preserve earlier performance evidence"
    record={"created_utc":datetime.now(timezone.utc).isoformat(),"mode":args.mode,"frozen_boundary":str(manifest),"boundary_sha256":pipeline.sha256(manifest),"baseline_sha":BASELINE,"frozen_sources":boundary["stages"],"driver_hashes":boundary["stages"]["after"]["driver_hashes"],"scope":results["after"]["data"]["scope"],"host_activity_note":"Before/after engine runs serialized. Other host processes may run; no physical Android performance or natural deep survival claim. Native wall frame includes harness/monitor sampling; CPU submission excludes asynchronous GPU. Stats are measured, not a promised FPS.","player_and_backups_unchanged":True,"source_snapshots_unchanged":True,"summary":{label:summary(item["data"]["cases"]) for label,item in results.items()},"observations":{label:{key:value for key,value in item.items() if key!="data"} for label,item in results.items()},"matched_initial_conditions":True,"no_production_edits":True}
    record["native_vs_simulation_physics_replay"]=replay
    pipeline.write_json(output,record);pipeline.write_json(canonical,record)
    print(json.dumps({"passed":True,"report":str(output),"sha256":pipeline.sha256(output),"mode":args.mode,"summary":record["summary"]},indent=2),flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--freeze",action="store_true")
    parser.add_argument("--prepare-baseline",action="store_true")
    parser.add_argument("--baseline-cache",type=Path)
    parser.add_argument("--stages",type=Path)
    parser.add_argument("--mode",choices=("simulation","native"))
    parser.add_argument("--ticks",type=int,default=720)
    parser.add_argument("--revision",default="",help="New named source/fixture boundary; preserves earlier reports")
    parser.add_argument("--engine");parser.add_argument("--qa-root",type=Path)
    args=parser.parse_args()
    assert not args.revision or all(c.isalnum() or c=="_" for c in args.revision)
    assert 180<=args.ticks<=1800
    if args.prepare_baseline:prepare_baseline(args);return
    assert args.freeze or args.stages
    manifest=freeze(args) if args.freeze else args.stages.resolve()
    if args.mode:measure(args,manifest)

if __name__=="__main__":main()
