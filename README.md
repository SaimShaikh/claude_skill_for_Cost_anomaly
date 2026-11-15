# AWS Cost Skills for Claude

## Skill: `aws-cost-anomaly-investigation`
Evidence-based Root Cause Analysis of unexpected AWS cost increases using only AWS-native services.
Single linear pass (Phases 0→7) with hard no-loop rules, read-only, and team ownership/handoffs.

```
aws-cost-anomaly-investigation/
├── SKILL.md                         # workflow, no-loop rules, phases 0–7
├── references/
│   ├── aws-services.md              # which AWS service to use for what
│   ├── cli-commands.md              # read-only CLI per phase
│   ├── service-playbooks.md         # deep-dive per AWS service
│   ├── athena-cur-queries.md        # CUR 2.0 SQL for resource-level RCA
│   ├── ownership-matrix.md          # FinOps / DevOps / Dev / Data / Security
│   ├── report-template.md           # final RCA report
│   └── iam-readonly-policy.json     # minimum permissions
└── scripts/
    └── collect_cost_snapshot.sh     # one-pass data collection
```

## Install
**Claude Code (personal):**
```bash
mkdir -p ~/.claude/skills
cp -R aws-cost-anomaly-investigation ~/.claude/skills/
chmod +x ~/.claude/skills/aws-cost-anomaly-investigation/scripts/*.sh
```
**Claude Code (per project):** copy into `<project>/.claude/skills/`.

**Claude.ai / Desktop:** zip the folder and upload under Settings → Capabilities → Skills:
```bash
zip -r aws-cost-anomaly-investigation.zip aws-cost-anomaly-investigation
```

## Use
> "Our AWS bill jumped ~\$4k between 1–14 Nov in account 1234. Investigate the root cause."

Claude will ask for missing scope once, then run Phases 0→7 and produce the RCA report.

