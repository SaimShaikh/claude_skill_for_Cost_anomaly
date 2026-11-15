# Service Deep-Dive Playbooks

Open only the playbook for the winning service(s) from Phase 2 (max 3).
Each playbook: **usage types to look at → checks → common root causes → owner**.

---

## 1. Amazon EC2 – Compute
**Usage types:** `BoxUsage:<type>`, `SpotUsage:<type>`, `DedicatedUsage`, `HostUsage`, `EBSOptimized`, Windows/RHEL license ops (`RunInstances:0002` etc.)

Checks:
1. Group by `INSTANCE_TYPE` and `PURCHASE_TYPE` → new instance family? Spot → On-Demand shift?
2. `aws ec2 describe-instances --filters Name=instance-state-name,Values=running` → count per type/ASG/tag vs baseline.
3. Auto Scaling: `aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg>` → scale-outs that never scaled in; min/desired changed.
4. CloudTrail `RunInstances`, `ModifyInstanceAttribute` (type change), `CreateAutoScalingGroup`, `UpdateAutoScalingGroup`.
5. Savings Plans/RI expired → rate increase with same usage.
6. GPU/large instances (`p*`, `g*`, `x*`, `*.metal`) in unusual regions → **Security**.

Common root causes: ASG min/desired raised; scale-in policy broken; forgotten test/load-test instances; instance type upsized; Spot capacity loss → On-Demand fallback; SP/RI expired; OS licence change (Linux → Windows/RHEL AMI).
Owner: DevOps/Platform (ASG, infra), Developers (load test, app perf), FinOps (SP/RI), Security (unknown instances).

## 2. Amazon EBS & Snapshots (billed under EC2 – Other)
**Usage types:** `EBS:VolumeUsage.gp2|gp3|io1|io2|st1|sc1`, `EBS:VolumeP-IOPS.*`, `EBS:VolumeP-Throughput.gp3`, `EBS:SnapshotUsage`, `EBS:SnapshotArchiveStorage`, `EBS:FastSnapshotRestore`

Checks:
1. Unattached volumes: `aws ec2 describe-volumes --filters Name=status,Values=available`.
2. Snapshot growth: `aws ec2 describe-snapshots --owner-ids self` → count/age, AWS Backup / DLM policies with no retention.
3. Provisioned IOPS/throughput raised (Config history on `AWS::EC2::Volume`).
4. Fast Snapshot Restore left enabled (`describe-fast-snapshot-restores`).

Common root causes: volumes orphaned after instance termination (`DeleteOnTermination=false`); backup policy retention changed / missing; io2 IOPS raised; FSR enabled.
Owner: DevOps/Platform, Backup owners.

## 3. Data Transfer & NAT Gateway (EC2 – Other / VPC)
**Usage types:** `NatGateway-Bytes`, `NatGateway-Hours`, `DataTransfer-Out-Bytes`, `DataTransfer-Regional-Bytes` (cross-AZ), `<REG1>-<REG2>-AWS-Out-Bytes` (inter-region), `VpcEndpoint-Bytes`, `TransitGateway-Bytes`, `PublicIPv4:InUseAddress`, `PublicIPv4:IdleAddress`

Checks:
1. NAT: CloudWatch `AWS/NATGateway` `BytesOutToDestination`, `BytesInFromDestination` per gateway → which day stepped up.
2. VPC Flow Logs (Athena / Logs Insights) → top source ENIs/IPs and destinations through NAT. Map ENI → instance/pod/service (`describe-network-interfaces`).
3. Missing **Gateway endpoints** (S3, DynamoDB – free) or **Interface endpoints** (ECR, STS, CloudWatch Logs) → traffic forced through NAT: `aws ec2 describe-vpc-endpoints`, check route tables.
4. Cross-AZ: services talking across AZs (EKS pods, Kafka/MSK, RDS reader in other AZ, ELB cross-zone).
5. Inter-region: replication (S3 CRR, DynamoDB global tables, Aurora global DB), backups copied cross-region.
6. Internet egress: CloudFront not used, large downloads/APIs serving data from EC2/S3 directly.
7. Public IPv4 charges (since Feb 2024, $0.005/hr per IP) — new ELBs/instances with public IPs, idle EIPs.

Common root causes: VPC endpoint removed/never created; new service pulling images/data via NAT; log shipping via NAT; chatty microservices across AZs; replication enabled; public IPs on every node.
Owner: DevOps/Network (endpoints, routes, flow logs), Developers (chatty app, big payloads), Data team (replication).

## 4. Amazon S3
**Usage types:** `TimedStorage-ByteHrs` (+ `-SIA`, `-ZIA`, `-INT`, `-GlacierByteHrs`), `Requests-Tier1` (PUT/LIST/COPY/POST), `Requests-Tier2` (GET), `DataTransfer-Out-Bytes`, `Retrieval-*`, `EarlyDelete-*`, `C3DataTransfer-*`, `Inventory`, replication

Checks:
1. Which bucket: CUR `line_item_resource_id` or CloudWatch `AWS/S3 BucketSizeBytes` / `NumberOfObjects` (daily) per bucket; Storage Lens dashboard.
2. Versioning ON without noncurrent-version lifecycle; incomplete multipart uploads (`list-multipart-uploads`).
3. Request spike: S3 request metrics / CloudTrail data events / server access logs → which principal is LISTing/PUTting (often an app loop, a crawler, or a misconfigured sync job).
4. Lifecycle transition to Glacier of millions of small objects → transition request charges; early-deletion charges.
5. Intelligent-Tiering monitoring fee on many small objects.
6. Replication (CRR) enabled.

Common root causes: app writing logs/temp files without expiry; retry loop calling LIST; versioning + frequent overwrites; misconfigured lifecycle; public/hotlinked downloads.
Owner: Developers (app behaviour), Data team (data lake), DevOps (lifecycle/replication config).

## 5. Amazon RDS / Aurora
**Usage types:** `InstanceUsage:db.*`, `Multi-AZUsage:db.*`, `RDS:GP2-Storage`/`GP3-Storage`, `RDS:PIOPS`, `RDS:ChargedBackupUsage`, `Aurora:StorageIOUsage`, `Aurora:StorageUsage`, `Aurora:ServerlessV2Usage`, `ExtendedSupport:*`, `RDS:Proxy`

Checks:
1. `aws rds describe-db-instances` / `describe-db-clusters` → class, Multi-AZ, storage, engine version.
2. Config / CloudTrail `ModifyDBInstance`, `CreateDBInstance`, `CreateDBInstanceReadReplica`, `RestoreDBInstance*`.
3. **Extended Support** charges: engine versions past end of standard support (e.g., MySQL 5.7, PostgreSQL 11/12) → rate increase with no usage change. Check AWS Health events.
4. Aurora I/O: `Aurora:StorageIOUsage` up → query pattern change (missing index, new batch job). CloudWatch `VolumeReadIOPs`/`VolumeWriteIOPs`, Performance Insights top SQL. Consider Aurora I/O-Optimized.
5. Backup storage beyond free allocation (retention raised, manual snapshots kept).
6. Serverless v2 ACUs not scaling down (min ACU raised).

Common root causes: instance upsized/Multi-AZ enabled; restored copies left running; Extended Support; bad query/new job driving I/O; retention increased; RI expired.
Owner: DBA/Data team, Developers (queries), DevOps (provisioning), FinOps (RIs).

## 6. AWS Lambda
**Usage types:** `Lambda-GB-Second`, `Request`, `Lambda-Provisioned-Concurrency`, `Lambda-GB-Second-ARM`, `DataTransfer`

Checks:
1. CloudWatch `AWS/Lambda` `Invocations`, `Duration`, `Errors`, `Throttles`, `ConcurrentExecutions` per function → which function's curve stepped up.
2. Memory size or timeout raised (`get-function-configuration`, Config history).
3. **Recursive loops** (Lambda → S3/SQS/SNS → same Lambda), retry storms from failing event sources (SQS redrive, Kinesis iterator stuck).
4. Provisioned concurrency left enabled.
5. Duration up because a downstream dependency got slower (DB, external API).

Owner: Developers (code/config), DevOps (IaC defaults).

## 7. Amazon CloudWatch (Logs, Metrics, Alarms)
**Usage types:** `DataProcessing-Bytes` (log ingestion), `TimedStorage-ByteHrs` (log storage), `VendedLog-Bytes`, `CW:MetricMonitorUsage` (custom metrics), `CW:GMD-Metrics` / `CW:Requests` (GetMetricData/API), `CW:AlarmMonitorUsage`, `Logs-Insights` scanned bytes

Checks:
1. Top log groups by ingestion: CloudWatch metric `AWS/Logs IncomingBytes` by `LogGroupName`.
2. Log retention "Never expire": `aws logs describe-log-groups --query 'logGroups[?retentionInDays==null].[logGroupName,storedBytes]'`.
3. Log level changed to DEBUG (deployment), VPC Flow Logs / EKS control-plane logs newly enabled to CloudWatch.
4. Custom metric explosion: high-cardinality dimensions (pod IDs, user IDs) → `list-metrics` count by namespace.
5. GetMetricData spike: monitoring/dashboards tools polling too often (third-party monitoring integrations pull via API).

Owner: Developers (log level, metric cardinality), DevOps/SRE (retention, flow logs, monitoring tooling).

## 8. Amazon DynamoDB
**Usage types:** `ReadRequestUnits`/`WriteRequestUnits` (on-demand), `ReadCapacityUnit-Hrs`/`WriteCapacityUnit-Hrs` (provisioned), `TimedStorage-ByteHrs`, `TimedBackupStorage`, `PITR`, `ReplWriteCapacityUnit` (global tables), Streams

Checks: CloudWatch `ConsumedRead/WriteCapacityUnits` per table/GSI; capacity mode switched (provisioned → on-demand); new GSIs (each write multiplied); scans instead of queries; global table replica added; PITR enabled.
Owner: Developers (access patterns), Data/DBA, DevOps (capacity config).

## 9. Containers – Amazon EKS / ECS / Fargate
**Usage types:** `AmazonEKS-Hours:perCluster`, **`AmazonEKS-Hours:extendedSupport`**, `Fargate-vCPU-Hours`, `Fargate-GB-Hours`, plus underlying EC2/EBS/NAT/ELB

Checks:
1. **EKS Extended Support** — cluster version past standard support ⇒ control plane price jumps from $0.10 to $0.60/hr per cluster (rate increase). `aws eks describe-cluster --query cluster.version`.
2. Node groups: `describe-nodegroup` scaling config changes; Karpenter/Cluster Autoscaler provisioning larger nodes.
3. Fargate tasks: ECS service desired count / task size changed (`describe-services`, CloudTrail `UpdateService`).
4. Each `LoadBalancer`-type Service creates an ELB; each PVC an EBS volume — orphaned after namespace deletion?
5. Image pulls via NAT (no ECR endpoints) → see Data Transfer playbook.

Owner: DevOps/Platform (cluster, autoscaling, upgrades), Developers (resource requests, replicas).

## 10. Elastic Load Balancing
**Usage types:** `LoadBalancerUsage`, `LCUUsage`, `NLCUUsage`. Checks: count of LBs vs baseline (each K8s Service of type LoadBalancer), idle LBs with 0 requests, LCU spike from traffic/new rules/TLS connections.
Owner: DevOps, Developers.

## 11. Commitment & billing-level causes (no resource change)
- Savings Plan / RI **expired** → coverage drop (Phase 3 commands). Owner: FinOps.
- **Free Tier** ended (account > 12 months). Owner: FinOps.
- **Credits** expired / used up → `RECORD_TYPE=Credit` shrank. Owner: FinOps/Account manager.
- **Upfront RI/SP purchase** → Unblended spike, Amortized flat. Not an anomaly.
- **AWS Support** fee scales with spend → secondary effect, follow the primary driver.
- **Tax** changes; **Marketplace** subscriptions (`aws marketplace` line items, auto-renewal). Owner: FinOps/Procurement.

## 12. Other frequent hidden drivers
| Service | Usage type / signal | Typical cause | Owner |
|---|---|---|---|
| AWS Config | `ConfigurationItemRecorded` | High resource churn (autoscaling, EKS pods ENIs) recorded continuously | DevOps/Security |
| AWS KMS | `KMS-Requests` | S3 without Bucket Keys, chatty decrypt calls | Developers/DevOps |
| Secrets Manager | `API Requests` | Secret fetched on every request instead of cached | Developers |
| GuardDuty / Security Hub / Inspector | volume-based | New data sources enabled, more accounts/resources | Security |
| Amazon OpenSearch | `ESInstance:*`, storage | Domain resized, UltraWarm, snapshots | Data/DevOps |
| Kinesis / MSK | shard-hours, broker hours | Shards increased, retention extended | Data team |
| Amazon Bedrock / SageMaker | tokens, instance hours | Endpoints/notebooks left running, model usage growth | ML/Developers |
| Route 53 | queries, health checks | Resolver query logging, DNS loops | DevOps |
| CloudFront / WAF | requests, bytes | Traffic surge / bot attack | DevOps/Security |

## 13. Security / unauthorized usage pattern (escalate immediately)
Signals: spend in regions you never use; GPU or large instances; `RunInstances` from unknown IPs/user agents; new IAM users/access keys; Lambda/ECS/SageMaker/Bedrock usage nobody owns; GuardDuty `CryptoCurrency:*`, `UnauthorizedAccess:*` findings.
Action: label **SECURITY – URGENT**, hand off to Security with CloudTrail evidence. Do **not** remediate yourself (read-only).

