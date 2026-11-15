# Read-Only CLI Commands by Phase

Replace `<...>` placeholders. Dates are `YYYY-MM-DD`; `End` is **exclusive**.
Cost Explorer commands always use `--region us-east-1`.
Log every command you run in the Query Log; never run the identical command twice.

## Phase 0 — Access
```bash
aws sts get-caller-identity
aws organizations list-accounts --query 'Accounts[].[Id,Name,Status]' --output table   # payer only
```

## Phase 1 — Confirm & quantify
```bash
# Anomalies AWS already detected
aws ce get-anomaly-monitors --region us-east-1
aws ce get-anomalies --region us-east-1 \
  --date-interval StartDate=<start>,EndDate=<end> \
  --query 'Anomalies[].{Start:AnomalyStartDate,End:AnomalyEndDate,Impact:Impact.TotalImpact,Causes:RootCauses}'

# Daily total, unblended vs amortized (spike window + baseline window in one range)
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=<baseline_start>,End=<spike_end> \
  --granularity DAILY --metrics UnblendedCost AmortizedCost

# Record type split (credits/refunds/tax/SP fees)
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=<baseline_start>,End=<spike_end> --granularity MONTHLY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=RECORD_TYPE
```

## Phase 2 — Decompose
```bash
# L1 service
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=<baseline_start>,End=<spike_end> --granularity DAILY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE

# L2 account + L3 region for the winning service (2 group-bys max)
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=<baseline_start>,End=<spike_end> --granularity DAILY \
  --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["<Service Name>"]}}' \
  --group-by Type=DIMENSION,Key=LINKED_ACCOUNT Type=DIMENSION,Key=REGION

# L4 usage type + quantity
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=<baseline_start>,End=<spike_end> --granularity DAILY \
  --metrics UnblendedCost UsageQuantity \
  --filter '{"And":[{"Dimensions":{"Key":"SERVICE","Values":["<Service Name>"]}},{"Dimensions":{"Key":"REGION","Values":["<region>"]}}]}' \
  --group-by Type=DIMENSION,Key=USAGE_TYPE

# Optional: operation inside usage type
#   --group-by Type=DIMENSION,Key=OPERATION

# Purchase type (On-Demand vs SP/RI/Spot)
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=<baseline_start>,End=<spike_end> --granularity DAILY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=PURCHASE_TYPE

# By tag (if cost allocation tags activated)
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=<baseline_start>,End=<spike_end> --granularity DAILY \
  --metrics UnblendedCost --group-by Type=TAG,Key=<Team|Owner|Application>

# L5 resource level (last 14 days only, opt-in required, SERVICE filter required)
aws ce get-cost-and-usage-with-resources --region us-east-1 \
  --time-period Start=<start_within_14d>,End=<end> --granularity DAILY \
  --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["<Service Name>"]}}' \
  --group-by Type=DIMENSION,Key=RESOURCE_ID
```
If L5 is unavailable → use CUR via Athena (`athena-cur-queries.md`).

## Phase 3 — Rate vs usage
```bash
aws ce get-savings-plans-coverage --region us-east-1 --time-period Start=<s>,End=<e> --granularity DAILY
aws ce get-savings-plans-utilization --region us-east-1 --time-period Start=<s>,End=<e> --granularity DAILY
aws ce get-reservation-coverage --region us-east-1 --time-period Start=<s>,End=<e> --granularity DAILY
aws savingsplans describe-savings-plans --states retired active \
  --query 'savingsPlans[].{Id:savingsPlanId,Type:savingsPlanType,State:state,End:end,Commit:commitment}'
aws ec2 describe-reserved-instances --region <region> --filters Name=state,Values=retired \
  --query 'ReservedInstances[].{Type:InstanceType,Count:InstanceCount,End:End}'
aws rds describe-reserved-db-instances --region <region>
```

## Phase 4 — Attribute
```bash
# Tags / owner
aws resourcegroupstaggingapi get-resources --region <region> --resource-arn-list <arn>

# Who created/changed it (management events, 90 days, per region)
aws cloudtrail lookup-events --region <region> \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=<resource-id> \
  --start-time <iso> --end-time <iso> \
  --query 'Events[].{Time:EventTime,Event:EventName,User:Username}'

aws cloudtrail lookup-events --region <region> \
  --lookup-attributes AttributeKey=EventName,AttributeValue=<RunInstances|CreateNatGateway|ModifyDBInstance|...> \
  --start-time <iso> --end-time <iso>

# Configuration history
aws configservice get-resource-config-history --region <region> \
  --resource-type <AWS::EC2::Instance> --resource-id <id> \
  --earlier-time <iso> --later-time <iso>

# Usage metric timeline (example: NAT bytes)
aws cloudwatch get-metric-statistics --region <region> \
  --namespace AWS/NATGateway --metric-name BytesOutToDestination \
  --dimensions Name=NatGatewayId,Value=<nat-id> \
  --start-time <iso> --end-time <iso> --period 86400 --statistics Sum

# Security signals
aws guardduty list-detectors --region <region>
aws guardduty list-findings --region <region> --detector-id <id> \
  --finding-criteria '{"Criterion":{"severity":{"Gte":4}}}'
aws iam generate-credential-report && aws iam get-credential-report --query Content --output text | base64 --decode
```

## CloudTrail Lake (if enabled) — who launched expensive things
```sql
SELECT eventTime, eventName, awsRegion, userIdentity.arn, sourceIPAddress, userAgent,
       element_at(requestParameters,'instanceType') AS instanceType
FROM <event_data_store_id>
WHERE eventName IN ('RunInstances','CreateNatGateway','CreateDBInstance','ModifyDBInstance',
                    'CreateCluster','UpdateNodegroupConfig','PutRetentionPolicy','CreateVolume')
  AND eventTime BETWEEN '<start>' AND '<end>'
ORDER BY eventTime
```

