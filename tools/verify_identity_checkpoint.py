"""Retained gameplay/collection checks and independent source-integrity evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
BASE='d882923c0e2114f6d8b86aa2079dc7365bb4f71a'

def source_evidence(out):
    paths=['scripts/roster_runtime.gd','scripts/spin_economy.gd',
           'scripts/run_context.gd','scripts/continuous_run.gd','scripts/threat_director.gd',
           'scripts/collection_save.gd','scripts/starters.gd','scripts/parts.gd']
    paths += [str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'assets/source-art').glob('*.aseprite')]
    records=[]
    for path in paths:
        current=ROOT/path
        if not current.exists(): continue
        old=subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
        sha=lambda data:hashlib.sha256(data).hexdigest()
        working=current.read_bytes()
        # Git's Windows checkout converts text to CRLF; compare canonical text.
        if path.endswith('.gd'): working=working.replace(b'\r\n',b'\n')
        assert sha(old)==sha(working),path
        records.append({'path':path,'canonical_sha256':sha(old),'unchanged':True})
    fx_diff=subprocess.check_output(['git','diff',BASE,'--','scripts/power_runtime.gd'],cwd=ROOT,text=True)
    (out/'source-retention.json').write_text(json.dumps({'baseline':BASE,'scope':'Canonical unchanged gameplay, persistent collection and historical native masters. PowerRuntime exception passes exact Chain recipient provenance through FX only; its physical requests, records and ordering remain unchanged. Battle diff is presentation payload/draw only.','files':records,'power_runtime_presentation_diff':fx_diff},indent=2))

def regressions(out,engine):
    retained=json.loads((ROOT/'tests/task002c5-integration-regression-results.json').read_text())
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
        (out/'regression-results.json').write_text(json.dumps({'baseline':BASE,'engine':engine,'suites':records,'passed_suites':sum(r['passed'] for r in records),'failed_suites':sum(not r['passed'] for r in records),'counted_checks':sum(r['checks'] for r in records)},indent=2))
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
    p.add_argument('--engine',default='E:/Desktop/Godot_v4.7.2-stable_win64_console.exe')
    p.add_argument('--source-only',action='store_true')
    p.add_argument('--summarize-existing',action='store_true');args=p.parse_args()
    # Summarising existing logs is separate from running tests; never fabricate runs.
    args.out.mkdir(parents=True,exist_ok=True);source_evidence(args.out)
    if args.summarize_existing: summarize_existing(args.out)
    elif not args.source_only: regressions(args.out,args.engine)

if __name__=='__main__':main()
