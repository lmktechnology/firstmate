#!/usr/bin/env bash
# Live driver for the exact stated intent: a previous, now-dead Windows session
# left both state/.lock (win:<dead>) and a stale auto-arm epoch ledger; the NEW
# session's Stop hook must still claim supervision.
set -u
ROOT="${1:?usage: drive_stale_epoch.sh <repo-root>}"
TMP="${2:?usage: drive_stale_epoch.sh <repo-root> <scratch-dir>}"
rm -rf "$TMP"; mkdir -p "$TMP"

live_win=$(ps -W 2>/dev/null | awk 'tolower($NF) ~ /bin[\/]claude$/ { print $4; exit }')
[ -n "$live_win" ] || { echo "SETUP-FAIL: no live claude in real ps -W" >&2; exit 3; }
echo "live claude WINPID: $live_win"

dir="$TMP/home"
mkdir -p "$dir/state" "$dir/bin"
git init -q "$dir" >/dev/null 2>&1
git -C "$dir" -c user.email=t@e.invalid -c user.name=t commit -q --allow-empty -m init
: > "$dir/AGENTS.md"
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

# The dead prior session's leftovers: a Windows-tagged lock AND a still-"arming"
# epoch ledger attributed to the old owner with its stale session binding.
printf 'win:9999999\n' > "$dir/state/.lock"
printf 'epoch=7 owner_pid=9999999 outcome=arming updated_at=1000000000 session_pid=win:9999999\n' \
  > "$dir/state/.claude-autoarm-epoch"
printf 'win:9999999\n' > "$dir/state/.claude-autoarm-epoch.tmp.identity"
touch -d '2020-01-01 00:00:00' "$dir/state/.claude-autoarm-epoch" 2>/dev/null || true

out=$(printf '%s\n' '{"session_id":"stale-epoch"}' \
  | CLAUDE_PID="$live_win" FM_HOME="$dir" bash "$dir/bin/fm-claude-stop-autoarm.sh" 2>&1); rc=$?
echo "hook rc=$rc (expect 2 -> supervision claimed)"
echo "lock after='$(cat "$dir/state/.lock" 2>/dev/null)' (expect win:$live_win)"
echo "epoch ledger after:"
sed 's/^/  /' "$dir/state/.claude-autoarm-epoch"
echo "arm-ran present: $([ -e "$dir/state/arm-ran" ] && echo yes || echo no)"
printf '%s\n' "$out" | sed 's/^/  hook-output| /' | head -3
