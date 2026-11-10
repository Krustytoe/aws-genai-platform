# ragapi (AWS)

FastAPI service that answers employee questions from an Amazon Bedrock Knowledge Base, with citations, guardrails, PII redaction, and per-tenant token/cost telemetry.

## Request path

1. **Redact** emails, SSNs, card numbers (Luhn-checked), phone numbers and AWS keys from the question, locally, before anything leaves the process.
2. **Retrieve** the top-k chunks from the knowledge base (`bedrock:Retrieve`).
3. **Gate**: drop chunks under `RAG_MIN_SCORE`. If nothing is left, return a fixed refusal **without calling the model**. That saves cost and removes the chance of a hallucinated answer.
4. **Generate** with the Converse API. Sources go in as `guardContent` qualified `grounding_source` and the question as `query`, so the guardrail's contextual-grounding check can block answers that aren't supported by the sources.
5. **Cite**: `[n]` markers are mapped back to their source URIs. An answer with no valid citation is reported as `grounded: false`.
6. **Account**: token usage and estimated cost are emitted as OpenTelemetry metrics, tagged with the `X-Tenant-Id` header, for showback/chargeback.

Logs record outcome, tenant, token counts and latency. They **never** contain question or answer text.

## Run locally (no cloud account needed)

```bash
uv sync
RAG_PROVIDER=fake uv run uvicorn --factory ragapi.main:create_app --port 8080

curl -s localhost:8080/v1/chat -H 'content-type: application/json' -H 'x-tenant-id: finance' \
  -d '{"question":"What is the domestic meal per diem?"}' | jq
```

The `fake` provider does keyword retrieval over `../evals/corpus` and returns the top passage with a citation. It's there for exercising the pipeline, not for judging answer quality.

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `RAG_PROVIDER` | `fake` | `bedrock` in deployed environments |
| `RAG_MODEL_ID` | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Model or inference profile ID |
| `RAG_KNOWLEDGE_BASE_ID` | | Required for `bedrock` |
| `RAG_GUARDRAIL_ID` | | Required for `bedrock`. IAM denies invokes without it anyway |
| `RAG_GUARDRAIL_VERSION` | `DRAFT` | Pin a published version in production |
| `RAG_TOP_K` | `5` | Chunks retrieved |
| `RAG_MIN_SCORE` | `0.35` | Relevance floor (0-1) below which chunks are ignored |
| `RAG_MAX_QUESTION_CHARS` | `2000` | Input size cap |
| `RAG_MAX_OUTPUT_TOKENS` | `800` | |
| `RAG_TEMPERATURE` | `0.1` | |
| `RAG_REDACT_PII` | `true` | |
| `RAG_PRICE_INPUT_PER_1K` / `RAG_PRICE_OUTPUT_PER_1K` | `0.003` / `0.015` | USD, used for the `rag.cost` metric |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | | Enables OTLP/HTTP export of traces and metrics |
| `AWS_REGION` | | Standard boto3 resolution; credentials come from the task/pod role |

## API

`POST /v1/chat` with header `X-Tenant-Id: <team>` (optional, `[a-z0-9-]`, max 63 chars)

```json
{
  "request_id": "9f1c...",
  "answer": "The domestic meal per diem is $75 per day [1].",
  "grounded": true,
  "blocked": false,
  "citations": [{"id": 1, "source": "s3://.../travel-and-expense-policy.md", "score": 0.71, "snippet": "..."}],
  "usage": {"input_tokens": 912, "output_tokens": 24, "estimated_cost_usd": 0.003096},
  "redactions": {}
}
```

Errors: `422` invalid input, `429` upstream throttling (with `Retry-After`), `502` upstream failure.

## Tests

```bash
uv run ruff check . && uv run ruff format --check .
uv run pytest          # offline; Bedrock calls go through botocore Stubber
```
