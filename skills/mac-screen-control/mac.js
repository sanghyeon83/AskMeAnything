// mac-screen-control — 맥 화면 보기·조작 (JXA)
// 사용: osascript -l JavaScript ~/.claude/skills/mac-screen-control/mac.js <동작> [인자...] [--옵션 값]
//
// 좌표는 전부 "포인트"다. 원점은 메인 화면(메뉴막대 있는 화면) 왼쪽 위, y 는 아래로 커진다.
// 메인보다 위·왼쪽에 놓인 모니터는 음수 좌표다. System Events 창 위치, CGWindowList,
// screencapture -R 이 모두 같은 좌표계라서 그대로 섞어 써도 된다.
ObjC.import('AppKit');
ObjC.import('CoreGraphics');
ObjC.import('ApplicationServices');
ObjC.import('stdlib');

const SA = Application.currentApplication();
SA.includeStandardAdditions = true;
const SE = Application('System Events');

// 브리지가 CG 상수를 문자열로 넘길 때가 있어서 숫자로 고정한다.
const EV = { ldown: 1, lup: 2, rdown: 3, rup: 4, move: 5, ldrag: 6 };
const HID_TAP = 0, CLICK_STATE = 1, SCROLL_LINE = 1;

// 키 이름 → 키코드. 글자를 "문자"로 보내면 한글 입력기가 켜져 있을 때 한글로 바뀌므로 키코드로 보낸다.
const KEY = {
  a: 0, s: 1, d: 2, f: 3, h: 4, g: 5, z: 6, x: 7, c: 8, v: 9, b: 11, q: 12, w: 13, e: 14, r: 15,
  y: 16, t: 17, '1': 18, '2': 19, '3': 20, '4': 21, '6': 22, '5': 23, '=': 24, '9': 25, '7': 26,
  '-': 27, '8': 28, '0': 29, ']': 30, o: 31, u: 32, '[': 33, i: 34, p: 35, l: 37, j: 38, "'": 39,
  k: 40, ';': 41, '\\': 42, ',': 43, '/': 44, n: 45, m: 46, '.': 47, '`': 50,
  return: 36, enter: 36, tab: 48, space: 49, delete: 51, backspace: 51, esc: 53, escape: 53,
  forwarddelete: 117, home: 115, end: 119, pageup: 116, pagedown: 121,
  left: 123, right: 124, down: 125, up: 126,
  f1: 122, f2: 120, f3: 99, f4: 118, f5: 96, f6: 97, f7: 98, f8: 100, f9: 101, f10: 109, f11: 103, f12: 111,
};
const MOD = {
  cmd: 'command down', command: 'command down', shift: 'shift down',
  alt: 'option down', opt: 'option down', option: 'option down', ctrl: 'control down', control: 'control down',
};

const USAGE = `mac.js <동작> [인자]
  info                              화면 배치·배율·커서·앞 앱·권한
  windows [걸러낼말]                 보이는 창 (창id·pid·앱·x,y,w,h·제목), 위에 있는 창부터
  front <앱|pid> [창제목일부]         앞으로 세우기 (최소화면 복원)
  ui <앱|pid> [깊이=4] [최대줄=150]   앞 창의 버튼·입력칸 등 요소와 중심 좌표
  capture [--region x,y,w,h | --window 창id | --screen n] [--max 픽셀] [--out 경로]
  click x y [right|double]          클릭
  move x y                          커서 이동
  drag x1 y1 x2 y2                  끌기
  scroll x y 양                     휠 (양수=위로, 음수=아래로)
  cursor                            현재 커서 좌표
  type "글자" [--to 앱]              글자 입력 (클립보드 붙여넣기 방식, 한글 안전, 클립보드는 복원)
  key 조합 [--to 앱]                 단축키: cmd+s, cmd+shift+z, return, esc, tab, down ...`;

class Stop extends Error {}
function fail(msg) { throw new Stop(msg); }
function sh(cmd) { return SA.doShellScript(cmd, { alteringLineEndings: false }); }
function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
function num(v, name) { const n = Number(v); if (v === undefined || v === '' || isNaN(n)) fail(`${name} 에 숫자가 필요하다`); return n; }
function val(dict, k) { const v = dict.objectForKey(k); return v && !v.isNil() ? ObjC.unwrap(v) : undefined; }

function screens() {
  const list = $.NSScreen.screens, mainH = list.objectAtIndex(0).frame.size.height, out = [];
  for (let i = 0; i < list.count; i++) {
    const s = list.objectAtIndex(i), f = s.frame;
    out.push({ n: i + 1, x: f.origin.x, y: mainH - f.origin.y - f.size.height, w: f.size.width, h: f.size.height, scale: s.backingScaleFactor });
  }
  return out;
}

function cursor() {
  const p = $.CGEventGetLocation($.CGEventCreate(null));
  return { x: Math.round(p.x), y: Math.round(p.y) };
}

function frontApp() {
  const p = SE.processes.whose({ frontmost: true })();
  return p.length ? { name: p[0].name(), shown: p[0].displayedName(), pid: p[0].unixId() } : null;
}

function cgWindows() {
  const arr = ObjC.castRefToObject($.CGWindowListCopyWindowInfo(1 | 16, 0)), out = [];  // 화면에 보이는 것만, 바탕화면 제외
  for (let i = 0; i < arr.count; i++) {
    const w = arr.objectAtIndex(i);
    if (val(w, 'kCGWindowLayer') !== 0) continue;
    const b = ObjC.deepUnwrap(w.objectForKey('kCGWindowBounds'));
    out.push({
      id: val(w, 'kCGWindowNumber'), pid: val(w, 'kCGWindowOwnerPID'),
      app: val(w, 'kCGWindowOwnerName') || '', title: val(w, 'kCGWindowName') || '',
      x: b.X, y: b.Y, w: b.Width, h: b.Height,
    });
  }
  return out;
}

// 화면 기록 권한이 없으면 다른 앱 창의 제목이 전부 빠진다.
function canRecord() {
  const ws = cgWindows();
  return ws.length ? ws.some(w => w.title) : null;
}

function info() {
  const L = screens().map(s => `화면${s.n}: 위치 ${s.x},${s.y}  크기 ${s.w}x${s.h}pt  배율 ${s.scale}x${s.n === 1 ? '  (메인·메뉴막대)' : ''}`);
  const c = cursor(), f = frontApp(), rec = canRecord();
  L.push(`커서: ${c.x},${c.y}`);
  L.push(`앞 앱: ${f ? `${f.shown} (프로세스 ${f.name}, pid ${f.pid})` : '없음'}`);
  L.push(`손쉬운 사용(클릭·키 입력): ${$.AXIsProcessTrusted() ? '허용됨' : '꺼짐 — 사용자에게 켜 달라고 한다'}`);
  L.push(`화면 기록(캡처): ${rec === null ? '판단 불가(보이는 창 없음)' : rec ? '허용됨' : '꺼짐 — 사용자에게 켜 달라고 한다'}`);
  return L.join('\n');
}

function windows(filter) {
  const f = (filter || '').toLowerCase();
  const rows = cgWindows().filter(w => !f || w.app.toLowerCase().includes(f) || w.title.toLowerCase().includes(f));
  return ['창id\tpid\t앱\tx,y,w,h\t제목']
    .concat(rows.map(w => `${w.id}\t${w.pid}\t${w.app}\t${w.x},${w.y},${w.w},${w.h}\t${w.title}`)).join('\n');
}

function findProc(target) {
  if (!target) fail('앱 이름이나 pid 가 필요하다');
  const set = SE.processes.whose({ backgroundOnly: false });
  const names = set.name(), shown = set.displayedName(), pids = set.unixId();
  const pick = test => names.map((n, i) => (test(n.toLowerCase(), String(shown[i]).toLowerCase(), pids[i]) ? i : -1)).filter(i => i >= 0);
  let idx;
  if (/^\d+$/.test(target)) idx = pick((n, s, p) => p === Number(target));
  else {
    const t = target.toLowerCase();
    idx = pick((n, s) => n === t || s === t);
    if (!idx.length) idx = pick((n, s) => n.includes(t) || s.includes(t));
  }
  if (!idx.length) fail(`'${target}' 앱을 못 찾음 — windows 로 앱 이름·pid 를 확인할 것`);
  const kinds = [...new Set(idx.map(i => shown[i]))];
  if (kinds.length > 1) fail(`'${target}' 에 여러 앱이 걸림: ${kinds.join(', ')} — 정확한 이름이나 pid 를 줄 것`);
  // 같은 이름 프로세스가 여럿이면(크롬 등) 창이 있는 쪽
  const procs = idx.map(i => SE.processes.whose({ unixId: pids[i] })()[0]);
  return procs.find(p => p.windows.length > 0) || procs[0];
}

function front(target, title) {
  const p = findProc(target);
  p.frontmost = true;
  if (title) {
    const wins = p.windows(), names = p.windows.name();
    const i = names.findIndex(n => String(n || '').includes(title));
    if (i < 0) fail(`제목에 '${title}' 가 든 창이 없음. 창: ${names.join(' | ')}`);
    try { if (wins[i].attributes.byName('AXMinimized').value()) wins[i].attributes.byName('AXMinimized').value = false; } catch (e) {}
    wins[i].actions.byName('AXRaise').perform();
  }
  delay(0.3);
  const f = frontApp();
  if (!f || f.pid !== p.unixId()) fail(`앞으로 못 세움 (지금 앞: ${f ? f.shown : '없음'})`);
  return `앞: ${f.shown} (pid ${f.pid})${title ? `, 창 '${title}'` : ''}`;
}

function walk(el, d, maxD, lines, cap) {
  if (d >= maxD || lines.length >= cap) return;
  let kids, roles, names, descs, pos, sizes;
  try {
    kids = el.uiElements();
    if (!kids.length) return;
    roles = el.uiElements.role(); names = el.uiElements.name(); descs = el.uiElements.description();
    pos = el.uiElements.position(); sizes = el.uiElements.size();
  } catch (e) { return; }
  for (let i = 0; i < kids.length && lines.length < cap; i++) {
    const label = [names[i], descs[i]].filter(v => v && v !== roles[i]).join(' / ');
    const at = pos[i] && sizes[i] ? `  중심 ${Math.round(pos[i][0] + sizes[i][0] / 2)},${Math.round(pos[i][1] + sizes[i][1] / 2)}  (${sizes[i][0]}x${sizes[i][1]})` : '';
    lines.push(`${'  '.repeat(d)}${roles[i]}${label ? ` "${label}"` : ''}${at}`);
    walk(kids[i], d + 1, maxD, lines, cap);
  }
}

function ui(target, depth, limit) {
  const p = findProc(target), wins = p.windows;
  if (!wins.length) fail('창이 없음');
  const w = wins[0], wp = w.position(), ws = w.size(), lines = [`창 "${w.name()}"  ${wp[0]},${wp[1]},${ws[0]},${ws[1]}`];
  const cap = Number(limit || 150);
  walk(w, 1, Number(depth || 4) + 1, lines, cap);
  if (lines.length >= cap) lines.push(`… ${cap}줄에서 자름. 깊이나 최대줄을 조절할 것`);
  return lines.join('\n');
}

function capture(o) {
  const out = o.out || `${ObjC.unwrap($.NSTemporaryDirectory())}mac-shot-${Date.now()}.png`;
  const args = ['-x', '-t', 'png'];
  let ox, oy, wpt;
  if (o.region) {
    const r = String(o.region).split(',').map(Number);
    if (r.length !== 4 || r.some(isNaN)) fail('--region 은 x,y,w,h');
    [ox, oy, wpt] = r;
    args.push('-R', r.join(','));
  } else if (o.window) {
    const w = cgWindows().find(w => String(w.id) === String(o.window));
    if (!w) fail(`창id ${o.window} 없음 (화면에 보이는 창만 된다) — windows 로 확인`);
    ox = w.x; oy = w.y; wpt = w.w;
    args.push('-o', '-l', String(w.id));
  } else {
    const n = Number(o.screen || 1), s = screens()[n - 1];
    if (!s) fail(`화면${n} 없음 — info 로 확인`);
    ox = s.x; oy = s.y; wpt = s.w;
    args.push('-D', String(n));
  }
  sh(`/usr/sbin/screencapture ${args.map(q).join(' ')} ${q(out)}`);
  const size = () => sh(`/usr/bin/sips -g pixelWidth -g pixelHeight ${q(out)}`).match(/pixelWidth: (\d+)[\s\S]*pixelHeight: (\d+)/).slice(1).map(Number);
  let [pw, ph] = size();
  if (o.max && Math.max(pw, ph) > Number(o.max)) { sh(`/usr/bin/sips -Z ${Number(o.max)} ${q(out)}`); [pw, ph] = size(); }
  const k = +(wpt / pw).toFixed(4);
  return `${out}  (${pw}x${ph}px)\n좌표 환산: 화면x = ${ox} + 픽셀x × ${k},  화면y = ${oy} + 픽셀y × ${k}`;
}

function post(type, x, y, button, clicks) {
  const e = $.CGEventCreateMouseEvent(null, type, { x: x, y: y }, button);
  if (clicks) $.CGEventSetIntegerValueField(e, CLICK_STATE, clicks);
  $.CGEventPost(HID_TAP, e);
}
function move(x, y) { post(EV.move, x, y, 0); }
function click(x, y, kind) {
  const r = kind === 'right', btn = r ? 1 : 0, dn = r ? EV.rdown : EV.ldown, up = r ? EV.rup : EV.lup;
  move(x, y); delay(0.05);
  post(dn, x, y, btn, 1); post(up, x, y, btn, 1);
  if (kind === 'double') { delay(0.05); post(dn, x, y, btn, 2); post(up, x, y, btn, 2); }
}
function drag(x1, y1, x2, y2) {
  move(x1, y1); delay(0.05);
  post(EV.ldown, x1, y1, 0, 1);
  for (let i = 1; i <= 20; i++) { post(EV.ldrag, x1 + (x2 - x1) * i / 20, y1 + (y2 - y1) * i / 20, 0); delay(0.01); }
  post(EV.lup, x2, y2, 0, 1);
}
function scroll(x, y, amount) {
  move(x, y); delay(0.05);
  $.CGEventPost(HID_TAP, $.CGEventCreateScrollWheelEvent2(null, SCROLL_LINE, 1, amount, 0, 0));
}

// --to 를 주면 앞 앱이 그 앱일 때만 보낸다. 엉뚱한 창에 입력이 들어가는 사고를 막는다.
function guard(to) {
  if (!to) return;
  const f = frontApp(), t = String(to).toLowerCase();
  if (!f || !(f.name.toLowerCase().includes(t) || String(f.shown).toLowerCase().includes(t)))
    fail(`앞 앱이 '${to}' 가 아니라서 보내지 않았다 (지금 앞: ${f ? f.shown : '없음'})`);
}

function key(combo, to) {
  if (!combo) fail('키 조합이 필요하다 (예: cmd+s)');
  const parts = String(combo).toLowerCase().split('+'), k = parts.pop();
  const using = parts.map(m => MOD[m] || fail(`모르는 수식키 '${m}' — cmd shift alt ctrl`));
  if (!(k in KEY)) fail(`모르는 키 '${k}'`);
  guard(to);
  if (using.length) SE.keyCode(KEY[k], { using: using }); else SE.keyCode(KEY[k]);
}

function typeText(text, to) {
  if (text === undefined) fail('입력할 글자가 필요하다');
  guard(to);
  const pb = $.NSPasteboard.generalPasteboard, saved = [], items = pb.pasteboardItems;
  if (items && !items.isNil()) {
    for (let i = 0; i < items.count; i++) {
      const it = items.objectAtIndex(i), types = it.types, entry = [];
      for (let j = 0; j < types.count; j++) {
        const t = types.objectAtIndex(j), d = it.dataForType(t);
        if (d && !d.isNil()) entry.push([t, d]);
      }
      saved.push(entry);
    }
  }
  pb.clearContents;
  pb.setStringForType($(String(text)), $.NSPasteboardTypeString);
  SE.keyCode(9, { using: ['command down'] });
  delay(0.3 + String(text).length / 20000);
  pb.clearContents;
  if (saved.length) {
    const objs = $.NSMutableArray.array;
    saved.forEach(entry => {
      const ni = $.NSPasteboardItem.alloc.init;
      entry.forEach(([t, d]) => ni.setDataForType(d, t));
      objs.addObject(ni);
    });
    pb.writeObjects(objs);
  }
}

function done() { const f = frontApp(); return `완료. 앞 앱: ${f ? f.shown : '없음'}`; }

function run(argv) {
  const act = argv[0], pos = [], o = {};
  for (let i = 1; i < argv.length; i++) {
    if (argv[i].startsWith('--')) o[argv[i].slice(2)] = argv[++i];
    else pos.push(argv[i]);
  }
  try {
    switch (act) {
      case 'info': return info();
      case 'windows': return windows(pos[0]);
      case 'front': return front(pos[0], pos[1]);
      case 'ui': return ui(pos[0], pos[1], pos[2]);
      case 'capture': return capture(o);
      case 'cursor': { const c = cursor(); return `${c.x},${c.y}`; }
      case 'move': move(num(pos[0], 'x'), num(pos[1], 'y')); return done();
      case 'click': click(num(pos[0], 'x'), num(pos[1], 'y'), pos[2]); return done();
      case 'drag': drag(num(pos[0], 'x1'), num(pos[1], 'y1'), num(pos[2], 'x2'), num(pos[3], 'y2')); return done();
      case 'scroll': scroll(num(pos[0], 'x'), num(pos[1], 'y'), num(pos[2], '양')); return done();
      case 'type': typeText(pos[0], o.to); return done();
      case 'key': key(pos[0], o.to); return done();
      default: return USAGE;
    }
  } catch (e) {
    console.log('오류: ' + (e instanceof Stop ? e.message : String(e)));
    $.exit(1);
  }
}
