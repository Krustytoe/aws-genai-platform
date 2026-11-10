#!/usr/bin/env bash
# Upload documents to the knowledge base bucket and run an ingestion job.
#
#   scripts/sync-knowledge-base.sh <docs-dir> <bucket> <knowledge-base-id> <data-source-id>
#
# Values come from `terraform output ingestion` in terraform/examples/complete.
# Ingestion is incremental: Bedrock only re-embeds objects that changed, and
# --delete plus the data source's DELETE policy removes vectors for deleted files.
set -euo pipefail

if [[ $# -ne 4 ]]; then
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

docs_dir=$1 bucket=$2 kb_id=$3 ds_id=$4

aws s3 sync "$docs_dir" "s3://${bucket}/" --delete --only-show-errors
echo "Synced ${docs_dir} -> s3://${bucket}/"

job_id=$(aws bedrock-agent start-ingestion-job \
  --knowledge-base-id "$kb_id" --data-source-id "$ds_id" \
  --query 'ingestionJob.ingestionJobId' --output text)
echo "Started ingestion job ${job_id}"

while true; do
  read -r status scanned indexed failed < <(aws bedrock-agent get-ingestion-job \
    --knowledge-base-id "$kb_id" --data-source-id "$ds_id" --ingestion-job-id "$job_id" \
    --query 'ingestionJob.[status, statistics.numberOfDocumentsScanned, statistics.numberOfNewDocumentsIndexed, statistics.numberOfDocumentsFailed]' \
    --output text)
  echo "  ${status}: scanned=${scanned} new=${indexed} failed=${failed}"
  case $status in
    COMPLETE) [[ $failed == 0 ]] && exit 0 || exit 1 ;;
    FAILED | STOPPED) exit 1 ;;
  esac
  sleep 10
done
