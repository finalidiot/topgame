"""Matched actual-physics enemy role/build studies on immutable source copies."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT / "tools/workspace"))
sys.path.insert(0,str(ROOT / "tools/build"))
import workspace
import windows_checkpoint as pipeline
DRIVER="observe_enemy_intelligence_003a1.gd"
METRICS=["attack_attempts","meaningful_hits","failed_commits","burst_usage","brake_ticks","brake_seconds","self_ring_outs","player_ring_outs",
         "edge_exposure_seconds","common_useful_ground_seconds","contact_severity_sum","contact_severity_peak","rpm_damage_caused",
         "power_rpm_damage_to_player","survival_time","recovery_seconds","stuck_state_count","distance_travelled","max_observed_speed"]

def hashes(root: Path) -> dict:
    paths=list((root / "scripts").glob("*.gd"))+[p for p in (root / "assets").rglob("*") if p.is_file()]
    return {p.relative_to(root).as_posix():pipeline.sha256(p) for p in sorted(paths)}

def player() -> dict:
    data=pipeline.production_profile(ROOT)
    directory=Path(data["directory"]) if data.get("directory") else None
    data["backups"]={str(p.relative_to(directory)):pipeline.sha256(p) for p in sorted((directory / "collection-backups").rglob("*")) if p.is_file()} if directory else {}
    return data

def summarize(rows: list[dict],field: str) -> dict:
    out={}
    for identity in dict.fromkeys(r[field] for r in rows):
        group=[r for r in rows if r[field]==identity]
        totals={m:sum(float(r[m]) for r in group) for m in METRICS}
        elapsed=totals["survival_time"]
        events={}
        for r in group:
            for kind,count in r["power_activation"].items():events[kind]=events.get(kind,0)+count
        available=[r for r in group if r["intended_position_available"]]
        out[identity]={"cases":len(group),"totals":totals,"means":{m:v/len(group) for m,v in totals.items()},
                       "power_activation":events,"hits_per_live_minute":totals["meaningful_hits"]*60/max(.001,elapsed),
                       "contact_rpm_damage_per_live_minute":totals["rpm_damage_caused"]*60/max(.001,elapsed),
                       "brake_live_fraction":totals["brake_seconds"]/max(.001,elapsed),
                       "edge_live_fraction":totals["edge_exposure_seconds"]/max(.001,elapsed),
                       "useful_ground_fraction":totals["common_useful_ground_seconds"]/max(.001,elapsed),
                       "survival_censored_cases":sum(r["survival_censored"] for r in group),
                       "intended_position_available_cases":len(available),
                       "intended_position_occupancy_seconds":sum(r["intended_position_occupancy_seconds"] for r in available) if available else None}
    return out

def validate(data: dict,label: str,seconds: float) -> None:
    assert data["label"]==label and data["case_count"]==48 and len(data["rows"])==48
    assert data["seconds_per_case"]==seconds
    assert data["supports_state_pilot"]==(label=="after") and data["supports_enemy_packages"]==(label=="after")
    for r in data["rows"]:
        assert r["initial"]["player"]["rpm"]==r["initial"]["enemy"]["rpm"]==1
        assert r["initial"]["player"]["pos"]==[-36,16] and r["initial"]["enemy"]["pos"]==[82,-12]
        assert r["physics_ticks"]<=int(seconds*60) and 0<r["survival_time"]<=seconds+.0001
        assert all(r[m]>=0 for m in METRICS)
        assert r["max_observed_speed"]<=520.01
        assert r["initial"]["player"]["powers"]==[]
        if label=="after":assert r["final_pilot"]["state"] in ["assess","position","setup","commit","follow_through","recover","defend","retreat"]

def main() -> None:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--baseline",required=True,type=Path)
    p.add_argument("--qa-root",type=Path)
    p.add_argument("--engine")
    p.add_argument("--seconds",type=float,default=45)
    p.add_argument("--revision",default="",help="New named evidence boundary; preserves canonical first study files")
    p.add_argument("--pilot-sha",default="482b156563731f102df9f9ebefa52bd4dc257c0f29e791a14458ecb2cef947fe")
    args=p.parse_args()
    assert 10<=args.seconds<=120
    qa=workspace.create_task_workspace("003A.1",args.qa_root)
    assert not args.revision or all(c.isalnum() or c=="_" for c in args.revision)
    identity="003a1_enemy_intelligence_matched_"+(args.revision+"_" if args.revision else "")+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    before_player=player()
    current=hashes(ROOT)
    before=hashes(args.baseline)
    assert pipeline.sha256(ROOT / "scripts/enemy_roles.gd")==args.pilot_sha, "Pilot freeze changed; declare a new source boundary"
    driver_sha=pipeline.sha256(ROOT / "tests" / DRIVER)
    stages={}
    for label in ("before","after"):
        source=qa / "temp" / (identity+"_"+label+"_source")
        assert not source.exists()
        shutil.copytree(args.baseline,source)
        if label=="after":
            for family in ("scripts","assets",".godot"):
                shutil.copytree(ROOT / family,source / family,dirs_exist_ok=True)
            shutil.copy2(ROOT / "project.godot",source / "project.godot")
        shutil.copy2(ROOT / "tests" / DRIVER,source / "tests" / DRIVER)
        expected=before if label=="before" else current
        assert hashes(source)==expected
        assert pipeline.sha256(source / "tests" / DRIVER)==driver_sha
        stages[label]={"source":source,"source_sha256":expected,"report":qa / "manifests" / (identity+"_"+label+".json"),
                       "log":qa / "logs" / (identity+"_"+label+".log")}
    assert hashes(ROOT)==current,"Production changed while freezing after source"
    engine=workspace.find_tool("godot",args.engine)
    def run(label: str) -> tuple[str,dict]:
        stage=stages[label]
        command=[engine,"--headless","--path",str(stage["source"]),"--script","res://tests/"+DRIVER,"--",
                 "--report="+str(stage["report"]),"--label="+label,"--seconds="+str(args.seconds)]
        process=pipeline.run_logged(command,stage["log"],1800)
        data=json.loads(stage["report"].read_text(encoding="utf-8"));validate(data,label,args.seconds)
        assert hashes(stage["source"])==stage["source_sha256"]
        return label,{"data":data,"process":process,"report":str(stage["report"]),"report_sha256":pipeline.sha256(stage["report"]),
                      "source":str(stage["source"]),"source_sha256":stage["source_sha256"]}
    with ThreadPoolExecutor(max_workers=2) as pool:results=dict(pool.map(run,("before","after")))
    assert player()==before_player,"Study altered real player data"
    for group,field,name in (("roles","role","003a1_enemy_intelligence_comparison.json"),("builds","build_id","003a1_enemy_build_behaviour.json")):
        if args.revision:name=Path(name).stem+"_"+args.revision+".json"
        common={"task":"003A.1 enemy intelligence foundation","group":group,"created_utc":datetime.now(timezone.utc).isoformat(),
                "accepted_baseline_sha":"2c06290591371035b5b1c68a0f5b0c565523d80b","current_base_git_sha":pipeline.git(ROOT,"rev-parse","HEAD"),
                "captured_working_tree":pipeline.git(ROOT,"status","--porcelain"),"driver":"tests/"+DRIVER,"driver_sha256":driver_sha,
                "same_driver_both_versions":True,"requested_seconds_per_case":args.seconds,"target_build":results["after"]["data"]["target_build"],
                "seeds":results["after"]["data"]["seeds"],"start_times":results["after"]["data"]["start_times"],
                "scope":results["after"]["data"]["scope"],"metric_definitions":results["after"]["data"]["metrics"],
                "material_comparison_boundary":"Before is exact accepted production AI/legacy NPC power eligibility/legacy NPC running arithmetic. After is frozen observed-state AI plus declared authored packages and player-equivalent Run costs/independent bounded power recovery. No HP/stat/force multiplier added by pilot. Composite production comparison; do not attribute every difference to AI policy alone.",
                "seed_boundary":"Matched seeded replay labels. No claim of independent random samples; deterministic full-top states can replay identically across seeds when only cosmetic streams differ.",
                "player_data_unchanged":True,"human_acceptance":"Pending; automated fixture studies and metrics do not substitute for hands-on feel or actual device testing."}
        for label in ("before","after"):
            result=results[label];rows=[r for r in result["data"]["rows"] if r["group"]==group]
            common[label]={"summary":summarize(rows,field),"rows":rows,"raw_manifest":result["report"],"raw_manifest_sha256":result["report_sha256"],
                           "process":result["process"],"frozen_source":result["source"],"source_sha256":result["source_sha256"]}
        paths=[qa / name,qa / "manifests" / name]
        assert all(not path.exists() for path in paths),"Preserve existing studies"
        text=json.dumps(common,indent=2)+"\n"
        for path in paths:path.write_text(text,encoding="utf-8")
        assert paths[0].read_bytes()==paths[1].read_bytes()
        print(json.dumps({"passed":True,"study":str(paths[0]),"sha256":pipeline.sha256(paths[0]),"before_cases":len(common["before"]["rows"]),"after_cases":len(common["after"]["rows"])},indent=2))

if __name__=="__main__":main()
