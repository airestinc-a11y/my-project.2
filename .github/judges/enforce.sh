#!/usr/bin/env bash
# Makes the two judges MANDATORY on the default branch (server-side, no bypass).
# Requires: GH_TOKEN with admin on the repo, and a plan where branch protection
# is available (GitHub Free = public repos only; private repos need Pro/Team).
# Usage: GH_TOKEN=... .github/judges/enforce.sh [owner/repo] [branch]
#
# Trade-off you are accepting (deliberate): required_approving_review_count=1 +
# require_code_owner_reviews=true is the only thing that stops a PR from editing
# post-verdict.sh / the workflows to green-light itself. GitHub never counts the
# PR author's own approval, so a solo owner needs a second account (or a
# collaborator) to approve PRs that touch /.github, /.claude or AGENTS.md.
set -euo pipefail
REPO="${1:-airestinc-a11y/my-project.2}"; BRANCH="${2:-main}"
ACTIONS_APP_ID=15368   # GitHub Actions app: only checks produced by Actions satisfy the rule
curl -sS --fail-with-body -X PUT \
  -H "Authorization: Bearer ${GH_TOKEN:?}" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
  "https://api.github.com/repos/$REPO/branches/$BRANCH/protection" \
  -d "$(cat <<JSON
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      {"context": "Judge 1 — The Court", "app_id": $ACTIONS_APP_ID},
      {"context": "Judge 2 — Doubt",     "app_id": $ACTIONS_APP_ID}
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "required_conversation_resolution": true
}
JSON
)" | jq '{checks: .required_status_checks.checks, enforce_admins: .enforce_admins.enabled, reviews: .required_pull_request_reviews | {required_approving_review_count, require_code_owner_reviews}}'
echo "Enforced on $REPO@$BRANCH: PRs only, both judges required, code-owner review required, admins not exempt."
