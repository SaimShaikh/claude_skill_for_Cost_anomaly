# CUR 2.0 (AWS Data Exports) – Athena Queries for Resource-Level RCA

Prerequisite: a CUR 2.0 export to S3 with an Athena table (owner: FinOps/Cloud team).
If not available → record as **Data Gap** and use Cost Explorer resource-level data (last 14 days) instead.

Replace `<cur_db>.<cur_table>`, dates and filters. Always filter on `billing_period` (partition) to limit scan cost.
Column names below are CUR 2.0; legacy CUR uses the same names in most cases.

## Q1 – Daily cost by service, spike vs baseline
```sql
SELECT date(line_item_usage_start_date) AS day,
       product_servicecode AS service,
       round(sum(line_item_unblended_cost),2) AS cost
FROM <cur_db>.<cur_table>
WHERE billing_period IN ('<YYYY-MM>','<YYYY-MM>')
  AND line_item_line_item_type IN ('Usage','DiscountedUsage','SavingsPlanCoveredUsage')
  AND line_item_usage_start_date BETWEEN timestamp '<baseline_start>' AND timestamp '<spike_end>'
GROUP BY 1,2
ORDER BY 1,3 DESC;
```

## Q2 – Delta by usage type (baseline vs spike, same length)
```sql
WITH b AS (
  SELECT line_item_usage_type ut, sum(line_item_unblended_cost) cost, sum(line_item_usage_amount) qty
  FROM <cur_db>.<cur_table>
  WHERE billing_period IN ('<YYYY-MM>') AND product_servicecode = '<AmazonEC2>'
    AND line_item_usage_start_date >= timestamp '<baseline_start>' AND line_item_usage_start_date < timestamp '<baseline_end>'
  GROUP BY 1),
s AS (
  SELECT line_item_usage_type ut, sum(line_item_unblended_cost) cost, sum(line_item_usage_amount) qty
  FROM <cur_db>.<cur_table>
  WHERE billing_period IN ('<YYYY-MM>') AND product_servicecode = '<AmazonEC2>'
    AND line_item_usage_start_date >= timestamp '<spike_start>' AND line_item_usage_start_date < timestamp '<spike_end>'
  GROUP BY 1)
SELECT coalesce(s.ut,b.ut) usage_type,
       round(coalesce(b.cost,0),2) baseline_cost, round(coalesce(s.cost,0),2) spike_cost,
       round(coalesce(s.cost,0)-coalesce(b.cost,0),2) delta_cost,
       round(coalesce(b.qty,0),2) baseline_qty, round(coalesce(s.qty,0),2) spike_qty
FROM s FULL OUTER JOIN b ON s.ut = b.ut
ORDER BY delta_cost DESC
LIMIT 20;
```
Interpretation: qty ↑ → usage increase; qty ≈ and cost ↑ → rate increase (Phase 3).

## Q3 – Top resources driving the delta
```sql
SELECT line_item_resource_id,
       line_item_usage_account_id,
       product_region_code,
       line_item_usage_type,
       min(line_item_usage_start_date) first_seen,
       round(sum(line_item_unblended_cost),2) cost
FROM <cur_db>.<cur_table>
WHERE billing_period IN ('<YYYY-MM>')
  AND product_servicecode = '<service_code>'
  AND line_item_usage_type LIKE '%<usage_type_fragment>%'
  AND line_item_usage_start_date >= timestamp '<spike_start>'
GROUP BY 1,2,3,4
ORDER BY cost DESC
LIMIT 20;
```
`first_seen` inside the spike window ⇒ **new resource** → find creator in CloudTrail.

## Q4 – Ownership via tags
```sql
SELECT resource_tags['user_team']  AS team,
       resource_tags['user_owner'] AS owner,
       resource_tags['user_environment'] AS env,
       round(sum(line_item_unblended_cost),2) cost
FROM <cur_db>.<cur_table>
WHERE billing_period IN ('<YYYY-MM>')
  AND line_item_resource_id IN ('<id1>','<id2>')
GROUP BY 1,2,3 ORDER BY cost DESC;
```
(Tag keys depend on activated cost allocation tags; legacy CUR uses `resource_tags_user_team` columns.)

## Q5 – Rate change check (effective unit price per day)
```sql
SELECT date(line_item_usage_start_date) day,
       line_item_usage_type,
       pricing_term,
       round(sum(line_item_unblended_cost)/nullif(sum(line_item_usage_amount),0),6) unit_cost,
       round(sum(line_item_usage_amount),2) qty
FROM <cur_db>.<cur_table>
WHERE billing_period IN ('<YYYY-MM>') AND line_item_usage_type = '<usage_type>'
GROUP BY 1,2,3 ORDER BY 1;
```
Unit cost jumps on one day ⇒ SP/RI expiry, Extended Support, tier change, Free Tier end.

## Q6 – Savings Plan / RI coverage lost
```sql
SELECT date(line_item_usage_start_date) day, line_item_line_item_type,
       round(sum(line_item_unblended_cost),2) cost
FROM <cur_db>.<cur_table>
WHERE billing_period IN ('<YYYY-MM>')
  AND line_item_line_item_type IN ('Usage','SavingsPlanCoveredUsage','DiscountedUsage','SavingsPlanNegation')
GROUP BY 1,2 ORDER BY 1,2;
```
`SavingsPlanCoveredUsage`/`DiscountedUsage` drop + `Usage` rise on the same day ⇒ commitment expired.

## Q7 – Credits / refunds disappearing
```sql
SELECT billing_period, line_item_line_item_type, round(sum(line_item_unblended_cost),2) amount
FROM <cur_db>.<cur_table>
WHERE billing_period IN ('<prev>','<curr>')
  AND line_item_line_item_type IN ('Credit','Refund','Tax','Fee','RIFee','SavingsPlanRecurringFee')
GROUP BY 1,2 ORDER BY 1,2;
```

