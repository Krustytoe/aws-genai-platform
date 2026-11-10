"""Bedrock adapters against botocore's Stubber: real request/response shapes, no network."""

import boto3
import pytest
from botocore.stub import ANY, Stubber

from ragapi.providers.base import ProviderError, ProviderThrottledError
from ragapi.providers.bedrock import BedrockConverseModel, BedrockKnowledgeBaseRetriever


@pytest.fixture(autouse=True)
def _fake_credentials(monkeypatch) -> None:
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


def client(service: str):
    return boto3.client(service, region_name="us-east-1")


def test_retrieve_maps_results_and_locations() -> None:
    c = client("bedrock-agent-runtime")
    with Stubber(c) as stub:
        stub.add_response(
            "retrieve",
            {
                "retrievalResults": [
                    {
                        "content": {"text": "Per diem is $75."},
                        "location": {"type": "S3", "s3Location": {"uri": "s3://docs/travel.md"}},
                        "score": 0.77,
                    },
                    {
                        "content": {"text": "Wiki page."},
                        "location": {"type": "WEB", "webLocation": {"url": "https://wiki/x"}},
                        "score": 0.5,
                    },
                    {"content": {"text": "No location."}, "score": 0.4},
                ]
            },
            {
                "knowledgeBaseId": "KB12345678",
                "retrievalQuery": {"text": "per diem"},
                "retrievalConfiguration": {"vectorSearchConfiguration": {"numberOfResults": 3}},
            },
        )
        passages = BedrockKnowledgeBaseRetriever("KB12345678", client=c).retrieve("per diem", 3)

    assert [p.source for p in passages] == ["s3://docs/travel.md", "https://wiki/x", "unknown"]
    assert passages[0].score == pytest.approx(0.77)


def test_converse_sends_guard_content_with_qualifiers() -> None:
    c = client("bedrock-runtime")
    expected = {
        "modelId": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "system": [{"text": "SYS"}],
        "inferenceConfig": {"maxTokens": 100, "temperature": 0.1},
        "guardrailConfig": {
            "guardrailIdentifier": "gr-123",
            "guardrailVersion": "2",
            "trace": "disabled",
        },
        "messages": [
            {
                "role": "user",
                "content": [
                    {"guardContent": {"text": {"text": "CTX", "qualifiers": ["grounding_source"]}}},
                    {"text": "Question:"},
                    {"guardContent": {"text": {"text": "Q?", "qualifiers": ["query"]}}},
                ],
            }
        ],
    }
    with Stubber(c) as stub:
        stub.add_response(
            "converse",
            {
                "output": {"message": {"role": "assistant", "content": [{"text": " $75 [1] "}]}},
                "stopReason": "end_turn",
                "usage": {"inputTokens": 900, "outputTokens": 12, "totalTokens": 912},
                "metrics": {"latencyMs": 420},
            },
            expected,
        )
        model = BedrockConverseModel(expected["modelId"], "gr-123", "2", client=c)
        completion = model.generate(
            system_prompt="SYS", context="CTX", question="Q?", max_tokens=100, temperature=0.1
        )

    assert completion.text == "$75 [1]"
    assert (completion.input_tokens, completion.output_tokens) == (900, 12)
    assert not completion.blocked


def test_converse_reports_guardrail_intervention() -> None:
    c = client("bedrock-runtime")
    with Stubber(c) as stub:
        stub.add_response(
            "converse",
            {
                "output": {"message": {"role": "assistant", "content": [{"text": "Blocked."}]}},
                "stopReason": "guardrail_intervened",
                "usage": {"inputTokens": 50, "outputTokens": 0, "totalTokens": 50},
                "metrics": {"latencyMs": 80},
            },
            {
                "modelId": "m",
                "system": ANY,
                "inferenceConfig": ANY,
                "guardrailConfig": ANY,
                "messages": ANY,
            },
        )
        completion = BedrockConverseModel("m", "gr-1", client=c).generate(
            system_prompt="s", context="c", question="q", max_tokens=10, temperature=0
        )
    assert completion.blocked


def test_converse_without_guardrail_uses_plain_text() -> None:
    c = client("bedrock-runtime")
    with Stubber(c) as stub:
        stub.add_response(
            "converse",
            {
                "output": {"message": {"role": "assistant", "content": [{"text": "ok"}]}},
                "stopReason": "end_turn",
                "usage": {"inputTokens": 1, "outputTokens": 1, "totalTokens": 2},
                "metrics": {"latencyMs": 1},
            },
            {
                "modelId": "m",
                "system": ANY,
                "inferenceConfig": ANY,
                "messages": [{"role": "user", "content": [{"text": "c\n\nQuestion: q"}]}],
            },
        )
        BedrockConverseModel("m", None, client=c).generate(
            system_prompt="s", context="c", question="q", max_tokens=10, temperature=0
        )


@pytest.mark.parametrize(
    ("code", "exc"),
    [("ThrottlingException", ProviderThrottledError), ("AccessDeniedException", ProviderError)],
)
def test_client_errors_are_translated(code, exc) -> None:
    c = client("bedrock-runtime")
    with Stubber(c) as stub:
        stub.add_client_error("converse", service_error_code=code, http_status_code=400)
        with pytest.raises(exc) as info:
            BedrockConverseModel("m", None, client=c).generate(
                system_prompt="s", context="c", question="q", max_tokens=10, temperature=0
            )
    assert code in str(info.value)


def test_retrieve_errors_are_translated() -> None:
    c = client("bedrock-agent-runtime")
    with Stubber(c) as stub:
        stub.add_client_error("retrieve", service_error_code="ResourceNotFoundException")
        with pytest.raises(ProviderError, match="ResourceNotFoundException"):
            BedrockKnowledgeBaseRetriever("KB12345678", client=c).retrieve("q", 1)


def test_local_botocore_errors_are_translated() -> None:
    # An invalid knowledge base ID fails botocore's parameter validation before any call.
    with pytest.raises(ProviderError, match="ParamValidationError"):
        BedrockKnowledgeBaseRetriever("bad", client=client("bedrock-agent-runtime")).retrieve(
            "q", 1
        )
