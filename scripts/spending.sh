#!/usr/bin/env bash
# Spend and budget per LiteLLM key: this budget period, and the last 7 days
# from the audit log. Kids are the keys with a birthdate.
# Usage: ./scripts/spending.sh
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose exec -T postgres psql -U litellm -d litellm <<'SQL'
SELECT t.key_alias AS key,
       CASE WHEN t.metadata ? 'birthdate' THEN 'kid' ELSE 'parent' END AS who,
       round(t.spend::numeric, 2) AS spent,
       t.max_budget AS budget,
       CASE WHEN t.max_budget > 0 THEN round((100 * t.spend / t.max_budget)::numeric) END AS pct,
       to_char(t.budget_reset_at, 'YYYY-MM-DD') AS resets,
       coalesce(w.requests, 0) AS req_7d,
       round(coalesce(w.spend, 0)::numeric, 2) AS spent_7d,
       CASE WHEN t.blocked THEN 'blocked' ELSE '' END AS status
FROM "LiteLLM_VerificationToken" t
LEFT JOIN (
  SELECT api_key, count(*) AS requests, sum(spend) AS spend
  FROM "LiteLLM_SpendLogs"
  WHERE "startTime" > now() - interval '7 days'
  GROUP BY api_key
) w ON w.api_key = t.token
WHERE t.key_alias IS NOT NULL
ORDER BY who DESC, t.key_alias;
SQL
echo "Change a kid's budget: ./scripts/set-kid-budget.sh <kid> <usd>"
