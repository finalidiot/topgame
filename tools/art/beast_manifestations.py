"""Native 002C.5.2 beast apparition masters and verified runtime exports.

The default operation exports existing artist-edited masters. --author is an
explicit original integer-pixel key-pose reconstruction. It only touches this
new beast family. No raster rotation, resampling, blur or old-asset authoring.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import uuid

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_power_art import read_ase, write_ase, color
from workspace.workspace import create_task_workspace, find_tool
from beast_colour_identity import colour_metadata, recolour_native, SPIRIT_PALETTES

SOURCE = ROOT / "assets/source-art/beasts_002c5_2"
OUT = ROOT / "assets/powers/beasts_002c5_2"
CELL = (128, 128)
PIVOT = (64, 96)
LAYERS = ["01 smoke returning to rotor", "02 far anatomy and silver silhouette",
          "03 main body and near anatomy", "04 muscle shell scales and edge light"]
PALETTE = {"smoke": "#343434", "shadow": "#414141", "body": "#606060",
           "plane": "#808080", "silver": "#b4b4b4", "light": "#dddddd"}
TIMINGS = {"prepare": [65, 60, 60, 65], "travel": [135, 110, 115, 140],
           "strike": [60, 70, 80, 90], "recovery": [55, 65, 80, 100],
           "guard": [140, 110, 110, 140]}
LABELS = {"black_arrow": "Black Arrow", "iron_bull": "Iron Bull",
          "stone_tortoise": "Stone Tortoise", "coil_dragon": "Coil Dragon"}
DESCRIPTIONS = {
    "black_arrow": "Compact muscular human spirit: backward shooting-star somersault, asymmetric axial corkscrew, opening to a chest-down landing. PAC / Neville movement tribute; no bird.",
    "iron_bull": "Broad-horned bull spirit: shoulder-first gather, low horn-led charge, planted lunge, recoil and a wide four-hoof guard.",
    "stone_tortoise": "Low broad tortoise spirit: domed stone shell, visible head and four planted feet, weight transfer and braced low guard.",
    "coil_dragon": "Long serpentine dragon spirit: open-centre coils, horned open jaws, clawed forelimbs and an uncoiling bite that recoils into a defensive curl.",
}


def ink(name, alpha=255):
    return color(PALETTE[name], alpha)


def blank():
    return [Image.new("RGBA", CELL) for _ in LAYERS]


def mask():
    return Image.new("L", CELL)


def polygon(im, points, name, alpha=255):
    ImageDraw.Draw(im).polygon(points, fill=ink(name, alpha))


def line(im, points, name, width=1, alpha=255):
    ImageDraw.Draw(im).line(points, fill=ink(name, alpha), width=width)


def mpoly(im, points):
    ImageDraw.Draw(im).polygon(points, fill=255)


def segment(im, a, b, wa, wb):
    """Tapered angular anatomy; integer vertices, never transformed pixels."""
    dx, dy = b[0]-a[0], b[1]-a[1]
    length = max(1, math.hypot(dx, dy))
    nx, ny = -dy/length, dx/length
    mpoly(im, [(round(a[0]+nx*wa), round(a[1]+ny*wa)),
               (round(b[0]+nx*wb), round(b[1]+ny*wb)),
               (round(b[0]-nx*wb), round(b[1]-ny*wb)),
               (round(a[0]-nx*wa), round(a[1]-ny*wa))])


def joint(im, p, radius):
    x, y = p
    mpoly(im, [(x-radius,y-1),(x-radius+1,y-radius),(x+1,y-radius),
               (x+radius,y-1),(x+radius-1,y+radius),(x-1,y+radius)])


def chain(im, points, widths):
    for index in range(len(points)-1):
        segment(im, points[index], points[index+1], widths[index], widths[index+1])
    for p, r in zip(points, widths):
        joint(im, p, r)


def spectral(im, body, fill="body", alpha=205):
    """A one-pixel silver contour encloses a translucent charcoal body."""
    rim = ImageChops.subtract(body.filter(ImageFilter.MaxFilter(3)),body)
    silver = Image.new("RGBA", CELL, ink("silver", min(245, alpha+35)))
    silver.putalpha(rim.point(lambda a: round(a*min(245, alpha+35)/255)))
    main = Image.new("RGBA", CELL, ink(fill, alpha))
    main.putalpha(body.point(lambda a: round(a*alpha/255)))
    im.alpha_composite(silver)
    im.alpha_composite(main)


def smoke(ims, index, tag, anchor, alpha=130):
    x, y = anchor
    # Three separate broken tendrils physically gather into the rotor pivot.
    # Smoke is a secondary small texture; it never supplies the creature shape.
    sway = [-3, 0, 3, 1][index]
    # Small broken wisps instead of long closed loops below the human's feet.
    low=max(y+7,81)
    polygon(ims[0], [(61,98),(57+sway,91),(x-5,low),(x-2,low+4),
                     (61+sway,91),(65,96)], "smoke", alpha//2)
    line(ims[0],[(69,97),(73+sway,90),(x+5,low+4)],"plane",2,alpha//3)
    line(ims[0],[(x-8,y+10),(x-6,y+16)],"silver",1,alpha//3)
    if tag in ("travel", "strike"):
        line(ims[0], [(x-24,y+10),(x-18,y+6),(x-13,y+6)], "silver", 1, alpha//2)
        line(ims[0], [(x-28,y+18),(x-20,y+15)], "plane", 2, alpha//2)


# Every human pose is a separate skeleton. Ordering is head, left shoulder,
# right shoulder, left hip, right hip; then elbow/hand and knee/foot pairs.
# The travel sequence changes projection and torso shape through arch, inverted
# tuck, crossed shoulders and a wide chest-down opening. No rotated base sprite.
HUMAN = [
    [(64,55),(51,65),(75,64),(59,81),(68,82),(42,73),(49,82),(82,74),(76,84),(51,92),(43,97),(78,91),(86,98)],
    [(62,45),(49,57),(77,56),(58,77),(68,76),(40,62),(38,72),(85,64),(89,72),(50,89),(45,99),(77,89),(84,98)],
    [(61,34),(47,47),(78,45),(57,64),(68,65),(39,43),(35,33),(87,42),(92,31),(49,83),(44,96),(77,81),(82,95)],
    [(64,26),(48,38),(79,41),(58,55),(68,57),(39,31),(34,22),(89,34),(94,24),(51,75),(47,89),(77,72),(85,86)],
    [(78,32),(58,39),(71,47),(51,58),(61,61),(67,28),(77,19),(86,43),(97,34),(46,74),(38,86),(68,69),(79,77)],
    [(56,70),(47,60),(67,57),(62,43),(72,42),(43,47),(49,37),(75,51),(79,41),(54,28),(46,38),(79,30),(86,44)],
    [(64,69),(59,57),(72,53),(59,40),(69,39),(76,46),(71,35),(54,45),(51,35),(51,30),(56,46),(77,26),(84,40)],
    [(83,53),(67,44),(72,62),(51,47),(57,58),(80,35),(92,38),(82,72),(89,80),(45,34),(34,32),(46,72),(40,87)],
    [(90,82),(73,71),(72,91),(53,69),(58,82),(88,68),(102,71),(88,100),(99,106),(43,61),(32,54),(43,91),(30,99)],
    [(90,85),(74,74),(72,94),(54,72),(59,85),(88,69),(102,70),(88,101),(100,106),(43,66),(32,59),(43,94),(31,101)],
    [(85,85),(71,79),(70,96),(53,80),(58,91),(87,77),(101,82),(84,104),(95,109),(46,72),(35,76),(44,100),(33,109)],
    [(74,73),(61,78),(80,84),(57,91),(66,96),(47,77),(40,87),(94,90),(98,100),(44,101),(34,108),(77,104),(88,110)],
    [(70,65),(57,76),(80,75),(57,90),(68,91),(45,87),(44,98),(92,87),(92,99),(49,100),(40,109),(78,100),(88,107)],
    [(67,52),(53,65),(79,64),(57,83),(69,84),(45,77),(48,86),(87,77),(82,89),(52,95),(43,104),(77,95),(84,104)],
    [(65,44),(51,57),(79,57),(58,77),(69,78),(43,67),(47,80),(87,69),(83,82),(53,91),(48,104),(76,92),(80,104)],
    [(64,53),(52,65),(77,65),(59,82),(69,82),(46,76),(53,86),(83,77),(77,88),(57,95),(53,105),(74,94),(78,104)],
    [(64,35),(47,48),(81,48),(58,68),(70,68),(39,60),(46,72),(90,61),(82,71),(50,85),(40,98),(80,84),(89,98)],
    [(61,34),(44,47),(79,50),(56,68),(68,68),(36,59),(48,63),(86,39),(79,30),(47,86),(38,99),(79,83),(90,96)],
    [(67,36),(49,51),(84,48),(59,69),(71,68),(44,40),(54,32),(93,58),(82,66),(53,84),(43,96),(81,88),(91,100)],
    [(64,37),(46,51),(82,50),(58,69),(70,69),(37,64),(49,71),(92,65),(81,72),(49,87),(40,101),(80,87),(89,101)],
]


def human(tag, key):
    index = list(TIMINGS).index(tag)*4+key
    h, ls, rs, lh, rh, le, handl, re, handr, lk, footl, rk, footr = HUMAN[index]
    ims = blank()
    alpha = [205,205,190,120][key] if tag == "recovery" else 210
    if tag == "prepare": alpha = [140,175,200,210][key]
    smoke(ims, key, tag, ((lh[0]+rh[0])//2, (lh[1]+rh[1])//2), 95)
    far = mask()
    chain(far, [rs,re,handr], [5,4,3])
    chain(far, [rh,rk,footr], [7,5,3])
    segment(far, footr, (footr[0]+4,footr[1]+1), 3, 2)
    spectral(ims[1], far, "shadow", alpha-25)
    body = mask()
    # Broad pectoral girdle narrows markedly at the waist before powerful thighs.
    waistl = (round(ls[0]*.30+lh[0]*.70)+1, round(ls[1]*.38+lh[1]*.62))
    waistr = (round(rs[0]*.30+rh[0]*.70)-1, round(rs[1]*.38+rh[1]*.62))
    mpoly(body, [ls,rs,waistr,rh,lh,waistl])
    shoulder_mid = ((ls[0]+rs[0])//2,(ls[1]+rs[1])//2)
    chain(body, [shoulder_mid,h], [5,4])
    x,y=h
    # Hair has a short tapered tail; the blank head never gains eyes or a face.
    mpoly(body, [(x-5,y-5),(x-2,y-8),(x+4,y-7),(x+7,y-3),(x+6,y+3),
                 (x+2,y+6),(x-3,y+5),(x-6,y+1)])
    mpoly(body, [(x-4,y-5),(x-8,y-2),(x-10,y+5),(x-7,y+3),(x-4,y+1)])
    chain(body, [ls,le,handl], [7,4,3])
    chain(body, [lh,lk,footl], [9,6,3])
    segment(body, footl, (footl[0]-4,footl[1]+1), 3,2)
    spectral(ims[2], body, "body", alpha)
    # Muscle planes follow each new authored joint, without outlines between
    # every part. Several pixels of clear air survive between both arms/legs.
    line(ims[3], [ls,(round(ls[0]*.55+lh[0]*.45),round(ls[1]*.55+lh[1]*.45))], "silver",2,alpha)
    chest_mid = ((ls[0]+rs[0])//2,(ls[1]+rs[1])//2+3)
    line(ims[3], [(ls[0]+3,ls[1]+2),chest_mid,(rs[0]-3,rs[1]+2)], "plane",2,alpha)
    line(ims[3], [ls,le], "plane",2,alpha)
    line(ims[3], [lh,lk], "silver",2,alpha-15)
    line(ims[3], [rh,rk], "plane",2,alpha-15)
    line(ims[3], [(x-3,y-5),(x+2,y-7),(x+5,y-3)], "light",1,alpha)
    # The crossed-shoulder key has a near forearm plane across the chest.
    if index == 6:
        line(ims[3], [le,handl], "light",2,alpha)
        line(ims[3], [ls,le], "silver",2,alpha)
    return ims


# Bull: rump, shoulder, head; four separate knee/hoof chains, horn spread.
BULL = [
    ((47,67),(69,62),(80,67),[(39,86),(34,98),(59,84),(58,99),(72,88),(73,103),(86,86),(91,99)],22),
    ((46,64),(67,57),(77,62),[(38,85),(31,98),(57,81),(58,97),(70,83),(70,100),(84,81),(92,97)],23),
    ((43,61),(67,54),(79,58),[(36,80),(27,94),(56,79),(51,96),(71,79),(79,97),(86,79),(99,91)],25),
    ((42,59),(68,52),(81,54),[(34,79),(24,91),(53,78),(55,98),(72,76),(84,94),(87,75),(102,86)],26),
    ((40,56),(65,50),(84,55),[(29,70),(20,81),(53,76),(52,92),(71,72),(83,84),(85,73),(103,77)],26),
    ((43,53),(69,49),(89,59),[(32,75),(23,89),(56,67),(67,77),(75,74),(71,94),(90,71),(107,84)],24),
    ((39,60),(66,55),(89,68),[(29,82),(19,94),(53,74),(60,83),(73,88),(84,101),(91,83),(109,92)],24),
    ((40,65),(68,59),(92,72),[(29,81),(20,89),(53,87),(48,103),(75,85),(88,95),(95,85),(109,103)],23),
    ((42,64),(71,63),(94,76),[(31,87),(23,102),(55,86),(50,101),(80,86),(97,100),(99,85),(113,98)],24),
    ((43,69),(74,71),(98,84),[(31,88),(24,104),(57,91),(51,106),(82,95),(103,108),(101,94),(116,105)],23),
    ((46,72),(72,72),(93,85),[(35,92),(29,105),(57,94),(55,108),(79,95),(90,108),(96,95),(109,106)],25),
    ((48,69),(70,65),(85,74),[(38,91),(32,104),(59,88),(55,103),(76,90),(80,104),(89,87),(98,103)],26),
    ((49,64),(70,57),(84,66),[(40,84),(36,99),(60,83),(57,100),(76,83),(77,100),(87,84),(95,98)],24),
    ((47,64),(68,58),(81,65),[(38,86),(33,100),(58,82),(56,99),(73,84),(73,101),(85,83),(92,99)],23),
    ((46,66),(68,62),(80,69),[(37,87),(32,100),(58,85),(57,101),(73,88),(74,103),(86,85),(92,100)],22),
    ((48,74),(68,70),(78,78),[(41,90),(38,103),(59,91),(60,104),(72,94),(76,108),(84,92),(90,103)],21),
    ((45,66),(68,59),(81,67),[(33,86),(26,104),(54,86),(50,104),(76,87),(82,106),(87,86),(98,103)],28),
    ((44,68),(68,62),(82,72),[(32,88),(24,105),(53,89),(49,106),(77,90),(85,108),(89,89),(101,105)],29),
    ((47,65),(70,57),(82,63),[(35,84),(28,102),(56,84),(53,103),(76,82),(83,102),(88,84),(99,103)],28),
    ((45,67),(68,61),(80,69),[(33,88),(25,104),(54,87),(49,105),(75,87),(83,107),(87,87),(99,104)],29),
]


def bull(tag, key):
    idx = list(TIMINGS).index(tag)*4+key
    rump, shoulder, head, leg_points, spread = BULL[idx]
    ims = blank(); alpha = 205 if tag != "recovery" else [205,190,165,125][key]
    smoke(ims,key,tag,shoulder,90)
    far=mask(); near=mask()
    rx,ry=rump; sx,sy=shoulder; hx,hy=head
    for j,root in enumerate([(rx-4,ry+8),(rx+9,ry+9),(sx-2,sy+15),(sx+11,sy+13)]):
        knee,hoof=leg_points[j*2:j*2+2]
        chain(far if j in (1,3) else near,[root,knee,hoof],[5,4,3])
        mpoly(far if j in (1,3) else near,[(hoof[0]-4,hoof[1]-1),(hoof[0]+4,hoof[1]-1),
                                                       (hoof[0]+5,hoof[1]+3),(hoof[0]-5,hoof[1]+3)])
    # A crooked tapering tail with a tuft separates the rump from the legs.
    chain(far,[(rx-9,ry-2),(rx-19,ry-6),(rx-22,ry+4)],[2,2,1])
    mpoly(far,[(rx-24,ry+3),(rx-20,ry+2),(rx-19,ry+9),(rx-24,ry+8)])
    spectral(ims[1],far,"shadow",alpha-20)
    mpoly(near,[(rx-15,ry-7),(rx-9,ry-16),(rx+7,ry-17),
                (sx-7,sy-18),(sx+5,sy-19),(sx+14,sy-10),(sx+16,sy+7),
                (sx+7,sy+19),(rx+4,ry+16),(rx-13,ry+11)])
    chain(near,[shoulder,head],[13,10])
    # Forehead / nose are broad bovine planes; the horn tips are high and wide.
    mpoly(near,[(hx-11,hy-10),(hx+7,hy-10),(hx+12,hy-3),(hx+10,hy+13),
                (hx+4,hy+19),(hx-6,hy+18),(hx-13,hy+8)])
    for sign in (-1,1):
        mpoly(near,[(hx+sign*7,hy-9),(hx+sign*18,hy-14),(hx+sign*spread,hy-24),
                    (hx+sign*(spread-1),hy-11),(hx+sign*17,hy-5),(hx+sign*8,hy-4)])
        # Side-pointed ears remain visibly below the horns.
        mpoly(near,[(hx+sign*10,hy-3),(hx+sign*20,hy-3),(hx+sign*16,hy+3),(hx+sign*10,hy+4)])
    spectral(ims[2],near,"body",alpha)
    polygon(ims[3],[(sx-8,sy-13),(sx+1,sy-17),(sx+9,sy-10),(sx+4,sy+6),(sx-4,sy+10)],"plane",alpha)
    line(ims[3],[(rx-11,ry-10),(rx+5,ry-15),(sx-5,sy-14)],"silver",2,alpha)
    polygon(ims[3],[(hx-7,hy-8),(hx+4,hy-8),(hx+7,hy-2),(hx+2,hy+9),(hx-4,hy+8)],"plane",alpha)
    line(ims[3],[(hx-7,hy+12),(hx+7,hy+13)],"silver",2,alpha)
    for sign in (-1,1):
        line(ims[3],[(hx+sign*10,hy-10),(hx+sign*18,hy-14),(hx+sign*(spread-1),hy-22)],"light",1,alpha)
    return ims


# Tortoise shell centre x/y, crown y, head x/y, four feet. Each phase authors
# weight transfer and limb clearance; guard pulls the head into the dome.
TORTOISE = [
    (61,77,51,(94,80),[(32,91),(46,100),(80,101),(91,91)]),
    (61,74,47,(95,77),[(31,90),(43,101),(81,100),(92,90)]),
    (60,72,43,(96,76),[(28,89),(42,100),(83,100),(95,88)]),
    (60,72,43,(99,74),[(28,87),(40,100),(82,101),(97,87)]),
    (61,69,41,(99,71),[(31,81),(37,98),(84,96),(98,80)]),
    (62,71,42,(101,75),[(26,91),(44,96),(78,104),(100,91)]),
    (64,70,42,(104,74),[(34,82),(40,101),(88,95),(99,85)]),
    (64,74,45,(105,78),[(27,93),(44,102),(82,106),(103,92)]),
    (65,77,46,(108,81),[(27,94),(42,104),(88,105),(105,94)]),
    (66,80,50,(110,86),[(26,95),(41,108),(91,109),(107,98)]),
    (65,80,51,(105,87),[(28,96),(43,108),(90,109),(102,98)]),
    (63,77,48,(99,84),[(30,93),(45,104),(85,104),(98,94)]),
    (63,75,46,(99,80),[(30,91),(44,102),(85,102),(96,91)]),
    (62,74,45,(96,79),[(31,91),(45,102),(82,102),(94,91)]),
    (62,75,46,(92,80),[(33,93),(47,103),(80,103),(91,92)]),
    (62,80,53,(87,86),[(36,94),(49,102),(78,102),(89,94)]),
    (62,75,44,(91,80),[(26,94),(39,107),(86,107),(98,94)]),
    (62,77,47,(86,83),[(24,96),(37,109),(88,109),(100,96)]),
    (62,78,48,(84,85),[(25,96),(38,109),(87,109),(100,96)]),
    (62,76,45,(87,82),[(25,95),(38,108),(87,108),(99,95)]),
]


def tortoise(tag,key):
    idx=list(TIMINGS).index(tag)*4+key
    cx,cy,top,head,feet=TORTOISE[idx]
    ims=blank(); alpha=205 if tag!="recovery" else [205,185,165,125][key]
    smoke(ims,key,tag,(cx,cy+9),85)
    far=mask(); body=mask()
    for j,foot in enumerate(feet):
        root=(cx+[-23,-13,14,26][j],cy+[4,12,12,3][j])
        knee=(round(root[0]*.40+foot[0]*.60),foot[1]-5)
        target=far if j in (0,3) else body
        chain(target,[root,knee,foot],[6,5,4])
        fx,fy=foot
        mpoly(target,[(fx-5,fy-2),(fx+4,fy-2),(fx+6,fy+3),(fx-7,fy+3)])
    chain(far,[(cx-26,cy+9),(cx-34,cy+15)],[3,1])
    spectral(ims[1],far,"shadow",alpha-20)
    hx,hy=head
    chain(body,[(cx+25,cy+5),(hx-7,hy),head],[7,6,7])
    mpoly(body,[(hx-7,hy-6),(hx+2,hy-8),(hx+8,hy-3),(hx+9,hy+4),
                (hx+5,hy+9),(hx-4,hy+9),(hx-9,hy+4)])
    # Plastron and dome are organic stepped polygons, not a circular shield.
    mpoly(body,[(cx-31,cy+1),(cx-26,cy+14),(cx-13,cy+21),(cx+13,cy+21),
                (cx+28,cy+13),(cx+33,cy),(cx+28,top+10),(cx+14,top+1),
                (cx-4,top-2),(cx-18,top+3),(cx-28,top+13)])
    spectral(ims[2],body,"body",alpha)
    polygon(ims[3],[(cx-30,cy),(cx-25,top+12),(cx-16,top+4),(cx-3,top),
                     (cx+12,top+3),(cx+25,top+11),(cx+30,cy),(cx+22,cy+12),
                     (cx+4,cy+16),(cx-15,cy+13)],"plane",alpha)
    # Five broad scutes obey the dome's crown/side planes. No ornamental gear.
    z=round((top+cy)/2)
    for path in [[(cx-3,top+1),(cx-9,z),(cx-6,cy+4),(cx+5,cy+8),(cx+14,z+4),(cx+12,top+4)],
                 [(cx-9,z),(cx-23,z+4),(cx-27,cy+2)],
                 [(cx-6,cy+4),(cx-18,cy+12)],
                 [(cx+14,z+4),(cx+27,z+10)],
                 [(cx+5,cy+8),(cx+8,cy+15)]]:
        line(ims[3],path,"shadow",2,alpha)
    line(ims[3],[(cx-24,top+12),(cx-15,top+5),(cx-3,top+1),(cx+11,top+4)],"light",1,alpha)
    line(ims[3],[(cx-26,cy+13),(cx-12,cy+20),(cx+12,cy+20),(cx+26,cy+13)],"silver",2,alpha)
    line(ims[3],[(hx-3,hy-6),(hx+3,hy-5),(hx+7,hy)],"silver",1,alpha)
    for foot in (feet[1],feet[2]):
        fx,fy=foot
        for dx in (-3,0,3):line(ims[3],[(fx+dx,fy+1),(fx+dx,fy+3)],"light",1,alpha)
    return ims


# Explicit serpent spines leave an open centre. Head directions are authored
# vector geometry, not rotated raster cells. Coils change handed projection,
# tail length, neck reach and claw poses between the action's keys.
DRAGON = [
    ([(85,47),(76,36),(56,33),(40,44),(36,64),(45,80),(65,85),(83,76),(80,63)],-8,[(78,61),(93,67),(70,79),(57,91)]),
    ([(89,43),(77,31),(54,30),(36,44),(33,65),(44,82),(67,87),(86,75),(83,59)],-18,[(82,57),(98,64),(73,81),(60,96)]),
    ([(92,38),(77,27),(54,29),(34,45),(32,67),(44,85),(67,88),(87,75),(85,56)],-20,[(85,51),(99,57),(73,82),(60,95)]),
    ([(95,38),(78,27),(53,29),(33,47),(34,71),(48,88),(70,87),(88,73),(84,54)],-12,[(86,51),(101,58),(76,80),(66,93)]),
    ([(100,39),(78,27),(49,31),(31,51),(36,76),(57,89),(80,81),(88,64),(73,55)],4,[(90,54),(104,63),(69,84),(51,96)]),
    ([(104,48),(85,31),(58,26),(35,40),(31,66),(46,85),(72,88),(92,76),(85,57)],18,[(94,65),(108,76),(78,84),(66,98)]),
    ([(104,61),(92,42),(72,29),(48,31),(31,49),(34,75),(55,89),(81,88),(90,70)],27,[(97,75),(110,88),(63,86),(46,98)]),
    ([(105,69),(93,47),(69,32),(44,37),(29,59),(39,82),(64,91),(88,82),(88,62)],22,[(95,83),(110,95),(73,87),(62,103)]),
    ([(104,73),(95,51),(70,35),(43,39),(28,59),(37,82),(64,93),(88,83),(87,61)],15,[(99,86),(114,98),(75,87),(63,105)]),
    ([(103,81),(98,60),(74,45),(45,45),(28,65),(41,86),(66,94),(87,82),(81,62)],9,[(100,95),(114,108),(72,88),(58,106)]),
    ([(105,85),(97,65),(77,51),(49,49),(33,65),(44,85),(67,92),(86,80),(78,61)],0,[(94,98),(108,111),(71,85),(56,101)]),
    ([(96,77),(90,57),(70,44),(47,46),(34,64),(42,82),(64,90),(83,80),(78,63)],-13,[(86,91),(102,101),(69,82),(58,99)]),
    ([(92,64),(83,45),(61,36),(41,44),(35,64),(45,82),(66,88),(85,76),(80,60)],-18,[(86,78),(99,85),(70,83),(56,96)]),
    ([(89,53),(77,36),(56,33),(38,45),(35,65),(46,82),(66,87),(85,74),(80,58)],-15,[(82,65),(97,73),(72,80),(58,93)]),
    ([(86,50),(74,38),(55,36),(39,48),(38,67),(49,82),(66,85),(82,73),(77,60)],-9,[(79,63),(91,71),(69,79),(58,89)]),
    ([(82,62),(73,49),(57,45),(43,55),(43,71),(53,82),(68,84),(80,73),(73,63)],0,[(77,72),(88,79),(69,77),(59,87)]),
    ([(86,44),(75,30),(51,29),(33,45),(32,68),(46,87),(70,90),(90,73),(82,54)],-4,[(84,60),(98,68),(74,83),(60,99)]),
    ([(84,43),(71,29),(48,32),(32,49),(35,72),(51,88),(76,87),(92,67),(78,52)],-8,[(83,59),(100,64),(76,79),(69,98)]),
    ([(87,46),(75,31),(51,29),(34,43),(30,67),(45,87),(69,91),(90,77),(84,56)],4,[(84,62),(100,71),(72,83),(56,98)]),
    ([(86,44),(74,30),(50,30),(32,47),(33,71),(48,88),(74,88),(91,69),(80,52)],-3,[(84,58),(99,67),(75,82),(64,99)]),
]


def dragon(tag,key):
    idx=list(TIMINGS).index(tag)*4+key
    spine,angle,claws=DRAGON[idx]
    ims=blank(); alpha=205 if tag!="recovery" else [205,180,155,110][key]
    smoke(ims,key,tag,spine[6],85)
    far=mask(); body=mask()
    # Longer rear claw is tucked underneath the far coil.
    chain(far,[spine[6],claws[2],claws[3]],[4,3,2])
    fx,fy=claws[3]
    for dx in (-4,0,4):chain(far,[(fx,fy),(fx+dx,fy+3),(fx+dx+2,fy+5)],[2,1,1])
    spectral(ims[1],far,"shadow",alpha-20)
    widths=[8,9,9,8,8,7,6,4,1]
    chain(body,spine,widths)
    chain(body,[spine[1],claws[0],claws[1]],[4,3,2])
    # Short sharp dorsal fins follow the outside spine, with no closed ring.
    for j in (1,2,3,4,5):
        x,y=spine[j]; nxt=spine[j+1]; prev=spine[j-1]
        dx,dy=nxt[0]-prev[0],nxt[1]-prev[1]; length=max(1,math.hypot(dx,dy))
        nx,ny=dy/length,-dx/length
        w=widths[j]
        mpoly(body,[(round(x+nx*(w-1)),round(y+ny*(w-1))),
                    (round(x+nx*(w+6)-dx/length*3),round(y+ny*(w+6)-dy/length*3)),
                    (round(x+nx*(w-1)+dx/length*5),round(y+ny*(w-1)+dy/length*5))])
    hx,hy=spine[0]; radians=math.radians(angle)
    def headpoint(x,y):return (round(hx+x*math.cos(radians)-y*math.sin(radians)),round(hy+x*math.sin(radians)+y*math.cos(radians)))
    # Oversized wedge jaws have a real transparent mouth gap; swept-back horns
    # and a brow crest differentiate the dragon from a snake or an FX crescent.
    for shape in [[(-10,-7),(-3,-13),(7,-11),(14,-5),(20,-3),(19,2),(8,2),(1,-1),(-9,4)],
                  [(-5,5),(7,7),(19,5),(15,11),(2,12),(-9,6)],
                  [(-6,-9),(-17,-23),(-14,-10),(-12,-3)],
                  [(1,-11),(-5,-25),(3,-18),(7,-8)],
                  [(-8,-5),(-15,-5),(-19,1),(-11,4)]]:
        mpoly(body,[headpoint(x,y) for x,y in shape])
    cx,cy=claws[1]
    for dx in (-4,0,4):chain(body,[(cx,cy),(cx+dx+1,cy+4),(cx+dx+4,cy+6)],[2,1,1])
    spectral(ims[2],body,"body",alpha)
    # Broken longitudinal scale planes preserve the open centre.
    for j in range(1,7):
        a,b=spine[j],spine[j+1]
        mid=(round(a[0]*.55+b[0]*.45),round(a[1]*.55+b[1]*.45))
        line(ims[3],[a,mid],"plane",3 if j<5 else 2,alpha)
        line(ims[3],[(a[0]-2,a[1]-1),(a[0]+1,a[1]-2),(a[0]+3,a[1])],"silver",1,alpha)
    for path in [[(-10,-8),(-3,-12),(7,-10),(13,-5),(19,-3)],
                 [(-4,8),(8,10),(16,8)], [(-5,-11),(-16,-22)],[(1,-13),(-4,-23)]]:
        line(ims[3],[headpoint(x,y) for x,y in path],"light",1,alpha)
    # Tiny two teeth sit on the upper jaw's lip, never fill the mouth aperture.
    for x in (9,15):polygon(ims[3],[headpoint(x,2),headpoint(x+2,2),headpoint(x+1,4)],"silver",alpha)
    return ims


RENDERERS={"black_arrow":human,"iron_bull":bull,"stone_tortoise":tortoise,"coil_dragon":dragon}


def author():
    SOURCE.mkdir(parents=True,exist_ok=True)
    for name,render in RENDERERS.items():
        frames=[]; spans=[]; durations=[]
        for tag,times in TIMINGS.items():
            start=len(frames)
            frames.extend(render(tag,key) for key in range(len(times)))
            spans.append((tag,start,len(frames)-1)); durations.extend(times)
        write_ase(SOURCE/f"{name}.aseprite",frames,LAYERS,spans,durations,PIVOT,
                  note=f"002C.5.2 / {LABELS[name]} / 20 independent anatomy keys / giant spectral avatar behind opaque equipped rotor / native128 nearest / pivot64,96 / {DESCRIPTIONS[name]}",palette=PALETTE)
        source = SOURCE/f"{name}.aseprite"
        source.write_bytes(recolour_native(source.read_bytes(), SPIRIT_PALETTES[name]))


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def export_and_validate(aseprite,qa,task="002C.5.2",check_only=False):
    OUT.mkdir(parents=True,exist_ok=True)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ") + "_" + uuid.uuid4().hex[:8]
    native_dir=qa/"temp/beast-manifestations-native"/run_id
    native_dir.mkdir(parents=True,exist_ok=False)
    evidence=qa/"manifests/beast-manifestations"/run_id
    evidence.mkdir(parents=True,exist_ok=False)
    manifest={"version":2,"task":task,"scope":"giant coloured translucent beast manifestations behind actual opaque top",
              "filter":"nearest","runtime_top_sprite_included":False,"effects":{}}
    checks=[]
    for name in RENDERERS:
        source=SOURCE/f"{name}.aseprite";frames,meta=read_ase(source)
        assert meta["cell"]==list(CELL) and meta["pivot"]==list(PIVOT)
        assert meta["layers"]==LAYERS and list(meta["tags"])==list(TIMINGS)
        assert len(frames)==20
        assert all(span["to"]-span["from"]==3 for span in meta["tags"].values())
        png=native_dir/f"{name}_native.png";data=evidence/f"{name}_native.json"
        command=[aseprite,"--batch",str(source),"--list-layers","--list-tags","--list-slices",
                 "--sheet",str(png),"--sheet-columns","4","--data",str(data),"--format","json-array"]
        result=subprocess.run(command,capture_output=True,text=True,check=True)
        native=Image.open(png).convert("RGBA")
        expected=Image.new("RGBA",(512,640))
        for i,frame in enumerate(frames):expected.alpha_composite(frame,((i%4)*128,(i//4)*128))
        assert native.size==expected.size
        rounding=0
        for a,b in zip(native.getdata(),expected.getdata()):
            assert a[3]==b[3],f"{name}: native alpha mismatch"
            if a[3]:assert max(abs(a[c]-b[c]) for c in range(3))<=1,f"{name}: source pixel mismatch {a} {b}"
            if a!=b:rounding+=1
        export=json.loads(data.read_text(encoding="utf-8"))
        native_meta=export["meta"]
        assert [x["name"] for x in native_meta["layers"]]==LAYERS
        assert native_meta["slices"][0]["keys"][0]["pivot"]=={"x":64,"y":96}
        assert [x["name"] for x in native_meta["frameTags"]]==list(TIMINGS)
        assert [x["duration"] for x in export["frames"]]==meta["durations_ms"]
        target=OUT/f"{name}.png"
        if not check_only: native.save(target)
        assert Image.open(target).convert("RGBA").tobytes()==native.tobytes()
        tags={tag:{**span,"duration_ms":sum(meta["durations_ms"][span["from"]:span["to"]+1]),
                   "loop":tag=="guard"} for tag,span in meta["tags"].items()}
        item={**meta,"texture":"res://"+target.relative_to(ROOT).as_posix(),
              "source":source.relative_to(ROOT).as_posix(),"columns":4,"frame_count":len(frames),
              "tags":tags,"label":LABELS[name],"description":DESCRIPTIONS[name],
              "source_sha256":digest(source),"texture_sha256":digest(target),
              "native_runtime_rgba_exact":True,"python_compositor_rounding_pixels":rounding,
              **colour_metadata(name,source,native)}
        manifest["effects"][name]=item
        nonempty=[frame.getbbox() is not None for frame in frames]
        distinct=len({hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames})
        assert all(nonempty) and distinct==20
        assert all(all(0<v<128 for v in frame.getbbox()) for frame in frames),f"{name}: cell-edge clipping"
        check={"beast":name,"frames":20,"distinct_pose_pixels":distinct,"native_runtime_rgba_exact":True,
               "cell":list(CELL),"pivot":list(PIVOT),"named_layers":LAYERS,
               "tags":tags,"source_sha256":digest(source),"texture_sha256":digest(target),
               "native_json_sha256":digest(data),"native_sheet_sha256":digest(png),
               "native_export_command":command,"stdout":result.stdout,"stderr":result.stderr,
               **colour_metadata(name,source,native)}
        (evidence/f"{name}_parity.json").write_text(json.dumps(check,indent=2)+"\n",encoding="utf-8")
        checks.append(check)
    if check_only:
        assert json.loads((OUT/"manifest.json").read_text(encoding="utf-8"))==manifest,"Beast manifest differs from current native export"
    else:
        (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    report={"task":task,"masters":4,"runtime_sheets":4,"authored_keys":80,
            "export_id":run_id,"evidence_directory":str(evidence),
            "native_export_directory":str(native_dir),"check_only":check_only,
            "native_aseprite":subprocess.run([aseprite,"--version"],capture_output=True,text=True,check=True).stdout.strip(),
            "source_runtime_parity":True,"editable_named_layers":True,"tags_pivots_timings":True,
            "runtime_pixels_equal_native_aseprite_rgba":True,"human_visual_acceptance_pending":True,
            "static_review_is_gameplay_evidence":False,"checks":checks}
    prefix="002c5_2" if task=="002C.5.2" else task.lower().replace(".","_")
    (evidence/f"{prefix}_beast_art_report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    return manifest,report


def review(manifest,qa,run_id):
    prefix="002c5_2" if manifest["task"]=="002C.5.2" else manifest["task"].lower().replace(".","_")
    images=qa/"images/beast-manifestations"/run_id
    images.mkdir(parents=True,exist_ok=False)
    font_path=Path("C:/Windows/Fonts/consola.ttf")
    font=ImageFont.truetype(str(font_path),12) if font_path.exists() else ImageFont.load_default()
    sheet=Image.new("RGBA",(544,20*154+30),(25,27,29,255))
    sil=sheet.copy();d=ImageDraw.Draw(sheet);s=ImageDraw.Draw(sil)
    d.text((10,5),"80 native beast keys / art QA only /128 cells",font=font,fill=ink("silver"))
    s.text((10,5),"80 grayscale silhouette keys / art QA only",font=font,fill=ink("silver"))
    row=0
    native_frames={}
    for name,item in manifest["effects"].items():
        texture=Image.open(ROOT/item["texture"].removeprefix("res://")).convert("RGBA")
        native_frames[name]=[texture.crop((i%4*128,i//4*128,i%4*128+128,i//4*128+128)) for i in range(20)]
        for tag,span in item["tags"].items():
            y=30+row*154
            label=f"{item['label']} / {tag} / {span['duration_ms']}ms"
            d.text((10,y),label,font=font,fill=ink("silver"));s.text((10,y),label,font=font,fill=ink("silver"))
            for key in range(4):
                x=8+key*134;frame=native_frames[name][span["from"]+key]
                d.line([(x,y+114),(x+127,y+114)],fill=(46,48,50,255))
                sheet.alpha_composite(frame,(x,y+18))
                # Flatten the avatar mask to pale grey at its authored alpha.
                # No colour is available to rescue the creature's identity.
                silhouette=Image.new("RGBA",CELL,ink("light"));silhouette.putalpha(frame.getchannel("A"))
                sil.alpha_composite(silhouette,(x,y+18))
                d.text((x+4,y+136),str(item["durations_ms"][span["from"]+key])+"ms",font=font,fill=ink("plane"))
                s.text((x+4,y+136),str(item["durations_ms"][span["from"]+key])+"ms",font=font,fill=ink("plane"))
            row+=1
        # Individual four-by-five key sheet, enlarged by nearest for review.
        texture.resize((1024,1280),Image.Resampling.NEAREST).save(images/f"{prefix}_{name}_all_keys_2x.png")
    sheet.save(images/f"{prefix}_beast_native_keys.png")
    sil.save(images/f"{prefix}_beast_grayscale_silhouettes.png")
    # Native640x360 fit uses existing opaque part art above the apparition.
    fit=Image.new("RGBA",(640,360),(45,48,50,255));draw=ImageDraw.Draw(fit)
    draw.text((8,6),"640x360 static fit / giant spirit behind opaque equipped top / art QA only",font=font,fill=ink("silver"))
    positions=[(86,153),(242,153),(398,153),(554,153)]
    for (name,frames),at in zip(native_frames.items(),positions):
        for row,key in enumerate((3,9)):
            x,y=at[0],at[1]+row*155
            fit.alpha_composite(frames[key],(x-64,y-96))
            for category,part in (("bits","ball"),("ratchets","mid")):
                path=ROOT/f"assets/top/parts/{category}/{part}.png"
                if path.exists():fit.alpha_composite(Image.open(path).convert("RGBA"),(x-24,y-40))
            blade=Image.open(ROOT/"assets/top/parts/blades/balance.png").convert("RGBA").crop((0,0,48,48))
            fit.alpha_composite(blade,(x-24,y-38))
            draw.text((x-65,y+17),LABELS[name],font=font,fill=ink("silver"))
    fit.save(images/f"{prefix}_beast_native_top_fit.png")
    fit.resize((1280,720),Image.Resampling.NEAREST).save(images/f"{prefix}_beast_native_top_fit_2x.png")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author",action="store_true",help="Explicitly reconstruct only these four beast masters")
    parser.add_argument("--aseprite")
    parser.add_argument("--qa-root",type=Path)
    parser.add_argument("--task",default="002C.5.2",help="Milestone for external evidence; historical default is retained")
    parser.add_argument("--check",action="store_true",help="Verify fresh native exports without rewriting source/runtime assets")
    args=parser.parse_args();qa=create_task_workspace(args.task,args.qa_root)
    if args.author and args.check: parser.error("--check cannot reconstruct source masters")
    if args.author:author()
    manifest,report=export_and_validate(find_tool("aseprite",args.aseprite),qa,args.task,args.check)
    if not args.check: review(manifest,qa,report["export_id"])
    print(json.dumps({key:value for key,value in report.items() if key!="checks"}))


if __name__=="__main__":main()
