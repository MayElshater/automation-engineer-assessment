import asyncio

import httpx
import pytest

from app import main


@pytest.fixture(autouse=True)
def reset_attempt_counters():
    main._enrichment_attempts.clear()


@pytest.fixture
async def client():
    transport = httpx.ASGITransport(app=main.app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as test_client:
        yield test_client


@pytest.mark.anyio
async def test_normal_success(client):
    response = await client.post("/enrich", json={"lead_id": "lead-1", "company_name": "Delta Systems", "email": None, "country": None})
    assert response.status_code == 200
    assert response.json() == {"status": "success", "industry": "Technology", "company_size": 240, "country": "Egypt", "strategic_account": False, "confidence": 0.91}


@pytest.mark.anyio
async def test_malformed_response(client):
    response = await client.post("/enrich", headers={"X-Mock-Scenario": "malformed"}, json={"lead_id": "lead-2", "company_name": "Delta Systems"})
    assert response.status_code == 200
    assert response.json() == {"status": "success", "company_size": "not-a-number"}


@pytest.mark.anyio
async def test_unavailable_returns_503(client):
    response = await client.post("/enrich", headers={"X-Mock-Scenario": "unavailable"}, json={"lead_id": "lead-3", "company_name": "Delta Systems"})
    assert response.status_code == 503


@pytest.mark.anyio
async def test_timeout_twice_then_success_on_third_request(client, monkeypatch):
    sleep_calls: list[float] = []
    original_sleep = asyncio.sleep

    async def non_blocking_sleep(seconds: float) -> None:
        sleep_calls.append(seconds)
        await original_sleep(0)

    monkeypatch.setattr(main.asyncio, "sleep", non_blocking_sleep)
    payload = {"lead_id": "lead-retry", "company_name": "Enterprise AI Corp"}
    headers = {"X-Mock-Scenario": "timeout_twice_then_success"}
    responses = [await client.post("/enrich", headers=headers, json=payload) for _ in range(3)]

    assert [response.status_code for response in responses] == [200, 200, 200]
    assert sleep_calls == [main._TIMEOUT_DELAY_SECONDS, main._TIMEOUT_DELAY_SECONDS]
    assert responses[2].json()["company_size"] == 850
    assert main._enrichment_attempts["lead-retry"] == 3