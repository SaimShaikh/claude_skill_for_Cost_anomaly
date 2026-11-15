---
name: aws-cost-anomaly-investigation
description: Investigates unexpected AWS cost increases and produces an evidence-backed Root Cause Analysis (RCA) using only AWS-native services (Cost Anomaly Detection, Cost Explorer, CUR + Athena, CloudTrail, Config, CloudWatch, Trusted Advisor, Compute Optimizer). Use when the user reports an AWS bill spike, a Cost Anomaly Detection alert, a budget alert, or asks "why did our AWS cost go up". Drills down from service to account, region, usage type, resource, change event, and actor, then assigns ownership (FinOps/Cloud, DevOps/Platform, Developers, Data, Security) with a handoff. Runs as a single linear pass with hard stop rules — no loops.
---

# AWS Cost Anomaly Investigation (RCA)

## Goal
Find the **actual root cause** of an AWS cost increase — not the symptom.

| Level | Example | Is it the RCA? |
|---|---|---|
| Symptom | "EC2 cost went up 40%" | ❌ |
| Driver | "NAT Gateway bytes in us-east-1 up 6x" | ❌ |
| Resource | "nat-0abc in vpc-prod, EKS cluster `payments`" | ❌ |
| **Root cause** | "Deployment of `payments-api` v2.3 on 3 Nov removed the ECR VPC endpoint route; image pulls + S3 traffic now go through NAT. Change made by role `github-deploy` (CloudTrail `DeleteVpcEndpoints`, 3 Nov 10:42 UTC)." | ✅ |

An RCA is complete only when it answers: **What** changed, **where** (account/region/resource), **when**, **who/what** made the change, **why** it costs more (rate vs usage), **how much**, and **which team owns the fix**.

## Hard Rules (read first)

1. **Read-only.** Never create, modify, stop, or delete any AWS resource. Only `Get*`, `List*`, `Describe*`, `Lookup*` and Athena `SELECT`. Recommend fixes; do not apply them.
2. **No loops.** The investigation is a **single linear pass through Phases 0 → 7**. Each phase runs once. See [No-Loop Rules](#no-loop-rules).
3. **AWS-native only.** Use the services listed in `references/aws-services.md`. No third-party tools.
4. **Evidence for every claim.** Every finding cites the command/query and the number it returned. If you could not verify something, label it `UNVERIFIED` — never guess.
5. **Cost Explorer API costs $0.01 per request.** Plan queries; never repeat an identical query.
6. Cost Explorer / Cost Anomaly Detection API calls use `--region us-east-1`.

## No-Loop Rules

- Phases run in order **exactly once**: 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7.
- **Drill-down budget:** Phase 2 has at most **5 levels** (Service → Account → Region → Usage Type → Resource). Stop at the first level where one item explains ≥ 70 % of the delta.
- **Top-N limit:** Investigate at most the **top 3 cost drivers** (by $ delta). Mention the rest in the report as "not investigated".
- **Retry limit:** A failed command may be retried **once** (e.g., fix a typo/flag). If it fails again, record it as a **Data Gap** and move on.
- **Missing access/data** (no CUR, no CloudTrail Lake, no resource-level data, AccessDenied) → record as Data Gap, state which team can provide it, continue with what you have.
- **Never re-run an identical query.** Keep a running query log.
- **Stop conditions** — go straight to Phase 6/7 when any is true:
  - Root cause found with HIGH confidence (see Phase 5).
  - All top-3 drivers investigated.
  - Remaining questions require another team's access/knowledge → hand off.
- If the user's question is answered, **stop**. Do not offer to "keep digging" automatically; list optional next steps instead.

---

## Phase 0 — Scope & Access (once)

Collect from the user (ask only what is missing, in one message):
- Account(s) / AWS Organization payer? Which account is affected?
- Time window of the spike and expected "normal" baseline period.
- Alert source (Cost Anomaly Detection, Budget, invoice, CUR report) and amount.
- Is CUR 2.0 / Data Exports to S3 + Athena set up? Is CloudTrail Lake enabled?

Verify access:
```bash
aws sts get-caller-identity
aws ce get-cost-and-usage --region us-east-1 --time-period Start=<YYYY-MM-01>,End=<YYYY-MM-02> --granularity DAILY --metrics UnblendedCost
```
Required permissions: see `references/iam-readonly-policy.json`.

## Phase 1 — Confirm & Quantify the Anomaly

1. Pull existing anomalies (AWS already did root-cause hints):
   ```bash
   aws ce get-anomalies --region us-east-1 --date-interval StartDate=<start>,EndDate=<end>
   ```
   Record `RootCauses` (service, account, region, usage type), `Impact.TotalImpact`, start/end dates.
2. Compare **spike window vs baseline window** of equal length (DAILY granularity, `UnblendedCost` **and** `AmortizedCost`).
3. Decide:
   - **Real increase** → continue.
   - **Accounting artifact** (only appears in Unblended, not Amortized → upfront RI/SP purchase; monthly fees on the 1st; tax; Support fee following spend; credits/refunds ending) → this *is* the root cause; go to Phase 5.
4. Output: `Baseline $/day`, `Spike $/day`, `Delta $`, `Delta %`, `Start date`.

## Phase 2 — Decompose the Delta (max 5 levels)

Use Cost Explorer `get-cost-and-usage`, filtering each level by the winner of the previous level. Commands in `references/cli-commands.md`.

| Level | Group by | Question |
|---|---|---|
| L1 | `SERVICE` | Which service? |
| L2 | `LINKED_ACCOUNT` | Which account? (Org payer only) |
| L3 | `REGION` | Which region? (unexpected regions → think Security) |
| L4 | `USAGE_TYPE` (+ `OPERATION`) | What exactly is billed? (hours, GB, requests, IOPS, data transfer) |
| L5 | Resource ID | Which resource? → `get-cost-and-usage-with-resources` (last 14 days, opt-in) or CUR `line_item_resource_id` via Athena (`references/athena-cur-queries.md`) |

Also group by `RECORD_TYPE` once (Usage / Credit / Refund / SavingsPlanCoveredUsage / Tax) and `PURCHASE_TYPE` once (On Demand / Reserved / Spot / Savings Plans).

## Phase 3 — Classify the Driver: Usage vs Rate

Compare `UsageQuantity` and cost for the winning usage type:

| Usage qty | Cost | Classification | Typical root causes |
|---|---|---|---|
| ↑ | ↑ | **Usage increase** | New resources, scaling, traffic, bug/retry storm, logging verbosity, data transfer path change |
| ≈ | ↑ | **Rate increase** | RI/Savings Plan expired, Spot → On-Demand fallback, Free Tier ended, credits ended, **Extended Support** (EKS/RDS old versions), public IPv4 charges, tier change, price change |
| ↑ | ≈ | Coverage absorbed | Not an issue now; check SP/RI coverage headroom |

For rate increases always check:
```bash
aws ce get-savings-plans-coverage / get-reservation-coverage   # coverage dropped?
aws savingsplans describe-savings-plans --states retired        # SP expired?
aws ec2 describe-reserved-instances --filters Name=state,Values=retired
```

Then open the matching **service playbook** in `references/service-playbooks.md` for the deep-dive steps for that service.

## Phase 4 — Attribute: Resource → Change → Actor

For each top driver resource:
1. **Metadata & ownership tags**: `describe-*`, `resourcegroupstaggingapi get-resources` (tags: Owner, Team, Environment, CostCenter, Application).
2. **What changed and when**: AWS Config `get-resource-config-history` (config diff around the start date).
3. **Who changed it**: CloudTrail `lookup-events` (90 days, management events, per region) or CloudTrail Lake SQL. Capture `eventName`, `eventTime`, `userIdentity.arn`, `sourceIPAddress`, `userAgent` (Terraform / CloudFormation / console / CI role).
4. **Usage behaviour**: CloudWatch metrics for the resource (e.g., `NetworkOut`, `BytesOutToDestination`, `IncomingBytes`, `Invocations`, `ConsumedWriteCapacityUnits`) — the metric curve's start time must match the cost start date.
5. Correlate timeline: **change event time ≈ metric step-up ≈ cost step-up**. If they line up → causal link.

## Phase 5 — Root Cause Statement & Confidence

Apply **5 Whys** once, from the symptom down to the change that triggered it. Stop at the first "why" that is an actionable decision/change owned by a team.

Confidence:
- **HIGH** – cost, usage metric, and change event (CloudTrail/Config) line up in time and amount explains ≥ 70 % of delta.
- **MEDIUM** – cost + usage metric line up, but the triggering change/actor is not proven.
- **LOW** – only cost data; cause inferred. Must list what evidence is needed and from whom.

## Phase 6 — Ownership & Handoff

Use `references/ownership-matrix.md` to assign each finding to a team. For every item outside the investigator's control, write an explicit handoff:
> **Handoff → DevOps/Platform:** Confirm why HPA max replicas for `payments-api` changed from 10 → 60 on 3 Nov (CloudTrail shows `UpdateNodegroupConfig` by `role/eks-admin`). Needed: deployment/change log, Helm values diff.

If the cause looks like **compromised credentials / unauthorized usage** (unknown regions, GPU instances, unknown IAM users/keys, crypto-mining pattern, GuardDuty findings) → mark **SECURITY – URGENT**, hand off to Security immediately, and tell the user to follow their incident response process.

## Phase 7 — Report (once, then stop)

Produce the report using `references/report-template.md`:
Executive summary → Anomaly quantification → Drill-down table → Root cause + evidence chain + timeline → Confidence → Ownership & handoffs → Remediation (immediate / short-term / prevention) → Estimated savings → Data gaps → Query log.

Prevention recommendations should use AWS-native controls: Cost Anomaly Detection monitors per service/account/cost-category, AWS Budgets + Budget Actions, cost allocation tags activated, Tag Policies / SCPs, Savings Plans/RI expiration alerts, Trusted Advisor & Compute Optimizer reviews.

**After the report: stop.** Offer optional next steps as a list; do not start them unless asked.

## Reference files
- `references/aws-services.md` – which AWS service to use for what
- `references/cli-commands.md` – exact read-only CLI commands per phase
- `references/service-playbooks.md` – deep-dive per service (EC2, EBS, NAT/Data Transfer, S3, RDS, Lambda, CloudWatch, DynamoDB, EKS/ECS, etc.)
- `references/athena-cur-queries.md` – CUR 2.0 SQL for resource-level RCA
- `references/ownership-matrix.md` – which team owns which root cause
- `references/report-template.md` – final RCA report format
- `references/iam-readonly-policy.json` – minimum read-only permissions
- `scripts/collect_cost_snapshot.sh` – one-pass read-only data collection (Phase 1–2)

