"""Runtime configuration, read from RAG_* environment variables."""

from enum import StrEnum
from pathlib import Path

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Provider(StrEnum):
    BEDROCK = "bedrock"
    FAKE = "fake"  # offline: keyword retrieval over a local corpus, canned answers


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="RAG_", extra="ignore")

    provider: Provider = Provider.FAKE

    # Bedrock
    model_id: str = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    knowledge_base_id: str | None = None
    guardrail_id: str | None = None
    guardrail_version: str = "DRAFT"

    # Fake provider
    fake_corpus_dir: Path = Path("../evals/corpus")

    # Retrieval and generation
    top_k: int = Field(5, ge=1, le=20)
    min_score: float = Field(0.35, ge=0.0, le=1.0)
    max_question_chars: int = Field(2000, ge=1, le=20_000)
    max_output_tokens: int = Field(800, ge=1, le=8192)
    temperature: float = Field(0.1, ge=0.0, le=1.0)

    # Data protection
    redact_pii: bool = True

    # Cost attribution (USD per 1K tokens). Set to your model's list price.
    price_input_per_1k: float = Field(0.003, ge=0.0)
    price_output_per_1k: float = Field(0.015, ge=0.0)

    @model_validator(mode="after")
    def _require_cloud_ids(self) -> "Settings":
        if self.provider is Provider.BEDROCK:
            missing = [
                name
                for name, value in (
                    ("RAG_KNOWLEDGE_BASE_ID", self.knowledge_base_id),
                    ("RAG_GUARDRAIL_ID", self.guardrail_id),
                )
                if not value
            ]
            if missing:
                raise ValueError(f"provider=bedrock requires {', '.join(missing)}")
        return self
