#!/usr/bin/env python3
"""카메라 확인 시험용 전광판 그림을 만든다.

    python3 scripts/make_test_boards.py

JapanTransitTests/Boards/ 에 그림(PNG), 정답표(cases.json), 화면에 띄워 놓고
아이폰 카메라로 비춰 볼 모음 페이지(index.html)를 쓴다.
같은 그림을 RouteBoardOCRTests 가 글자 인식 → 판정까지 돌려 정답과 맞춰 본다.

그림마다 맨 윗줄(先発)이 판정을 정한다: 앱도 전광판의 첫 줄을 다음 열차로 본다.
그림에는 역 이름을 행선지 칸에만 쓴다. 노선 이름(浅草線 등)에 역 이름이 들어 있으면
판정이 그 글자를 읽어 버리므로 머리줄에도 쓰지 않는다.
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "JapanTransitTests", "Boards")
FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"

# 열차 종류 칸 색 (일본 역 전광판에서 흔한 색)
KIND = {
    "各停": "#FFFFFF", "普通": "#FFFFFF", "快速": "#FF6A2B", "中央特快": "#2E7BFF",
    "青梅特快": "#2EB872", "急行": "#FF3B3B", "特急": "#FF3B3B", "エアポート快特": "#FF8A00",
    "内回り": "#9ACD32", "外回り": "#9ACD32", "": "#FFFFFF",
}

# 경로 · 전광판 줄(종류, 시각, 행선지, 칸 수) · 맨 윗줄의 정답 · 무엇을 시험하나
CASES = [
    dict(id="01-chuo-tokkai", frm="新宿", to="八王子", line="#F15A22", track=8,
         rows=[("中央特快", "23:05", "高尾", "10両"), ("快速", "23:09", "豊田", "10両"), ("快速", "23:12", "青梅", "10両")],
         expect="board", matched="高尾", problem=2,
         why="中央特快는 하치오지에 서요. 빠른 열차를 타도 되는 경우"),
    dict(id="02-chuo-branch", frm="新宿", to="八王子", line="#F15A22", track=8,
         rows=[("快速", "23:12", "青梅", "10両"), ("中央特快", "23:18", "高尾", "10両"), ("快速", "23:21", "八王子", "10両")],
         expect="wrong", matched="青梅", problem=3,
         why="青梅行은 다치카와에서 갈라져 하치오지에 가지 않아요"),
    dict(id="03-chuo-short", frm="新宿", to="八王子", line="#F15A22", track=8,
         rows=[("快速", "23:41", "立川", "10両"), ("快速", "23:52", "高尾", "10両"), ("快速", "0:04", "武蔵小金井", "10両")],
         expect="short", matched="立川", problem=1,
         why="立川에서 끝나는 열차라 하치오지까지 가지 않아요"),
    dict(id="04-chuo-skip", frm="新宿", to="西荻窪", line="#F15A22", track=8,
         rows=[("中央特快", "23:05", "高尾", "10両"), ("快速", "23:09", "豊田", "10両"), ("快速", "23:12", "青梅", "10両")],
         expect="skip", matched="西荻窪", problem=2,
         why="中央特快는 니시오기쿠보를 지나쳐요"),
    dict(id="05-chuo-paid", frm="新宿", to="八王子", line="#F15A22", track=10,
         rows=[("特急", "23:00", "あずさ 松本", "12両"), ("中央特快", "23:05", "高尾", "10両"), ("快速", "23:09", "豊田", "10両")],
         expect="skip", matched="新宿", problem=2,
         why="특급 あずさ는 특급권이 있어야 해요. 일반 표로는 못 타요"),
    dict(id="06-fukutoshin-express", frm="渋谷", to="北参道", line="#9C5E31", track=3,
         rows=[("急行", "18:02", "和光市", "10両"), ("各停", "18:05", "川越市", "10両"), ("各停", "18:09", "和光市", "8両")],
         expect="skip", matched="北参道", problem=2,
         why="急行는 기타산도를 지나쳐요. 各停를 타야 해요"),
    dict(id="07-fukutoshin-local", frm="渋谷", to="北参道", line="#9C5E31", track=3,
         rows=[("各停", "18:05", "川越市", "10両"), ("急行", "18:09", "和光市", "10両"), ("各停", "18:12", "和光市", "8両")],
         expect="board", matched="川越市", problem=1,
         why="다른 회사 노선(도부선) 끝까지 가는 各停. 낯선 행선지여도 타요"),
    dict(id="08-asakusa-junction", frm="新橋", to="西馬込", line="#E85298", track=2,
         rows=[("エアポート快特", "12:14", "羽田空港", "8両"), ("普通", "12:18", "西馬込", "8両"), ("普通", "12:24", "三崎口", "8両")],
         expect="wrong", matched="羽田空港", problem=3,
         why="羽田空港行은 센가쿠지에서 게이큐선으로 갈라져 니시마고메에 가지 않아요"),
    dict(id="09-chiyoda-through", frm="表参道", to="代々木上原", line="#00BB85", track=2,
         rows=[("急行", "09:31", "唐木田", "10両"), ("各停", "09:35", "代々木上原", "10両"), ("各停", "09:39", "本厚木", "10両")],
         expect="board", matched="唐木田", problem=1,
         why="오다큐선까지 가는 열차. 지요다선 안에서는 모든 역에 서요"),
    dict(id="10-fukuoka-branch", frm="fukuoka/天神", to="fukuoka/博多", line="#F07E19", track=1,
         rows=[("普通", "10:02", "貝塚", "6両"), ("普通", "10:05", "福岡空港", "6両"), ("普通", "10:09", "貝塚", "6両")],
         expect="wrong", matched="貝塚", problem=3,
         why="貝塚行은 나카스카와바타에서 하코자키선으로 갈라져요"),
    dict(id="11-fukuoka-airport", frm="fukuoka/天神", to="fukuoka/博多", line="#F07E19", track=1,
         rows=[("普通", "10:05", "福岡空港", "6両"), ("普通", "10:09", "貝塚", "6両"), ("普通", "10:12", "福岡空港", "6両")],
         expect="board", matched="福岡空港", problem=1,
         why="福岡空港行은 하카타에 서요"),
    dict(id="12-yamanote-inner", frm="品川", to="田町", line="#9ACD32", track=2,
         rows=[("内回り", "07:41", "東京・上野方面", "11両"), ("内回り", "07:44", "東京・上野方面", "11両")],
         expect="board", matched="内回り", problem=1,
         why="순환선은 内回り · 外回り 글자로 방향을 정해요"),
    dict(id="13-yamanote-outer", frm="品川", to="田町", line="#9ACD32", track=1,
         rows=[("外回り", "07:42", "渋谷・新宿方面", "11両"), ("外回り", "07:45", "渋谷・新宿方面", "11両")],
         expect="wrong", matched="外回り", problem=1,
         why="外回り는 반대쪽으로 도는 열차예요"),
    dict(id="14-front-fukutoshin", frm="渋谷", to="北参道", line="#9C5E31", front=True,
         rows=[("急行", "", "和光市", "")],
         expect="skip", matched="北参道", problem=2,
         why="열차 앞 표시. 急行는 기타산도를 지나쳐요"),
    dict(id="15-front-chuo", frm="新宿", to="八王子", line="#F15A22", front=True,
         rows=[("快速", "", "青梅", "")],
         expect="wrong", matched="青梅", problem=3,
         why="열차 앞 표시. 青梅行은 다치카와에서 갈라져요"),
]

EXPECT_KO = {"board": "타세요", "wrong": "반대 방향", "skip": "타지 마세요", "short": "여기까지 안 가요"}


def font(size):
    return ImageFont.truetype(FONT, size)


def text_w(draw, text, f):
    return draw.textbbox((0, 0), text, font=f)[2]


def board(case):
    """역 천장의 발차 안내판: 짙은 바탕에 흰 글씨, 열차 종류는 색 칸.
    칸은 종류 · 시각 · 행선지 · 칸 수. 글자가 칸을 넘으면 줄여서 넣는다."""
    W, H = 1800, 760
    KIND_X, KIND_W, TIME_X, DEST_X = 40, 500, 600, 880
    im = Image.new("RGB", (W, H), "#0B1020")
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, W, 16), fill=case["line"])
    d.text((40, 40), "発車案内", font=font(46), fill="#FFFFFF")
    track = f"{case['track']}番線"
    d.text((W - 40 - text_w(d, track, font(46)), 40), track, font=font(46), fill="#FFD400")
    for t, x in [("種別", KIND_X), ("時刻", TIME_X), ("行先", DEST_X), ("両数", W - 170)]:
        d.text((x, 130), t, font=font(32), fill="#8A93A8")
    d.line((30, 182, W - 30, 182), fill="#2A3350", width=3)
    y = 210
    for i, (kind, time, dest, cars) in enumerate(case["rows"]):
        size = 84 if i == 0 else 64
        h = 150 if i == 0 else 120
        color = KIND.get(kind, "#FFFFFF")
        dark = color in ("#FFFFFF", "#9ACD32")
        ks = size
        while text_w(d, kind, font(ks)) > KIND_W - 40:
            ks -= 2
        box_w = max(text_w(d, kind, font(ks)) + 40, 220)
        d.rounded_rectangle((KIND_X, y + 12, KIND_X + box_w, y + h - 18), radius=10, fill=color)
        d.text((KIND_X + 20, y + (h - ks) // 2 - 6), kind, font=font(ks), fill="#0B1020" if dark else "#FFFFFF")
        d.text((TIME_X, y + (h - size) // 2 - 6), time, font=font(size - 8), fill="#FFFFFF")
        d.text((DEST_X, y + (h - size) // 2 - 8), dest, font=font(size), fill="#FFFFFF")
        cf = font(size - 24)
        d.text((W - 40 - text_w(d, cars, cf), y + (h - size) // 2 + 4), cars, font=cf, fill="#C9CFDB")
        y += h
        d.line((30, y, W - 30, y), fill="#1C2440", width=2)
    return im


def front(case):
    """열차 앞 위쪽의 행선 표시기: 검은 판에 주황 종류, 흰 행선지."""
    W, H = 1600, 900
    im = Image.new("RGB", (W, H), case["line"])
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((120, 60, W - 120, H - 60), radius=60, fill="#D9DDE3")
    d.rounded_rectangle((260, 140, W - 260, 420), radius=18, fill="#050505")
    kind, _, dest, _ = case["rows"][0]
    d.text((310, 205), kind, font=font(120), fill="#FF8A1E")
    d.text((310 + text_w(d, kind, font(120)) + 70, 205), dest, font=font(120), fill="#FFFFFF")
    d.rounded_rectangle((300, 520, 660, 700), radius=24, fill="#30343B")
    d.rounded_rectangle((W - 660, 520, W - 300, 700), radius=24, fill="#30343B")
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = []
    for case in CASES:
        im = front(case) if case.get("front") else board(case)
        im.save(os.path.join(OUT, case["id"] + ".png"), optimize=True)
        manifest.append({
            "id": case["id"], "from": case["frm"], "to": case["to"],
            "expect": case["expect"], "matched": case["matched"], "problem": case["problem"],
            "why": case["why"],
            # 판정에 들어가는 글자: 그림의 각 줄을 왼쪽부터 띄어 쓴 것 (글자 인식 없이 판정만 시험)
            "rows": [" ".join(x for x in r if x) for r in case["rows"]],
        })
    with open(os.path.join(OUT, "cases.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    write_gallery(manifest)
    print(f"{len(manifest)}장 → {OUT}")


def write_gallery(manifest):
    """화면에 띄워 놓고 아이폰으로 비추는 모음 페이지. 그림을 누르면 화면 가득."""
    names = {"新宿": "신주쿠", "八王子": "하치오지", "西荻窪": "니시오기쿠보", "渋谷": "시부야", "北参道": "기타산도",
             "新橋": "신바시", "西馬込": "니시마고메", "表参道": "오모테산도", "代々木上原": "요요기우에하라",
             "fukuoka/天神": "후쿠오카 덴진", "fukuoka/博多": "하카타", "品川": "시나가와", "田町": "다마치"}
    color = {"board": "#1E9E5A", "wrong": "#D6333F", "skip": "#D6333F", "short": "#D6333F"}
    cards = "\n".join(f"""  <figure>
    <img src="{c['id']}.png" alt="{c['why']}" onclick="this.requestFullscreen?.()">
    <figcaption>
      <b>{names.get(c['from'], c['from'])} → {names.get(c['to'], c['to'])}</b>
      <span class="v" style="background:{color[c['expect']]}">{EXPECT_KO[c['expect']]}</span>
      <small>문제 {c['problem']} · {c['why']}</small>
    </figcaption>
  </figure>""" for c in manifest)
    html = f"""<!doctype html>
<html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>전광판 시험</title>
<style>
  :root {{ color-scheme: light dark; --bg:#F4F1EA; --card:#fff; --ink:#1A2233; --soft:#5D6678; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg:#0E131E; --card:#182030; --ink:#ECEEF3; --soft:#A3ABBB; }} }}
  body {{ margin:0; padding:24px 16px; background:var(--bg); color:var(--ink); font:15px/1.5 -apple-system,sans-serif; }}
  main {{ max-width:1200px; margin:auto; }}
  h1 {{ font-size:22px; margin:0 0 4px; }} p {{ color:var(--soft); margin:0 0 20px; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(340px,1fr)); gap:16px; }}
  figure {{ margin:0; background:var(--card); border-radius:16px; overflow:hidden; }}
  img {{ width:100%; display:block; cursor:zoom-in; background:#000; }}
  img:fullscreen {{ object-fit:contain; cursor:zoom-out; }}
  figcaption {{ padding:12px 14px; display:grid; gap:4px; }}
  .v {{ justify-self:start; color:#fff; font-weight:700; font-size:13px; padding:2px 10px; border-radius:99px; }}
  small {{ color:var(--soft); }}
</style>
<main>
<h1>전광판 시험</h1>
<p>앱에서 위 경로를 찾고 '승강장에서 열차 비춰 보기'를 누른 뒤, 그림을 눌러 화면 가득 띄우고 아이폰으로 비추세요. 색 딱지가 앱이 내야 할 답이에요.</p>
<div class="grid">
{cards}
</div>
</main>
</html>
"""
    with open(os.path.join(OUT, "index.html"), "w") as f:
        f.write(html)


if __name__ == "__main__":
    main()
