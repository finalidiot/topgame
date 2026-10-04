"""Original finite mechanical event punctuation for002C.5; no music or loops."""
import json
from build_escalation_audio import render, OUT
CUES = {
    'redline_overcap': (.31, [(0,.26,220,1190,.43,.35,2.1,2.71),(.12,.19,760,1410,.23,.1,3,2.03)]),
    'redline_heat': (.27, [(0,.09,690,430,.27,.3,5,3.13),(.13,.12,760,510,.27,.25,5,2.71)]),
    'clutch_activate': (.30, [(0,.13,170,100,.32,.42,5,2.71),(.12,.18,340,250,.31,.2,5,1.51)]),
    'clutch_recover': (.34, [(0,.1,120,90,.35,.45,7,2.71),(.07,.27,390,890,.32,.07,3,1.51)]),
    'high_gear_surge': (.24, [(0,.24,320,1550,.35,.25,2.6,1.51)]),
    'ghost_preview': (.12, [(0,.08,1120,1080,.13,.03,6,2.01)]),
    'ghost_latch': (.40, [(0,.09,140,76,.46,.52,6,2.73),(.05,.28,620,880,.38,.07,3,1.51),(.13,.27,1240,1760,.23,.02,3,2.01)]),
    'iron_comet_charge': (.28, [(0,.23,160,620,.40,.40,2.1,2.71),(.1,.18,420,930,.2,.07,3,2.03)]),
    'iron_comet_release': (.37, [(0,.31,98,42,.65,.72,8,2.73),(.02,.29,780,320,.3,.30,6,3.13)]),
    'momentum_release': (.24, [(0,.22,210,710,.38,.35,3,2.71)]),
    'crash_guard': (.20, [(0,.19,140,76,.42,.42,6,2.73)]),
    'crosscut': (.22, [(0,.19,890,390,.3,.24,5,2.03),(.05,.17,440,670,.2,.12,5,1.51)])
}
if __name__ == '__main__':
    data = {k: render(k, *v) for k,v in CUES.items()}
    (OUT/'roster_manifest.json').write_text(json.dumps({'version':1,'authoring':'original deterministic finite mechanical component synthesis','cues':data},indent=2)+'\n')
    print('Exported12 finite002C.5 cues; audio voice cap and priorities remain runtime-owned.')
