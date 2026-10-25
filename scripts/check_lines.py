#!/usr/bin/env python3
"""노선 데이터 정리·검사.

  python3 scripts/check_lines.py          # 검사만
  python3 scripts/check_lines.py --fix    # 표기 정리를 파일에 반영

하는 일
1. 표지판 부제를 따로 뺀다: "押上〈スカイツリー前〉" → ja "押上", jaSub "スカイツリー前".
   같은 역이 노선마다 다르게 적혀 환승이 끊기는 것을 막는다.
2. ヶ/ケ 표기 차이를 알린다 (앱은 둘을 같은 역으로 본다).
3. 같은 도시에서 이름은 다른데 300m 안에 있는 역 쌍을 뽑는다: data/transfers.json 에 넣을 환승 후보.
   후보일 뿐이다. 역 안에서 걸어서 갈아탈 수 있는지는 근거를 찾아 확인한 뒤 넣는다.
"""
import glob, json, math, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
FIX = "--fix" in sys.argv
SUB = re.compile(r"^(.*?)[〈<（(](.+?)[〉>）)]$")


def key(ja, region="tokyo"):
    return region + "/" + ja.replace("ヶ", "ケ").replace("ヵ", "カ")


def dist(a, b):
    r = 6371000
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


places = {}
for f in sorted(glob.glob(str(ROOT / "data/lines/*.json"))):
    d = json.load(open(f))
    changed = False
    for s in d["stations"]:
        m = SUB.match(s["ja"])
        if m:
            print(f"부제: {d['id']} {s['code']} {s['ja']} → {m.group(1)} + {m.group(2)}")
            s["ja"], s["jaSub"] = m.group(1), m.group(2)
            em = SUB.match(s.get("en", ""))
            if em:
                s["en"], s["enSub"] = em.group(1).strip(), em.group(2)
            changed = True
        region = d.get("region", "tokyo")
        places.setdefault(key(s["ja"], region), {"names": set(), "pts": [], "lines": set(), "ko": s["ko"], "region": region})
        p = places[key(s["ja"], region)]
        p["names"].add(s["ja"])
        p["pts"].append((s["lat"], s["lng"]))
        p["lines"].add(d["id"])
    # 정차역 목록·행선지도 같은 표기로 (부제를 남기면 "이 역에 안 선다"로 잘못 읽힌다).
    def base(name):
        m = SUB.match(name)
        return m.group(1) if m else name
    for sv in d.get("services", []):
        fixed = [base(x) for x in sv["stops"]]
        if fixed != sv["stops"]:
            print(f"정차역 부제: {d['id']} {sv['id']}")
            sv["stops"], changed = fixed, True
    for part in ("throughTermini", "junctionTermini"):
        block = d.get(part) or {}
        for k, v in block.items():
            if isinstance(v, list) and [base(x) for x in v] != v:
                block[k], changed = [base(x) for x in v], True
    names = {s["ja"] for s in d["stations"]}
    for sv in d.get("services", []):
        for x in sv["stops"]:
            if x not in names:
                print(f"❌ {d['id']} {sv['id']} 정차역 {x} 이 노선에 없음")
    if changed and FIX:
        json.dump(d, open(f, "w"), ensure_ascii=False, indent=2)
        open(f, "a").write("\n")

for k, p in places.items():
    if len(p["names"]) > 1:
        print(f"표기 차이(같은 역으로 봄): {' / '.join(sorted(p['names']))}  {sorted(p['lines'])}")

print("\n환승 후보 (이름 다름, 300m 이내):")
items = list(places.items())
for i, (ka, a) in enumerate(items):
    for kb, b in items[i + 1:]:
        if a["region"] != b["region"]:
            continue
        d = min(dist(x, y) for x in a["pts"] for y in b["pts"])
        if d <= 300:
            print(f"  {ka}({a['ko']}) {sorted(a['lines'])}  ↔  {kb}({b['ko']}) {sorted(b['lines'])}  {int(d)}m")
