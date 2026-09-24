#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$SCRIPT_DIR/bin/omarchy-backup-ctl"

echo "=========================================="
echo "Testing omarchy-backup-ctl backend script"
echo "=========================================="

# Test 1: status output valid JSON
echo -n "[Test 1] Testing 'status' output is valid JSON... "
STATUS_JSON="$("$CTL" status)"
echo "$STATUS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert 'status' in data, 'Missing status field'
assert 'last_backup_time' in data, 'Missing last_backup_time'
assert 'timer_active' in data, 'Missing timer_active'
assert 'frequency' in data, 'Missing frequency'
assert 'remote_url' in data, 'Missing remote_url'
assert 'history' in data, 'Missing history'
"
echo "PASS"

# Test 2: Frequency validation and setting
echo -n "[Test 2] Testing 'set-frequency 2h'... "
RES="$("$CTL" set-frequency 2h)"
echo "$RES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert data.get('success') is True, 'set-frequency 2h failed'
assert data.get('frequency') == '2h', 'frequency value mismatch'
"
# Verify systemd timer OnCalendar updated
grep -q "OnCalendar=\*-\*-\* 00/2:00:00" ~/.config/systemd/user/omarchy-dotfiles-backup.timer
echo "PASS"

# Test 3: Set back to recommended 4h
echo -n "[Test 3] Restoring frequency to 4h... "
RES="$("$CTL" set-frequency 4h)"
echo "$RES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert data.get('success') is True, 'set-frequency 4h failed'
assert data.get('frequency') == '4h', 'frequency value mismatch'
"
grep -q "OnCalendar=\*-\*-\* 00/4:00:00" ~/.config/systemd/user/omarchy-dotfiles-backup.timer
echo "PASS"

# Test 4: Invalid frequency error handling
echo -n "[Test 4] Testing invalid frequency handling... "
ERR_RES="$("$CTL" set-frequency invalid_freq || true)"
echo "$ERR_RES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert data.get('success') is False, 'Should fail on invalid frequency'
"
echo "PASS"

# Test 5: Logs command
echo -n "[Test 5] Testing 'logs' command... "
LOGS_JSON="$("$CTL" logs 5)"
echo "$LOGS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert data.get('success') is True, 'logs command failed'
"
echo "PASS"

# Test 6: Performance benchmark
echo -n "[Test 6] Benchmarking status check execution speed... "
TIME_OUT=$(python3 -c "
import time, subprocess
t0 = time.perf_counter()
subprocess.run(['$CTL', 'status'], stdout=subprocess.DEVNULL)
t1 = time.perf_counter()
print(f'{(t1 - t0)*1000:.1f}ms')
")
echo "PASS (${TIME_OUT})"

# Test 7: Restore command
echo -n "[Test 7] Testing 1-button 'restore --no-pull'... "
RESTORE_JSON="$("$CTL" restore --no-pull)"
echo "$RESTORE_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert data.get('success') is True, 'restore command failed'
assert 'Dotfiles and system configurations restored' in data.get('message', ''), 'unexpected message'
"
echo "PASS"

echo "=========================================="
echo "All CLI backend tests PASSED!"
echo "=========================================="
