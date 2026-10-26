#!/usr/bin/env python3
"""App Store 크리에이티브 자산(제품 페이지 헤더 · 검색 결과) 생성: HTML → 헤드리스 Chrome.

사용법: python3 scripts/make_creative_assets.py [언어 ...]     (없으면 전부)

자리
  docs/screenshots/creative/<스토어 로케일>/header.png   3840x1646  제품 페이지 맨 위
  docs/screenshots/creative/<스토어 로케일>/search.png   3840x2560  검색 결과 (없으면 스크린샷이 대신 보인다)

⚠️ 안전 영역 밖은 기기에 따라 잘린다. 글은 **반드시** 안전 영역 안에 둔다(배경 · 기기 그림은 넘쳐도 된다).
   수치는 Apple 공식 PSD 템플릿에서 잰 값이다(https://developer.apple.com/app-store/asset-best-practices/).
   아이폰에서 헤더는 가운데만 남고, 검색 결과는 약 385pt 폭으로 줄어 보인다. 그래서 글이 크다.

⚠️ 가격 · 할인 · 주소(URL) · 수상 · 다른 플랫폼 이름은 넣지 않는다(Apple 가이드).
"""
import os, signal, subprocess, sys, pathlib, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
# 기기 화면 재료: 마케팅 스크린샷과 같은 원본(docs/screenshots/raw/<로케일>/).
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots" / "creative"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# (가로, 세로, 안전 영역 left, top, right, bottom)
SPEC = {
    "header": (3840, 1646, (1097, 493, 2743, 1154)),
    "search": (3840, 2560, (836, 765, 3004, 1795)),
}

# 문구: 헤더는 한 가지 약속(소개 페이지 첫 문장과 같은 말), 검색 결과는 스크린샷 1장과 같은 이야기.
#   header: [눈썹글, 헤드라인] · search: [눈썹글, 헤드라인, 보조 한 줄]. 눈썹글은 검색창에 칠 말.
LOCALES = ["ko"]
COPY = {
    "ko": {
        "header": ("일본 지하철 여행", "이 열차, 타도 될까요?"),
        "search": ("일본 지하철 길찾기", "가고 싶은 곳만<br>찾으세요", "내릴 역과 타는 방면을 표지판 그대로"),
    },
}


def copy(lang, kind):
    return COPY[lang][kind]


# 노선 색(장식): 2호선 · 4호선 · 공항철도 · 1호선 · 3호선
LINES = ["#00A84D", "#00A5DE", "#0090D2", "#0052A4", "#EF7C1C"]

# ⚠️ 바탕 · 글자색은 앱 · 소개 페이지 팔레트(docs/style.css, KORATheme)와 같다: 태극 빨강 #CD2E3A.
BASE_CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:#F4F1EA; position:relative; -webkit-font-smoothing:antialiased;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", sans-serif; }
body:lang(ja) { font-family:-apple-system, "Hiragino Sans", sans-serif; }
body:lang(zh-Hans) { font-family:-apple-system, "PingFang SC", sans-serif; }
body:lang(zh-Hant) { font-family:-apple-system, "PingFang TC", sans-serif; }
body:lang(th) { font-family:-apple-system, "Thonburi", sans-serif; }
.glow { position:absolute; border-radius:50%%; filter:blur(170px); pointer-events:none; }
.text { position:absolute; display:flex; flex-direction:column; justify-content:center; }
.eyebrow { font-weight:700; color:#345698; letter-spacing:-0.01em; line-height:1.15; }
.headline { font-weight:800; color:#1A2233; letter-spacing:-0.02em; line-height:1.2; text-wrap:balance; }
.sub { font-weight:500; color:#5D6678; letter-spacing:-0.01em; line-height:1.4; text-wrap:balance; }
:lang(ja) .headline, :lang(zh) .headline, :lang(ja) .eyebrow, :lang(zh) .eyebrow { letter-spacing:.01em; }
:lang(ko) .headline, :lang(ko) .sub, :lang(ko) .eyebrow { word-break:keep-all; }
.phone { position:absolute; background:#17171a; border:6px solid #3a3a3e;
  box-shadow:0 60px 160px rgba(28,24,23,.22); }
.phone img { display:block; width:100%%; }
svg.map { position:absolute; left:0; top:0; }
"""

# 글이 상자를 넘지 않을 때까지 줄인다. 잘리는 글은 없다 - 끝까지 안 맞으면 표시하고 멈춘다.
FIT_JS = """
<script>
// 문구에 적은 줄(<br>)보다 더 쪼개지면 "Rispondi / con un / tocco" 처럼 읽기가 끊긴다.
// 적은 줄 수를 지킬 때까지 줄인다.
function lines(el) {
  return Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight));
}
function fit(box, el, max, min) {
  const want = el.querySelectorAll('br').length + 1;
  let size = max;
  el.style.fontSize = size + 'px';
  while (size > min && (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 ||
         lines(el) > want)) {
    size -= 4; el.style.fontSize = size + 'px';
  }
  if (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 || lines(el) > want)
    document.body.dataset.overflow = '1';
}
document.fonts.ready.then(() => {
  const box = document.querySelector('.text');
  const h = document.querySelector('.headline');
  fit(box, h, +h.dataset.max, +h.dataset.min);
  document.body.dataset.done = '1';
});
</script>
"""


TMP = pathlib.Path(tempfile.gettempdir()) / "japantransit-creative"
# ⚠️ 프로필을 따로 쓴다. 기본 프로필을 다른 Chrome 과 같이 쓰면 잠금에 걸려 멈춘다.
PROFILE = TMP / "chrome-profile"


def phone(lang, img, left, top, width, rotate=0):
    pad = round(width * 0.04)
    src = (RAW / lang / img).as_uri()
    return (f'<div class="phone" style="left:{left}px;top:{top}px;width:{width}px;padding:{pad}px;'
            f'border-radius:{round(width * 0.19)}px;transform:rotate({rotate}deg)">'
            f'<img src="{src}" style="border-radius:{round(width * 0.155)}px"></div>')


def metro(W, H, paths):
    """노선도처럼 꺾인 굵은 선과 역 동그라미(장식). 글 뒤에 깔리므로 옅게."""
    out = []
    for color, pts in paths:
        d = " ".join(f"{x},{y}" for x, y in pts)
        out.append(f'<polyline points="{d}" fill="none" stroke="{color}" stroke-width="34" '
                   f'stroke-linecap="round" stroke-linejoin="round" opacity=".22"/>')
        for x, y in pts[1:-1]:
            out.append(f'<circle cx="{x}" cy="{y}" r="30" fill="#F4F1EA" stroke="{color}" stroke-width="14" opacity=".5"/>')
    return f'<svg class="map" width="{W}" height="{H}">{"".join(out)}</svg>'


def search_html(lang):
    W, H, (l, t, r, b) = SPEC["search"]
    eyebrow, headline, sub = copy(lang, "search")
    sw, sh = r - l, b - t
    col = int(sw * 0.58)
    x = l + col + 40
    deco = metro(W, H, [(LINES[0], [(-40, 2350), (420, 2350), (700, 2070), (1400, 2070)]),
                        (LINES[1], [(3400, -40), (3400, 300), (3600, 500), (3900, 500)])])
    return f"""
{deco}
<div class="glow" style="left:{x - 200}px;top:500px;width:1800px;height:1800px;background:rgba(52,86,152,.12)"></div>
{phone(lang, "route.png", x + 680, t - 300, 820, 7)}
{phone(lang, "place.png", x + 110, t - 200, 860, -4)}
<div class="text" style="left:{l}px;top:{t}px;width:{col}px;height:{sh}px">
  <div class="eyebrow" style="font-size:92px">{eyebrow}</div>
  <div class="headline" data-max="220" data-min="120" style="margin-top:40px">{headline}</div>
  <div class="sub" style="font-size:78px;margin-top:56px">{sub}</div>
</div>"""


def header_html(lang):
    W, H, (l, t, r, b) = SPEC["header"]
    eyebrow, headline = copy(lang, "header")
    sw, sh = r - l, b - t
    deco = metro(W, H, [(LINES[2], [(-40, 160), (1000, 160), (1180, 340), (1180, 420)]),
                        (LINES[4], [(3900, 1500), (2900, 1500), (2700, 1300), (2700, 1250)])])
    return f"""
{deco}
<div class="glow" style="left:{l - 200}px;top:{t - 400}px;width:{sw + 400}px;height:{sh + 800}px;background:rgba(52,86,152,.10)"></div>
{phone(lang, "route.png", 330, 330, 640, -8)}
{phone(lang, "place.png", 2870, 330, 640, 8)}
<div class="text" style="left:{l}px;top:{t}px;width:{sw}px;height:{sh}px;align-items:center;text-align:center">
  <div class="eyebrow" style="font-size:76px">{eyebrow}</div>
  <div class="headline" data-max="200" data-min="110" style="margin-top:28px">{headline}</div>
</div>"""


def html_lang(lang):
    return "en" if lang in ("en-US", "en-GB") else lang


def chrome(args, log, done, timeout=300):
    """헤드리스 Chrome 을 띄우고 done() 이 참이 되면 끈다.
    ⚠️ 이 맥에서는 Chrome 이 일을 다 하고도 끝나지 않고 매달려 있는 일이 있다(업데이터 자식 프로세스).
       그래서 끝나기를 기다리지 않고 결과(DOM 출력·PNG 파일)가 나오면 프로세스 묶음을 통째로 끈다."""
    TMP.mkdir(exist_ok=True)
    with open(log, "w") as out:
        proc = subprocess.Popen([CHROME, "--headless=new", f"--user-data-dir={PROFILE}", "--no-first-run",
                                 "--disable-component-update", *args],
                                stdout=out, stderr=subprocess.DEVNULL, start_new_session=True)
        ok = False
        end = time.time() + timeout
        while time.time() < end:
            time.sleep(1)
            if done():
                ok = True
                break
            if proc.poll() is not None:
                # 빨리 끝난 Chrome — done() 이 여러 번 확인하는 조건(파일 크기 안정)이면 몇 번 더 본다.
                for _ in range(4):
                    ok = done()
                    if ok:
                        break
                    time.sleep(0.5)
                break
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            proc.kill()
        # 이 프로필을 쓰는 남은 Chrome 프로세스(렌더러 등)도 끈다
        subprocess.run(["pkill", "-9", "-f", f"--user-data-dir={PROFILE}"], capture_output=True)
        proc.wait()
    return ok


def render(lang, kind):
    W, H, _ = SPEC[kind]
    body = search_html(lang) if kind == "search" else header_html(lang)
    page = (f'<!doctype html><html lang="{html_lang(lang)}"><head><meta charset="utf-8"><style>'
            f'{BASE_CSS % {"W": W, "H": H}}</style></head><body>{body}{FIT_JS}</body></html>')
    html_path = pathlib.Path(tempfile.gettempdir()) / f"japantransit-creative-{lang}-{kind}.html"
    html_path.write_text(page, encoding="utf-8")
    # 글이 끝까지 안 맞으면 그림을 만들지 않는다(잘린 글이 스토어에 올라가는 것보다 낫다).
    flags = [f"--window-size={W},{H}", "--force-device-scale-factor=1", "--disable-gpu",
             "--virtual-time-budget=3000", "--allow-file-access-from-files"]
    dom_txt = TMP / f"{lang}-{kind}.dom"
    chrome(["--dump-dom", *flags, html_path.as_uri()], dom_txt,
           lambda: "</html>" in dom_txt.read_text(errors="ignore"))
    dom = dom_txt.read_text(errors="ignore")
    if 'data-done="1"' not in dom:
        raise SystemExit(f"글 맞추기가 끝나지 않았다: {lang} {kind}")
    if 'data-overflow="1"' in dom:
        raise SystemExit(f"글이 안전 영역을 넘는다: {lang} {kind} - 문구를 줄일 것")
    out_dir = OUT / lang
    out_dir.mkdir(parents=True, exist_ok=True)
    out_png = out_dir / f"{kind}.png"
    out_png.unlink(missing_ok=True)
    sizes = []

    def written():
        sizes.append(out_png.stat().st_size if out_png.exists() else 0)
        return len(sizes) > 2 and sizes[-1] > 0 and sizes[-1] == sizes[-2] == sizes[-3]
    if not chrome([f"--screenshot={out_png}", "--hide-scrollbars", *flags, html_path.as_uri()],
                  TMP / f"{lang}-{kind}.log", written):
        raise SystemExit(f"Chrome 이 그리지 못했다: {out_png}")
    print(f"rendered {out_png}")


if __name__ == "__main__":
    langs = sys.argv[1:] or LOCALES
    for lang in langs:
        if lang not in LOCALES:
            raise SystemExit(f"모르는 로케일: {lang} (아는 것: {', '.join(LOCALES)})")
        for kind in ("header", "search"):
            render(lang, kind)
