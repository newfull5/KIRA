#!/usr/bin/env bash
set -euo pipefail

# ./run_flaky.sh [n-concurrent]        # 이전 런에서 통과한 적 있는 flaky 태스크만 타임아웃 2배로 재실행
# TIMEOUT_MULT=3 ./run_flaky.sh 4      # 타임아웃 배수 조정
# FLAKY="a b c" ./run_flaky.sh 4       # 대상 태스크 직접 지정
#
# 왜 이 목록인가: content_filter로 결정론적 차단되는 부류 A(feal 등)는 재시도해도
# 똑같이 막히므로 제외했다. 여기 태스크들은 과거 런에서 reward=1.0을 받은 적이 있어,
# 재시도로 통과 확률을 노릴 수 있는 flaky 케이스만 모은 것이다.

cd "$(dirname "$0")/.."  # uv run은 프로젝트 루트에서 실행되어야 함

export VERTEXAI_PROJECT="${VERTEXAI_PROJECT:-our-highway-505510-e5}"
export VERTEXAI_LOCATION="${VERTEXAI_LOCATION:-global}"

N_CONCURRENT="${1:-4}"
TIMEOUT_MULT="${TIMEOUT_MULT:-2}"
DISABLE_KIRA="${DISABLE_KIRA:-false}"

# 과거 통과 이력이 있는 flaky 태스크 (부류 B: 느린 연산 / 부류 C: 오답)
FLAKY="${FLAKY:-extract-moves-from-video mcmc-sampling-stan train-fasttext install-windows-3.11}"

TASK_FLAGS=""
for t in $FLAKY; do
    TASK_FLAGS="$TASK_FLAGS -t $t"
done

echo "========================================"
echo "Flaky retry: $(echo "$FLAKY" | wc -w | tr -d ' ') tasks - Starting at $(date)"
echo "Tasks: $FLAKY"
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
echo "Flaky retry - Finished at $(date)"
echo "----------------------------------------"
LATEST_JOB=$(ls -td jobs/*/ | head -1)
python3 - "$LATEST_JOB" <<'EOF'
import json, sys
from pathlib import Path
rows, solved = [], 0
for f in sorted(Path(sys.argv[1]).glob("*/result.json")):
    d = json.load(open(f))
    reward = ((d.get("verifier_result") or {}).get("rewards") or {}).get("reward")
    exc = (d.get("exception_info") or {}).get("exception_type")
    ok = bool(reward and reward >= 1.0)
    solved += ok
    rows.append((f.parent.name.rsplit("__", 1)[0], "PASS" if ok else "FAIL", exc or "-"))
for name, status, exc in rows:
    print(f"[{status}] {name}   ({exc})")
print("----------------------------------------")
print(f"Solved: {solved}/{len(rows)}")
EOF
echo "========================================"
