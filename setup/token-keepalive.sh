#!/bin/zsh
# Claude CLI 로그인 토큰 자동 갱신 · 만료 경보 (macOS)
#
# 왜 필요한가:
#   데스크톱 앱 로그인과 CLI 로그인은 별개다. CLI 만 로그아웃되면 launchd 로 띄우는
#   remote-control 세션이 전부 안 뜨는데, 앱은 멀쩡해서 눈치채기 어렵다.
#   윈도우 PC 가 2026-08-26 부터 이 상태였고 9/7 에야 발견됐다.
#
# 무엇을 하나:
#   1) CLI 로그인 상태 확인 (API 호출 없음, 무료)
#   2) 갱신토큰 잔여 기간 확인 (키체인에서 만료시각만 읽는다. 토큰 값은 읽지도 찍지도 않는다)
#   3) 잔여가 THRESHOLD_DAYS 미만이면 최소 호출로 갱신을 유도한다
#   4) 로그아웃됐거나 갱신에 실패하면 알림을 띄운다 (복구는 사용자만 가능: claude → /login)
#
# 한계: 맥이 꺼져 있는 동안은 아무것도 못 한다. 갱신 창(약 4일)보다 오래 꺼두면 만료된다.
#
# 수동 실행: zsh ~/.claude/remote-control/token-keepalive.sh
# 중지:      launchctl bootout gui/$(id -u)/com.sanghyeon.claude-token-keepalive

CLAUDE="$HOME/.local/bin/claude"
WORKDIR="$HOME/workspace/AskMeAnything"   # trust 승인된 폴더 (미승인 폴더면 프롬프트에서 멈춘다)
LOG="$HOME/.claude/remote-control/logs/token-keepalive.log"
STATE="$HOME/.claude/remote-control/state/token.json"
THRESHOLD_DAYS=2        # 갱신토큰 잔여가 이 아래면 갱신을 유도한다
ALERT_DAYS=1            # 유도 후에도 이 아래면 사용자에게 알린다
mkdir -p "${LOG:h}" "${STATE:h}"

log() { print -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" }

# 명령을 초 단위 제한으로 실행 (macOS 기본에 timeout 이 없다)
run_limited() {
  local secs=$1; shift
  "$@" & local p=$!
  ( sleep $secs; kill -9 $p 2>/dev/null ) & local k=$!
  wait $p 2>/dev/null; local rc=$?
  kill $k 2>/dev/null
  return $rc
}

notify() {
  log "!! 알림: $1"
  /usr/bin/osascript -e "display notification \"$1\" with title \"Claude CLI 로그인\" sound name \"Basso\"" 2>/dev/null
}

# ── 1) 로그인 상태 (무료)
authjson=$(run_limited 30 "$CLAUDE" auth status --json 2>/dev/null)
logged=$(print -- "$authjson" | /usr/bin/python3 -c \
  "import json,sys
try: print('yes' if json.load(sys.stdin).get('loggedIn') else 'no')
except Exception: print('unknown')" 2>/dev/null)

if [[ "$logged" == "no" ]]; then
  notify "CLI 가 로그아웃됐습니다. 터미널에서 claude 실행 후 /login 하세요. (remote-control 세션이 안 뜹니다)"
  print -- '{"state":"logged_out"}' > "$STATE"
  exit 1
fi

# ── 2) 갱신토큰 잔여 (만료시각만 읽는다)
read_days() {
  run_limited 20 /usr/bin/security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
  | /usr/bin/python3 -c "
import json,sys,time
try:
    o=json.load(sys.stdin); o=o.get('claudeAiOauth',o)
    r=o.get('refreshTokenExpiresAt'); a=o.get('expiresAt')
    if not r: print('na'); raise SystemExit
    print('%.3f %d %d' % ((r/1000-time.time())/86400, r, a or 0))
except Exception: print('na')"
}

info=$(read_days)
if [[ "$info" == "na" || -z "$info" ]]; then
  log "-- 키체인에서 만료시각을 읽지 못했다 (로그인 상태는 정상). 판단 보류."
  print -- '{"state":"unknown_expiry"}' > "$STATE"
  exit 0
fi
days=${info%% *}; rest=${info#* }; rexp=${rest%% *}; aexp=${rest##* }

# ── 3) 여유가 있으면 아무것도 하지 않는다 (호출 낭비 금지)
if (( $(print -- "$days > $THRESHOLD_DAYS" | bc -l) )); then
  log "정상 — 갱신토큰 잔여 ${days}일. 조치 없음."
  print -- "{\"state\":\"ok\",\"days_left\":$days,\"refresh_expires_at\":$rexp,\"checked_at\":$(date +%s)}" > "$STATE"
  exit 0
fi

# ── 4) 임박 → 최소 호출로 갱신 유도
log "임박 — 갱신토큰 잔여 ${days}일. 갱신 유도 호출 시작."
cd "$WORKDIR" 2>/dev/null || cd "$HOME"
run_limited 90 env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SSE_PORT \
  "$CLAUDE" -p "OK" --max-turns 1 >/dev/null 2>&1
rc=$?

after=$(read_days)
if [[ "$after" == "na" || -z "$after" ]]; then
  log "갱신 후 확인 실패 (호출 rc=$rc)"
  exit 0
fi
ndays=${after%% *}
log "갱신 유도 완료 (rc=$rc) — 잔여 ${days}일 → ${ndays}일"
print -- "{\"state\":\"refreshed\",\"days_left\":$ndays,\"before\":$days,\"checked_at\":$(date +%s)}" > "$STATE"

if (( $(print -- "$ndays < $ALERT_DAYS" | bc -l) )); then
  notify "갱신토큰이 곧 만료됩니다 (잔여 ${ndays}일). 자동 갱신이 듣지 않았습니다. claude 실행 후 /login 하세요."
fi
exit 0
