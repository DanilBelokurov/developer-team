#!/bin/bash
# Quick test of scripts/state.sh (v6.2 file-based)
set -e
cd /Users/danilbelokurov/Desktop/devTeam

source scripts/state.sh
echo "OK: source works"

# Use a temp dir as ROOT
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
ROOT="$TEST_DIR" export ROOT
cd "$TEST_DIR"

ensure_state_dir
echo "OK: ensure_state_dir"

set_kv_state "test.key" "test_value"
echo "OK: set_kv_state"
GOT=$(get_kv_state "test.key")
echo "  get: '$GOT'"
[ "$GOT" = "test_value" ] || { echo "FAIL: roundtrip"; exit 1; }
echo "OK: roundtrip"

GOT=$(get_kv_state "nonexistent.key" "default-value")
echo "  default: '$GOT'"
[ "$GOT" = "default-value" ] || { echo "FAIL: default"; exit 1; }
echo "OK: default"

START=$(start_session "/devteam:build --feature 'test'" "build" "normal")
echo "OK: start_session → $START"

SESSION_ID=$(get_current_session_id)
echo "OK: current session = $SESSION_ID"

# Set state fields
set_state "current_phase" "executing"
set_state "current_iteration" "3"
PHASE=$(get_state "current_phase")
ITER=$(get_state "current_iteration")
echo "  phase=$PHASE iter=$ITER"
[ "$PHASE" = "executing" ] || { echo "FAIL: phase"; exit 1; }
[ "$ITER" = "3" ] || { echo "FAIL: iter"; exit 1; }
echo "OK: set_state / get_state"

# Increment counters
increment_iteration
NEW_ITER=$(get_current_iteration)
echo "  iter after inc: $NEW_ITER"
[ "$NEW_ITER" = "4" ] || { echo "FAIL: increment"; exit 1; }
echo "OK: increment_iteration"

increment_failures; increment_failures
FAILS=$(get_consecutive_failures)
echo "  fails: $FAILS"
[ "$FAILS" = "2" ] || { echo "FAIL: increment_failures"; exit 1; }
echo "OK: increment_failures"

reset_failures
[ "$(get_consecutive_failures)" = "0" ] || { echo "FAIL: reset_failures"; exit 1; }
echo "OK: reset_failures"

# KV state
set_kv_state "stage.analytics.status" "completed"
[ "$(get_kv_state stage.analytics.status)" = "completed" ] || { echo "FAIL: KV"; exit 1; }
echo "OK: KV state"

# Tokens
add_tokens 1000 500
TOK_IN=$(get_state "total_tokens_input")
TOK_OUT=$(get_state "total_tokens_output")
echo "  tokens in=$TOK_IN out=$TOK_OUT"
[ "$TOK_IN" = "1000" ] || { echo "FAIL: add_tokens input"; exit 1; }
[ "$TOK_OUT" = "500" ] || { echo "FAIL: add_tokens output"; exit 1; }
echo "OK: add_tokens"

# Session summary
echo "--- session summary ---"
get_session_summary
echo "--- end summary ---"

# End session
end_session "completed" "Test OK"
STATUS=$(get_state "status")
echo "  status after end: $STATUS"
[ "$STATUS" = "completed" ] || { echo "FAIL: end_session"; exit 1; }
echo "OK: end_session"

# Verify file structure
echo ""
echo "=== files in $TEST_DIR/.devteam/state/ ==="
find "$TEST_DIR/.devteam/state" -type f | sort

# Cleanup
cd /Users/danilbelokurov/Desktop/devTeam
rm -rf "$TEST_DIR"

echo ""
echo "ALL TESTS PASSED"
