"""Deterministic mock services used by local workflow integration tests."""

from __future__ import annotations

import asyncio
import logging
from collections import defaultdict
from typing import Literal

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Lead Automation Mock Services", version="1.0.0")
logger = logging.getLogger("uvicorn.error")

# Process-local by design. Counters reset whenever the application restarts.
_enrichment_attempts: defaultdict[str, int] = defaultdict(int)
_TIMEOUT_DELAY_SECONDS = 7.0


class EnrichmentRequest(BaseModel):
    lead_id: str
    company_name: str | None = None
    email: str | None = None
    country: str | None = None


class EnrichmentResponse(BaseModel):
    status: Literal["success"] = "success"
    industry: str
    company_size: int
    country: str
    strategic_account: bool
    confidence: float


_COMPANY_DATA = {
    "delta systems": {"industry": "Technology", "company_size": 240, "country": "Egypt", "strategic_account": False, "confidence": 0.91},
    "enterprise ai corp": {"industry": "Technology", "company_size": 850, "country": "Egypt", "strategic_account": True, "confidence": 0.91},
    "small services co": {"industry": "Professional Services", "company_size": 15, "country": "Egypt", "strategic_account": False, "confidence": 0.91},
}


def _enrichment_for(request: EnrichmentRequest) -> dict[str, object]:
    company_key = (request.company_name or "").strip().casefold()
    known = _COMPANY_DATA.get(company_key)
    if known is not None:
        return {"status": "success", **known}
    return {
        "status": "success",
        "industry": "Unknown",
        "company_size": 50,
        "country": request.country or "Egypt",
        "strategic_account": False,
        "confidence": 0.6,
    }


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/enrich")
async def enrich(
    request: EnrichmentRequest,
    x_mock_scenario: str = Header(default="normal", alias="X-Mock-Scenario"),
) -> dict[str, object] | EnrichmentResponse:
    scenario = x_mock_scenario.strip().lower()
    allowed = {"normal", "timeout_twice_then_success", "malformed", "unavailable"}
    if scenario not in allowed:
        logger.info(
            "[MOCK_ENRICHMENT] lead_id=%s scenario=%s attempt=1 action=unsupported_scenario",
            request.lead_id,
            scenario,
        )
        raise HTTPException(status_code=400, detail=f"Unsupported X-Mock-Scenario: {scenario}")

    if scenario == "unavailable":
        logger.info(
            "[MOCK_ENRICHMENT] lead_id=%s scenario=%s attempt=1 action=service_unavailable",
            request.lead_id,
            scenario,
        )
        raise HTTPException(status_code=503, detail="Mock enrichment service unavailable")

    if scenario == "malformed":
        result = {"status": "success", "company_size": "not-a-number"}
        logger.info(
            "[MOCK_ENRICHMENT] lead_id=%s scenario=%s attempt=1 action=malformed_response result=%s",
            request.lead_id,
            scenario,
            result,
        )
        return result

    if scenario == "timeout_twice_then_success":
        _enrichment_attempts[request.lead_id] += 1
        attempt = _enrichment_attempts[request.lead_id]
        if attempt <= 2:
            logger.info(
                "[MOCK_ENRICHMENT] lead_id=%s scenario=%s attempt=%d action=simulate_timeout",
                request.lead_id,
                scenario,
                attempt,
            )
            await asyncio.sleep(_TIMEOUT_DELAY_SECONDS)
            return EnrichmentResponse(**_enrichment_for(request))

        result_data = _enrichment_for(request)
        logger.info(
            "[MOCK_ENRICHMENT] lead_id=%s scenario=%s attempt=%d action=success result=%s",
            request.lead_id,
            scenario,
            attempt,
            result_data,
        )
        return EnrichmentResponse(**result_data)

    result_data = _enrichment_for(request)
    logger.info(
        "[MOCK_ENRICHMENT] lead_id=%s scenario=%s attempt=1 action=success result=%s",
        request.lead_id,
        scenario,
        result_data,
    )
    return EnrichmentResponse(**result_data)