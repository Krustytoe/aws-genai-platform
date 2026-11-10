"""Amazon Bedrock adapters: Knowledge Base Retrieve and the Converse API."""

from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from .base import Completion, Passage, ProviderError, ProviderThrottledError

_RETRY = Config(retries={"mode": "adaptive", "max_attempts": 4}, connect_timeout=5, read_timeout=60)
_THROTTLE_CODES = frozenset(
    {"ThrottlingException", "ServiceQuotaExceededException", "TooManyRequestsException"}
)


def _wrap(exc: Exception, what: str) -> ProviderError:
    if isinstance(exc, ClientError):
        code = exc.response.get("Error", {}).get("Code", "")
        if code in _THROTTLE_CODES:
            return ProviderThrottledError(f"{what} throttled: {code}")
        return ProviderError(f"{what} failed: {code or 'unknown error'}")
    return ProviderError(f"{what} failed: {type(exc).__name__}")


def _source(location: dict[str, Any]) -> str:
    for key, field in (
        ("s3Location", "uri"),
        ("webLocation", "url"),
        ("confluenceLocation", "url"),
        ("sharePointLocation", "url"),
        ("salesforceLocation", "url"),
    ):
        if value := location.get(key, {}).get(field):
            return value
    return location.get("type", "unknown")


class BedrockKnowledgeBaseRetriever:
    def __init__(self, knowledge_base_id: str, client: Any = None) -> None:
        self._kb_id = knowledge_base_id
        self._client = client or boto3.client("bedrock-agent-runtime", config=_RETRY)

    def retrieve(self, query: str, top_k: int) -> list[Passage]:
        try:
            response = self._client.retrieve(
                knowledgeBaseId=self._kb_id,
                retrievalQuery={"text": query},
                retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": top_k}},
            )
        except (ClientError, BotoCoreError) as exc:
            raise _wrap(exc, "knowledge base retrieve") from exc

        return [
            Passage(
                text=r["content"]["text"],
                source=_source(r.get("location", {})),
                score=float(r.get("score", 0.0)),
            )
            for r in response.get("retrievalResults", [])
            if r.get("content", {}).get("text")
        ]


class BedrockConverseModel:
    system = "aws.bedrock"

    def __init__(
        self,
        model_id: str,
        guardrail_id: str | None,
        guardrail_version: str = "DRAFT",
        client: Any = None,
    ) -> None:
        self.model_id = model_id
        self._guardrail_id = guardrail_id
        self._guardrail_version = guardrail_version
        self._client = client or boto3.client("bedrock-runtime", config=_RETRY)

    def generate(
        self,
        *,
        system_prompt: str,
        context: str,
        question: str,
        max_tokens: int,
        temperature: float,
    ) -> Completion:
        kwargs: dict[str, Any] = {
            "modelId": self.model_id,
            "system": [{"text": system_prompt}],
            "inferenceConfig": {"maxTokens": max_tokens, "temperature": temperature},
        }

        if self._guardrail_id:
            # Qualifiers tell the guardrail which text is evidence and which is the
            # user's query, which is what contextual grounding checks compare.
            content = [
                {"guardContent": {"text": {"text": context, "qualifiers": ["grounding_source"]}}},
                {"text": "Question:"},
                {"guardContent": {"text": {"text": question, "qualifiers": ["query"]}}},
            ]
            kwargs["guardrailConfig"] = {
                "guardrailIdentifier": self._guardrail_id,
                "guardrailVersion": self._guardrail_version,
                "trace": "disabled",
            }
        else:
            content = [{"text": f"{context}\n\nQuestion: {question}"}]

        kwargs["messages"] = [{"role": "user", "content": content}]

        try:
            response = self._client.converse(**kwargs)
        except (ClientError, BotoCoreError) as exc:
            raise _wrap(exc, "bedrock converse") from exc

        blocks = response.get("output", {}).get("message", {}).get("content", [])
        usage = response.get("usage", {})
        return Completion(
            text="".join(b.get("text", "") for b in blocks).strip(),
            input_tokens=int(usage.get("inputTokens", 0)),
            output_tokens=int(usage.get("outputTokens", 0)),
            blocked=response.get("stopReason") == "guardrail_intervened",
        )
