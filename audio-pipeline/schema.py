"""
schema.py
=========

Immutable data-contract models for the **Penlo Contract v1.1**.

These Pydantic (v2) models are the single source of structural truth for the
pipeline. Any payload written to ``./output/`` must successfully validate
against :class:`PenloPayload`. If the LLM returns data that does not conform,
validation raises and the transcript is routed to ``./failed/``.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


def _utc_now_iso() -> str:
    """Return the current UTC time as an ISO 8601 string (e.g. ``2026-05-29T17:53:00+00:00``)."""
    return datetime.now(timezone.utc).isoformat()


class Fact(BaseModel):
    """A single Subject-Predicate-Object knowledge triple extracted from a transcript.

    The ``confidence`` field is bounded to the Penlo-mandated range of 0.60-0.85
    because the source material is an AI-generated transcript (never fully certain).
    """

    # Forbid unexpected keys so the contract stays strict and predictable.
    model_config = ConfigDict(extra="forbid")

    subject: str = Field(..., description="Proper noun or well-formed noun phrase.")
    predicate: str = Field(..., description="Short, present-tense verb phrase.")
    object: str = Field(..., description="Concise, specific detail.")
    confidence: float = Field(
        ...,
        ge=0.60,
        le=0.85,
        description="Confidence score, strictly within the 0.60-0.85 band.",
    )
    capturedAt: str = Field(
        default_factory=_utc_now_iso,
        description="ISO 8601 UTC timestamp marking when this fact was captured.",
    )


class Person(BaseModel):
    """A specific human mentioned or speaking within a transcript."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(..., description="The person's name.")
    email: Optional[str] = Field(default=None, description="Email if mentioned, else None.")
    phone: Optional[str] = Field(default=None, description="Phone if mentioned, else None.")
    notes: Optional[str] = Field(default=None, description="Brief note (< 10 words) or None.")


class PenloPayload(BaseModel):
    """The complete, validated payload persisted to ``./output/``.

    Defaults encode the Penlo Contract v1.1 envelope. ``syncedAt`` and the
    ``capturedAt`` on each :class:`Fact` are injected at processing time by the
    pipeline so they reflect the exact execution moment.
    """

    model_config = ConfigDict(extra="forbid")

    schemaVersion: str = Field(default="1.1", description="Penlo contract version.")
    deviceID: str = Field(
        default="PENLO_LOCAL_PIPELINE",
        description="Identifier of the device/process that produced this payload.",
    )
    userEmail: Optional[str] = Field(
        default="local-operator@penlo.ai",
        description="Owning user's email, or None.",
    )
    syncedAt: str = Field(
        default_factory=_utc_now_iso,
        description="ISO 8601 UTC timestamp generated at processing execution.",
    )
    facts: List[Fact] = Field(default_factory=list)
    people: List[Person] = Field(default_factory=list)
    topicSummary: List[str] = Field(default_factory=list)
