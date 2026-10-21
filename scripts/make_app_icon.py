#!/usr/bin/env python3
"""앱 아이콘 생성기: 남색 바탕에 흰 열차 정면, 행선지 표시판만 빨강.

  python3 scripts/make_app_icon.py

KORA(한국길찾기)의 아이콘과 같은 그림이다. 두 앱이 한 시리즈로 보이도록
모양은 그대로 두고 색만 바꾼다 (KORA = 코랄, 일본길찾기 = 남색).
모양을 고치면 KORA 의 scripts/make_app_icon.py 도 같이 고친다.

출력: JapanTransit/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024, 모서리 없음, 투명 없음)
      docs/icon.png (웹사이트용 같은 그림)
iOS 가 모서리를 깎으므로 그림은 정사각형 꽉 채워 그린다.
"""
import pathlib
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[1]
S = 4                      # 슈퍼샘플링 배율 (가장자리를 매끄럽게)
N = 1024 * S

TOP = (52, 86, 152)        # 바탕 위쪽
BOTTOM = (30, 56, 112)     # 바탕 아래쪽 (藍色 근처)
WINDOW = (22, 40, 84)      # 앞 유리·전조등
SIGN = (230, 50, 65)       # 행선지 표시판 (앱 강조색 #E63241)
WHITE = (255, 255, 255)


def s(*v):
    return [x * S for x in v]


def main():
    img = Image.new("RGB", (N, N))
    d = ImageDraw.Draw(img)
    for y in range(N):     # 위에서 아래로 은은한 그라데이션
        t = y / (N - 1)
        d.line([(0, y), (N, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))

    # 열차 몸체
    d.rounded_rectangle(s(272, 176, 752, 760), radius=120 * S, fill=WHITE)
    # 행선지 표시판
    d.rounded_rectangle(s(402, 222, 622, 262), radius=20 * S, fill=SIGN)
    # 앞 유리
    d.rounded_rectangle(s(330, 304, 694, 520), radius=48 * S, fill=WINDOW)
    # 전조등
    for cx in (392, 632):
        d.ellipse(s(cx - 38, 610, cx + 38, 686), fill=WINDOW)
    # 다리와 선로
    for x0, x1 in ((392, 330), (632, 694)):
        d.line(s(x0, 740, x1, 852), fill=WHITE, width=44 * S)
        d.ellipse(s(x1 - 22, 830, x1 + 22, 874), fill=WHITE)
    d.rounded_rectangle(s(232, 852, 792, 892), radius=20 * S, fill=WHITE)

    out = img.resize((1024, 1024), Image.LANCZOS)
    out.save(ROOT / "JapanTransit/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    out.save(ROOT / "docs/icon.png")
    print("AppIcon.png, docs/icon.png")


if __name__ == "__main__":
    main()
