"""Sparse C.4 mechanical punctuation; no loops or replacement soundtrack."""
import json
from build_escalation_audio import render,OUT
CUES={
 'boss_port':(.65,[(0,.4,90,48,.7,.4,4,2.73),(.18,.4,220,140,.5,.2,4,3.1)]),
 'boss_payoff':(.72,[(0,.45,105,32,.75,.65,6,2.71),(.13,.5,360,550,.35,.1,4,1.5)]),
 'rpm_reclaim':(.23,[(0,.20,390,780,.32,.1,3,1.5),(.06,.17,780,1170,.22,.03,4,2)]),
 'low_rpm':(.23,[(0,.09,140,100,.2,.14,6,2.7),(.13,.1,105,72,.2,.13,6,3.1)]),
 'breakneck_recovery':(.32,[(0,.25,290,48,.4,.6,5,2.7),(.10,.22,90,36,.3,.3,6,3.1)])}
if __name__=='__main__':
 data={k:render(k,*v) for k,v in CUES.items()}
 (OUT/'signature_manifest.json').write_text(json.dumps(data,indent=2)+'\n')
