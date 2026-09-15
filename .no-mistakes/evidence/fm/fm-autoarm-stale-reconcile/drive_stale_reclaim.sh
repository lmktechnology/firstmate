#!/usr/bin/env bash
# Live driver for the stale Windows-tagged session-lock reclaim.
# Runs the REAL bin/fm-claude-stop-autoarm.sh and bin/fm-lock.sh from the
# change under test, against the REAL MINGW `ps -W` table and a REAL live
# claude process (WINPID taken from the host), with no `ps` shim.
set -u
ROOT="${1:?usage: drive_stale_reclaim.sh <repo-root>}"
TMP="${2:?usage: drive_stale_reclaim.sh <repo-root> <scratch-dir>}"
rm -rf "$TMP"
mkdir -p "$TMP"

live_win=$(ps -W 2>/dev/null | awk 'NR>1 { c=$NF; gsub(/\\\\/,"/",c); n=c; sub(/.*\//,"",n); sub(/\.exe$/,"",n); if (n=="claude") { print $4; exit } }')
if [ -z "$live_win" ]; then
  echo "SETUP-FAIL: no live claude process in the real ps -W table" >&2
  exit 3
fi
echo "live claude WINPID from real ps -W: $live_win"

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
printf 'watcher: started pid=%s (beacon fresh)\n' "$$"
printf 'stale: fixture-win actionable\n'
exit 0
SH
  chmod +x "$dir/bin/fm-watch-arm.sh"
  : > "$dir/state/task.meta"
}

echo "=== Scenario A: dead Windows-tagged lock is reclaimed before arming ==="
dir="$TMP/home-dead"
install "$dir"
printf 'win:9999999\n' > "$dir/state/.lock"
out=$(printf '%s\n' '{"session_id":"stale-win"}' \
  | CLAUDE_PID="$live_win" FM_HOME="$dir" bash "$dir/bin/fm-claude-stop-autoarm.sh" 2>&1); rc=$?
echo "hook rc=$rc (expect 2)"
echo "lock after reclaim='$(cat "$dir/state/.lock" 2>/dev/null)' (expect win:$live_win)"
echo "arm-ran present: $([ -e "$dir/state/arm-ran" ] && echo yes || echo no)"
echo "outcome=$(sed -n 's/.*\"outcome\":\"\([a-z-]*\)\".*/\1/p' "$dir/state/.claude-autoarm-epoch" 2>/dev/null | tail -1)"
printf '%s\n' "$out" | sed 's/^/  hook-output| /' | head -5

echo
echo "=== Scenario B: live Windows-tagged holder is NOT reclaimed (stays inert) ==="
dir2="$TMP/home-live"
install "$dir2"
printf 'win:%s\n' "$live_win" > "$dir2/state/.lock"
out2=$(printf '%s\n' '{"session_id":"live-win"}' \
  | CLAUDE_PID="$live_win" FM_HOME="$dir2" bash "$dir2/bin/fm-claude-stop-autoarm.sh" 2>&1); rc2=$?
echo "hook rc=$rc2 (expect 0)"
echo "lock after='$(cat "$dir2/state/.lock" 2>/dev/null)' (expect unchanged win:$live_win)"
echo "arm-ran present: $([ -e "$dir2/state/arm-ran" ] && echo yes || echo no) (expect no)"

echo
echo "=== Scenario C: genuinely-absent tagged holder vs fail-closed unreadable table ==="
dead=$(bash -c '. "'"$ROOT"'/bin/fm-session-lock-lib.sh"; fm_harness_pid_alive win:9999999 && echo ALIVE || echo dead')
echo "readable table, no row (win:9999999) -> $dead (expect dead)"
# Fault-inject a failing / empty ps -W by shadowing ps on PATH only for the read.
shim="$TMP/psfail"
mkdir -p "$shim"
cat > "$shim/ps" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "-W" ] && { echo 'ps: unable to read process table' >&2; exit 1; }; done
exec /usr/bin/ps "$@"
SH
chmod +x "$shim/ps"
fail=$(PATH="$shim:$PATH" bash -c '. "'"$ROOT"'/bin/fm-session-lock-lib.sh"; fm_harness_pid_alive win:'"$live_win"' && echo ALIVE || echo dead')
echo "ps -W fails -> $fail (expect ALIVE = fail closed)"
shim2="$TMP/psempty"
mkdir -p "$shim2"
cat > "$shim2/ps" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "-W" ] && exit 0; done
exec /usr/bin/ps "$@"
SH
chmod +x "$shim2/ps"
empty=$(PATH="$shim2:$PATH" bash -c '. "'"$ROOT"'/bin/fm-session-lock-lib.sh"; fm_harness_pid_alive win:'"$live_win"' && echo ALIVE || echo dead')
echo "ps -W empty -> $empty (expect ALIVE = fail closed)"

echo
echo "=== Scenario D: digits-only win: prefix validation ==="
for v in 'win:' 'win:12abc' 'win:0x1' 'win:7204' '7204' '0' '1' 'abc' ''; do
  r=$(bash -c '. "'"$ROOT"'/bin/fm-session-lock-lib.sh"; fm_session_pid_valid "'"$v"'" && echo valid || echo rejected')
  echo "  fm_session_pid_valid '$v' -> $r"
done
