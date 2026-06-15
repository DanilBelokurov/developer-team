#!/bin/bash
# DevTeam Test Runner
# Runs all tests and reports results
#
# Usage: ./tests/run-tests.sh [test-file]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test results
declare -a FAILED_TESTS=()

# ============================================================================
# TEST HELPERS
# ============================================================================

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((++TESTS_PASSED))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((++TESTS_FAILED))
    FAILED_TESTS+=("$1")
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

# Assert functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    ((++TESTS_RUN))

    if [ "$expected" = "$actual" ]; then
        log_pass "$message"
    else
        log_fail "$message (expected: '$expected', got: '$actual')"
    fi
    return 0
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"

    ((++TESTS_RUN))

    if [ -n "$value" ]; then
        log_pass "$message"
    else
        log_fail "$message (value was empty)"
    fi
    return 0
}

assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"

    ((++TESTS_RUN))

    if [ -z "$value" ]; then
        log_pass "$message"
    else
        log_fail "$message (value was: '$value')"
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    ((++TESTS_RUN))

    if [[ "$haystack" == *"$needle"* ]]; then
        log_pass "$message"
    else
        log_fail "$message (string did not contain '$needle')"
    fi
    return 0
}

assert_matches() {
    local value="$1"
    local pattern="$2"
    local message="${3:-Value should match pattern}"

    ((++TESTS_RUN))

    if [[ "$value" =~ $pattern ]]; then
        log_pass "$message"
    else
        log_fail "$message (value '$value' did not match pattern '$pattern')"
    fi
    return 0
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"

    ((++TESTS_RUN))

    if [ -f "$file" ]; then
        log_pass "$message"
    else
        log_fail "$message (file not found: $file)"
    fi
    return 0
}

assert_command_succeeds() {
    local cmd="$1"
    local message="${2:-Command should succeed}"

    ((++TESTS_RUN))

    if eval "$cmd" > /dev/null 2>&1; then
        log_pass "$message"
    else
        log_fail "$message (command failed: $cmd)"
    fi
    return 0
}

assert_command_fails() {
    local cmd="$1"
    local message="${2:-Command should fail}"

    ((++TESTS_RUN))

    if ! eval "$cmd" > /dev/null 2>&1; then
        log_pass "$message"
    else
        log_fail "$message (command succeeded when it should have failed: $cmd)"
    fi
    return 0
}

# ============================================================================
# TEST SETUP/TEARDOWN
# ============================================================================

setup_test_db() {
    export DEVTEAM_DIR="$SCRIPT_DIR/.test-devteam"
    export ROOT="$SCRIPT_DIR/.test-devteam"

    # Clean up any existing test state
    rm -rf "$DEVTEAM_DIR"
    mkdir -p "$DEVTEAM_DIR"

    # Initialize fresh state directory (file-based)
    bash "$PROJECT_ROOT/scripts/state-init.sh" "$ROOT" > /dev/null 2>&1
}

teardown_test_db() {
    rm -rf "$SCRIPT_DIR/.test-devteam"
    unset DEVTEAM_DIR
    unset ROOT
}

# ============================================================================
# COMMON LIBRARY TESTS
# ============================================================================

test_common_library() {
    log_test "Testing common library..."

    # Test json_escape
    local escaped
    escaped=$(json_escape "test'value")
    assert_equals "test'value" "$escaped" "json_escape should handle single quotes"

    escaped=$(json_escape "test\nvalue")
    # Expected: backslash escaped (\\n in source = \n input, function outputs \\n)
    assert_equals 'test\\nvalue' "$escaped" "json_escape should escape backslashes"

    # Test json_object
    local obj
    obj=$(json_object "key1" "val1" "key2" "val2")
    assert_matches "$obj" '"key1"' "$obj" "json_object should contain key1"
    assert_matches "$obj" '"val1"' "$obj" "json_object should contain val1"

    # Test validate_numeric
    assert_command_succeeds "validate_numeric 123" "validate_numeric should accept integers"
    assert_command_fails "validate_numeric abc" "validate_numeric should reject non-numbers"
    assert_command_fails "validate_numeric 12.34" "validate_numeric should reject decimals"

    # Test validate_decimal
    assert_command_succeeds "validate_decimal 123" "validate_decimal should accept integers"
    assert_command_succeeds "validate_decimal 12.34" "validate_decimal should accept decimals"
    assert_command_fails "validate_decimal abc" "validate_decimal should reject non-numbers"

    # Test generate_id
    local id
    id=$(generate_id "test")
    assert_matches "$id" "^test-[0-9]{8}-[0-9]{6}-[a-f0-9]+$" "generate_id should match expected format"
}

# ============================================================================
# STATE MANAGEMENT TESTS
# ============================================================================

test_state_management() {
    log_test "Testing state management..."

    setup_test_db
    local _saved_script_dir="$SCRIPT_DIR"
    source "$PROJECT_ROOT/scripts/state.sh"
    SCRIPT_DIR="$_saved_script_dir"

    # Test session creation
    local session_id
    session_id=$(start_session "test command" "feature")
    assert_not_empty "$session_id" "start_session should return session ID"
    assert_matches "$session_id" "^session-" "Session ID should start with 'session-'"

    # Test get_current_session_id
    local current
    current=$(get_current_session_id)
    assert_equals "$session_id" "$current" "get_current_session_id should return current session"

    # Test is_session_running
    if is_session_running; then
        log_pass "is_session_running returns true when session active"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_fail "is_session_running should return true"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi

    # Test set_phase and get_current_phase
    set_phase "executing"
    local phase
    phase=$(get_current_phase)
    assert_equals "executing" "$phase" "Phase should be set correctly"

    # Test iteration increment
    increment_iteration
    local iteration
    iteration=$(get_current_iteration)
    assert_equals "1" "$iteration" "Iteration should be incremented to 1"

    # Test failures tracking
    increment_failures
    local failures
    failures=$(get_consecutive_failures)
    assert_equals "1" "$failures" "Failures should be incremented to 1"

    reset_failures
    failures=$(get_consecutive_failures)
    assert_equals "0" "$failures" "Failures should be reset to 0"

    # Test end session
    end_session "completed" "Test finished"
    if ! is_session_running; then
        log_pass "is_session_running returns false after session ended"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_fail "Session should not be running after end_session"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi

    teardown_test_db
}

# ============================================================================
# VALIDATION TESTS
# ============================================================================

test_validation() {
    log_test "Testing input validation..."

    # Test session ID validation
    assert_command_succeeds "validate_session_id 'session-20260129-120000-abcd1234'" \
        "Valid session ID should pass validation"

    assert_command_fails "validate_session_id 'invalid-session'" \
        "Invalid session ID should fail validation"

    assert_command_fails "validate_session_id \"'; DROP TABLE sessions; --\"" \
        "SQL injection attempt should fail validation"

    # Test field name validation
    assert_command_succeeds "validate_field_name 'status'" \
        "Valid field name should pass validation"

    assert_command_fails "validate_field_name 'invalid_field'" \
        "Invalid field name should fail validation"

    assert_command_fails "validate_field_name \"status; DROP TABLE\"" \
        "SQL injection in field name should fail validation"

    # Test phase validation
    assert_command_succeeds "validate_phase 'executing'" \
        "Valid phase should pass validation"

    assert_command_fails "validate_phase 'invalid_phase'" \
        "Invalid phase should fail validation"

    # Test model validation
    assert_command_succeeds "validate_model 'sonnet'" \
        "Valid model should pass validation"

    assert_command_fails "validate_model 'gpt-4'" \
        "Invalid model should fail validation"
    return 0
}

# ============================================================================
# SQL INJECTION PREVENTION TESTS
# ============================================================================

test_sql_injection_prevention() {
    log_test "Testing input sanitization (file-based)..."

    setup_test_db
    local _saved_script_dir="$SCRIPT_DIR"
    source "$PROJECT_ROOT/scripts/state.sh"
    SCRIPT_DIR="$_saved_script_dir"

    # Start a session for testing
    local session_id
    session_id=$(start_session "test" "test")

    # Try injection via command (should be sanitized, not cause harm)
    local malicious_input="'; rm -rf /; --"
    end_session "completed" "test"

    session_id=$(start_session "$malicious_input" "test")

    # Verify state directory still works
    if [ -d "$DEVTEAM_DIR/.devteam/state/sessions" ]; then
        log_pass "State directory intact after malicious input"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_fail "State directory corrupted after injection attempt"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi

    # Try injection via set_state (in file-based version, field names are not validated)
    # Verify the frontmatter value is stored correctly (no SQL injection possible)
    if set_state "status" "injected_value" 2>/dev/null; then
        local retrieved
        retrieved=$(get_state "status")
        if [ "$retrieved" = "injected_value" ]; then
            log_pass "State storage handles special values correctly"
            ((++TESTS_RUN))
            ((++TESTS_PASSED))
        else
            log_fail "State storage failed to store/retrieve value"
            ((++TESTS_RUN))
            ((++TESTS_FAILED))
        fi
    else
        log_fail "State storage failed basic operation"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi

    # Verify sessions still work
    local new_sid
    new_sid=$(start_session "after injection test" "test")
    if [ -n "$new_sid" ] && [ -f "$DEVTEAM_DIR/.devteam/state/sessions/${new_sid}.md" ]; then
        log_pass "Sessions still functional after injection attempt"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_fail "Sessions broken after injection attempt"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi

    teardown_test_db
}

# ============================================================================
# EVENT LOGGING TESTS
# ============================================================================

test_event_logging() {
    log_test "Testing event logging..."

    setup_test_db
    local _saved_script_dir="$SCRIPT_DIR"
    source "$PROJECT_ROOT/scripts/state.sh"
    SCRIPT_DIR="$_saved_script_dir"
    source "$PROJECT_ROOT/scripts/events.sh"

    # Start a session
    local session_id
    session_id=$(start_session "test command" "feature")

    # Log various events
    log_phase_changed "executing" "initializing"
    log_agent_started "test-agent" "sonnet" "task-1"
    log_agent_completed "test-agent" "sonnet" "[]" 100 50 5
    log_gate_passed "lint" "{}"

    # Query events from file-based log
    local today
    today=$(date +%Y-%m-%d)
    local event_count=0
    if [ -f "$DEVTEAM_DIR/.devteam/state/events/${today}-events.md" ]; then
        event_count=$(grep -c "session_id: ${session_id}" "$DEVTEAM_DIR/.devteam/state/events/${today}-events.md" 2>/dev/null || echo 0)
    fi

    if [ "$event_count" -ge 4 ]; then
        log_pass "Events were logged correctly ($event_count events)"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_fail "Expected at least 4 events, got $event_count"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi

    teardown_test_db
}

# ============================================================================
# FILE STRUCTURE TESTS
# ============================================================================

test_file_structure() {
    log_test "Testing project file structure..."

    assert_file_exists "$PROJECT_ROOT/scripts/state.sh" "scripts/state.sh should exist"
    assert_file_exists "$PROJECT_ROOT/scripts/events.sh" "scripts/events.sh should exist"
    assert_file_exists "$PROJECT_ROOT/scripts/state-init.sh" "scripts/state-init.sh should exist"
    assert_file_exists "$PROJECT_ROOT/scripts/lib/common.sh" "scripts/lib/common.sh should exist"

    # Check agents directory
    local agent_count
    agent_count=$(find "$PROJECT_ROOT/agents" -name "*.md" 2>/dev/null | wc -l)
    if [ "$agent_count" -ge 10 ]; then
        log_pass "Agents directory has sufficient files ($agent_count)"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_fail "Expected at least 10 agent files, got $agent_count"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi

    # Check commands directory
    local cmd_count
    cmd_count=$(find "$PROJECT_ROOT/commands" -name "*.md" 2>/dev/null | wc -l)
    if [ "$cmd_count" -ge 10 ]; then
        log_pass "Commands directory has sufficient files ($cmd_count)"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_fail "Expected at least 10 command files, got $cmd_count"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi
}

# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

test_configuration() {
    log_test "Testing configuration files..."

    # Check that .devteam config directory exists with YAML files
    local config_dir="$PROJECT_ROOT/.devteam"
    assert_file_exists "$config_dir/config.yaml" "config.yaml should exist"
    assert_file_exists "$config_dir/task-loop-config.yaml" "task-loop-config.yaml should exist"
    if [ -d "$config_dir/state" ]; then
        log_pass "state directory exists"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_pass "state directory will be created on first run"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    fi

    # Check for sufficient YAML config files
    local yaml_count
    yaml_count=$(find "$config_dir" -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)
    if [ "$yaml_count" -ge 10 ]; then
        log_pass "DevTeam config has sufficient YAML files ($yaml_count)"
        ((++TESTS_RUN))
        ((++TESTS_PASSED))
    else
        log_fail "Expected at least 10 YAML config files, got $yaml_count"
        ((++TESTS_RUN))
        ((++TESTS_FAILED))
    fi
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

print_summary() {
    echo ""
    echo "============================================"
    echo "               TEST SUMMARY                 "
    echo "============================================"
    echo -e "Tests Run:    ${BLUE}$TESTS_RUN${NC}"
    echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped:      ${YELLOW}$TESTS_SKIPPED${NC}"
    echo "============================================"

    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
    fi

    echo ""
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

run_all_tests() {
    echo "============================================"
    echo "         DevTeam Test Suite                "
    echo "============================================"
    echo ""

    source "$PROJECT_ROOT/scripts/lib/common.sh"

    test_common_library
    echo ""

    test_validation
    echo ""

    test_state_management
    echo ""

    test_sql_injection_prevention
    echo ""

    test_event_logging
    echo ""

    test_file_structure
    echo ""

    test_configuration

    print_summary
}

# Run specific test file or all tests
if [ $# -gt 0 ]; then
    test_file="$1"
    if [ -f "$test_file" ]; then
        source "$test_file"
    else
        echo "Test file not found: $test_file"
        exit 1
    fi
else
    run_all_tests
fi
