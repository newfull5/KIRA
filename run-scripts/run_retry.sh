#!/usr/bin/env bash
set -euo pipefail

# ./run_retry.sh [n-concurrent] [job-dir]        # 잡(기본: 최신)에서 reward<1 태스크만 재실행
# TIMEOUT_MULT=2 ./run_retry.sh 7                # 타임아웃 2배로 재실행
# DISABLE_KIRA=true ./run_retry.sh 7             # 순정 Terminus2로 재실행
#
# --timeout-multiplier  태스크별 agent/verifier 타임아웃에 곱하는 배수

cd "$(dirname "$0")/.."  # uv run은 프로젝트 루트에서 실행되어야 함

# Vertex AI (Gemini) — ADC 인증(gcloud auth application-default login) 선행 필요
export VERTEXAI_PROJECT="${VERTEXAI_PROJECT:-our-highway-505510-e5}"
export VERTEXAI_LOCATION="${VERTEXAI_LOCATION:-global}"

N_CONCURRENT="${1:-7}"
JOB_DIR="${2:-$(ls -td jobs/*/ | head -1)}"
TIMEOUT_MULT="${TIMEOUT_MULT:-2}"
DISABLE_KIRA="${DISABLE_KIRA:-false}"

# 잡 디렉토리에서 reward<1 태스크 수집 (태스크명에 공백 없음 전제)
FAILED=$(python3 - "$JOB_DIR" <<'EOF'
import json, sys
from pathlib import Path
for f in sorted(Path(sys.argv[1]).glob("*/result.json")):
    d = json.load(open(f))
    reward = ((d.get("verifier_result") or {}).get("rewards") or {}).get("reward")
    if not (reward and reward >= 1.0):
        print(f.parent.name.rsplit("__", 1)[0])
EOF
)
TASK_FLAGS=""
for t in $FAILED; do
    TASK_FLAGS="$TASK_FLAGS -t $t"
done

if [ -z "$FAILED" ]; then
    echo "재실행할 실패 태스크 없음 ($JOB_DIR)"
    exit 0
fi

echo "========================================"
echo "Retry: $(echo "$FAILED" | wc -w | tr -d ' ') tasks from $JOB_DIR - Starting at $(date)"
echo "Concurrency: $N_CONCURRENT / Timeout x$TIMEOUT_MULT / KIRA: $([ "$DISABLE_KIRA" = "true" ] && echo OFF || echo ON)"
echo "========================================"

uv run harbor run \
    --agent-import-path "terminus_kira.terminus_kira:TerminusKira" \
    -d "terminal-bench@2.0" \
    $TASK_FLAGS \
    -m "vertex_ai/gemini-3.7-flash" \
    -e docker \
    -n "$N_CONCURRENT" \
    --timeout-multiplier "$TIMEOUT_MULT" \
    --ak disable_kira="$DISABLE_KIRA"

echo "========================================"
echo "Retry - Finished at $(date)"
echo "----------------------------------------"
LATEST_JOB=$(ls -td jobs/*/ | head -1)
python3 - "$LATEST_JOB" <<'EOF'
import json, sys
from pathlib import Path
rows, solved, cost_sum = [], 0, 0.0
for f in sorted(Path(sys.argv[1]).glob("*/result.json")):
    d = json.load(open(f))
    r = d.get("agent_result") or {}
    reward = ((d.get("verifier_result") or {}).get("rewards") or {}).get("reward")
    ok = bool(reward and reward >= 1.0)
    solved += ok
    cost = r.get("cost_usd") or 0.0
    cost_sum += cost
    rows.append((f.parent.name, "PASS" if ok else "FAIL", r.get("n_input_tokens", 0),
                 r.get("n_output_tokens", 0), r.get("n_cache_tokens", 0), cost))
for name, status, i, o, c, cost in rows:
    print(f"[{status}] {name}")
    print(f"        input: {i:,}  output: {o:,}  cache: {c:,}  cost: ${cost:.4f}")
print("----------------------------------------")
print(f"Solved: {solved}/{len(rows)}   Total cost: ${cost_sum:.4f}")
EOF
echo "========================================"
