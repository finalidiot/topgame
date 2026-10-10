"""Verify protected player bytes, accepted music and prior QA without restoration."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT / "tools/build"))
import windows_checkpoint as pipeline

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start",type=Path,required=True)
    parser.add_argument("--phase",choices=("before-build","after-build"),required=True)
    args = parser.parse_args()
    start = json.loads(args.start.read_text())
    qa = ROOT.parent / "GyroBrothers-QA/003A.1"
    output = qa / "manifests" / ("003a1_enemy_foundation_preservation_" + args.phase.replace("-","_") + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f") + ".json")
    def changes(records,base):
        result = {}
        for name, item in records.items():
            old = item["sha256"] if isinstance(item,dict) else item
            path = base / name
            current = pipeline.sha256(path) if path.is_file() else None
            if old != current: result[name] = {"before":old,"current":current}
        return result
    protected = {name:record for name,record in start["player_profile"].items()
                 if name in ("collection.json","collection.json.bak","prototype.cfg") or name.startswith("collection-backups/")}
    profile_changes = changes(protected,Path(start["profile_root"]))
    music = {name:record for name,record in start["assets"].items() if name.startswith("assets/audio/music") or "music" in name and name.endswith(".aseprite")}
    music_changes = changes(music,ROOT)
    compact_changes = changes(start["compact_evidence"],ROOT)
    historical_changes = changes(start["prior_qa"],qa)
    build_changes = changes(start["builds"],ROOT)
    passed = not (profile_changes or music_changes or compact_changes or historical_changes) and (args.phase == "after-build" or not build_changes)
    record = {"schema":1,"status":"passed" if passed else "failed","phase":args.phase,"starting_sha":start["source_sha"],
              "current_head":pipeline.git(ROOT,"rev-parse","HEAD"),"protected_player_files":len(protected),"protected_player_changes":profile_changes,
              "accepted_music_files":len(music),"accepted_music_changes":music_changes,"prior_compact_files":len(start["compact_evidence"]),"prior_compact_changes":compact_changes,
              "historical_qa_files":len(start["prior_qa"]),"historical_qa_changes":historical_changes,"historical_build_changes":build_changes,
              "build_policy":"Before-build requires good builds unchanged. After-build permits only externally validated guarded promotion; delivery manifests must establish this separately.",
              "player_policy":"Engine logs and isolated test fixtures are excluded. Primary collection, backup, preferences and all recovery backup files remain protected. Never restore over newer human data."}
    pipeline.write_json(output,record)
    print(json.dumps({"report":str(output),"status":record["status"],"protected_player_files":len(protected),"music_files":len(music),"changes":{k:v for k,v in record.items() if k.endswith("changes")}},indent=2))
    raise SystemExit(0 if passed else 1)

if __name__ == "__main__": main()
