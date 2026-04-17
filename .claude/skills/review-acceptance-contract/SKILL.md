---
name: review-acceptance-contract
description: Review acceptance targets and scripts for contract drift, partial gates, and missing labels.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash
context: fork
agent: acceptance-reviewer
---

Review acceptance targets as executable contracts.

Required outputs:
- aggregate/documentation mismatches
- missing or drifted labels
- partial gates presented as complete
- the smallest safe patch list
