"""Deterministic mock services used by local workflow integration tests."""

from __future__ import annotations

import asyncio
from collections import defaultdict
from typing import Literal

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Lead Automation Mock Services", version="1.0.0")

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
        raise HTTPException(status_code=400, detail=f"Unsupported X-Mock-Scenario: {scenario}")
    if scenario == "unavailable":
        raise HTTPException(status_code=503, detail="Mock enrichment service unavailable")
    if scenario == "malformed":
        return {"status": "success", "company_size": "not-a-number"}
    if scenario == "timeout_twice_then_success":
        _enrichment_attempts[request.lead_id] += 1
        if _enrichment_attempts[request.lead_id] <= 2:
            await asyncio.sleep(_TIMEOUT_DELAY_SECONDS)
    return EnrichmentResponse(**_enrichment_for(request))