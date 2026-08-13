// Ctrl+휠을 페이지 확대/축소 요청으로 변환 (윈도우 크롬과 동일한 동작)
let last = 0;
window.addEventListener('wheel', (e) => {
    if (!e.ctrlKey) return;
    e.preventDefault();
    const now = Date.now();
    if (now - last < 60) return; // 연속 휠 이벤트 과속 방지
    last = now;
    chrome.runtime.sendMessage({ dir: e.deltaY < 0 ? 1 : -1 });
}, { passive: false, capture: true });
