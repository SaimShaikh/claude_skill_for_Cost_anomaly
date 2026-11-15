# AWS Services Used in the Investigation

Only AWS-native services. Use them in this order.

| # | AWS Service | Used for | Phase | Notes / limits |
|---|---|---|---|---|
| 1 | **AWS Cost Anomaly Detection** (`ce get-anomalies`) | Detected anomalies, AWS-suggested root causes (service, account, region, usage type), $ impact | 1 | Needs monitors configured. Free. |
| 2 | **AWS Cost Explorer** (`ce get-cost-and-usage`) | Daily/monthly cost & usage, group by SERVICE / LINKED_ACCOUNT / REGION / USAGE_TYPE / OPERATION / RECORD_TYPE / PURCHASE_TYPE / TAG | 1–3 | $0.01 per API request. Max 2 group-bys per query. Data delayed up to ~24 h. |
| 3 | **Cost Explorer resource-level data** (`ce get-cost-and-usage-with-resources`) | Cost per resource ID | 2 (L5) | Must be opted-in (Cost Management preferences). Last 14 days only. Requires a SERVICE filter. |
| 4 | **CUR 2.0 / AWS Data Exports + Amazon Athena** | Line-item, resource-level, hourly, full history; tags; pricing; discounts | 2–3 | Best source for deep RCA. Requires export to S3 already configured (owner: FinOps/Cloud). |
| 5 | **Savings Plans / Reserved Instances** (`ce get-savings-plans-coverage`, `get-reservation-coverage`, `savingsplans describe-savings-plans`, `ec2 describe-reserved-instances`) | Detect expired commitments / coverage drops (rate increases) | 3 | |
| 6 | **AWS CloudTrail** (`cloudtrail lookup-events`) / **CloudTrail Lake** | Who created/changed resources, when, from where, with which tool | 4 | `lookup-events`: 90 days, management events only, per region, 2 req/s. Data events (S3 object, Lambda invoke) only if trail configured. |
| 7 | **AWS Config** (`configservice get-resource-config-history`, advanced query) | Configuration diff of a resource over time (instance type, storage, replicas, routes, endpoints) | 4 | Only if Config recorder is enabled for that resource type. |
| 8 | **Amazon CloudWatch** (metrics, Logs Insights) | Usage behaviour: traffic, invocations, log ingestion, IOPS — confirm timeline | 4 | Metric must step-up at the same time as cost. |
| 9 | **Resource Groups Tagging API** (`resourcegroupstaggingapi get-resources`) | Owner / Team / Environment tags → ownership | 4, 6 | |
| 10 | **VPC Flow Logs** (via CloudWatch Logs or S3 + Athena) | Who is sending traffic through NAT / cross-AZ / internet | 4 | Only if enabled. Owner: Network/DevOps. |
| 11 | **Amazon S3 Storage Lens / S3 metrics** | Bucket growth, request patterns, noncurrent versions, incomplete multipart uploads | 4 | |
| 12 | **AWS Trusted Advisor** & **AWS Compute Optimizer** | Idle/over-provisioned resources, unattached EBS, idle IPs | 7 | Full Trusted Advisor checks need Business/Enterprise support. |
| 13 | **Amazon GuardDuty** & **IAM Access Analyzer / IAM credential report** | Unauthorized usage (crypto mining, leaked keys) | 4, 6 | Escalate to Security. |
| 14 | **AWS Organizations** (`organizations list-accounts`) | Map account IDs → names/OUs → owning team | 2, 6 | Payer/management account. |
| 15 | **AWS Budgets** | Prevention: alerts / budget actions | 7 | Recommendation only. |
| 16 | **AWS Health** (`health describe-events`) | Planned AWS changes (e.g., end of standard support → Extended Support charges) | 3 | Needs Business/Enterprise support for API. |

## Which source answers which question

| Question | Best source | Fallback |
|---|---|---|
| Is the spike real? | Cost Explorer (Unblended vs Amortized) | Anomaly Detection |
| Which service/account/region? | Cost Explorer | CUR |
| Which usage type? | Cost Explorer `USAGE_TYPE` | CUR `line_item_usage_type` |
| Which resource? | CUR `line_item_resource_id` | CE with-resources (14 d), CloudWatch per-resource metrics |
| Who changed it? | CloudTrail Lake / lookup-events | Config history, tags, Terraform state (ask DevOps) |
| Why does it cost more? | CUR pricing columns, SP/RI coverage | Cost Explorer `UsageQuantity` vs cost |
| Is it a security incident? | GuardDuty, CloudTrail (unusual IPs/regions) | IAM credential report |

