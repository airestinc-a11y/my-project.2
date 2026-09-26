#!/usr/bin/env bash
# Usage: JUDGE=<name> MARKER=<html marker> STRUCTURED=<json> PR_NUMBER=<n> post-verdict.sh
# 1) decides the verdict (REJECT unless APPROVE with zero blocking/major findings,
#    invalid or missing JSON = REJECT), 2) writes verdict to GITHUB_OUTPUT BEFORE
#    any network call, 3) posts/updates ONE sticky PR comment, 4) exits non-zero on REJECT.
set -euo pipefail
: "${JUDGE:?}" "${MARKER:?}" "${PR_NUMBER:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}"
RAW="${STRUCTURED:-}"
REPO="$GITHUB_REPOSITORY"

VALID=0
if [ -n "$RAW" ] && printf '%s' "$RAW" | jq -e 'type=="object" and (.verdict|IN("APPROVE","REJECT")) and (.summary|type=="string") and (.findings|type=="array") and all(.findings[]; type=="object")' >/dev/null 2>&1; then
  VALID=1
fi

if [ "$VALID" -eq 0 ]; then
  VERDICT="REJECT"
  BODY="$MARKER
## ⚖️ $JUDGE — ❌ NO VERDICT (counts as REJECT)
The judge did not return a valid structured verdict.
Raw output:
\`\`\`
${RAW:0:2000}
\`\`\`"
else
  VERDICT=$(printf '%s' "$RAW" | jq -r .verdict)
  CONF=$(printf '%s' "$RAW" | jq -r '.confidence // "guess"')
  SUMMARY=$(printf '%s' "$RAW" | jq -r .summary)
  SEVERE=$(printf '%s' "$RAW" | jq '[.findings[] | select(.severity=="blocking" or .severity=="major")] | length')
  if [ "$SEVERE" -gt 0 ] && [ "$VERDICT" = "APPROVE" ]; then
    VERDICT="REJECT"; SUMMARY="$SUMMARY (auto-downgraded: $SEVERE blocking/major finding(s) cannot coexist with APPROVE)"
  fi
  FINDINGS=$(printf '%s' "$RAW" | jq -r '.findings[] | "- **[\(.severity // "note")]** \(.title // "untitled")\(if (.location // "") != "" then " — `\(.location)`" else "" end)\n  \(.detail // "")"')
  [ -z "$FINDINGS" ] && FINDINGS="_No findings._"
  ICON="✅"; [ "$VERDICT" = "REJECT" ] && ICON="❌"
  BODY="$MARKER
## ⚖️ $JUDGE — $ICON $VERDICT [$CONF]
$SUMMARY

### Findings
$FINDINGS

<sub>Commit: \`${HEAD_SHA:-unknown}\` · Run: ${GITHUB_SERVER_URL:-https://github.com}/${REPO}/actions/runs/${GITHUB_RUN_ID:-0}</sub>"
fi

# Record the verdict first: a failure to comment must never hide the result.
echo "verdict=$VERDICT" >> "$GITHUB_OUTPUT"
echo "::notice title=$JUDGE::$VERDICT"
BODY="${BODY:0:60000}"

# Sticky comment: only comments by the Actions bot that start with MARKER.
IDS=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments" --paginate \
  --jq ".[] | select(.user.login==\"github-actions[bot]\" and (.body|startswith(\"$MARKER\"))) | .id")
EXISTING="${IDS%%$'\n'*}"
if [ -n "$EXISTING" ]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$EXISTING" -f body="$BODY" >/dev/null
else
  gh api -X POST "repos/$REPO/issues/$PR_NUMBER/comments" -f body="$BODY" >/dev/null
fi

[ "$VERDICT" = "APPROVE" ] || { echo "::error title=$JUDGE::REJECT — see PR comment"; exit 1; }
