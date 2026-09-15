#!/usr/bin/env bash
# Adversarial live driver: a DIFFERENT live Windows-tagged harness holder must
# not be reclaimed by this session's Stop hook (no handing a running session's
# home to a second one). Uses the real MINGW ps -W and a real live process at a
# windows path containing a "claude" component.
set -u
ROOT="${1:?usage: drive_live_holder.sh <repo-root>}"
TMP="${2:?usage: drive_live_holder.sh <repo-root> <scratch-dir>}"
rm -rf "$TMP"
mkdir -p "$TMP"

# Real live process at C:\...\<TMP>\claude\sleep.exe: a Windows executable whose
# executable path carries a whole "claude" component, so the product's own
# path-component harness matcher must see it as a live harness.
mkdir -p "$TMP/claude"
cp /usr/bin/sleep.exe "$TMP/claude/sleep.exe"
"$TMP/claude/sleep.exe" 120 &
sleeper_bg=$!
sleep 1
holder_win=$(ps -W 2>/dev/null | awk 'tolower($NF) ~ /claude[\/]sleep/ { print $4; exit }')
if [ -z "$holder_win" ]; then
  echo "SETUP-FAIL: live fake-harness sleeper not found in real ps -W" >&2
  kill "$sleeper_bg" 2>/dev/null
  exit 3
fi
echo "different live tagged holder WINPID: $holder_win"
# This session's own harness (the real claude) is a different live pid.
own_win=$(ps -W 2>/dev/null | awk 'tolower($NF) ~ /bin\/claude$/ { print $4; exit }')
echo "this session's own harness WINPID: $own_win"

echo "--- product view of the different holder ---"
bash -c '. "'"$ROOT"'/bin/fm-session-lock-lib.sh"; echo "comm=$(fm_win_command '"$holder_win"')"; fm_harness_pid_alive win:'"$holder_win"' && echo "alive=yes" || echo "alive=no"'

install() {
  local dir=$1
  mkdir -p "$dir/state" "$dir/bin"
  git init -q "$dir" >/dev/null 2>&1
  git -C "$dir" -c user.email=t@e.invalid -c user.name=t commit -q --allow-empty -m init
  : > "$dir/AGENTS.md"
  local f
  for f in fm-claude-stop-autoarm.sh fm-primary-scope-lib.sh fm-supervision-lib.sh \
           fm-wake-lib.sh fm-session-lock-lib.sh fm-cursor-lib.sh fm-hook-host-lib.sh fm-lock.sh; do
    cp "$ROOT/bin/$f" "$dir/bin/$f"
  done
  chmod +x "$dir/bin/fm-claude-stop-autoarm.sh" "$dir/bin/fm-lock.sh"
  cat > "$dir/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
echo "$$" >> "$FM_HOME/state/arm-ran"
printf 'pending:downtime:fixture-generation\n' > "$FM_HOME/state/.watcher-down"
touch "$FM_HOME/state/.last-watcher-beat"
printf 'stale: fixture-win actionable\n'
exit 0
SH
  chmod +x "$dir/bin/fm-watch-arm.sh"
  : > "$dir/state/task.meta"
}

dir="$TMP/home-other-holder"
install "$dir"
printf 'win:%s\n' "$holder_win" > "$dir/state/.lock"
out=$(printf '%s\n' '{"session_id":"other-live-win"}' \
  | CLAUDE_PID="$own_win" FM_HOME="$dir" bash "$dir/bin/fm-claude-stop-autoarm.sh" 2>&1); rc=$?
echo "hook rc=$rc (expect 0 inert)"
echo "lock after='$(cat "$dir/state/.lock" 2>/dev/null)' (expect unchanged win:$holder_win)"
echo "arm-ran present: $([ -e "$dir/state/arm-ran" ] && echo yes || echo no) (expect no)"
printf '%s\n' "$out" | sed 's/^/  hook-output| /' | head -3

kill "$sleeper_bg" 2>/dev/null
wait "$sleeper_bg" 2>/dev/null
