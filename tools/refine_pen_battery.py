#!/usr/bin/env python3
"""The Pen's edges, measured off the device: Snap's reach, an overshoot, Smoothing, tiny loops.

    tools/refine_pen_battery.py [--pbn .build/release/pbn] [--out <dir>]

Writes the Tool Guide's practice picture (`pbn practice`) and replays batteries of finger strokes
on it with `pbn refine` (Sources/pbn/Refine.swift's gestures.json): a cloud ending 0 to 20 points
short of its start and past it, Snap on and off; a chord of the moon ending short of and past its
outline; a wobbly stroke at Smoothing 0, 0.5 and 1 (then measures how far each line strays); a
line that doubles back, a figure eight, tiny loops, a line edge to edge, a line edge to edge
through the tree and the roof (painting-company row 175), and the Pen page's Try This. Prints what each gesture made
(cells cut, strokes left, pieces recolored, the note). Written for the second Refine audit
(painting-company row 175), where it showed Snap's reach at 3 points and Smoothing at 20 doing
nothing a finger could see; run it after a change to PenAssist, RefineGestures or the editor's
draw, and compare. Needs pbn built (`tools/swift.sh build -c release --static-swift-stdlib`).
"""
import argparse, json, math, os, subprocess, sys

args = argparse.ArgumentParser(description=__doc__.split("\n")[0])
args.add_argument("--pbn", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".build", "release", "pbn"))
args.add_argument("--out", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "refine-pen-battery"))
opts = args.parse_args()
PBN = os.path.abspath(opts.pbn)
S = os.path.abspath(opts.out)
PR = os.path.join(S, "practice")
os.makedirs(PR, exist_ok=True)
for scene in ("inked", "painted"):
    subprocess.run([PBN, "practice", scene, "--out", os.path.join(PR, scene)], check=True, capture_output=True)
W,H=960.0,720.0   # the picture on screen, points (1200x900 at width 960)
def pt(x,y): return [x/W, y/H]   # screen points -> normalized
def loop(cx,cy,r,gap_pt,n=40,over=0):
    # a loop starting at angle 0, going round, ending gap_pt short of the start (or over past it)
    pts=[]; circ=2*math.pi*r; end_angle=2*math.pi*(1-gap_pt/circ)+2*math.pi*(over/circ)
    for k in range(n+1):
        a=end_angle*k/n; pts.append(pt(cx+r*math.cos(a), cy+r*math.sin(a)))
    return pts
def wobbly(x0,y0,x1,y1,amp,n=120,period=14.0):
    pts=[]
    L=math.hypot(x1-x0,y1-y0); ux,uy=(x1-x0)/L,(y1-y0)/L; nx,ny=-uy,ux
    for k in range(n+1):
        t=k/n; s=t*L; w=amp*math.sin(2*math.pi*s/period)
        pts.append(pt(x0+ux*s+nx*w, y0+uy*s+ny*w))
    return pts
def line(x0,y0,x1,y1,n=30): return [pt(x0+(x1-x0)*k/n, y0+(y1-y0)*k/n) for k in range(n+1)]
# The moon on screen: center (1.04*720, 0.2*720)=(748.8,144), r=54 pt. Crown: (216,511), r 61.
runs={}
g=[]
for snap in (True,False):
    for gap in (0,2,4,6,8,12,20):
        g.append({"tool":"pen","points":loop(300,150,60,gap),"inked":True,"snap":snap,"caption":f"cloud, end {gap} pt short of start, snap {'on' if snap else 'off'}"})
        g.append({"tool":"undo"})
    for over in (6,15):
        g.append({"tool":"pen","points":loop(300,150,60,0,over=over),"inked":True,"snap":snap,"caption":f"cloud, end {over} pt past start (crossing), snap {'on' if snap else 'off'}"})
        g.append({"tool":"undo"})
runs['cloud']=g
g=[]
for snap in (True,False):
    for gap in (0,2,3,4,6,10):
        # a chord of the moon: from the left of its outline to the right, ends `gap` pt short of the outline inside the moon
        r=54-gap; g.append({"tool":"pen","points":line(748.8-r,144,748.8+r,144),"inked":True,"snap":snap,"caption":f"moon chord, ends {gap} pt short of the outline, snap {'on' if snap else 'off'}"})
        g.append({"tool":"undo"})
    for over in (2,6,15):
        r=54+over; g.append({"tool":"pen","points":line(748.8-r,144,748.8+r,144),"inked":True,"snap":snap,"caption":f"moon chord, ends {over} pt past the outline, snap {'on' if snap else 'off'}"})
        g.append({"tool":"undo"})
runs['chord']=g
g=[]
for amp in (2,4,8):
    for sm in (0,0.5,1):
        g.append({"tool":"pen","points":wobbly(100,120,600,100,amp),"inked":True,"smoothing":sm,"caption":f"wobble ±{amp} pt, smoothing {sm}"})
        g.append({"tool":"undo"})
runs['smoothing']=g
g=[
 {"tool":"pen","points":line(100,80,500,80)+line(500,80,100,80)[1:],"inked":True,"caption":"out and straight back over itself"},
 {"tool":"undo"},
 {"tool":"pen","points":[pt(400+30*math.cos(a)*math.cos(a*2), 150+30*math.sin(a)) for a in [k*2*math.pi/60 for k in range(61)]],"inked":True,"caption":"a figure eight"},
 {"tool":"undo"},
 {"tool":"pen","points":loop(500,100,5,0),"inked":True,"caption":"tiny loop, 5 pt radius"},
 {"tool":"undo"},
 {"tool":"pen","points":loop(500,100,12,0),"inked":True,"caption":"small loop, 12 pt radius"},
 {"tool":"undo"},
 {"tool":"pen","points":loop(500,100,20,0),"inked":True,"caption":"loop, 20 pt radius"},
 {"tool":"undo"},
 {"tool":"pen","points":line(0,120,960,100),"inked":True,"caption":"edge to edge across the sky, ink only"},
 {"tool":"undo"},
 {"tool":"pen","points":line(0,120,960,100),"caption":"edge to edge across the sky, Color from Photo"},
 {"tool":"undo"},
 {"tool":"pen","points":line(0,520,220,480)+line(220,480,420,540)[1:]+line(420,540,650,540)[1:]+line(650,540,760,560)[1:],"snap":False,"caption":"from the left edge through the crown and across the roof, ending in grass; Color from Photo"},
 {"tool":"undo"},
 {"tool":"pen","points":line(0,520,220,480)+line(220,480,420,540)[1:]+line(420,540,650,540)[1:]+line(650,540,760,560)[1:],"snap":False,"inked":True,"caption":"the same line, ink only"},
 {"tool":"undo"},
 {"tool":"pen","points":line(700,100,800,190),"caption":"across the moon, Color from Photo (the page's Try This)"},
 {"tool":"undo"},
 {"tool":"pen","points":loop(300,150,60,0),"caption":"cloud closed, Color from Photo"},
]
runs['misc']=g
for name,gs in runs.items():
    for scene in (['inked'] if name!='misc' else ['inked','painted']):
        out=f"{S}/{name}-{scene}"
        json.dump({"screen":{"width":960},"gestures":gs},open(f"{S}/{name}.json","w"))
        r=subprocess.run([PBN,"refine",f"{PR}/{scene}/photo.ppm",f"{S}/{name}.json","--template",f"{PR}/{scene}/template.pbnt","--out",out,"--no-steps"],capture_output=True,text=True)
        if r.returncode: print(name,scene,"FAILED",r.stderr[-500:]); continue
        rep=json.load(open(out+"/refine.json"))
        print(f"\n== {name} on {scene}: {rep['regions']} areas {rep['palette']} paints valid={rep['valid']}")
        for s in rep['steps']:
            if s['tool']=='undo': continue
            keys=['verdict','regionsSplit','strokes','recolored','paintsAdded','joins','tooSmall','toast']
            print(" -",s.get('caption'),"|"," ".join(f"{k}={s.get(k)}" for k in keys if s.get(k) not in (None,0,False,'')))

# Smoothing: how far each steadied line strays from the straight line between its ends.
rep = json.load(open(f"{S}/smoothing-inked/refine.json"))
u = 1200 / 960
print("\n== smoothing, measured (points on screen)")
for s in rep["steps"]:
    if s["tool"] != "pen":
        continue
    pts = s["edit"]["points"]; (x0, y0), (x1, y1) = pts[0], pts[-1]
    L = math.hypot(x1 - x0, y1 - y0); ux, uy = (x1 - x0) / L, (y1 - y0) / L
    dev = [abs(-uy * (x - x0) + ux * (y - y0)) / u for x, y in pts]
    length = sum(math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]) for k in range(len(pts) - 1)) / u
    print(f" - {s['caption']:28} points={len(pts):3} strays at most {max(dev):5.2f}, on average {sum(dev) / len(dev):5.2f}; length {length:6.1f} (straight {L / u:.1f})")
