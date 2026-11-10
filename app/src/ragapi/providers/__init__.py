"""Provider wiring: pick adapters from settings."""

from ..config import Provider, Settings
from .base import ChatModel, Retriever


def build_providers(settings: Settings) -> tuple[Retriever, ChatModel]:
    if settings.provider is Provider.BEDROCK:
        from .bedrock import BedrockConverseModel, BedrockKnowledgeBaseRetriever

        assert settings.knowledge_base_id  # noqa: S101 - guaranteed by Settings validation
        return (
            BedrockKnowledgeBaseRetriever(settings.knowledge_base_id),
            BedrockConverseModel(
                settings.model_id, settings.guardrail_id, settings.guardrail_version
            ),
        )

    from .fake import FakeChatModel, FakeRetriever

    return FakeRetriever(settings.fake_corpus_dir), FakeChatModel()
