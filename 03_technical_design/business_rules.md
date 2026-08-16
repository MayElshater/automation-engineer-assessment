# Business Rules

## Overview

The qualification engine combines deterministic business rules with AI-based qualitative classification.

The deterministic score is the primary decision mechanism. The AI model provides qualitative analysis and confidence but does not directly modify the numerical score.

---

# Identity Resolution

Identity resolution in WF02 is separate from qualification scoring in WF03.

## Exact Duplicate

Exact duplicate detection is deterministic. A lead is an exact duplicate when either its normalized phone or normalized email matches an existing canonical lead. Exact identifier matching takes precedence over contextual duplicate scoring.

```text
Normalized Phone Match?
        ↓ yes
Exact Duplicate
        ↓
Evaluate Merge Safety

else

Normalized Email Match?
        ↓ yes
Exact Duplicate
        ↓
Evaluate Merge Safety

else
        ↓
Contextual Duplicate Evaluation
```

The same normalized phone is sufficient for exact identity detection, as is the same normalized email. Neither match requires name or company agreement, and an exact identifier match must never fall through to `unique`.

Conflicting secondary data is recorded as an identity conflict and handled as a merge-safety concern; it does not reverse the exact identity decision. The automatic merge path may fill missing canonical fields but must not overwrite a conflicting non-empty canonical identifier.

```text
same phone
different email
        ↓
identity = exact_duplicate
match_type = exact_phone
confidence = 1.0
        ↓
evaluate whether automatic merge is safe
```

## Likely Duplicate

Contextual likely-duplicate scoring runs only when there is no exact normalized phone match and no exact normalized email match. The contextual signals and weights remain:

- Normalized name match: +0.3
- Company match: +0.2
- Different source: +0.1
- Arrival within 2 minutes: +0.2
- Same service interest: +0.1

A contextual confidence of at least 0.6 remains a likely duplicate and enters Manual Review.

```text
likely_duplicate
        ↓
manual_review
```

## Unique

A lead is unique only when no exact normalized phone match exists, no exact normalized email match exists, and the contextual score is below the likely-duplicate threshold.

```text
Identity Match Score
→ determines whether submissions likely represent the same person
→ WF02

Qualification Score
→ determines lead business value
→ WF03
```

These scores are independent and must not be mixed.

---

# Rule-Based Scoring

## Company Size

| Company Size | Score |
|--------------|------:|
| >= 500 employees | +25 |
| 100–499 | +20 |
| 20–99 | +10 |
| < 20 | +5 |

---

## Service Value

| Service | Score |
|---------|------:|
| High-value | +25 |
| Medium-value | +15 |
| Low-value | +5 |

---

## Intent / Request Quality

| Intent | Score |
|--------|------:|
| Clear business requirement | +15 |
| General inquiry | +5 |

---

## Urgency

| Urgency | Score |
|---------|------:|
| High | +15 |
| Medium | +10 |
| Low | +0 |

---

## Geography

| Geography | Score |
|-----------|------:|
| Target Market | +10 |
| Non-target Market | +0 |

---

## Strategic Account

| Condition | Score |
|-----------|------:|
| Strategic Account | +20 |

---

## Data Quality Penalty

| Condition | Score |
|-----------|------:|
| Missing non-critical information | -10 |

---

## Final Score

```text
score = min(100, max(0, calculated_score))
```

---

# Qualification Thresholds

| Score | Result |
|-------:|--------|
| >= 90 OR Strategic Account | VIP |
| >= 70 | Qualified |
| 40–69 | Nurture |
| < 40 | Unqualified |

---

# AI Classification

The Gemini model is used only for qualitative analysis.

It returns structured JSON similar to:

```json
{
  "classification": "high_potential",
  "urgency": "high",
  "intent": "purchase",
  "confidence": 0.91,
  "reason": "The lead describes an immediate enterprise automation requirement."
}
```

The AI model **does not modify the deterministic score**.

---

# Conflict Resolution

The deterministic rule engine is the primary decision mechanism. AI classification is an independent qualitative signal: it does not modify the numerical score and cannot automatically promote or demote a lead.

| Rule Classification | AI High Potential | AI Medium Potential | AI Low Potential | AI Unknown |
|---------------------|-------------------|---------------------|------------------|------------|
| VIP | VIP | VIP | Manual Review | VIP |
| Qualified | Qualified | Qualified | Manual Review | Qualified |
| Nurture | Manual Review | Nurture | Nurture | Nurture |
| Unqualified | Manual Review | Unqualified | Unqualified | Unqualified |

The governing principle is:

```text
Deterministic classification = primary decision

AI agreement or neutral assessment
        ↓
Preserve deterministic classification

Material AI disagreement
        ↓
Manual Review

AI must never automatically promote or demote the deterministic classification.
```

## Material Conflicts

1. Rule = VIP or Qualified AND AI = `low_potential` → Manual Review.
2. Rule = Nurture or Unqualified AND AI = `high_potential` → Manual Review.
3. AI = `medium_potential` → Preserve the deterministic classification.
4. AI = `unknown` → Preserve the deterministic classification unless the unknown state is caused by an AI execution or validation failure.

A valid `unknown` classification is a neutral qualitative result. It is distinct from a technical AI failure.

## Technical AI Failures

If Gemini times out after retry exhaustion, returns malformed or empty output, violates the expected schema, or is unavailable, the system must not interpret that failure as `low_potential`.

```text
AI technical failure
        ↓
Manual Review
```

The deterministic score and rule classification remain preserved for auditability when technical AI failure causes Manual Review.

---
# Post-Qualification Routing

Every final classification has an explicit post-qualification handling path:

```text
Qualification Decision
        ↓
Post-Qualification Routing
        ├── VIP
        │      ↓
        │   Manager Approval
        │      ↓
        │   Sales Assignment
        │
        ├── Qualified
        │      ↓
        │   Sales Assignment
        │
        ├── Nurture
        │      ↓
        │   Nurture / Follow-Up Engine
        │
        ├── Unqualified
        │      ↓
        │   Close or Low-Frequency Nurture
        │
        └── Manual Review
               ↓
            Human Review
```

- **VIP** and **Qualified** leads may enter the **Sales Assignment Engine**.
- **VIP** leads require Manager Approval before automated outbound sales communication.
- **Nurture** leads do not enter direct sales assignment; they enter the nurture/follow-up path.
- **Unqualified** leads are closed or placed into a low-frequency nurture path according to business policy.
- **Manual Review** leads stop automated qualification and routing and wait for human resolution.

## Sales Assignment Engine

For eligible VIP and Qualified leads, the Sales Assignment Engine selects and assigns a sales representative using this priority:

1. Service Category
2. Geography
3. Available Sales Representatives
4. Lowest Current Workload
5. Urgency Priority

---

## Assignment Fallback

If the selected sales representative is unavailable or overloaded:

```text
Fallback Candidate
        ↓
Next Lowest Workload
        ↓
Reassign
```

# Business Rules Execution Order

1. Normalize & Validate
2. Idempotency Check
3. Identity Resolution
4. Enrichment
5. Rule-Based Scoring
6. AI Classification
7. Conflict Resolution
8. Qualification Decision
9. Post-Qualification Routing
10. CRM Synchronization
11. Customer Communication
12. Audit & Monitoring