#!/usr/bin/env bash
# Verifies the BedrockUser permission set from the user's side.
# Run with credentials from the BedrockUser permission set, e.g.:
#   aws sso login --profile bedrock-user
#   AWS_PROFILE=bedrock-user ./tests/verify.sh
#
# Required environment variables:
#   REGION            Bedrock region (same as var.region)
#   ALLOWED_MODEL     A model ID or inference profile ID on the allow list
#   BLOCKED_MODEL     A model ID that is NOT on the allow list
#   GUARDRAIL_ID      terraform output guardrail_id
#   GUARDRAIL_VERSION terraform output guardrail_version
set -uo pipefail

: "${REGION:?}" "${ALLOWED_MODEL:?}" "${BLOCKED_MODEL:?}" "${GUARDRAIL_ID:?}" "${GUARDRAIL_VERSION:?}"

MESSAGES='[{"role":"user","content":[{"text":"Reply with the single word: ok"}]}]'
GUARDRAIL="guardrailIdentifier=${GUARDRAIL_ID},guardrailVersion=${GUARDRAIL_VERSION}"
pass=0
fail=0

# expect <name> <expected: allow|deny> <command...>
expect() {
  local name=$1 expected=$2
  shift 2
  local out
  if out=$("$@" 2>&1); then
    result=allow
  elif grep -q "AccessDeniedException" <<<"$out"; then
    result=deny
  else
    echo "ERROR  $name: unexpected failure"
    echo "$out" | sed 's/^/       /'
    fail=$((fail + 1))
    return
  fi

  if [[ $result == "$expected" ]]; then
    echo "PASS   $name ($result)"
    pass=$((pass + 1))
  else
    echo "FAIL   $name (expected $expected, got $result)"
    fail=$((fail + 1))
  fi
}

converse() {
  aws bedrock-runtime converse --region "$REGION" --model-id "$1" \
    --messages "$MESSAGES" "${@:2}" --output json
}

expect "allowed model + pinned guardrail" allow \
  converse "$ALLOWED_MODEL" --guardrail-config "$GUARDRAIL"

expect "allowed model without guardrail" deny \
  converse "$ALLOWED_MODEL"

expect "allowed model + DRAFT guardrail" deny \
  converse "$ALLOWED_MODEL" --guardrail-config "guardrailIdentifier=${GUARDRAIL_ID},guardrailVersion=DRAFT"

expect "model not on allow list + guardrail" deny \
  converse "$BLOCKED_MODEL" --guardrail-config "$GUARDRAIL"

# Tamper protection (DenyWeakeningControls) is not tested here on purpose:
# if it were misconfigured, the test itself would delete the logging setup.
# Check it with the IAM policy simulator instead (see README).

echo
echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]]
