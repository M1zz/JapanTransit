#!/usr/bin/env python3
"""docs/ 의 소개·지원·개인정보 페이지를 만든다 (GitHub Pages, 한국어).

    python3 scripts/make_docs.py
"""
from pathlib import Path

BASE = "https://m1zz.github.io/JapanTransit/"
DOCS = Path(__file__).resolve().parent.parent / "docs"
PAGES = [("index.html", "홈"), ("support.html", "지원"), ("privacy.html", "개인정보 처리방침")]


def page(name, title, description, body):
    nav = "\n".join(
        f'    <a href="{n}"' + (' aria-current="page"' if n == name else "") + f">{label}</a>"
        for n, label in PAGES
    )
    return f"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>{title}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{BASE}{'' if name == 'index.html' else name}">
<link rel="alternate" hreflang="ko" href="{BASE}{'' if name == 'index.html' else name}">
<link rel="stylesheet" href="style.css">
<link rel="icon" href="icon.png">
<link rel="apple-touch-icon" href="icon.png">
</head>
<body>
<div class="container">

  <header class="site">
    <img src="icon.png" alt="일본길찾기 앱 아이콘">
    <div>
      <div class="title">일본길찾기</div>
      <div class="subtitle">일본 지하철, 이 열차 타도 될까</div>
    </div>
  </header>

  <nav class="pages" aria-label="페이지">
{nav}
  </nav>

  <main>
{body}
    <div class="contact">
      궁금한 점이나 틀린 역 정보는 <a href="mailto:mizzking75@gmail.com">mizzking75@gmail.com</a> 으로 보내 주세요.
    </div>
  </main>

  <footer class="site">
    © 2026 Leeo · <a href="support.html">지원</a> · <a href="privacy.html">개인정보 처리방침</a>
  </footer>
</div>
</body>
</html>
"""


INDEX = """    <div class="sign">
      <div class="eyebrow">各停 · 急行 · 快速</div>
      <div class="big">일본 지하철에서<br>이 열차 타도 될까요?</div>
    </div>
    <p class="lead">일본 역 전광판에는 내가 내릴 역이 없습니다. 열차 종류와 끝나는 역만 보입니다.
    일본길찾기는 가는 길을 알려 주고, 승강장에서 카메라로 비추면 눈앞의 열차를 타도 되는지 말해 줍니다.</p>

    <h2>할 수 있는 것</h2>
    <div class="card">
      <h3>가고 싶은 곳으로 역 찾기</h3>
      <p>"빅사이트", "센소지"처럼 가고 싶은 곳을 찾으면 내려야 할 역과 걸어가는 시간을 알려 줍니다. 관광지 187곳이 들어 있습니다.</p>
    </div>
    <div class="card">
      <h3>표지판 그대로 길 안내</h3>
      <p>어느 방면 열차를 타는지 역의 표지판에 적힌 그대로 보여 줍니다. 갈아타는 곳, 개찰구 밖으로 나가는 환승, 회사가 바뀌어 요금이 따로 붙는 곳까지 알려 줍니다.</p>
    </div>
    <div class="card">
      <h3>급행 주의</h3>
      <p>내 역을 지나치는 급행, 지정석 요금이 드는 열차, 주말에만 서지 않는 역, 중간에 갈라지는 열차를 미리 알려 줍니다.</p>
    </div>
    <div class="card">
      <h3>카메라로 확인</h3>
      <p>승강장에서 열차 앞 표시나 전광판을 비추면 타도 되는 열차인지 초록과 빨강으로 알려 줍니다. 글자는 기기 안에서만 읽습니다.</p>
    </div>
    <div class="card">
      <h3>지도에서 역 고르기</h3>
      <p>역 이름을 몰라도 지도에서 역과 관광지를 보고 고를 수 있습니다.</p>
    </div>

    <h2>지원 지역</h2>
    <p>도쿄, 요코하마, 오사카, 교토, 고베, 나고야, 후쿠오카, 삿포로, 센다이의 지하철과 주요 JR·사철 59개 노선. 길 안내는 같은 도시 안에서 이어집니다.</p>
"""

SUPPORT = """    <h1>지원</h1>
    <p class="lead">자주 묻는 질문을 먼저 확인해 보세요.</p>

    <div class="card">
      <h3>카메라 확인은 어떻게 쓰나요?</h3>
      <p>경로를 연 뒤 타는 구간의 "승강장에서 열차 비춰 보기"를 누르고, 승강장의 전광판이나 열차 앞의 행선지 표시를 화면에 크게 비춰 주세요.</p>
      <ul>
        <li>초록이면 타도 되는 열차, 빨강이면 반대 방향이거나 내 역에 서지 않는 열차입니다.</li>
        <li>어둡거나 멀거나 비스듬하면 읽기 어렵습니다. 가까이서 정면으로 비춰 보세요.</li>
        <li>결과는 참고용입니다. 헷갈리면 역의 표지판과 안내도 함께 확인해 주세요.</li>
      </ul>
    </div>

    <div class="card">
      <h3>가고 싶은 곳이 어느 역인지 모르겠어요</h3>
      <p>역 고르기 화면에서 관광지 이름을 한국어나 일본어로 찾아보세요. 가까운 역과 걸어가는 시간이 함께 나옵니다. 위쪽의 "지도"로 바꾸면 관광지와 역을 지도에서 함께 볼 수 있습니다.</p>
    </div>

    <div class="card">
      <h3>다른 도시로 가는 길은 안 나와요</h3>
      <p>지금은 같은 도시 안의 지하철과 전철만 잇습니다. 도쿄에서 오사카처럼 신칸센으로 가는 길은 아직 안내하지 않습니다.</p>
    </div>

    <div class="card">
      <h3>시간이 실제와 달라요</h3>
      <p>걸리는 시간은 역 사이 거리로 어림한 값입니다. 실제 시간표와 운행 상황은 역의 안내를 따라 주세요.</p>
    </div>

    <div class="card">
      <h3>왜 위치와 카메라 권한이 필요한가요?</h3>
      <ul>
        <li><strong>위치</strong>: 내 근처 역을 찾을 때만 씁니다.</li>
        <li><strong>카메라</strong>: 전광판과 열차 앞 표시를 읽을 때만 씁니다.</li>
      </ul>
      <p>둘 다 허용하지 않아도 역을 직접 골라 길 안내를 쓸 수 있습니다.</p>
    </div>

    <div class="card">
      <h3>인터넷이 없어도 되나요?</h3>
      <p>네. 노선과 관광지 정보가 앱 안에 들어 있어 길 찾기와 카메라 확인 모두 인터넷 없이 됩니다.</p>
    </div>

    <div class="card">
      <h3>역이나 노선이 없어요</h3>
      <p>역 이름과 노선을 메일로 알려 주시면 다음 업데이트에 반영하겠습니다.</p>
    </div>
"""

PRIVACY = """    <h1>개인정보 처리방침</h1>
    <p class="lead">일본길찾기는 개인정보를 모으지 않습니다.</p>

    <div class="card">
      <h3>모으는 정보</h3>
      <p>없습니다. 회원가입, 광고, 이용 통계가 없고 앱이 인터넷으로 정보를 보내지 않습니다.</p>
    </div>

    <div class="card">
      <h3>위치</h3>
      <p>"내 근처 역"을 누를 때 가까운 역을 찾는 데만 씁니다. 위치는 기기 안에서만 쓰이고 저장하거나 보내지 않습니다.</p>
    </div>

    <div class="card">
      <h3>카메라</h3>
      <p>전광판과 열차 앞 표시의 글자를 읽는 데만 씁니다. 글자 인식은 기기 안에서 이뤄지고 사진이나 영상을 저장하거나 보내지 않습니다.</p>
    </div>

    <div class="card">
      <h3>기기에 남는 것</h3>
      <p>마지막으로 고른 출발역과 도착역, 노선 탭에서 고른 도시만 기기 안에 남습니다. 앱을 지우면 함께 지워집니다.</p>
    </div>

    <div class="card">
      <h3>바뀔 때</h3>
      <p>이 방침이 바뀌면 이 페이지에 먼저 알립니다.</p>
      <p>시행일: 2026년 10월 27일</p>
    </div>
"""

for name, title, desc, body in [
    ("index.html", "일본길찾기", "일본 지하철에서 이 열차를 타도 되는지 카메라로 확인하는 길 안내 앱.", INDEX),
    ("support.html", "지원 · 일본길찾기", "일본길찾기 자주 묻는 질문과 문의 방법.", SUPPORT),
    ("privacy.html", "개인정보 처리방침 · 일본길찾기", "일본길찾기는 개인정보를 모으지 않습니다.", PRIVACY),
]:
    (DOCS / name).write_text(page(name, title, desc, body), encoding="utf-8")
    print("wrote", name)
