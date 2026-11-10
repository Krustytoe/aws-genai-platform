import pytest
from pydantic import ValidationError

from ragapi.config import Provider, Settings


def test_defaults_to_fake(monkeypatch) -> None:
    monkeypatch.delenv("RAG_PROVIDER", raising=False)
    assert Settings().provider is Provider.FAKE


def test_bedrock_requires_knowledge_base_and_guardrail() -> None:
    with pytest.raises(ValidationError, match="RAG_KNOWLEDGE_BASE_ID, RAG_GUARDRAIL_ID"):
        Settings(provider="bedrock")


def test_reads_environment(monkeypatch) -> None:
    monkeypatch.setenv("RAG_PROVIDER", "bedrock")
    monkeypatch.setenv("RAG_KNOWLEDGE_BASE_ID", "KB12345678")
    monkeypatch.setenv("RAG_GUARDRAIL_ID", "gr-1")
    monkeypatch.setenv("RAG_TOP_K", "8")
    s = Settings()
    assert (s.provider, s.knowledge_base_id, s.top_k) == (Provider.BEDROCK, "KB12345678", 8)


def test_rejects_out_of_range_values() -> None:
    with pytest.raises(ValidationError):
        Settings(min_score=1.5)
