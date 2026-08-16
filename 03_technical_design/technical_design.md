# Technical Design

## Assumptions

The system uses n8n for orchestration, PostgreSQL/Supabase for durable state, Gemini for qualitative classification, and FastAPI-based adapters for deterministic assessment integrations. See [assumptions.md](assumptions.md) for the CRM/Odoo constraint and other runtime assumptions.

## Architecture Overview

External lead sources are the website webhook, simulated WhatsApp webhook, and manual CSV import. n8n workflows WF01–WF08 normalize, validate, resolve identity, enrich, qualify, route, synchronize CRM state, manage follow-ups and bookings, recover failures, and monitor SLA state.

PostgreSQL/Supabase stores canonical leads, audit events, idempotency keys, duplicate decisions, representatives, follow-ups, approvals, bookings, and dead-letter records. Gemini supplies a qualitative signal to the deterministic qualification process.

FastAPI-based integration services provide enrichment, messaging, booking/availability, and the assessment CRM adapter.

```text
n8n
  → CRM Synchronization
  → CRM Integration Interface
  → Assessment Mock CRM API (submitted runtime)
  → Production Odoo Adapter (production)
```

Shared reliability includes bounded retry, scheduler-driven recovery, a dead-letter queue, safe targeted manual reprocessing, idempotency protection, immutable audit events, and SLA monitoring.

## Workflow Breakdown

| Workflow | Responsibility |
| --- | --- |
| WF01 | Website, WhatsApp, and CSV intake; canonical normalization |
| WF02 | Validation, normalization, identity resolution, and duplicate decisions |
| WF03 | Enrichment, deterministic scoring, Gemini classification, and final qualification |
| WF04 | Post-qualification routing, approvals, sales assignment, and CRM synchronization boundary |
| WF05 | Qualified and nurture follow-up scheduling and execution |
| WF06 | Booking, cancellation of pending follow-ups, conversion, and Won-state handling |
| WF07 | Centralized DLQ recovery, bounded retry, and idempotent manual replay |
| WF08 | Operational metrics, SLA evaluation, and one-time escalation |

## Data Schema

The main entities are `leads`, `lead_events`, `idempotency_keys`, `duplicate_decisions`, `sales_reps`, `followups`, `manager_approvals`, `bookings`, and `dead_letter_queue`. Canonical business state lives in `leads`; variable integration and audit payloads use JSONB. Foreign keys protect canonical relationships, while idempotency and uniqueness constraints prevent repeated operations.

## External Integrations / APIs

### Odoo CRM Integration

The production architecture targets Odoo CRM as the central CRM and system of record. The production adapter is expected to synchronize lead/opportunity creation and updates, sales owner, qualification status, score, source, qualification reason, next action, follow-up status, booking state, conversion/Won stage, and relevant SLA/escalation state.

The submitted assessment runtime uses a deterministic CRM adapter because live Odoo External API access was unavailable in the available Odoo Online environment under the active plan. The assessment adapter preserves the same business contract planned for the Odoo adapter.

| Workflow Event | Production Odoo Action |
| --- | --- |
| Qualified lead | Create or update opportunity |
| Sales assigned | Set salesperson/owner |
| Qualification completed | Sync score, status, and reason |
| Follow-up state changed | Sync next action and status |
| Meeting booked | Move to booked/meeting stage |
| Lead converted | Move opportunity to Won |
| VIP approval/rejection | Sync approval state |
| SLA escalation | Update priority and next activity |

### Other Integrations

Gemini provides qualitative classification under a validated response contract. FastAPI-based assessment services expose deterministic enrichment, messaging, booking/availability, and CRM interfaces. Production provider calls can replace these adapters without changing upstream business decisions.

## CRM Integration Boundary

Business decisions are separate from CRM transport. Workflows determine qualification, owner, priority, stage, next action, booking state, and conversion state. The CRM adapter only synchronizes that canonical state externally. A production Odoo adapter can therefore replace the assessment adapter without changing validation, identity, qualification, routing, follow-up, recovery, or monitoring rules.

## Authentication and Secrets Handling

No real credentials are committed. Production configuration is supplied through n8n credentials or environment variables:

```dotenv
CRM_MODE=mock
ODOO_BASE_URL=
ODOO_DATABASE=
ODOO_USERNAME=
ODOO_API_KEY=
```

Secrets must be stored in the deployment secret manager or n8n credential store, restricted by least privilege, and rotated independently of workflow definitions.

## Idempotency Strategy

Stable operation keys protect intake and downstream effects. Completed idempotency records are never reset or replayed. Follow-up execution uses explicit lifecycle state. WF07 checks original idempotency and current booking/follow-up state before recovery. Unique booking identifiers and atomic conditional updates protect concurrent execution.

## Error Handling and Retry Strategy

Failures are classified as transient, permanent, configuration, or unknown. Transient operations receive bounded attempts; failed attempts return to pending for a later scheduler cycle. Permanent, exhausted, configuration, and unsafe failures terminate in the DLQ or require manual resolution. Targeted manual recovery preserves attempt history and performs state/idempotency checks before side effects. This is bounded retry and scheduler-driven recovery, not fully implemented exponential backoff.

## Human Approval / Manual Review Logic

VIP outbound sales communication requires manager approval. Likely duplicates, material AI/rule conflicts, validation exceptions, unsafe recovery cases, and technical AI failures stop automated progress for human review. Manual recovery cannot replay resolved or actively reprocessing DLQ rows.

## Logging and Observability

`lead_events` is the immutable business audit trail. Integration failures retain structured payloads in `dead_letter_queue`. WF08 derives DB-backed operational metrics and records one SLA breach event per lead-level escalation while avoiding healthy polling noise.

## Testing Approach

The assessment includes evidence T01–T36. Tests cover intake, validation, identity, qualification, routing, follow-up, booking, recovery, monitoring, and audit behavior.

T36 is the end-to-end happy path:

```text
CSV → validation / identity → enrichment → qualification
→ sales routing → CRM integration boundary → follow-up
→ booking → pending follow-up cancellation → conversion → Won → monitoring
```

T36 exercises the assessment CRM adapter; it does not demonstrate live Odoo transport. WF07 reliability tests independently cover transient retry, exhaustion, DLQ recovery, and safe idempotent replay after partial success. T37 is not claimed as executed.

## Known Limitations and Next Improvements

### Live Odoo Connectivity

The submitted version does not perform live writes to Odoo.

CRM operations are executed against the assessment CRM adapter.

This limitation affects the transport/integration layer only. The business logic determining CRM stage, owner, priority, next action, booking state, and conversion state is implemented and tested.

The production next step is to replace the assessment CRM adapter with an authenticated Odoo External API adapter and map the canonical CRM contract to Odoo CRM models and stages.

SLA breach deduplication is lead-level in the assessment implementation. A production system with multiple independent sales cycles should use an SLA-cycle or assignment-specific idempotency key.

Additional improvements include a dedicated DLQ claim lease timestamp, explicit retry eligibility timestamps, production monitoring export, and contract tests against the authenticated Odoo adapter.
