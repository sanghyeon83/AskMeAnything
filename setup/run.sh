#!/bin/zsh
# Claude Remote Control 자동 시작 (macOS) — 윈도우 claude-remote-control.vbs 대응
# 세션 추가/제거: 맨 아래 RunRC 줄을 추가/삭제 (새 폴더는 trust 승인 먼저!)
# 문서: ~/workspace/AskMeAnything/2026-07-27_remote-control_정리.md
# 전체 재시작: launchctl kickstart -k gui/$(id -u)/com.sanghyeon.claude-remote-control
# 전체 중지:   launchctl bootout gui/$(id -u)/com.sanghyeon.claude-remote-control
#              (세션별 자동 재시작 루프가 있어서 프로세스만 죽이면 60초 뒤 되살아난다.
#               완전히 멈추려면 반드시 bootout을 쓸 것)

CLAUDE="$HOME/.local/bin/claude"
LOGDIR="$HOME/.claude/remote-control/logs"
mkdir -p "$LOGDIR"

sleep 20  # 로그인 직후 네트워크 안정화 대기 (윈도우 구성과 동일하게 20초)

# RunRC "폴더경로" "표시이름" "이어받기옵션"
#   이어받기옵션:
#     ""                  매번 빈 대화로 새로 시작
#     "-c"                remote-control 계보의 마지막 대화 이어받기
#     "--session-id <ID>" 특정 클라우드 세션 고정
#     "--resume <UUID>"   특정 로컬 대화(jsonl)를 그대로 원격 세션으로 상시 노출
#                         (옵션 형태 claude --remote-control 사용, pty 필요.
#                          데스크톱 앱에서 시작한 대화를 모바일/PC에서 이어갈 때 쓴다)
#
# 동작 원리:
#   - 세션마다 무한 루프: 죽으면 60초 후 자동 재시작 (개별 세션 자가 복구)
#   - "-c" 폴백 체인: ①-c ②bridge-pointer.json의 마지막 세션 ID로 재접속 ③새 대화
#     → 재부팅/장기 종료 후에도 같은 세션·같은 대화로 이어지고, 목록에 새 세션이 안 쌓인다
RunRC() {
  local dir="$1" name="$2" resume="$3"
  local log="$LOGDIR/${name// /_}.log"
  {
    while true; do
      echo "=== $(date '+%Y-%m-%d %H:%M:%S') 시작: $name ($dir) resume='$resume'"
      if ! cd "$dir"; then
        echo "폴더 없음: $dir — 5분 후 재시도"
        sleep 300
        continue
      fi
      if [[ "$resume" == --resume* ]]; then
        # 로컬 대화 resume: 재실행/재부팅해도 같은 로컬 대화 + 같은 클라우드 세션에 재접속됨
        /usr/bin/script -q /dev/null "$CLAUDE" ${=resume} --remote-control "$name" || {
          echo "--- 로컬 대화 resume 실패 → 새 대화로 폴백"
          "$CLAUDE" remote-control --spawn=same-dir --name "$name"
        }
      elif [[ -n "$resume" ]]; then
        "$CLAUDE" remote-control --spawn=same-dir ${=resume} --name "$name" || {
          local enc=$(printf '%s' "$dir" | sed 's/[^a-zA-Z0-9]/-/g')
          local sid=$(sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' "$HOME/.claude/projects/$enc/bridge-pointer.json" 2>/dev/null)
          if [[ -n "$sid" ]]; then
            echo "--- 이어받기(-c) 실패 → 기록된 세션으로 재접속: $sid"
            "$CLAUDE" remote-control --session-id "$sid" --name "$name" || {
              echo "--- 세션 ID 재접속도 실패 → 새 대화로 폴백"
              "$CLAUDE" remote-control --spawn=same-dir --name "$name"
            }
          else
            echo "--- 이어받기(-c) 실패, 기록된 세션 없음 → 새 대화로 폴백"
            "$CLAUDE" remote-control --spawn=same-dir --name "$name"
          fi
        }
      else
        "$CLAUDE" remote-control --spawn=same-dir --name "$name"
      fi
      echo "=== $(date '+%Y-%m-%d %H:%M:%S') 종료: $name → 60초 후 자동 재시작"
      sleep 60
    done
  } >> "$log" 2>&1 &
}

# ── 자동 실행 세션 목록 ─────────────────────────────
# AskMeAnything: 2026-08-13 데스크톱 앱 대화를 포크한 로컬 대화(bd9cae22)를 상시 노출
RunRC "$HOME/workspace/AskMeAnything" "AskMeAnything_맥" "--resume bd9cae22-e860-40ec-a674-4beea7764f16"
RunRC "$HOME/workspace/Tokbell" "Tokbell_맥" "-c"
RunRC "$HOME/workspace/tokbell_sender" "Tokbell Sender_맥" "-c"
RunRC "$HOME/workspace/morning_economy" "Morning Economy_맥" "-c"
RunRC "$HOME/workspace/rabbit-typing-adventure" "Rabbit Typing_맥" "-c"
RunRC "$HOME/workspace/kafka_test" "kafka test_맥" "-c"
# ───────────────────────────────────────────────────

wait  # 백그라운드 루프 유지
