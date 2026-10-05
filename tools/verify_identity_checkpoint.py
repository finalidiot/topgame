"""Retained gameplay/collection checks and independent source-integrity evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/workspace'))
from workspace import find_tool
BASE='d882923c0e2114f6d8b86aa2079dc7365bb4f71a'

def source_evidence(out, baseline=BASE):
    baseline=subprocess.check_output(['git','rev-parse','--verify',baseline+'^{commit}'],cwd=ROOT,text=True).strip()
    strict_v2=baseline!=BASE
    paths=['scripts/roster_runtime.gd','scripts/spin_economy.gd',
           'scripts/run_context.gd','scripts/continuous_run.gd','scripts/threat_director.gd',
           'scripts/collection_save.gd','scripts/starters.gd','scripts/parts.gd']
    if strict_v2:
        # V2 is entirely artwork/presentation. Every other production script,
        # including Battle, PowerRuntime, catalogue and persistent menus, must
        # remain canonical byte-identical to the requested checkpoint.
        presentation={'power_identity.gd','power_visuals.gd','main.gd'}
        paths=[str(p.relative_to(ROOT)).replace('\\','/') for p in sorted((ROOT/'scripts').glob('*.gd')) if p.name not in presentation]
    paths += [str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'assets/source-art').glob('*.aseprite')]
    if strict_v2:
        # Preserve the accepted physical top pixels used by the corrected art.
        paths += [str(p.relative_to(ROOT)).replace('\\','/') for p in sorted((ROOT/'assets/top').rglob('*')) if p.is_file() and p.suffix in {'.png','.json'}]
    records=[]
    for path in paths:
        current=ROOT/path
        if not current.exists(): continue
        old=subprocess.check_output(['git','show',baseline+':'+path],cwd=ROOT)
        sha=lambda data:hashlib.sha256(data).hexdigest()
        working=current.read_bytes()
        # Git's Windows checkout converts text to CRLF; compare canonical text.
        if path.endswith(('.gd','.json')): old=old.replace(b'\r\n',b'\n'); working=working.replace(b'\r\n',b'\n')
        assert sha(old)==sha(working),path
        records.append({'path':path,'canonical_sha256':sha(old),'unchanged':True})
    fx_diff=subprocess.check_output(['git','diff',baseline,'--','scripts/power_runtime.gd'],cwd=ROOT,text=True)
    report={'baseline':baseline,'files':records,'power_runtime_presentation_diff':fx_diff}
    if strict_v2:
        assert not fx_diff, 'V2 must not change PowerRuntime, including its existing FX provenance'
        old=subprocess.check_output(['git','show',baseline+':scripts/main.gd'],cwd=ROOT).replace(b'\r\n',b'\n')
        current=(ROOT/'scripts/main.gd').read_bytes().replace(b'\r\n',b'\n')
        # The one explicit UI-version label is the only Main exemption.
        title=re.compile(rb'^\tDisplayServer\.window_set_title\([^\n]*\)\n',re.M)
        assert len(title.findall(old))==len(title.findall(current))==1
        assert title.sub(b'',old)==title.sub(b'',current), 'Main may change only its window version label'
        report['main_version_label_only']={'path':'scripts/main.gd','canonical_sha256_excluding_window_title':hashlib.sha256(title.sub(b'',old)).hexdigest(),'gameplay_unchanged':True,'only_exempt_change':'DisplayServer.window_set_title version label','baseline_window_title':title.findall(old)[0].decode().strip(),'current_window_title':title.findall(current)[0].decode().strip()}
        report.update(scope='V2: all production gameplay scripts, Battle, PowerRuntime, persistent collection/menu flow, historical native masters and accepted top textures are canonical unchanged. Main changes only its explicit window version label. PowerIdentity/PowerVisuals presentation diffs are retained separately and exercised by draw-isolation regressions. No PowerRuntime exception.',power_runtime_unchanged=True,presentation_diffs={path:subprocess.check_output(['git','diff',baseline,'--',path],cwd=ROOT,text=True) for path in ['scripts/power_identity.gd','scripts/power_visuals.gd']})
    else:
        report.update(scope='Canonical unchanged gameplay, persistent collection and historical native masters. PowerRuntime exception passes exact Chain recipient provenance through FX only; its physical requests, records and ordering remain unchanged. Battle diff is presentation payload/draw only.')
    report['canonical_unchanged_file_count']=len(records)
    (out/'source-retention.json').write_text(json.dumps(report,indent=2))

def regressions(out,engine,baseline=BASE):
    retained=json.loads((ROOT/'tests/results/task002c5-integration-regression-results.json').read_text())
    suites=[s['suite'] for s in retained['suites']]+['power_identity']
    records=[]
    for suite in suites:
        began=time.monotonic(); log=out/(suite+'.log')
        with log.open('wb') as handle:
            result=subprocess.run([engine,'--headless','--path',str(ROOT),'--script','res://tests/test_'+suite+'.gd'],stdout=handle,stderr=subprocess.STDOUT,timeout=240)
        text=log.read_text(errors='replace')
        errors=bool(re.search(r'SCRIPT ERROR|ERROR:|FAIL:|failures=[1-9]|\b[1-9]\d*\s+failures\b(?![=:])',text))
        markers=[line for line in text.splitlines() if re.search(r'pass|checks=|0 failures',line,re.I)]
        checks=re.findall(r'checks=(\d+)',text)
        if not checks: checks=re.findall(r'(\d+)\s+(?:checks|assertions|passed)',text,re.I)
        row={'suite':suite,'passed':result.returncode==0 and not errors and bool(markers),
             'exit_code':result.returncode,'seconds':round(time.monotonic()-began,3),
             'checks':max(map(int,checks),default=0),'summary':markers[-1] if markers else '', 'log':str(log)}
        records.append(row); print(json.dumps(row),flush=True)
        (out/'regression-results.json').write_text(json.dumps({'baseline':baseline,'engine':engine,'suites':records,'passed_suites':sum(r['passed'] for r in records),'failed_suites':sum(not r['passed'] for r in records),'counted_checks':sum(r['checks'] for r in records)},indent=2))
    assert all(r['passed'] for r in records),'See regression logs'

def summarize_existing(out):
    path=out/'regression-results.json'; report=json.loads(path.read_text())
    for row in report['suites']:
        text=Path(row['log']).read_text(errors='replace')
        errors=bool(re.search(r'SCRIPT ERROR|ERROR:|FAIL:|failures=[1-9]|\b[1-9]\d*\s+failures\b(?![=:])',text))
        markers=[line for line in text.splitlines() if re.search(r'pass|checks=|0 failures',line,re.I)]
        checks=re.findall(r'checks=(\d+)',text) or re.findall(r'(\d+)\s+(?:checks|assertions|passed)',text,re.I)
        row.update(passed=row['exit_code']==0 and not errors and bool(markers),
                   checks=max(map(int,checks),default=0),summary=markers[-1][:800] if markers else '')
    report.update(passed_suites=sum(r['passed'] for r in report['suites']),
                  failed_suites=sum(not r['passed'] for r in report['suites']),
                  counted_checks=sum(r['checks'] for r in report['suites']))
    path.write_text(json.dumps(report,indent=2));print(json.dumps({k:report[k] for k in ['passed_suites','failed_suites','counted_checks']}))
    assert report['failed_suites']==0

def main():
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True)
    p.add_argument('--engine',help='Override TOPGAME_GODOT / PATH / shared local engine discovery')
    p.add_argument('--baseline',default=BASE,help='Git checkpoint for source-integrity proof; default preserves original art-addendum baseline')
    p.add_argument('--source-only',action='store_true')
    p.add_argument('--summarize-existing',action='store_true');args=p.parse_args()
    # Summarising existing logs is separate from running tests; never fabricate runs.
    args.out.mkdir(parents=True,exist_ok=True);source_evidence(args.out,args.baseline)
    if args.summarize_existing: summarize_existing(args.out)
    elif not args.source_only: regressions(args.out,find_tool('godot',args.engine),args.baseline)

if __name__=='__main__':main()
