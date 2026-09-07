#!/bin/zsh
# Claude CLI 로그인 만료 감시 · 경보 (macOS)
#
# ⚠️ 이름은 keepalive 지만 "갱신"은 하지 않는다. 할 수 없기 때문이다.
#    2026-09-07 실측: 액세스 토큰은 갱신돼도(09-07 19:00 -> 09-08 02:57)
#    갱신토큰 만료는 09-11 04:25 그대로였다. 갱신토큰은 로그인 시점부터
#    약 29~30일 고정이고, 아무리 써도 뒤로 밀리지 않는다.
#      맥  : 키체인 항목 생성 2026-08-13 -> 만료 2026-09-11 (29일)
#      윈도우: 재로그인 2026-09-07      -> 만료 2026-10-06 (29일)
#    즉 한 달에 한 번은 사람이 다시 로그인해야 한다. 자동화로는 못 막는다.
#
# 그래서 이 스크립트가 하는 일은 하나다: **만료 전에 알려주는 것.**
#   1) CLI 로그인 상태 확인 (API 호출 없음)
#   2) 키체인에서 만료시각만 읽는다 (토큰 값은 읽지도 기록하지도 않는다)
#   3) 남은 날짜가 임계 이하면 알린다. 복구는 사용자만 가능: claude 실행 -> /login
#
# 왜 필요한가: 데스크톱 앱 로그인과 CLI 로그인은 별개다. CLI 만 만료되면
#   launchd remote-control 세션이 전부 안 뜨는데 앱은 멀쩡해서 눈치채기 어렵다.
#   윈도우 PC 가 2026-08-26 부터 그 상태였고 9/7 에야 발견됐다.
#
# 수동 실행: zsh ~/.claude/remote-control/token-keepalive.sh
# 중지:      launchctl bootout gui/$(id -u)/com.sanghyeon.claude-token-keepalive

CLAUDE="$HOME/.local/bin/claude"
LOG="$HOME/.claude/remote-control/logs/token-keepalive.log"
STATE="$HOME/.claude/remote-control/state/token.json"
WARN_DAYS=5        # 이 아래면 알린다 (하루 한 번)
URGENT_DAYS=2      # 이 아래면 실행할 때마다 알린다
ALERT_GAP=43200    # 경보 최소 간격 12시간 (초)
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

last_alert() { [[ -f "$STATE" ]] && /usr/bin/python3 -c "
import json,sys
try: print(int(json.load(open('$STATE')).get('last_alert',0)))
except Exception: print(0)" || print 0 }

save_state() {  # $1=state $2=days $3=alerted_epoch
  print -- "{\"state\":\"$1\",\"days_left\":$2,\"last_alert\":$3,\"checked_at\":$(date +%s)}" > "$STATE"
}

notify() {
  log "!! 경보: $1"
  /usr/bin/osascript -e "display notification \"$1\" with title \"Claude CLI 로그인 만료\" sound name \"Basso\"" 2>/dev/null
}

# ── 1) 로그인 상태
authjson=$(run_limited 30 "$CLAUDE" auth status --json 2>/dev/null)
logged=$(print -- "$authjson" | /usr/bin/python3 -c "
import json,sys
try: print('yes' if json.load(sys.stdin).get('loggedIn') else 'no')
except Exception: print('unknown')" 2>/dev/null)

if [[ "$logged" == "no" ]]; then
  notify "이미 로그아웃됐습니다. 터미널에서 claude 실행 후 /login 하세요. remote-control 세션이 안 뜹니다."
  save_state logged_out 0 $(date +%s)
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
  save_state unknown_expiry 0 $(last_alert)
  exit 0
fi

# ── 3) 판정
prev=$(last_alert); now=$(date +%s); alerted=$prev
if (( $(print -- "$days > $WARN_DAYS" | bc -l) )); then
  log "정상 — 재로그인까지 ${days}일. 조치 없음."
  save_state ok $days $prev
  exit 0
fi

urgent=$(( $(print -- "$days < $URGENT_DAYS" | bc -l) ))
if (( urgent == 1 || now - prev > ALERT_GAP )); then
  notify "CLI 로그인이 ${days}일 뒤 만료됩니다. 터미널에서 claude 실행 후 /login 하세요. (자동 갱신은 불가능합니다)"
  alerted=$now
else
  log "임박(${days}일)하지만 최근 경보 후 12시간이 안 지나 알림은 생략."
fi
save_state expiring $days $alerted
exit 0
