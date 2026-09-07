#!/bin/zsh
# Claude Remote Control 자동 시작 (macOS) — 윈도우 claude-remote-control.vbs 대응
# 세션 추가/제거: 맨 아래 RunRC 줄을 추가/삭제 (새 폴더는 trust 승인 먼저!)
# 문서: ~/workspace/AskMeAnything/2026-08-13_맥-환경-구축-정리.md
# 전체 재시작: launchctl kickstart -k gui/$(id -u)/com.sanghyeon.claude-remote-control
# 전체 중지:   launchctl bootout gui/$(id -u)/com.sanghyeon.claude-remote-control
#              (세션별 자동 재시작 루프가 있어서 프로세스만 죽이면 60초 뒤 되살아난다)

CLAUDE="$HOME/.local/bin/claude"
LOGDIR="$HOME/.claude/remote-control/logs"
STATEDIR="$HOME/.claude/remote-control/state"   # bridge-pointer 스냅샷 보관
mkdir -p "$LOGDIR" "$STATEDIR"

sleep 20  # 로그인 직후 네트워크 안정화 대기

# 동작 원리 (2026-08-14 개정 — 잠자기 깨어남 사고 후):
#   - claude가 "정상 종료"하면 bridge-pointer.json(세션 기록)을 지워버린다.
#     그래서 실행 중 60초마다 스냅샷을 떠서 state/에 보관하고, 기록이 사라졌으면 스냅샷으로 복원한다.
#   - 이어받기 실패 시 절대 새 세션을 만들지 않는다. 60초 후 재시도만 한다 (대화 보존 최우선).
#     새 세션이 필요한 새 폴더는 이어받기옵션을 ""로 등록할 것.
RunRC() {
  local dir="$1" name="$2" resume="$3"
  local log="$LOGDIR/${name// /_}.log"
  local enc=$(printf '%s' "$dir" | sed 's/[^a-zA-Z0-9]/-/g')
  local bp="$HOME/.claude/projects/$enc/bridge-pointer.json"
  local snap="$STATEDIR/${name// /_}.bridge-pointer.json"
  {
    # claude를 백그라운드로 돌리며 살아있는 동안 bridge-pointer를 주기 스냅샷
    run_watched() {
      "$@" &
      local cpid=$!
      while kill -0 $cpid 2>/dev/null; do
        sleep 60
        [[ -f "$bp" ]] && cp "$bp" "$snap" 2>/dev/null
      done
      wait $cpid
    }
    while true; do
      echo "=== $(date '+%Y-%m-%d %H:%M:%S') 시작: $name ($dir) resume='$resume'"
      if ! cd "$dir"; then
        echo "폴더 없음: $dir — 5분 후 재시도"; sleep 300; continue
      fi
      # 기록이 지워졌으면 스냅샷으로 복원
      if [[ ! -f "$bp" && -f "$snap" ]]; then
        mkdir -p "$(dirname "$bp")" && cp "$snap" "$bp"
        echo "--- bridge-pointer 소실 → 스냅샷으로 복원"
      fi
      if [[ "$resume" == --resume* ]]; then
        # 로컬 대화 상시 노출 (옵션 형태, pty 필요)
        run_watched /usr/bin/script -q /dev/null "$CLAUDE" ${=resume} --remote-control "$name" \
          || echo "--- 로컬 대화 resume 실패 → 60초 후 재시도"
      elif [[ -n "$resume" ]]; then
        # ⚠️ CLI 규칙: --session-id/-c 는 --spawn 계열과 함께 못 쓴다 (단독 사용)
        local sid=$(sed -n 's/.*"sessionId": *"\([^"]*\)".*/\1/p' "$bp" 2>/dev/null)
        [[ -z "$sid" ]] && sid=$(sed -n 's/.*"sessionId": *"\([^"]*\)".*/\1/p' "$snap" 2>/dev/null)
        if [[ "$resume" == --session-id* ]]; then sid="${resume#--session-id }"; fi
        if [[ -n "$sid" ]]; then
          echo "--- 기록된 세션으로 재접속: $sid"
          run_watched "$CLAUDE" remote-control --session-id "$sid" --name "$name" \
            || echo "--- 세션 재접속 실패 → 60초 후 재시도 (새 세션은 만들지 않음)"
        else
          echo "--- 기록/스냅샷 없음 → -c 단독 시도"
          run_watched "$CLAUDE" remote-control -c --name "$name" \
            || echo "--- -c도 실패 → 60초 후 재시도 (새 세션은 만들지 않음)"
        fi
      else
        run_watched "$CLAUDE" remote-control --spawn=same-dir --name "$name"
      fi
      echo "=== $(date '+%Y-%m-%d %H:%M:%S') 종료: $name → 60초 후 재시작"
      sleep 60
    done
  } >> "$log" 2>&1 &
}

# ── 자동 실행 세션 목록 ─────────────────────────────
# AskMeAnything: 데스크톱 앱 대화를 포크한 로컬 대화(bd9cae22)를 상시 노출
RunRC "$HOME/workspace/AskMeAnything" "AskMeAnything_맥" "--resume bd9cae22-e860-40ec-a674-4beea7764f16"
RunRC "$HOME/workspace/Tokbell" "Tokbell_맥" "-c"
RunRC "$HOME/workspace/tokbell_sender" "Tokbell Sender_맥" "-c"
RunRC "$HOME/workspace/morning_economy" "Morning Economy_맥" "-c"
RunRC "$HOME/workspace/rabbit-typing-adventure" "Rabbit Typing_맥" "-c"
RunRC "$HOME/workspace/kafka_test" "kafka test_맥" "-c"
RunRC "$HOME/workspace/tokbell_ha" "Tokbell HA_맥" "-c"
RunRC "$HOME/workspace/webs.madang.ai" "Webs Madang_맥" "-c"
# ───────────────────────────────────────────────────

wait  # 백그라운드 루프 유지
