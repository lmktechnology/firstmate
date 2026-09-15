#!/usr/bin/env bash
# Live-ish focused driver for the Cygwin STIME-column parse and the
# unreadable-Windows-table guard, using the repo's own fm_cygwin_fakebin
# platform fixture (tests/lib.sh) exactly as the excluded ancestry suite does.
set -u
ROOT="${1:?usage: drive_stime.sh <repo-root>}"
TMP="${2:?usage: drive_stime.sh <repo-root> <scratch-dir>}"
TMP=$(cygpath -u "$TMP" 2>/dev/null || printf '%s' "$TMP")
rm -rf "$TMP"
mkdir -p "$TMP"
export FM_TEST_LIB_SOURCED=
# shellcheck source=/dev/null
. "$ROOT/tests/lib.sh" 2>/dev/null || true

fakebin=$(fm_cygwin_fakebin "$TMP/fake")
echo "fakebin=$fakebin"
lib_eval() { PATH="$fakebin:$PATH" bash -c '. "'"$ROOT"'/bin/fm-session-lock-lib.sh"; '"$1"; }

WIN_TABLE_DATE_STIME='  4201508       0       0       7204  ?              0 Sep  6 C:\Users\u\.local\bin\claude.exe
  4198625       0       0       4321  ?              0 Sep  6 C:\Windows\explorer.exe'
WIN_TABLE='  4201508       0       0       7204  ?              0 22:24:48 C:\Users\u\.local\bin\claude.exe'

echo "=== STIME: time-form (single field) comm/args/ppid ==="
echo "fm_ps_comm 700 = $(lib_eval 'fm_ps_comm 700')"
echo "fm_ps_args 700 = $(lib_eval 'fm_ps_args 700')"
echo "fm_ps_ppid 700 = $(lib_eval 'fm_ps_ppid 700')"
echo "=== STIME: date-form 'Sep  6' (two fields) must not truncate COMMAND ==="
echo "fm_ps_comm 700 = $(FM_TEST_CYG_STIME='Sep  6' lib_eval 'fm_ps_comm 700')"
echo "fm_ps_args 700 = $(FM_TEST_CYG_STIME='Sep  6' lib_eval 'fm_ps_args 700')"
echo "fm_ps_ppid 700 = $(FM_TEST_CYG_STIME='Sep  6' lib_eval 'fm_ps_ppid 700')"
echo "fm_win_command 7204 = $(FM_TEST_WIN_TABLE="$WIN_TABLE_DATE_STIME" lib_eval 'fm_win_command 7204')"
echo "fm_harness_ancestry_pid (date STIME, CLAUDE_PID=7204) = $(FM_TEST_WIN_TABLE="$WIN_TABLE_DATE_STIME" CLAUDE_PID=7204 lib_eval 'fm_harness_ancestry_pid')"
echo "=== path-shaped lookalike must NOT match (claude-notes) ==="
WIN_TABLE_LOOKALIKE='  4199454       0       0       5150  ?              0 22:24:48 C:\tools\claude-notes\helper.exe'
echo "fm_win_command 5150 = $(FM_TEST_WIN_TABLE="$WIN_TABLE_LOOKALIKE" lib_eval 'fm_win_command 5150')"
echo "fm_harness_pid_alive win:5150 -> $(FM_TEST_WIN_TABLE="$WIN_TABLE_LOOKALIKE" lib_eval 'fm_harness_pid_alive win:5150 && echo alive || echo dead') (expect dead)"
echo "=== unreadable table fail-closed ==="
echo "ps -W fails -> $(FM_TEST_PS_W_FAIL=1 lib_eval 'fm_harness_pid_alive win:7204 && echo alive || echo dead') (expect alive)"
echo "ps -W empty -> $(FM_TEST_PS_W_EMPTY=1 lib_eval 'fm_harness_pid_alive win:7204 && echo alive || echo dead') (expect alive)"
echo "readable no row -> $(FM_TEST_WIN_TABLE="$WIN_TABLE" lib_eval 'fm_harness_pid_alive win:9999 && echo alive || echo dead') (expect dead)"
