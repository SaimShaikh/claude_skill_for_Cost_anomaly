# Ownership Matrix – Who Fixes What

Assign every finding to exactly one **primary owner** (and optional secondary).
If the root cause is outside your control, write a **handoff** (template at the bottom).

## Team definitions
| Team | Owns |
|---|---|
| **FinOps / Cloud Cost** | Savings Plans, RIs, credits, Free Tier, billing artifacts, CUR/Cost Explorer setup, budgets, anomaly monitors, tagging policy |
| **DevOps / Platform / SRE** | IaC (Terraform/CloudFormation/CDK), VPC/NAT/endpoints/routes, ASGs, EKS/ECS clusters & upgrades, node autoscaling, log retention, backups, monitoring tooling, CI/CD roles |
| **Developers / App teams** | Application code & config: log levels, retry loops, request patterns, Lambda memory/timeout, metric cardinality, DynamoDB access patterns, S3 usage, replicas/requests in manifests |
| **Data / DBA / Analytics** | RDS/Aurora sizing & queries, Redshift, EMR, Glue, Athena, Kinesis/MSK, data lake buckets, replication |
| **ML team** | SageMaker endpoints/notebooks, Bedrock usage, GPU instances for training |
| **Security** | Unauthorized usage, leaked credentials, GuardDuty/Security Hub/Config/Inspector cost, WAF/DDoS |
| **Procurement / Finance** | Marketplace subscriptions, Support plan, tax, contracts |

## Root cause → owner
| Root cause pattern | Evidence that proves it | Primary owner | Secondary |
|---|---|---|---|
| SP/RI expired, coverage dropped | Coverage report / CUR Q6 | FinOps | — |
| Credits ended / Free Tier ended | RECORD_TYPE Credit ↓, account age | FinOps | Finance |
| Upfront commitment purchase | Unblended spike, Amortized flat | FinOps (not an anomaly) | — |
| EKS/RDS Extended Support | Usage type `*ExtendedSupport*`, version EoL | DevOps (EKS) / DBA (RDS) | FinOps |
| ASG / node group scaled up, not down | Scaling activities, CloudTrail `UpdateAutoScalingGroup` | DevOps | Developers (if load-driven) |
| Instance / DB upsized | Config history, `ModifyInstanceAttribute` / `ModifyDBInstance` | Whoever made the change (CloudTrail actor) → DevOps or DBA | — |
| Forgotten test / load-test / POC resources | `first_seen` in window, tags `env=test`, creator = human user | Team of the creator (CloudTrail + Organizations account owner) | DevOps (cleanup policy) |
| NAT / data transfer via missing VPC endpoint | Flow logs, endpoints/route tables | DevOps / Network | Developers (new traffic source) |
| Chatty cross-AZ / inter-region traffic | `DataTransfer-Regional-Bytes`, flow logs | Developers (architecture) | DevOps |
| Log ingestion spike (DEBUG logs) | `IncomingBytes` per log group, deploy time | Developers | DevOps (retention / alerts) |
| Log retention "never expire" | `describe-log-groups` | DevOps | — |
| Custom metric cardinality explosion | `CW:MetricMonitorUsage`, list-metrics | Developers | DevOps |
| Monitoring tool polling GetMetricData | `CW:GMD-Metrics`, CloudTrail `GetMetricData` caller | DevOps / SRE | — |
| Lambda recursive loop / retry storm | Invocations curve, event source errors | Developers | — |
| Lambda memory/timeout/provisioned concurrency raised | Config/CloudTrail `UpdateFunctionConfiguration` | Developers | DevOps (IaC) |
| S3 request storm (LIST/PUT loop) | Request metrics, data events/access logs | Developers | Data team |
| S3 storage growth (versions, no lifecycle) | BucketSizeBytes, lifecycle config | Data team / bucket owner | DevOps |
| Aurora I/O spike from new query/job | `StorageIOUsage`, Performance Insights | Developers / Data team | DBA |
| DynamoDB on-demand spike / new GSI / scans | Consumed capacity, `UpdateTable` | Developers | Data team |
| Orphaned EBS / snapshots / ELBs / EIPs | `available` volumes, idle LBs, idle IPv4 | DevOps | Owning app team |
| Config recorder cost from churn | `ConfigurationItemRecorded` | Security / DevOps | — |
| Marketplace subscription / renewal | Marketplace line items | Procurement | FinOps |
| Unknown regions / GPU / unknown IAM principals | CloudTrail, GuardDuty | **Security – URGENT** | DevOps |
| Real business growth (traffic ↑, revenue ↑) | Traffic metrics ↑ proportionally, no config change | Product / App team (expected) | FinOps (forecast, SP purchase) |

## Handoff template
```
Handoff → <Team>
Finding:   <one-line root cause>
Impact:    $<delta> over <period> (~$<monthly run-rate>/month)
Evidence:  <commands/queries + key numbers, CloudTrail event + actor + time>
Ask:       <specific question or action, e.g. "confirm intended change", "add S3 gateway endpoint to vpc-xxx">
Needed by: <date / priority>
Confidence: HIGH | MEDIUM | LOW
```

