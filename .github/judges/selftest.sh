#!/usr/bin/env bash
# Self-test for the gate scripts. Runs post-verdict.sh against a stubbed `gh`
# and prepare-inputs.sh against hostile PR text. Exit 0 = all cases as specified.
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T" .judge-input' EXIT
cat > "$T/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_LOG"
case "$*" in *"-X PATCH"*|*"-X POST"*) echo '{"id":1}';; *"--jq"*) printf '%s' "${STUB_IDS:-}";; esac
STUB
chmod +x "$T/gh"
export STUB_LOG="$T/log" PATH="$T:$PATH" GITHUB_OUTPUT="$T/out" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 PR_NUMBER=7 HEAD_SHA=abc JUDGE=J MARKER="<!-- m -->"
fail=0
expect() { # expect <exit> <label> <json>
  STRUCTURED="$3" .github/judges/post-verdict.sh >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq "$1" ]; then echo "ok   $2 (exit $rc)"; else echo "FAIL $2 (exit $rc, want $1)"; fail=1; fi
}
expect 0 approve            '{"verdict":"APPROVE","confidence":"likely","summary":"ok","findings":[]}'
expect 0 approve+minor      '{"verdict":"APPROVE","confidence":"certain","summary":"s","findings":[{"severity":"minor","title":"t","detail":"d","location":"f:1"}]}'
expect 1 approve+major      '{"verdict":"APPROVE","confidence":"certain","summary":"s","findings":[{"severity":"major","title":"t","detail":"d"}]}'
expect 1 approve+blocking   '{"verdict":"APPROVE","confidence":"certain","summary":"s","findings":[{"severity":"blocking","title":"t","detail":"d"}]}'
expect 1 reject             '{"verdict":"REJECT","confidence":"certain","summary":"bad","findings":[]}'
expect 1 json-string        '"x"'
expect 1 empty-object       '{}'
expect 1 empty              ''
expect 1 garbage            'not json'
expect 1 findings-not-objects '{"verdict":"APPROVE","confidence":"certain","summary":"x","findings":["s"]}'
STUB_IDS=$'42\n43' expect 0 sticky-existing '{"verdict":"APPROVE","confidence":"likely","summary":"ok","findings":[]}'
grep -q "PATCH repos/o/r/issues/comments/42" "$STUB_LOG" && echo "ok   sticky-existing patched oldest id" || { echo "FAIL sticky PATCH"; fail=1; }
[ "$(grep -c '^verdict=' "$GITHUB_OUTPUT")" -eq 11 ] && echo "ok   verdict written 11/11" || { echo "FAIL GITHUB_OUTPUT count"; fail=1; }
# prepare-inputs with hostile text
if BASE_REF=main PR_TITLE='-n $(title) `x`' PR_BODY=$'body\n$(rm -rf /)' GITHUB_WORKSPACE=. .github/judges/prepare-inputs.sh >/dev/null 2>&1 \
   && grep -qF -- '-n $(title) `x`' .judge-input/contract.md && grep -qF '$(rm -rf /)' .judge-input/contract.md; then
  echo "ok   prepare-inputs renders hostile text literally"
else echo "FAIL prepare-inputs"; fail=1; fi
exit $fail
