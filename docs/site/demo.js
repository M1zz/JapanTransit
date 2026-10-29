// 일본길찾기 웹 체험: 京成上野 승강장의 전광판 한 줄을 비추면 탈지 말지 알려 준다.
// 규칙은 앱과 같다 (RouteSegment.boardJudge → TrainBoardJudge): 행선지가 내 역이거나 그 너머면 같은 방향,
// 열차 종류가 내 역을 지나치면 빨강, 지정석 유료 열차는 일반 표로 못 탄다. 정차역은 data/lines/KS.json 그대로.
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text);
  const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");

  // 게이세이 본선 (京成上野 KS01 → 成田空港 KS42) 중 체험에 쓰는 역. 번호 순서가 곧 방향이다.
  const ST = { "京成上野": [1, "게이세이우에노"], "千住大橋": [5, "센주오하시"], "青砥": [9, "아오토"],
    "京成八幡": [16, "게이세이야와타"], "船橋競馬場": [24, "후나바시케이바조"], "京成津田沼": [26, "게이세이쓰다누마"],
    "京成佐倉": [35, "게이세이사쿠라"], "京成成田": [40, "게이세이나리타"], "成田空港": [42, "나리타 공항"] };
  // 지나치는 열차의 정차역 (KS.json services). 普通은 모든 역에 서서 목록에 없다.
  const STOPS = {
    "スカイライナー": { name: "스카이라이너", paid: true, stops: [] },
    "快速特急": { name: "쾌속특급", stops: ["京成上野", "青砥", "京成八幡", "京成成田", "成田空港"] },
    "アクセス特急": { name: "액세스특급", stops: ["京成上野", "青砥", "成田空港"] },
    "快速": { name: "쾌속", stops: ["京成上野", "千住大橋", "青砥", "京成八幡", "船橋競馬場", "京成佐倉", "京成成田", "成田空港"] },
  };
  const BOARD = [["10:02", "スカイライナー", "成田空港", "sky"], ["10:05", "快速特急", "京成成田", "kt"],
    ["10:09", "アクセス特急", "成田空港", "ac"], ["10:12", "快速", "京成佐倉", "ks"], ["10:16", "普通", "京成津田沼", "lo"]];
  const DESTS = ["千住大橋", "青砥", "京成八幡", "船橋競馬場"];
  const code = ja => `KS${String(ST[ja][0]).padStart(2, "0")}`;
  let dest = "京成八幡";

  root.innerHTML = `
    <div class="jt-side">
      <p class="jt-label">${esc(T.pick)}</p>
      <div class="jt-dests" role="radiogroup" aria-label="${esc(T.pick)}">
        ${DESTS.map(d => `<button type="button" role="radio" class="jt-dest" data-dest="${d}" lang="ja">
          <span class="jt-code">${code(d)}</span><span>${d}<small lang="ko">${ST[d][1]}</small></span></button>`).join("")}
      </div>
      <div class="jt-verdict" aria-live="polite"><strong></strong><p></p></div>
      <p class="muted small">${esc(T.note)}</p>
    </div>
    <div class="jt-board" lang="ja">
      <div class="jt-head">${esc(T.board)}</div>
      ${BOARD.map(([t, type, to, c], i) => `<button type="button" class="jt-row" data-i="${i}">
        <span class="jt-time">${t}</span><span class="jt-type ${c}">${type}</span><span class="jt-to">${to}</span></button>`).join("")}
    </div>`;

  const verdict = root.querySelector(".jt-verdict"), vTitle = verdict.querySelector("strong"), vText = verdict.querySelector("p");
  const fill = (s, v) => s.replace(/\{(\w+)\}/g, (_, k) => v[k]);

  function idle() { verdict.className = "jt-verdict"; vTitle.textContent = T.idle; vText.textContent = ""; }

  function judge(i) {
    const [, type, to] = BOARD[i];
    const v = { dest: to, destKo: ST[to][1], to: ST[dest][1], name: STOPS[type]?.name || "보통" };
    // 행선지가 내 역 이후면 같은 방향 (체험의 모든 열차가 그렇다). 다음은 열차 종류.
    const s = STOPS[type];
    let ok = ST[to][0] >= ST[dest][0], text;
    if (ok && s && !s.stops.includes(dest)) { ok = false; text = fill(s.paid ? T.paidDetail : T.skipDetail, v); }
    else text = fill(T.okDetail, v);
    verdict.className = `jt-verdict ${ok ? "ok" : "no"}`;
    vTitle.textContent = ok ? T.ok : T.skip;
    vText.textContent = text;
    root.querySelectorAll(".jt-row").forEach((r, k) => r.classList.toggle("on", k === i));
    root.dataset.used = "1";
  }

  function pick(d) {
    dest = d;
    root.querySelectorAll(".jt-dest").forEach(b => b.setAttribute("aria-checked", String(b.dataset.dest === d)));
    root.querySelectorAll(".jt-row").forEach(r => r.classList.remove("on"));
    idle();
  }

  root.addEventListener("click", e => {
    const d = e.target.closest(".jt-dest"), r = e.target.closest(".jt-row");
    if (d) pick(d.dataset.dest);
    if (r) judge(+r.dataset.i);
  });
  pick(dest);
})();
