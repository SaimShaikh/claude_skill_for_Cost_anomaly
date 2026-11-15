# AWS Cost Anomaly RCA Report — <short title>

**Date:** <YYYY-MM-DD> **Investigator:** <name> **Accounts:** <ids/names> **Period:** <spike window> vs <baseline window>

## 1. Executive Summary (3–5 lines)
- **What:** <service/usage type> cost increased by **$<delta> (+<x>%)** starting **<date>**.
- **Root cause:** <one sentence: change + actor + reason it costs more>.
- **Owner:** <team>. **Confidence:** HIGH | MEDIUM | LOW.
- **Monthly impact if unchanged:** ~$<run-rate>/month. **Estimated savings after fix:** ~$<x>/month.

## 2. Anomaly Quantification
| Metric | Baseline | Spike | Delta |
|---|---|---|---|
| Avg cost/day (Unblended) | | | |
| Avg cost/day (Amortized) | | | |
| Usage quantity/day (driver usage type) | | | |
| Anomaly Detection impact (if alerted) | | | |

## 3. Drill-Down Path
| Level | Winner | Share of delta | Evidence (query #) |
|---|---|---|---|
| Service | | | |
| Account | | | |
| Region | | | |
| Usage type | | | |
| Resource(s) | | | |

Classification: **Usage increase** / **Rate increase** / **Billing artifact** / **Security incident**

## 4. Root Cause & Evidence Chain
**5 Whys**
1. Why did cost rise? →
2. Why? →
3. Why? →
4. Why? → **Root cause:**

**Timeline (UTC)**
| Time | Event | Source |
|---|---|---|
| | Change made (CloudTrail eventName, actor ARN, userAgent) | CloudTrail / Config |
| | Usage metric stepped up | CloudWatch |
| | Cost stepped up | Cost Explorer / CUR |
| | Alert fired | Cost Anomaly Detection / Budget |

## 5. Other Contributing Drivers (top 3 only)
| # | Driver | $ delta | Status (investigated / not investigated) |
|---|---|---|---|

## 6. Ownership & Handoffs
| Finding | Primary owner | Secondary | Ask | Priority |
|---|---|---|---|---|

<Handoff blocks from ownership-matrix.md>

## 7. Remediation (recommendations — not executed)
- **Immediate (stop the bleeding):**
- **Short-term (fix the cause):**
- **Prevention (AWS-native):** Cost Anomaly Detection monitor for <service/account>, AWS Budget + alert at <x>, activate cost allocation tags <Team/Owner/Env>, Tag Policy / SCP, SP/RI expiry reminders, Trusted Advisor/Compute Optimizer review, log retention defaults, VPC endpoints baseline in IaC.

## 8. Data Gaps & Assumptions
| Gap | Impact on confidence | Who can provide |
|---|---|---|
| e.g. CUR not enabled | resource-level attribution limited to 14 days | FinOps |

## 9. Query Log
| # | Command / query | Key result |
|---|---|---|
| 1 | | |

