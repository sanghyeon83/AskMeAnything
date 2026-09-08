#!/bin/zsh
# Claude CLI 재로그인. 만료가 임박하면 token-keepalive.sh 가 이 창을 자동으로 띄운다.
# 수동 실행도 가능: open ~/.claude/remote-control/relogin.command
print -- "────────────────────────────────────────────"
print -- " Claude CLI 재로그인"
print -- " 브라우저가 열리면 승인만 하시면 됩니다."
print -- "────────────────────────────────────────────"
print -- ""
"$HOME/.local/bin/claude" auth login --claudeai --email shpark@ibank.co.kr
rc=$?
print -- ""
if [[ $rc -eq 0 ]]; then
  "$HOME/.local/bin/claude" auth status --text 2>/dev/null | head -5
  print -- ""
  print -- "✅ 완료되었습니다. 이 창은 닫으셔도 됩니다."
else
  print -- "⚠️ 로그인이 완료되지 않았습니다 (종료코드 $rc). 창을 닫고 다시 시도하세요."
fi
print -- ""
print -- "(3분 뒤 자동으로 닫힙니다)"
sleep 180
