# Error Handling and Recovery Strategy

## 1. Purpose

The platform separates business failures, transient integration failures, permanent or configuration failures, and partial-success failures. This separation ensures that each failure receives an appropriate response instead of being silently discarded or retried without control.

The recovery design aims to:

- preserve enough context to diagnose and recover failed operations
- prevent uncontrolled or infinite retries
- prevent duplicate externally visible side effects
- distinguish correctable integration failures from invalid business or configuration states
- provide an auditable path from failure through retry, terminal handling, or resolution

## 2. Failure Classification

WF07 deterministically classifies failures before deciding whether recovery is safe.

### Transient failures

Examples include:

- HTTP 5xx responses
- a provider being temporarily unavailable
- timeouts
- temporary network or integration failures
- HTTP 429 rate limiting

Transient failures are retryable when the persisted attempt count remains below the configured maximum. Recovery is bounded and scheduler-driven. When the maximum is reached, the DLQ item enters terminal failure instead of continuing indefinitely.

### Permanent / Non-Retryable Failures

Examples include:

- invalid request or data that another attempt cannot correct
- unsupported operations
- malformed payloads
- deterministic integration rejection

These failures are not retried indefinitely. The system preserves the error type, message, operation, payload, and attempt history. The item enters terminal failure handling and requires data correction or operator action where appropriate.

### Configuration Failures

Examples include:

- missing or invalid integration configuration
- unavailable required credentials
- authentication or authorization failures

Configuration failures are not treated as ordinary transient provider failures. Repeating the same request without correcting the environment would not resolve the problem, so WF07 fails safely for manual resolution.

### Partial-Success Failures

An external or local side effect may complete even though the workflow later times out or fails before recording success. This is a critical replay case.

Before executing a recovered operation, WF07 loads the original idempotency state and relevant persisted operation state. If the operation is already complete, recovery resolves the DLQ item without replaying the side effect. This protects CRM writes, messages, bookings, follow-ups, and other externally visible operations from duplication after partial success.

## 3. Retry Policy

The implemented policy uses bounded retry and scheduler-driven recovery:

- maximum attempts are defined by the recovery context
- the current attempt count is persisted in `dead_letter_queue`
- only classified transient failures are automatically retryable
- a failed retry returns an eligible item to `pending`
- a later WF07 scheduler cycle can claim the pending item
- exhaustion transitions the item to terminal `failed` state

The assessment does not claim precise exponential-backoff timing. Recovery is scheduler-driven and bounded. Exact delay scheduling is not enforced because the current schema has no `next_retry_at` field, and the workflow intentionally does not use long Wait nodes.

## 4. Dead Letter Queue (DLQ)

The `dead_letter_queue` is the durable recovery boundary for failed operations. It stores:

- DLQ ID
- nullable lead ID
- originating workflow
- operation
- structured payload
- error type
- error message
- attempt count
- status
- creation timestamp
- reprocessing timestamp when applicable

The implemented lifecycle supports:

- `pending`: eligible for scheduled selection or targeted manual selection
- `reprocessing`: atomically claimed by one recovery execution
- `resolved`: successfully recovered or safely resolved without replay
- `failed`: terminal, exhausted, permanent, or manual-resolution state

Retry exhaustion and terminal failures remain available for controlled investigation and manual recovery instead of being silently dropped.

## 5. Recovery Modes

### Scheduled Recovery

WF07 runs on a five-minute schedule and deterministically selects the oldest eligible `pending` DLQ item. The item is claimed with an atomic conditional update from `pending` to `reprocessing`. The condition prevents two executions from successfully claiming the same pending item.

### Manual Targeted Recovery

An operator can configure a specific `manual_dlq_id` for targeted recovery. A pending target is eligible. A failed target may be explicitly returned to `pending` without resetting its attempt history. Resolved and currently reprocessing targets are not replayed.

When no target is configured, manual execution selects the oldest pending item. Scheduled and manual recovery use the same claim, normalization, classification, current-state inspection, idempotency, execution, and persistence pipeline.

## 6. Safe Reprocessing and Idempotency

WF07 reconstructs a stable recovery context containing:

- `dlq_id`
- `lead_id`
- originating `workflow`
- `operation`
- `attempt_count`
- `max_attempts`
- error context
- structured `payload`
- optional `idempotency_key`
- `recovery_mode`

The original operation state is loaded before replay. Recovery decisions follow these safety principles:

- already completed: do not execute the side effect; resolve without replay
- transient, below the attempt limit, and safe: permit controlled retry
- attempts exhausted: do not retry automatically
- permanent: enter terminal handling
- configuration or unknown unsafe condition: require manual resolution

A successful external operation must not be duplicated merely because the workflow failed after the side effect occurred. Atomic claims reduce concurrent recovery risk, while operation idempotency and persisted state protect partial-success replay.

The current DLQ schema does not contain a safe claim lease timestamp. An execution that crashes after claiming may leave an item in `reprocessing` for operator intervention. Automatic reset based on the DLQ creation timestamp is intentionally not used because creation time is not claim time.

## 7. CRM Failure Handling

CRM synchronization uses a provider-agnostic CRM integration boundary.

- Assessment runtime: deterministic assessment CRM adapter
- Production target: authenticated Odoo adapter

Reliability behavior is expressed against the shared CRM contract rather than a provider-specific implementation. For example:

- CRM HTTP 503: transient and eligible for bounded recovery
- CRM timeout: transient, but original-operation state is checked before replay
- retry exhaustion: terminal DLQ failure
- successful recovery or confirmed prior completion: mark the DLQ item resolved

The submitted evidence does not claim execution against live Odoo. Live Odoo External API transport remains a production integration step.

## 8. Follow-Up / Booking Side-Effect Safety

Follow-up execution uses operation-specific idempotency keys such as:

```text
followup:<lead_id>:<sequence_type>:<step_number>
```

Persisted follow-up and idempotency state ensure that an already executed step is not executed again. Booking processing operates on persisted booking state, cancels remaining scheduled follow-ups when a meeting is booked, and converts the existing booking/lead state rather than creating an unrelated duplicate. Recovery handlers inspect current booking and follow-up state before allowing replay.

These protections cover the operations implemented and tested by the assessment; they do not imply unimplemented provider behavior.

## 9. Observability and Auditability

Failures and recovery decisions are observable through:

- `dead_letter_queue` status and structured failure context
- immutable `lead_events` audit events when a lead ID exists
- n8n workflow execution context
- persisted attempt counts
- creation and reprocessing timestamps
- recovery mode, decision, and result
- WF08 operational summaries and SLA monitoring where applicable

This evidence allows an operator to explain why an operation failed, whether it was retried, whether replay was skipped, and how the DLQ item reached its current state. A nullable DLQ lead ID never causes the workflow to fabricate an identifier or insert an invalid lead audit event.

## 10. Tested Failure Scenarios

The implemented evidence includes:

- **T29 — transient failure → retry:** validates that a retryable failure enters controlled bounded recovery.
- **T30 — retry exhaustion → DLQ:** validates terminal handling when the maximum attempt count is reached.
- **T31 — DLQ recovery / replay:** validates controlled recovery of persisted failed work.
- **T32 — idempotent replay after partial success:** validates that completed side effects are not duplicated during replay.

These scenarios validate WF07 reliability behavior independently from the end-to-end business path.

T36 validates the end-to-end happy path through CSV intake, validation and identity, enrichment, qualification, routing, the CRM integration boundary, follow-up, booking, conversion, Won state, and monitoring. It uses the deterministic assessment CRM adapter rather than live Odoo.

A separate end-to-end resilience scenario, T37, was not executed and must not be presented as completed.

## 11. Known Limitations

1. Retry scheduling is bounded and scheduler-driven; exact exponential-backoff timing is not implemented or claimed.
2. Assessment CRM reliability tests use the deterministic assessment CRM adapter, not live Odoo.
3. Recovery is tested for implemented operation classes and should receive provider-specific production integration tests when the Odoo adapter is introduced.
4. SLA breach deduplication is lead-level in the assessment implementation. Multiple independent sales cycles should use an SLA-cycle or assignment-specific idempotency key.
5. The DLQ schema has no `claimed_at` or `lease_expires_at`; a crashed recovery claim can require operator intervention.
6. Operational monitoring is returned as structured workflow output rather than exported to a production dashboard or alerting platform.

## 12. Production Improvements

Future improvements include:

- authenticated Odoo adapter contract and integration tests
- provider-aware retry policies
- jittered exponential backoff where appropriate
- explicit retry eligibility timestamps
- DLQ claim leases using `claimed_at` and `lease_expires_at`
- a richer DLQ operator dashboard
- alerting for DLQ growth and repeated failures
- per-operation retry configuration
- SLA-cycle-specific idempotency
- additional end-to-end resilience tests

These are planned production improvements, not features claimed by the submitted assessment.
