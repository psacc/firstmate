#!/usr/bin/env bash
# Behavior tests for bin/fm-lavish-check.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-lavish-check)

BIN="$ROOT/bin/fm-lavish-check.sh"

classify() {
  # classify <lavish-axi-poll-text> -> stdout of --classify for a fixed board label.
  printf '%s' "$1" | "$BIN" --classify "work-status-board.html"
}

# Samples are the real `lavish-axi poll` text digest (0.1.42): a non-empty send
# renders a `prompts[N]{...}:` header, an empty one renders `prompts: []`.
PROMPTS_2=$'session:\n  status: feedback\nprompts[2]{uid,prompt,selector,tag,text}:\n  "",a,"",message,""\n  "",b,"",message,""\nnext_step: "apply the changes"'
SEND_AND_END_1=$'session:\n  status: ended\nprompts[1]{uid,prompt,selector,tag,text}:\n  "",final,"",message,""\nnext_step: "final feedback"'
WARNINGS_ONLY=$'session:\n  status: feedback\nprompts: []\nlayout_warnings[1]{selector,kind,overflowPx,viewportWidth,severity,persistent}:\n  #x,overlapping-text,3,1200,error,false\nnext_step: "fix overflow"'
WAITING=$'session:\n  status: waiting\nnext_step: "No user feedback arrived before the optional timeout."'
ENDED_NO_PROMPTS=$'session:\n  status: ended\nprompts: []'

test_classify_real_prompts_wakes() {
  local out
  out=$(classify "$PROMPTS_2")
  assert_contains "$out" "work-status-board.html" "wake line lost the board label"
  assert_contains "$out" "2 prompt(s)" "wake line lost the prompt count"
  pass "fm-lavish-check --classify: real prompts wake firstmate with a count"
}

test_classify_send_and_end_with_prompts_wakes() {
  local out
  out=$(classify "$SEND_AND_END_1")
  assert_contains "$out" "1 prompt(s)" "Send & End final feedback should still wake"
  pass "fm-lavish-check --classify: ended-with-prompts (Send & End) wakes"
}

test_classify_warnings_only_is_silent() {
  local out
  out=$(classify "$WARNINGS_ONLY")
  [ -z "$out" ] || fail "warnings-only return must stay silent, got: $out"
  pass "fm-lavish-check --classify: warnings-only (empty prompts) stays silent"
}

test_classify_waiting_is_silent() {
  local out
  out=$(classify "$WAITING")
  [ -z "$out" ] || fail "waiting return must stay silent, got: $out"
  pass "fm-lavish-check --classify: waiting stays silent"
}

test_classify_ended_without_prompts_is_silent() {
  local out
  out=$(classify "$ENDED_NO_PROMPTS")
  [ -z "$out" ] || fail "ended-without-prompts must stay silent, got: $out"
  pass "fm-lavish-check --classify: ended-without-prompts stays silent"
}

test_classify_empty_and_unrecognized_are_silent() {
  local out
  out=$(classify '')
  [ -z "$out" ] || fail "empty input must stay silent, got: $out"
  out=$(classify $'just some noise\nno header here')
  [ -z "$out" ] || fail "unrecognized input must stay silent, got: $out"
  pass "fm-lavish-check --classify: empty and unrecognized input stay silent"
}

test_classify_prompts_word_mid_line_is_silent() {
  # The header match is line-anchored: `prompts[N]` inside a next_step sentence
  # must NOT be read as real feedback.
  local out
  out=$(classify $'session:\n  status: waiting\nnext_step: "re-run to collect prompts[5] later"')
  [ -z "$out" ] || fail "a mid-line prompts[N] must stay silent, got: $out"
  pass "fm-lavish-check --classify: a mid-line prompts[N] does not wake"
}

test_generate_creates_registered_check() {
  local home board out check trust
  home="$TMP_ROOT/gen-ok"
  mkdir -p "$home/state"
  board="$home/board.html"
  printf '<html><body>b</body></html>' > "$board"
  out=$(FM_HOME="$home" "$BIN" lavish-demo-1 "$board" 2>&1) \
    || fail "generate failed: $out"
  assert_contains "$out" "armed: state/lavish-demo-1.check.sh" "generate did not report armed"
  check="$home/state/lavish-demo-1.check.sh"
  trust="$home/state/lavish-demo-1.check-trust"
  assert_present "$check" "check script was not created"
  assert_present "$trust" "check was not registered (trust file missing)"
  [ -x "$check" ] || fail "generated check is not executable"
  [ ! -L "$check" ] || fail "generated check must be a regular file, not a symlink"
  assert_grep "lavish-axi poll" "$check" "generated check does not poll"
  assert_grep "board.html" "$check" "generated check lost the board path"
  assert_grep "--classify" "$check" "generated check does not delegate the wake decision"
  pass "fm-lavish-check: generate creates a registered, executable per-board check"
}

test_generate_refresh_is_idempotent() {
  local home board
  home="$TMP_ROOT/gen-refresh"
  mkdir -p "$home/state"
  board="$home/board.html"
  printf '<html></html>' > "$board"
  FM_HOME="$home" "$BIN" lavish-demo-2 "$board" >/dev/null 2>&1 || fail "first generate failed"
  FM_HOME="$home" "$BIN" lavish-demo-2 "$board" >/dev/null 2>&1 || fail "refresh (regenerate) failed"
  assert_present "$home/state/lavish-demo-2.check-trust" "refresh left the check unregistered"
  pass "fm-lavish-check: regenerating an existing board check is idempotent"
}

test_generate_rejects_missing_board() {
  local home
  home="$TMP_ROOT/gen-missing"
  mkdir -p "$home/state"
  FM_HOME="$home" "$BIN" lavish-demo-3 "$home/nope.html" >/dev/null 2>&1
  expect_code 1 $? "missing board file should exit 1"
  assert_absent "$home/state/lavish-demo-3.check.sh" "no check should be written for a missing board"
  pass "fm-lavish-check: missing board file is refused"
}

test_generate_rejects_invalid_id() {
  local home board
  home="$TMP_ROOT/gen-badid"
  mkdir -p "$home/state"
  board="$home/board.html"
  printf '<html></html>' > "$board"
  FM_HOME="$home" "$BIN" "bad id" "$board" >/dev/null 2>&1
  expect_code 2 $? "invalid task id should exit 2 (usage)"
  pass "fm-lavish-check: invalid task id is refused"
}

test_classify_real_prompts_wakes
test_classify_send_and_end_with_prompts_wakes
test_classify_warnings_only_is_silent
test_classify_waiting_is_silent
test_classify_ended_without_prompts_is_silent
test_classify_empty_and_unrecognized_are_silent
test_classify_prompts_word_mid_line_is_silent
test_generate_creates_registered_check
test_generate_refresh_is_idempotent
test_generate_rejects_missing_board
test_generate_rejects_invalid_id
