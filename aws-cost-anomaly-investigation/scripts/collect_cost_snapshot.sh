#!/usr/bin/env bash
# One-pass, READ-ONLY cost snapshot for Phase 1–2 of the RCA.
# Runs each Cost Explorer query exactly once (no loops, no retries) and saves JSON.
# Cost: ~6 Cost Explorer API requests (~$0.06).
#
# Usage:
#   ./collect_cost_snapshot.sh <baseline_start> <spike_end> [service_name] [region] [profile]
# Example:
#   ./collect_cost_snapshot.sh 2026-10-20 2026-11-15 "EC2 - Other" us-east-1 prod-readonly
#
# Dates: YYYY-MM-DD, end date exclusive.

set -euo pipefail

START="${1:?baseline_start required (YYYY-MM-DD)}"
END="${2:?spike_end required (YYYY-MM-DD, exclusive)}"
SERVICE="${3:-}"
REGION_FILTER="${4:-}"
PROFILE_ARG=()
if [[ -n "${5:-}" ]]; then PROFILE_ARG=(--profile "$5"); fi

OUT="cost_snapshot_${START}_${END}"
mkdir -p "$OUT"
CE=(aws ce --region us-east-1 "${PROFILE_ARG[@]}" --output json)

echo "[1/6] Identity"
aws sts get-caller-identity "${PROFILE_ARG[@]}" > "$OUT/00_identity.json"

echo "[2/6] Detected anomalies"
"${CE[@]}" get-anomalies --date-interval "StartDate=${START},EndDate=${END}" \
  > "$OUT/01_anomalies.json" || echo "  WARN: get-anomalies failed (record as Data Gap)"

echo "[3/6] Daily total (Unblended + Amortized)"
"${CE[@]}" get-cost-and-usage --time-period "Start=${START},End=${END}" \
  --granularity DAILY --metrics UnblendedCost AmortizedCost \
  > "$OUT/02_daily_total.json"

echo "[4/6] Daily by service"
"${CE[@]}" get-cost-and-usage --time-period "Start=${START},End=${END}" \
  --granularity DAILY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  > "$OUT/03_daily_by_service.json"

echo "[5/6] Monthly by record type"
"${CE[@]}" get-cost-and-usage --time-period "Start=${START},End=${END}" \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=RECORD_TYPE \
  > "$OUT/04_record_type.json"

if [[ -n "$SERVICE" ]]; then
  echo "[6/6] Usage types for service: $SERVICE"
  if [[ -n "$REGION_FILTER" ]]; then
    FILTER="{\"And\":[{\"Dimensions\":{\"Key\":\"SERVICE\",\"Values\":[\"${SERVICE}\"]}},{\"Dimensions\":{\"Key\":\"REGION\",\"Values\":[\"${REGION_FILTER}\"]}}]}"
  else
    FILTER="{\"Dimensions\":{\"Key\":\"SERVICE\",\"Values\":[\"${SERVICE}\"]}}"
  fi
  "${CE[@]}" get-cost-and-usage --time-period "Start=${START},End=${END}" \
    --granularity DAILY --metrics UnblendedCost UsageQuantity \
    --filter "$FILTER" --group-by Type=DIMENSION,Key=USAGE_TYPE \
    > "$OUT/05_usage_types.json"
else
  echo "[6/6] Skipped usage-type drill-down (no service given)"
fi

echo "Done. Files in ./$OUT — feed them to Claude for Phase 1–3 analysis."

