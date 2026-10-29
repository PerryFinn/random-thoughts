#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCALE="${1:-all}"
STAGE="${2:-all}"
case "$SCALE" in all|small|medium|large) ;; *) echo 'Scale must be all, small, medium or large.' >&2; exit 2 ;; esac
case "$STAGE" in all|scan|tokenize|plan|schedule|constraints) ;; *) echo 'Stage must be all, scan, tokenize, plan, schedule or constraints.' >&2; exit 2 ;; esac
[[ $# -le 2 ]] || { echo 'Usage: measure-report-performance.sh [all|small|medium|large] [all|scan|tokenize|plan|schedule|constraints]' >&2; exit 2; }

mkdir -p "$ROOT_DIR/.build/acceptance-35"
RUN_DIR="$(mktemp -d "$ROOT_DIR/.build/acceptance-35/run-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
echo "Aggregate samples and complete logs: $RUN_DIR"
for scale in small medium large; do
  [[ "$SCALE" == all || "$SCALE" == "$scale" ]] || continue
  for stage in scan tokenize plan schedule constraints; do
    [[ "$STAGE" == all || "$STAGE" == "$stage" ]] || continue
    concurrencies=(3)
    [[ "$stage" != schedule ]] || concurrencies=(1 3 8)
    for concurrency in "${concurrencies[@]}"; do
      log="$RUN_DIR/$scale-$stage-$concurrency.log"
      filter=ReportPerformanceTests
      marker=ISSUE35_SAMPLE
      output=samples.jsonl
      expected=2
      [[ "$stage" != schedule ]] || expected=3
      if [[ "$stage" == constraints ]]; then
        filter=ReportPerformanceFailureTests
        marker=ISSUE35_CHECK
        output=checks.jsonl
        expected=1
      fi
      status=0
      RANDOM_THOUGHTS_PERFORMANCE_SCALE="$scale" \
      RANDOM_THOUGHTS_PERFORMANCE_STAGE="$stage" \
      RANDOM_THOUGHTS_PERFORMANCE_CONCURRENCY="$concurrency" \
        "$ROOT_DIR/script/test-isolated.sh" --configuration Release --filter "$filter" > "$log" 2>&1 || status=$?
      awk -v marker="$marker " 'index($0, marker) == 1 { print substr($0, length(marker)+1) }' "$log" >> "$RUN_DIR/$output"
      if [[ $status -ne 0 ]]; then
        echo "FAILED: $scale / $stage / $concurrency (exit $status); see $log" >&2
        tail -20 "$log" >&2
        exit "$status"
      fi
      count="$(awk -v marker="$marker " 'index($0, marker) == 1 { n++ } END { print n+0 }' "$log")"
      [[ "$count" == "$expected" ]] || { echo "Missing measurements in $log" >&2; exit 1; }
      echo "Measured: $scale / $stage / $concurrency"
    done
  done
done
