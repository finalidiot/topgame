"""Instrument canonical contact gains without touching the paired curve driver."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/presentation"))
import upgrade_sustain_003a1 as study
pipeline, workspace = study.pipeline, study.workspace

INSTRUMENTATION = '''class ContactEconomy extends "res://scripts/spin_economy.gd":
	var contact_readings: Array[Dictionary] = []
	var last_collision_loss: float = 0.0
	func spend(fighter: Dictionary, amount: float, source: String) -> void:
		var before: float = float(fighter.rpm)
		var watched: bool = player(fighter)
		super.spend(fighter, amount, source)
		if watched and source == "collisions": last_collision_loss = before - float(fighter.rpm)
	func contact(target: Dictionary, severity: float, damage: float, approach_speed: float, moving_speed: float = -1.0) -> void:
		var before: float = float(gains.combat_reclamation)
		var p: Dictionary = host().player_entity()
		var steering: float = control
		super.contact(target, severity, damage, approach_speed, moving_speed)
		contact_readings.append({"time":host().elapsed,"target":target.entity_id,"severity":severity,"inflicted_rpm_loss":damage,"player_received_rpm_loss":last_collision_loss,"approach_normal_speed":approach_speed,"player_moving_speed":moving_speed,"steering":steering,"actual_generic_reclaim":float(gains.combat_reclamation)-before,"player_wobble":p.wobble,"anchor_stress":p.get("anchor_stress",0.0),"rank_dead_centre":host().powers.rank(p,"dead_centre")})

'''

def generated_driver(original: str) -> str:
    result = original.replace('const Battle = preload(', INSTRUMENTATION + 'const Battle = preload(',1)
    needle = '\tbattle.continuous.progression_level = maxi(1, investments)\n'
    assert result.count(needle) == 1
    result = result.replace(needle,needle+'\tvar audit: ContactEconomy = ContactEconomy.new()\n\taudit.setup(battle)\n\tbattle.continuous.economy = audit\n')
    result = result.replace('\tassert(row.initial_ranks == row.final_ranks,', '\trow.contact_readings = audit.contact_readings\n\tassert(row.initial_ranks == row.final_ranks,')
    result = result.replace('const INVESTMENTS: Array[int] = [0,3,6,12]', 'const INVESTMENTS: Array[int] = [0,3,12]')
    skipped = '\t\tfor seed_value: int in seeds:\n\t\t\truns.append(observe(style, 12, seed_value, true))\n\t\t\twrite_report(output + ".partial")\n'
    assert skipped in result
    return result.replace(skipped, '')

def analyse(data: dict) -> dict:
    result = {}
    for run in data["runs"]:
        contacts = run["contact_readings"]
        paid = [c for c in contacts if c["actual_generic_reclaim"] > 0]
        low = [c for c in paid if c["approach_normal_speed"] < 25]
        away = [c for c in paid if c["approach_normal_speed"] < 0]
        committed = [c for c in paid if c["approach_normal_speed"] >= 65]
        total = sum(c["actual_generic_reclaim"] for c in paid)
        result[f'{run["style"]}_{run["investments"]}_{run["seed"]}'] = {
            "contacts":len(contacts),"paid_contacts":len(paid),"total_generic_reclaim":total,"low_approach_paid_contacts":len(low),"low_approach_reclaim":sum(c["actual_generic_reclaim"] for c in low),
            "moving_away_paid_contacts":len(away),"moving_away_reclaim":sum(c["actual_generic_reclaim"] for c in away),"committed_paid_contacts":len(committed),"committed_reclaim":sum(c["actual_generic_reclaim"] for c in committed),
            "paid_contact_incoming_rpm_loss":sum(c["player_received_rpm_loss"] for c in paid),"paid_contact_inflicted_rpm_loss":sum(c["inflicted_rpm_loss"] for c in paid),
            "total_loss":run["total_loss"],"total_gain":run["total_gain"],"survival_seconds":run["survival_seconds"],"final_rpm":run["final_rpm"],"reason":run["reason"]}
        assert abs(total-run["gain_by_source"]["combat_reclamation"]) < 1e-8
    return result

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project",type=Path,required=True)
    parser.add_argument("--case",choices=("defensive","aggressive","mixed"),required=True)
    parser.add_argument("--engine")
    parser.add_argument("--horizon",type=float,default=120)
    args = parser.parse_args()
    qa = workspace.create_task_workspace("003A.1")
    name = "003a1_contact_reclaim_audit_"+args.case+"_"+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    generated = qa / "temp" / (name+".gd")
    report = qa / "manifests" / (name+".json")
    original = study.DRIVER.read_bytes()
    generated.write_text(generated_driver(original.decode("utf-8")),encoding="utf-8")
    before, player = study.source(args.project), study.player()
    process = pipeline.run_logged([workspace.find_tool("godot",args.engine),"--headless","--path",str(args.project),"--script",str(generated),"--","--report="+str(report),"--case="+args.case,"--horizon="+str(args.horizon)],qa/"logs"/(name+".log"),1800)
    assert before == study.source(args.project) and player == study.player() and original == study.DRIVER.read_bytes()
    data = json.loads(report.read_text(encoding="utf-8"))
    assert len(data["runs"]) == 9 and all(r["ledger_closure_error"]<1e-6 for r in data["runs"])
    data.update(analysis=analyse(data),observer_template_sha256=pipeline.sha256(study.DRIVER),instrumented_observer=str(generated),instrumented_observer_sha256=pipeline.sha256(generated),
                source_before=before,source_after=study.source(args.project),source_unchanged=True,player_before=player,player_unchanged=True,process=process,
                instrumentation_boundary="Only canonical Economy.spend/contact delegating overrides record real incoming/inflicted loss and actual accepted generic reclaim. No amount/qualification/cooldown/control/physics changes. Paired curve observer remains unchanged.")
    report.write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"passed":True,"report":str(report),"analysis":data["analysis"]},indent=2),flush=True)

if __name__ == "__main__": main()
