#!/usr/bin/env bash
set -euo pipefail

# ./run_hard.sh [n-concurrent]              # difficulty=hard 태스크 전체 실행 (기본 4)
# DISABLE_KIRA=true ./run_hard.sh 7         # KIRA 하네스 끄고 순정 Terminus2로 실행
#
# --agent-import-path  사용할 에이전트 클래스 (module:Class)
# -d                   데이터셋 name@version. 샘플만: terminal-bench-sample@2.0
# -t                   실행할 태스크명 (hard 태스크마다 하나씩)
# -m                   모델 (litellm 형식 provider/model)
# -e                   실행 환경: docker(로컬) | daytona | runloop(클라우드)
# -n                   동시 실행 태스크 수 (--n-concurrent). Docker 메모리 ÷ 2G가 상한
# --ak                 에이전트 kwarg. disable_kira=true면 KIRA 오버라이드 전체 우회

cd "$(dirname "$0")/.."  # uv run은 프로젝트 루트에서 실행되어야 함

# Vertex AI (Gemini) — ADC 인증(gcloud auth application-default login) 선행 필요
export VERTEXAI_PROJECT="${VERTEXAI_PROJECT:-our-highway-505510-e5}"
export VERTEXAI_LOCATION="${VERTEXAI_LOCATION:-global}"

N_CONCURRENT="${1:-4}"
DISABLE_KIRA="${DISABLE_KIRA:-false}"

# data/tasks/*/task.toml 에서 difficulty="hard" 태스크만 -t 플래그로 수집
TASK_FLAGS=()
for toml in data/tasks/*/task.toml; do
    if grep -q 'difficulty = "hard"' "$toml"; then
        TASK_FLAGS+=(-t "$(basename "$(dirname "$toml")")")
    fi
done

echo "========================================"
echo "Hard tasks: $((${#TASK_FLAGS[@]} / 2)) - Starting at $(date)"
echo "Concurrency: $N_CONCURRENT / KIRA harness: $([ "$DISABLE_KIRA" = "true" ] && echo OFF || echo ON)"
echo "========================================"

uv run harbor run \
    --agent-import-path "terminus_kira.terminus_kira:TerminusKira" \
    -d "terminal-bench@2.0" \
    "${TASK_FLAGS[@]}" \
    -m "vertex_ai/gemini-3.7-flash" \
    -e docker \
    -n "$N_CONCURRENT" \
    --ak disable_kira="$DISABLE_KIRA"

echo "========================================"
echo "Hard tasks - Finished at $(date)"
echo "----------------------------------------"
LATEST_JOB=$(ls -td jobs/*/ | head -1)
python3 - "$LATEST_JOB" <<'EOF'
import json, sys
from pathlib import Path
rows, solved, cost_sum = [], 0, 0.0
for f in sorted(Path(sys.argv[1]).glob("*/result.json")):
    d = json.load(open(f))
    r = d.get("agent_result") or {}
    reward = (d.get("verifier_result") or {}).get("reward")
    reward = reward if reward is not None else d.get("reward")
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
