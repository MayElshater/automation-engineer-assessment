# Lead Automation Platform

An n8n-based lead automation assessment covering multi-source intake, validation and identity resolution, enrichment and qualification, post-qualification routing, follow-up, booking/conversion, recovery, and SLA monitoring.

## Architecture Summary

The project includes three architecture views:

- Container / System Architecture
- Lead Processing Workflow
- Sequence Diagram

The CRM Adapter in the sequence diagram represents the deterministic assessment adapter in the submitted runtime and an Odoo External API adapter in production. It does not imply that live Odoo calls occur in assessment mode.

Core components are n8n WF01–WF08, PostgreSQL/Supabase persistence, Gemini qualitative classification, and FastAPI-based assessment services.

## CRM Integration Mode

Current assessment runtime:

```dotenv
CRM_MODE=mock
```

Production target:

```dotenv
CRM_MODE=odoo
```

The submitted assessment uses a deterministic CRM adapter behind a CRM integration interface. Odoo CRM is the production target. Live Odoo External API access was unavailable in the available assessment environment under the active plan, so the runtime uses the assessment mock adapter while preserving the production CRM contract. Live Odoo integration is not claimed as implemented.

## Workflows

| Workflow | Responsibility |
| --- | --- |
| WF01 | Website, WhatsApp, and CSV lead intake and normalization |
| WF02 | Validation, contact normalization, identity resolution, and duplicate handling |
| WF03 | Enrichment, deterministic qualification, and Gemini classification |
| WF04 | Post-qualification routing, manager approval, sales assignment, and CRM boundary |
| WF05 | Follow-up sequence scheduling and idempotent execution |
| WF06 | Booking, follow-up cancellation, conversion, and Won-state handling |
| WF07 | DLQ recovery, bounded scheduler-driven retry, and safe manual replay |
| WF08 | Operational summaries, SLA evaluation, and escalation |

## Environment Placeholders

Copy these into the deployment environment or secret manager.

```dotenv
CRM_MODE=mock

# Production Odoo adapter
ODOO_BASE_URL=
ODOO_DATABASE=
ODOO_USERNAME=
ODOO_API_KEY=
```

Configure PostgreSQL/Supabase, Gemini, and other provider credentials through n8n's credential store or environment-specific secret management.

## Running the Project

### Assessment Mode

1. Apply `04_database/schema.sql` to PostgreSQL/Supabase.
2. From `05_mock_services`, install dependencies and start the deterministic services:

   ```bash
   python -m pip install -r requirements.txt
   uvicorn app.main:app --host 0.0.0.0 --port 8081
   ```

3. Import WF01–WF08 from `02_workflows` into n8n.
4. Configure the existing PostgreSQL and Gemini credentials in n8n.
5. Set `CRM_MODE=mock`, select referenced sub-workflows after import where n8n requires an environment-specific workflow ID, and activate workflows in dependency order.
6. Use `07_sample_data/leads.csv` or the webhook examples to run the flows.

Recovery is bounded and scheduler-driven; exact exponential-delay timing is not claimed.

### Production Odoo Mode

Set `CRM_MODE=odoo`, provide the Odoo environment variables through secure deployment configuration, implement and enable the authenticated Odoo External API adapter, map the canonical CRM contract to the target Odoo models/stages, and run adapter contract/integration tests before enabling writes. The submitted repository does not include completed live Odoo connectivity.

## Test Evidence

Mandatory edge cases and execution evidence are under `06_test_evidence`.

- T36 demonstrates the CSV end-to-end happy path through validation, identity, enrichment, qualification, sales routing, the CRM integration boundary, follow-up, booking, cancellation, conversion, Won, and monitoring.
- WF07 evidence covers transient retry, retry exhaustion, DLQ recovery, and idempotent replay after partial success.
- T36 uses the assessment CRM adapter; it does not prove live Odoo synchronization.
- Live Odoo transport remains a documented production integration step.
- T37 is not claimed as executed.

## Documentation

Technical decisions and limitations are documented in `03_technical_design/technical_design.md` and `03_technical_design/assumptions.md`.


### Large Demo Recordings

Two large demo recordings are intentionally excluded from the GitHub repository because they exceed GitHub's standard file-size limit:

- `T32_Idempotent_replay_after_partial_success-demo.mp4`
- `T36_End-to-End_Happy_Path_Demo.mp4`

Both recordings are included in the ZIP submission. Equivalent screenshots and JSON evidence for T32 and T36 are included in `06_test_evidence`.
