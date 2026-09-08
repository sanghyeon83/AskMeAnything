#!/bin/zsh
# Claude CLI 로그인 만료 감시 · 재로그인 자동 기동 (macOS)
#
# ⚠️ 토큰 자체를 "갱신"하지는 못한다. 2026-09-07 실측:
#    액세스 토큰은 갱신돼도(09-07 19:00 -> 09-08 02:57) 갱신토큰 만료는
#    09-11 04:25 그대로였다. 갱신토큰은 로그인 시점부터 약 28~29일 고정이다.
#      맥    로그인 2026-08-13 -> 만료 2026-09-11
#      윈도우 로그인 2026-09-07 -> 만료 2026-10-06
#    유일한 연장 수단은 브라우저 재인증이고, 그건 사람이 승인해야 한다.
#
# 그래서 할 수 있는 데까지 자동화한다:
#   만료가 임박하면 **재로그인 창을 대신 띄워준다.** 사용자는 브라우저에서
#   승인만 하면 된다. (2026-09-08 사용자 요청)
#
#   1) claude auth status --json 으로 로그인 상태 확인 (API 호출 없음)
#   2) 키체인에서 만료시각만 읽는다 (토큰 값은 읽지도 기록하지도 않는다)
#   3) WARN_DAYS 이하 → 알림 (12시간에 한 번)
#   4) AUTO_DAYS 이하 → relogin.command 를 open 으로 띄운다 (24시간에 한 번)
#   5) URGENT_DAYS 이하 → 실행할 때마다 알림
#
# 창을 AppleScript 가 아니라 `open <파일>.command` 로 띄우는 이유:
#   osascript 로 Terminal 을 조종하려면 자동화(TCC) 권한이 필요한데,
#   launchd 에서 도는 프로세스는 그 권한을 못 받아 조용히 실패할 수 있다.
#   open 은 LaunchServices 경로라 권한 없이 된다 (2026-09-08 실측).
#
# 수동 재로그인: open ~/.claude/remote-control/relogin.command
# 중지:         launchctl bootout gui/$(id -u)/com.sanghyeon.claude-token-keepalive

CLAUDE="$HOME/.local/bin/claude"
RELOGIN="$HOME/.claude/remote-control/relogin.command"
LOG="$HOME/.claude/remote-control/logs/token-keepalive.log"
STATE="$HOME/.claude/remote-control/state/token.json"
WARN_DAYS=5        # 이 아래면 알린다
AUTO_DAYS=3        # 이 아래면 재로그인 창을 자동으로 띄운다
URGENT_DAYS=2      # 이 아래면 실행할 때마다 알린다
ALERT_GAP=43200    # 알림 최소 간격 12시간
LAUNCH_GAP=86400   # 창 자동 기동 최소 간격 24시간 (창이 우르르 뜨는 것 방지)
mkdir -p "${LOG:h}" "${STATE:h}"

log() { print -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" }

run_limited() {   # macOS 기본에 timeout 이 없다
  local secs=$1; shift
  "$@" & local p=$!
  ( sleep $secs; kill -9 $p 2>/dev/null ) & local k=$!
  wait $p 2>/dev/null; local rc=$?
  kill $k 2>/dev/null
  return $rc
}

# 상태 파일에서 값 하나 읽기 (없거나 깨졌으면 0)
st() { [[ -f "$STATE" ]] && /usr/bin/python3 -c "
import json
try: print(int(json.load(open('$STATE')).get('$1',0)))
except Exception: print(0)" || print 0 }

save_state() {  # $1=state $2=days $3=last_alert $4=last_launch
  print -- "{\"state\":\"$1\",\"days_left\":$2,\"last_alert\":$3,\"last_launch\":$4,\"checked_at\":$(date +%s)}" > "$STATE"
}

notify() {
  log "!! 경보: $1"
  /usr/bin/osascript -e "display notification \"$1\" with title \"Claude CLI 로그인 만료\" sound name \"Basso\"" 2>/dev/null
}

# 재로그인 창을 띄운다. 이미 진행 중이면 띄우지 않는다.
launch_relogin() {
  if pgrep -f "auth login" >/dev/null 2>&1; then
    log "   재로그인 절차가 이미 진행 중 → 창을 새로 띄우지 않음"
    return 1
  fi
  if [[ ! -x "$RELOGIN" ]]; then
    log "   relogin.command 이 없거나 실행 권한 없음: $RELOGIN"
    return 1
  fi
  /usr/bin/open "$RELOGIN" 2>/dev/null && { log "   재로그인 창을 띄웠다 (브라우저 승인 필요)"; return 0 }
  log "   재로그인 창 기동 실패"
  return 1
}

# ── 1) 로그인 상태
authjson=$(run_limited 30 "$CLAUDE" auth status --json 2>/dev/null)
logged=$(print -- "$authjson" | /usr/bin/python3 -c "
import json,sys
try: print('yes' if json.load(sys.stdin).get('loggedIn') else 'no')
except Exception: print('unknown')" 2>/dev/null)

prev_alert=$(st last_alert); prev_launch=$(st last_launch); now=$(date +%s)

if [[ "$logged" == "no" ]]; then
  notify "이미 로그아웃됐습니다. 재로그인 창을 띄웁니다. 브라우저에서 승인해 주세요."
  launch_relogin && prev_launch=$now
  save_state logged_out 0 $now $prev_launch
  exit 1
fi

# ── 2) 남은 날짜 (만료시각만 읽는다)
days=$(run_limited 20 /usr/bin/security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
  | /usr/bin/python3 -c "
import json,sys,time
try:
    o=json.load(sys.stdin); o=o.get('claudeAiOauth',o)
    r=o.get('refreshTokenExpiresAt')
    print('na' if not r else '%.3f' % ((r/1000-time.time())/86400))
except Exception: print('na')")

if [[ "$days" == "na" || -z "$days" ]]; then
  log "-- 키체인에서 만료시각을 읽지 못했다 (로그인 상태는 정상). 판단 보류."
  save_state unknown_expiry 0 $prev_alert $prev_launch
  exit 0
fi

# ── 3) 여유가 있으면 아무것도 하지 않는다
if (( $(print -- "$days > $WARN_DAYS" | bc -l) )); then
  log "정상 — 재로그인까지 ${days}일. 조치 없음."
  save_state ok $days $prev_alert $prev_launch
  exit 0
fi

# ── 4) 임박 → 필요하면 창을 띄우고, 알린다
alerted=$prev_alert; launched=$prev_launch
if (( $(print -- "$days < $AUTO_DAYS" | bc -l) )) && (( now - prev_launch > LAUNCH_GAP )); then
  log "임박(${days}일) — 재로그인 창 자동 기동 시도"
  launch_relogin && launched=$now
fi

if (( $(print -- "$days < $URGENT_DAYS" | bc -l) )) || (( now - prev_alert > ALERT_GAP )); then
  notify "CLI 로그인이 ${days}일 뒤 만료됩니다. 뜨는 창에서 브라우저 승인만 하시면 됩니다. (자동 갱신은 불가능합니다)"
  alerted=$now
else
  log "임박(${days}일)하지만 최근 알림 후 12시간이 안 지나 알림은 생략."
fi
save_state expiring $days $alerted $launched
exit 0
