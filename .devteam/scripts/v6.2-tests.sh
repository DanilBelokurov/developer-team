#!/bin/bash
# V13, V14, V15 verifications for v6.2 file-based state
# Run after main V1-V12 to ensure file state works correctly.
#
# Usage: bash scripts/v6.2-tests.sh

set -u
PASS=0; FAIL=0
run_check() { if [ "$2" = "OK" ]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1: $2"; FAIL=$((FAIL+1)); fi; }

echo "════════════════════════════════════════════════════════════"
echo " V13: File state roundtrip (KV, session, atomicity)"
echo "════════════════════════════════════════════════════════════"
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
export ROOT="$TEST_DIR"

# Source the real state.sh
bash -c "
set -e
source /Users/danilbelokurov/Desktop/devTeam/scripts/state.sh
set_kv_state 'test.key' 'test_value'
GOT=\$(get_kv_state 'test.key')
[ \"\$GOT\" = 'test_value' ] || { echo 'FAIL: KV roundtrip'; exit 1; }
echo 'OK: KV roundtrip'

GOT=\$(get_kv_state 'nonexistent' 'default')
[ \"\$GOT\" = 'default' ] || { echo 'FAIL: default'; exit 1; }
echo 'OK: default value'

START=\$(start_session '/devteam:build --feature \"X\"' 'build' 'normal')
[ -n \"\$START\" ] || { echo 'FAIL: start_session'; exit 1; }
[ \"\$(get_current_session_id)\" = \"\$START\" ] || { echo 'FAIL: current_session_id mismatch'; exit 1; }
echo \"OK: session created: \$START\"

set_state 'current_phase' 'executing'
set_state 'current_iteration' '5'
[ \"\$(get_state 'current_phase')\" = 'executing' ] || { echo 'FAIL: phase'; exit 1; }
[ \"\$(get_state 'current_iteration')\" = '5' ] || { echo 'FAIL: iter'; exit 1; }
echo 'OK: session state setters/getters'

increment_iteration
[ \"\$(get_current_iteration)\" = '6' ] || { echo 'FAIL: increment_iteration'; exit 1; }
echo 'OK: increment_iteration'

increment_failures; increment_failures; increment_failures
[ \"\$(get_consecutive_failures)\" = '3' ] || { echo 'FAIL: increment_failures'; exit 1; }
echo 'OK: increment_failures'

reset_failures
[ \"\$(get_consecutive_failures)\" = '0' ] || { echo 'FAIL: reset_failures'; exit 1; }
echo 'OK: reset_failures'

end_session 'completed' 'Test OK'
[ \"\$(get_state 'status')\" = 'completed' ] || { echo 'FAIL: end_session'; exit 1; }
echo 'OK: end_session'

add_tokens 1000 500
[ \"\$(get_state 'total_tokens_input')\" = '1000' ] || { echo 'FAIL: tokens in'; exit 1; }
[ \"\$(get_state 'total_tokens_output')\" = '500' ] || { echo 'FAIL: tokens out'; exit 1; }
echo 'OK: add_tokens'

# Atomic write test
[ -f '.devteam/state/kv/test.key' ] || { echo 'FAIL: KV file not created'; exit 1; }
echo 'OK: KV file created'

# Session file MD format
SESSION_FILE=\".devteam/state/sessions/\$START.md\"
[ -f \"\$SESSION_FILE\" ] || { echo 'FAIL: session file not created'; exit 1; }
grep -q '^---$' \"\$SESSION_FILE\" || { echo 'FAIL: no frontmatter delimiters'; exit 1; }
grep -q '^id: ' \"\$SESSION_FILE\" || { echo 'FAIL: no id in frontmatter'; exit 1; }
grep -q '^status: completed' \"\$SESSION_FILE\" || { echo 'FAIL: status not updated'; exit 1; }
echo 'OK: session MD file has valid frontmatter'

# Atomic writes: concurrent test
for i in 1 2 3 4 5; do
  ( set_kv_state 'concurrent.test' \"value-\$i\" ) &
done
wait
GOT=\$(get_kv_state 'concurrent.test')
[ -n \"\$GOT\" ] || { echo 'FAIL: concurrent write left empty value'; exit 1; }
echo \"OK: concurrent write (final value: \$GOT)\"

echo 'ALL V13 TESTS PASSED'
" 2>&1
RC=$?
if [ $RC -eq 0 ]; then
    run_check "V13: file state roundtrip" "OK"
else
    run_check "V13: file state roundtrip" "FAIL (rc=$RC)"
fi
cd /Users/danilbelokurov/Desktop/devTeam
rm -rf "$TEST_DIR"

echo ""
echo "════════════════════════════════════════════════════════════"
echo " V14: No sqlite3 dependency (install.sh creates only MD state)"
echo "════════════════════════════════════════════════════════════"
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
bash /Users/danilbelokurov/Desktop/devTeam/install.sh 2>&1 | tail -3 >/dev/null
# Check no .devteam/devteam.db was created
if [ -f ".devteam/devteam.db" ]; then
    run_check "V14.1: no .devteam/devteam.db" "FAIL (.db created)"
else
    run_check "V14.1: no .devteam/devteam.db" "OK"
fi
# Check MD state structure
if [ -f ".devteam/state/circuit-breaker.md" ]; then
    run_check "V14.2: circuit-breaker.md" "OK"
else
    run_check "V14.2: circuit-breaker.md" "FAIL (not created)"
fi
if [ -f ".devteam/state/gates.md" ]; then
    run_check "V14.3: gates.md" "OK"
else
    run_check "V14.3: gates.md" "FAIL (not created)"
fi
TODAY=$(date +%Y-%m-%d)
if [ -f ".devteam/state/events/${TODAY}-events.md" ]; then
    run_check "V14.4: events file" "OK"
else
    run_check "V14.4: events file" "FAIL (not created)"
fi
# Check that hooks still work
if [ -f "$HOME/.qwen/.devteam-installed" ] || [ -f "/Users/danilbelokurov/.qwen/.devteam-installed" ]; then
    run_check "V14.5: hooks sentinel still created" "OK"
else
    run_check "V14.6: hooks sentinel" "WARN (check HOME)"
fi
cd /Users/danilbelokurov/Desktop/devTeam
rm -rf "$TEST_DIR"

echo ""
echo "════════════════════════════════════════════════════════════"
echo " V15: Sessions/KV/agent-runs MD format validity"
echo "════════════════════════════════════════════════════════════"
python3 <<'PY'
import sys
import re
from pathlib import Path

errors = []

# V15.1: Sessions have valid frontmatter
sessions_dir = Path('.devteam/state/sessions')
if sessions_dir.exists():
    for f in sessions_dir.glob('*.md'):
        text = f.read_text()
        if not re.match(r'^---\n', text):
            errors.append(f"V15.1 {f.name}: no frontmatter start")
            continue
        # Extract first --- ... --- block
        m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
        if not m:
            errors.append(f"V15.1 {f.name}: frontmatter not closed")
            continue
        fm = m.group(1)
        if 'id:' not in fm:
            errors.append(f"V15.1 {f.name}: no 'id' field")
        if 'status:' not in fm:
            errors.append(f"V15.1 {f.name}: no 'status' field")

# V15.2: KV files are non-empty
kv_dir = Path('.devteam/state/kv')
if kv_dir.exists():
    for f in kv_dir.iterdir():
        if f.is_file() and not f.name.startswith('.'):
            content = f.read_text()
            if not content:
                errors.append(f"V15.2 kv/{f.name}: empty value")

# V15.3: Agent-runs have frontmatter (if any)
runs_dir = Path('.devteam/state/agent-runs')
if runs_dir.exists():
    for f in runs_dir.glob('*.md'):
        text = f.read_text()
        if not re.match(r'^---\n', text):
            errors.append(f"V15.3 {f.name}: no frontmatter")

# V15.4: circuit-breaker.md has valid frontmatter
cb = Path('.devteam/state/circuit-breaker.md')
if cb.exists():
    text = cb.read_text()
    if not re.match(r'^---\n.*^state:', text, re.MULTILINE | re.DOTALL):
        errors.append("V15.4 circuit-breaker.md: no 'state' in frontmatter")

if errors:
    print("FAIL:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("OK: all MD files have valid frontmatter")
PY
RC=$?
if [ $RC -eq 0 ]; then
    run_check "V15: MD format validity" "OK"
else
    run_check "V15: MD format validity" "FAIL"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " RESULT: $PASS passed, $FAIL failed"
echo "════════════════════════════════════════════════════════════"
[ $FAIL -eq 0 ] && exit 0 || exit 1
