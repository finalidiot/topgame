"""Author the Task 002C.5.2 component content asset from the preserved parent data.

One-off reproducible content authoring, no saves or runtime grants. The JSON is
the runtime source of truth; rerunning this script requires the parent Git object.
"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARENT = "3d52a55d9d9bc154b50b3b1c90255f7ff0e62148"
source = subprocess.check_output(["git", "show", f"{PARENT}:scripts/parts.gd"], cwd=ROOT, text=True)
raw = re.search(r"const PARTS: Dictionary = (\{.*?\n\})\n", source, re.S).group(1)
parts = json.loads(raw)

def add(category, ident, name, rarity, description, identity, tradeoff, stats, physics):
    parts[category][ident] = dict(name=name, rarity=rarity, description=description,
                                mechanical_identity=identity, tradeoff=tradeoff,
                                stats=dict(zip(("mass", "power", "stamina", "grip", "speed", "stability"), stats)),
                                physics=physics)

add("blade", "hammerfall", "HAMMERFALL", "UNCOMMON",
    "Two heavy striking lobes hammer aligned hits. Thin shoulders kick back on glancing contact.",
    "Two-lobe aligned striker", "Strong aligned impulse; weak glancing hits and high self recoil",
    [8,8,4,4,5,4], dict(radius=13.8,lobes=2,radial_depth=0.14,aligned_impact=0.52,glancing_impact=0.55,glancing_recoil=0.48,recoil=1.08))
add("blade", "sawtooth", "SAWTOOTH", "UNCOMMON",
    "Twelve short teeth build pressure through repeated contact. Close brawling spends its own RPM faster.",
    "Repeated-contact grinder", "Pressure ramps only while staying in contact; each paid tooth also drains spin",
    [6,6,5,5,6,6], dict(radius=13.0,lobes=12,profile_angle=0.15,radial_depth=0.045,impact=0.86,repeat_pressure=0.65,contact_drain=0.004,contact_interval=0.12))
add("blade", "puck", "PUCK", "COMMON",
    "A compact solid disc shrugs off sideways kicks. Its short edge struggles to reach or lever larger blades.",
    "Compact dense defensive disc", "Narrow reach and low attack leverage; dense mass resists knockback",
    [8,4,7,5,4,8], dict(radius=10.0,mass=1.20,recoil=0.75,impact=0.79,wobble_recovery=1.18))
add("blade", "outrigger", "OUTRIGGER", "RARE",
    "Three broad wings catch rivals across an orbit. The wide rim catches walls and throws you out of line.",
    "Wide orbit catcher", "Large reach and lateral pressure; wall exposure and expensive rim strikes",
    [6,6,5,4,7,5], dict(radius=15.5,lobes=3,radial_depth=0.10,tangent_transfer=0.19,orbit=1.35,wall_cost=1.35,recoil=1.08))
add("blade", "lopsider", "LOPSIDER", "EPIC",
    "One thick counter-lobe lands fierce uneven blows. The off-centre mass keeps pulling the machine off balance.",
    "Eccentric heavy attacker", "High peak attack; persistent sway and wobble demand correction",
    [9,8,4,4,4,3], dict(radius=13.6,lobes=1,profile_angle=3.141592653589793,radius_lobes=2,radius_angle=0.0,radial_depth=0.16,aligned_impact=0.48,impact=1.15,imbalance=0.052,sway=14.0,wobble_recovery=0.72))
add("blade", "crescent", "CRESCENT", "RARE",
    "A curved scoop turns glancing contact into a sideways shove. Direct head-on strikes lose much of that leverage.",
    "Tangential scoop", "Strong sideways transfer on glancing hits; modest direct damage",
    [6,6,6,5,6,5], dict(radius=15.5,lobes=1,profile_angle=3.141592653589793,radius_gap_angle=0.0,radius_gap_width=0.6981317007977318,radius_gap_depth=0.67,tangent_transfer=0.38,tangent_glance=0.80,impact=0.83,recoil=1.07))
add("blade", "fork", "FORK", "UNCOMMON",
    "Two opposed forks carry four striking tines. Precise approaches bite hard; deep recesses between the tines land softly.",
    "Recessed four-tine striker", "Narrow contact windows reward alignment; deep recesses give away reach",
    [6,7,5,5,7,5], dict(radius=16.0,contact_points=[0.5404195002705842,-0.5404195002705842,2.601173153319209,3.682012153860377],point_width=0.42,radial_depth=0.68,aligned_impact=0.38,glancing_impact=0.72,tangent_transfer=0.06,recoil=1.12))
add("ratchet", "ballast", "BALLAST", "COMMON",
    "A dense low core makes the machine difficult to shove. Extra weight slows every chase and steering correction.",
    "Low heavy core", "High displacement resistance; slow acceleration and correction",
    [0.9,0,0.2,0,-0.7,0.9], dict(mass=1.38,acceleration=0.83,control=0.86,wobble_recovery=1.20,visual_height=3,contact_height=-0.30))
add("ratchet", "flex", "FLEX", "UNCOMMON",
    "A sprung collar softens impact shock and wobble. The same flex muffles the blade's outgoing punch.",
    "Compliant shock collar", "Lower received collision drain and wobble; softer attack transfer",
    [0.1,-0.5,0.1,0,0,0.6], dict(shock=0.62,impact=0.79,recoil=0.93,wobble_recovery=1.28,visual_height=0))
add("ratchet", "kickback", "KICKBACK", "RARE",
    "A tall spring seat turns impact into big rebounds. Use the displacement to escape; mistimed hits throw you toward gates.",
    "Recoil and wall rebound converter", "Large escape displacement and wall carry; increased collision and gate risk",
    [0.2,0.3,-0.2,0,0.4,-0.6], dict(recoil=1.38,wall_restitution=1.16,wall_retention=1.055,shock=1.12,wobble_recovery=0.86,visual_height=-2,contact_height=0.22))
add("ratchet", "offset", "OFFSET", "EPIC",
    "An offset axle adds leverage to uneven hits. The weight circles the axis, making straight travel and recovery difficult.",
    "Offset mass and leverage", "Additional contact leverage; rhythmic sway and sustained instability",
    [0.4,0.6,-0.2,0,0,-0.6], dict(impact=1.18,imbalance=0.045,sway=19.0,control=0.90,wobble_recovery=0.78,visual_height=-1,contact_height=0.16))
add("ratchet", "flywheel", "FLYWHEEL", "RARE",
    "A broad inertia ring carries spin through a brawl. It takes time to accelerate, turn or stop that rotating weight.",
    "High rotational inertia", "Collision spin efficiency and recovery; sluggish acceleration, turning and braking",
    [0.5,-0.2,0.3,0,-0.4,0.4], dict(inertia=1.65,acceleration=0.90,control=0.80,brake=0.74,rpm_drain=0.95,mass=1.08,visual_height=1))
add("ratchet", "scrap", "SCRAP", "TRASH",
    "A crooked salvaged collar rattles and kicks sideways off walls. Awkward to steer, but the light frame carries surprising drift.",
    "Warped salvage wall kicker", "Poor stability and authority; light, low-drag frame creates odd escape angles",
    [-0.4,0,-0.2,0,0.2,-0.8], dict(mass=0.87,drag=0.80,control=0.84,imbalance=0.066,sway=9.0,wall_tangent=0.32,recoil=1.10,visual_height=2,contact_height=-0.17))
add("bit", "skate", "SKATE", "UNCOMMON",
    "A polished shoe holds long drifting arcs. Speed carries through release, but late steering barely changes the line.",
    "Low-grip momentum skate", "Very long lateral retention; weak steering and braking",
    [0,-0.2,0.6,-1.0,1.3,-0.2], dict(control=0.49,acceleration=0.89,speed=1.18,drag=0.25,brake=0.45,rpm_drain=0.86))
add("bit", "claw", "CLAW", "RARE",
    "Flexible feet bite at low speed, then fold into a skid above 140 speed. Fast launches demand an early recovery turn.",
    "Speed-threshold grip collapse", "Strong low-speed authority; sudden high-speed slip and wobble",
    [0.2,0.3,-0.6,1.0,0.8,0.0], dict(acceleration=1.12,speed=1.13,drag=0.90,brake=1.30,grip_threshold=140.0,grip_low=1.28,grip_high=0.31,high_speed_wobble=0.15,rpm_drain=1.15))
add("bit", "freewheel", "FREEWHEEL", "COMMON",
    "A freely rolling collar wastes little spin in motion. It resists commands as willingly as it resists slowing down.",
    "Efficient free-rolling foot", "Efficient movement and retained speed; low control and braking authority",
    [0,-0.2,0.8,-0.5,0.2,0.2], dict(control=0.55,acceleration=0.88,drag=0.45,brake=0.55,rpm_drain=0.69))
add("bit", "eccentric", "ECCENTRIC", "LEGENDARY",
    "An eccentric heel grips and releases in a repeating beat. Time corrections to the bite; a missed beat sends the top skating.",
    "Rhythmic grip and release", "Alternating strong authority and long slide windows; costly correction and inconsistent braking",
    [0,0.2,-0.1,0.3,0.5,-0.4], dict(grip_wave=0.70,grip_frequency=1.6,control=0.94,drag=0.64,turn_cost=0.0035,sway=5.0,imbalance=0.014))
add("bit", "chisel", "CHISEL", "UNCOMMON",
    "A rectangular flat digs into your chosen heading and scrubs sideways motion. Tight corrections are sharp but spend spin.",
    "Directional side-scrubbing foot", "Strong heading authority and little sideslip; expensive sharp turns and limited pace",
    [0.1,0.3,-0.3,0.8,-0.3,0.4], dict(control=1.20,acceleration=1.02,speed=0.92,lateral_drag=2.65,drag=0.87,turn_cost=0.0055,brake=1.16))
add("bit", "tripod", "TRIPOD", "COMMON",
    "Three tiny feet settle toward the centre and stop hard under braking. The planted stance is poor at chasing or escaping.",
    "Centre-seeking brake foot", "Strong centre occupancy, recovery and braking; slow pursuit and weak escape",
    [0.2,-0.3,0.5,0.4,-0.8,0.8], dict(centre_hold=35.0,speed=0.66,acceleration=0.72,brake=2.15,drag=1.15,wobble_recovery=1.28,bank=1.25))
add("bit", "groove", "GROOVE", "EPIC",
    "A curved running groove steers broad orbits and keeps speed in arcs. Straight pursuit needs constant correction near the bank.",
    "Curved orbit-running foot", "Strong orbit momentum; curved tracking and wide bank exposure",
    [0,0.1,0,-0.2,0.7,-0.1], dict(orbit=2.60,curve=0.24,control=0.84,speed=1.12,drag=0.73,brake=0.79,rpm_drain=1.02))

legacy_rarities = {"balance":"COMMON","smash":"COMMON","guard":"COMMON","hook":"UNCOMMON", "low":"COMMON","mid":"COMMON","high":"UNCOMMON", "needle":"COMMON","ball":"COMMON","flat":"COMMON","rubber":"UNCOMMON"}
legacy_radius = {"balance":12.2,"smash":13.1,"guard":13.5,"hook":12.5}
for category, definitions in parts.items():
    folder = {"blade":"blades","ratchet":"ratchets","bit":"bits"}[category]
    for index, (ident, data) in enumerate(definitions.items()):
        data.update(id=ident, category=category, sort_order=index, legacy=ident in legacy_rarities)
        data.setdefault("rarity", legacy_rarities.get(ident))
        data.setdefault("mechanical_identity", data["description"])
        data.setdefault("tradeoff", data["description"])
        data.setdefault("physics", {})
        if ident in legacy_radius: data["physics"]["radius"] = legacy_radius[ident]
        if ident == "hook": data["physics"]["tangent_transfer"] = 0.12
        if category == "ratchet" and ident in ("low","mid","high"):
            data["physics"]["visual_height"] = {"low":3,"mid":0,"high":-3}[ident]
        data["visual"] = {"sprite":f"res://assets/top/parts/{folder}/{ident}.png", "pivot":[24,40], "cell":[48,48], "nearest":True}
        if category == "blade": data["visual"]["spin"] = f"res://assets/top/parts/blades/{ident}_spin.png"

out = ROOT / "assets/data/parts_catalogue.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({"schema_version":1,"rarities":["TRASH","COMMON","UNCOMMON","RARE","EPIC","LEGENDARY"],"categories":parts}, indent=2)+"\n", encoding="utf-8")
print(f"Wrote {sum(map(len,parts.values()))} component definitions to {out}")
