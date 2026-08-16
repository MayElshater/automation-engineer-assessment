# Assumptions

## CRM / Odoo Integration Assumption

The assessment implementation uses a deterministic simulated CRM adapter behind a defined CRM integration boundary.

Odoo CRM is the intended production system of record for:

- lead and opportunity creation and updates
- sales ownership
- qualification result and score
- CRM stage
- next action
- follow-up state
- booking state
- conversion and Won state
- relevant SLA and escalation state

The available Odoo Online environment did not expose the required External API access under the active plan. Therefore, live Odoo writes are not executed in the submitted assessment runtime.

The CRM boundary is intentionally provider-agnostic. Replacing the assessment adapter with a production Odoo adapter must not require changes to upstream validation, identity resolution, qualification, routing, follow-up, recovery, or monitoring logic.

CRM semantics are implemented and tested. CRM transport is mocked in the assessment environment, while Odoo remains the production target. The mock is the assessment CRM adapter; it is not a mock of Odoo itself.

## Runtime and Integration Assumptions

- PostgreSQL/Supabase is the authoritative persistence layer.
- n8n WF01–WF08 owns orchestration, business-state transitions, audit events, recovery, and monitoring.
- Gemini provides an independent qualitative classification signal and never changes the deterministic numerical score.
- FastAPI services provide deterministic assessment boundaries for enrichment, messaging, booking/availability, and CRM transport where production services are unavailable.
- Retries are bounded. WF07 recovery is scheduler-driven and does not enforce exact exponential-delay timing.
- No production credentials or secrets are committed.
