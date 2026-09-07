// 크롬 기본 줌 단계와 동일한 단계로 페이지 줌 조정
const STEPS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5];

chrome.runtime.onMessage.addListener((msg, sender) => {
    const tabId = sender.tab && sender.tab.id;
    if (tabId == null || !msg || !msg.dir) return;
    chrome.tabs.getZoom(tabId).then((z) => {
        // 현재 줌과 가장 가까운 단계를 찾아 한 칸 이동
        let nearest = 0;
        for (let i = 1; i < STEPS.length; i++) {
            if (Math.abs(STEPS[i] - z) < Math.abs(STEPS[nearest] - z)) nearest = i;
        }
        const next = Math.min(STEPS.length - 1, Math.max(0, nearest + msg.dir));
        chrome.tabs.setZoom(tabId, STEPS[next]);
    }).catch(() => {});
});
