# bedrock-knowledge-base

## Requirements

Terraform >= 1.7, AWS provider >= 6.27. Run `terraform test` for offline validation (no AWS credentials required).

A Bedrock Knowledge Base backed by **Amazon S3 Vectors**, with an encrypted S3 bucket for source documents, a fixed-size chunking data source, and a least-privilege service role.

## Why S3 Vectors

OpenSearch Serverless, the usual Bedrock KB vector store, bills a minimum number of OCUs around the clock, which is often several hundred USD a month before any traffic. S3 Vectors has no cluster to run: you pay for stored vectors and queries. For internal knowledge bases with spiky, modest query volume, that's a large cost reduction with no servers to patch.

## Gotchas this module handles

- **Dimension drift.** The embedding model dimension and the index dimension must match, or ingestion fails. Both come from one variable, and only Titan v2's supported sizes are accepted.
- **Metadata limits.** Bedrock writes the chunk text and its own metadata onto each vector. Marking `AMAZON_BEDROCK_TEXT` and `AMAZON_BEDROCK_METADATA` non-filterable keeps them out of the small filterable-metadata budget, which ingestion otherwise overruns.
- **CMK and the S3 Vectors indexer.** With a customer managed key, S3 Vectors' background indexer (`indexing.s3vectors.amazonaws.com`) needs `kms:Decrypt`. The generated key policy grants it, scoped by `aws:SourceAccount` and the vector bucket ARN.
- **Create-time role validation.** The knowledge base checks its role when it's created, so it `depends_on` the role policy to avoid a race on first apply.
- **Partition-aware.** The embedding model ARN is built from `aws_partition`, so the module works unchanged in GovCloud.

## Usage

```hcl
module "kb" {
  source = "git::https://github.com/Krustytoe/aws-genai-platform.git//terraform/modules/bedrock-knowledge-base?ref=v0.1.0" # x-release-please-version

  name = "handbook"
}
```

Upload documents to `docs_bucket_name`, then start an ingestion job (`scripts/sync-knowledge-base.sh`).

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Base name for the knowledge base, vector bucket, index and docs bucket. Lowercase letters, digits and hyphens (S3 Vectors naming rules). | n/a (required) |
| `description` | Knowledge base description. | `"Enterprise RAG knowledge base backed by S3 Vectors"` |
| `embedding_model_id` | Bedrock embedding model ID. | `"amazon.titan-embed-text-v2:0"` |
| `embedding_dimensions` | Embedding vector size. Titan Text Embeddings v2 supports 256, 512 or 1024. Must match the index; changing it forces a new index and a full re-ingest. | `1024` |
| `docs_bucket_name` | S3 bucket that holds source documents. null derives a name from the base name, account ID and region. | `null` |
| `inclusion_prefixes` | Only ingest objects under these S3 prefixes. Empty ingests the whole bucket. | `[]` |
| `chunk_max_tokens` | Maximum tokens per chunk (fixed-size chunking). | `512` |
| `chunk_overlap_percentage` | Overlap between adjacent chunks, as a percentage (1-99). Overlap keeps sentences that straddle a boundary retrievable. | `20` |
| `kms_key_arn` | Existing KMS key for the docs bucket and vector bucket. null creates a rotating CMK. | `null` |
| `force_destroy` | Allow Terraform to delete buckets that still contain data. Keep false outside of sandboxes. | `false` |
| `tags` | Tags applied to every resource. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `knowledge_base_id` | Knowledge base ID, used by the app's Retrieve calls. |
| `knowledge_base_arn` | Knowledge base ARN, used to scope bedrock:Retrieve. |
| `data_source_id` | Data source ID, passed to StartIngestionJob after uploading documents. |
| `docs_bucket_name` | Upload source documents here. |
| `docs_bucket_arn` | ARN of the source documents bucket. |
| `vector_index_arn` | ARN of the S3 Vectors index. |
| `role_arn` | Service role the knowledge base assumes. |
| `kms_key_arn` | KMS key protecting documents and vectors (created or supplied). |
