from ragapi.config import Settings
from ragapi.providers import build_providers
from ragapi.providers.bedrock import BedrockConverseModel, BedrockKnowledgeBaseRetriever
from ragapi.providers.fake import FakeChatModel, FakeRetriever

from .conftest import CORPUS


def test_builds_bedrock_adapters(monkeypatch) -> None:
    # boto3 client construction is local; no AWS calls are made.
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-gov-west-1")
    retriever, model = build_providers(
        Settings(
            provider="bedrock",
            knowledge_base_id="KB12345678",
            guardrail_id="gr-123",
            guardrail_version="3",
        )
    )
    assert isinstance(retriever, BedrockKnowledgeBaseRetriever)
    assert isinstance(model, BedrockConverseModel)
    assert model.model_id.startswith("us.anthropic.")


def test_builds_fake_adapters() -> None:
    retriever, model = build_providers(Settings(fake_corpus_dir=CORPUS))
    assert isinstance(retriever, FakeRetriever)
    assert isinstance(model, FakeChatModel)
