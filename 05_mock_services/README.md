# Mock Enrichment Service

This FastAPI application provides deterministic enrichment responses for local n8n workflow demonstrations and integration tests. It contains no production data or credentials.

## Run

From `05_mock_services`:

```bash
python -m pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8081
```

Configure WF03's `MOCK_ENRICHMENT_URL` as `http://<mock-service-host>:8081/enrich`.

## Endpoints

### `GET /health`

Returns `{"status":"ok"}`.

### `POST /enrich`

Request body:

```json
{
  "lead_id": "uuid",
  "company_name": "string|null",
  "email": "string|null",
  "country": "string|null"
}
```

The optional `X-Mock-Scenario` header accepts:

- `normal` (default): returns deterministic enrichment data.
- `timeout_twice_then_success`: sleeps for 7 seconds on attempts 1 and 2 for each `lead_id`, then succeeds immediately on attempt 3. WF03's 5-second timeout therefore demonstrates timeout, timeout, success.
- `malformed`: returns HTTP 200 with intentionally invalid enrichment data.
- `unavailable`: returns HTTP 503.

Attempt counters are held in process memory and reset whenever the service restarts.

Known companies are `Delta Systems`, `Enterprise AI Corp`, and `Small Services Co`. Unknown companies receive a deterministic generic result, using the submitted country or `Egypt` when absent.

## Examples

Normal enrichment:

```bash
curl -X POST http://localhost:8081/enrich \
  -H "Content-Type: application/json" \
  -d '{"lead_id":"lead-1","company_name":"Delta Systems","email":null,"country":null}'
```

Timeout twice, then success (run three times with the same `lead_id`):

```bash
curl -X POST http://localhost:8081/enrich \
  -H "Content-Type: application/json" \
  -H "X-Mock-Scenario: timeout_twice_then_success" \
  -d '{"lead_id":"lead-retry","company_name":"Enterprise AI Corp","email":null,"country":"Egypt"}'
```

Malformed response:

```bash
curl -X POST http://localhost:8081/enrich \
  -H "Content-Type: application/json" \
  -H "X-Mock-Scenario: malformed" \
  -d '{"lead_id":"lead-2","company_name":"Delta Systems"}'
```

Unavailable response:

```bash
curl -X POST http://localhost:8081/enrich \
  -H "Content-Type: application/json" \
  -H "X-Mock-Scenario: unavailable" \
  -d '{"lead_id":"lead-3","company_name":"Delta Systems"}'
```