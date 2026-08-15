#!/usr/bin/env bash
set -euo pipefail

# 순정 KIRA(터미널벤치 에이전트, KIRA-N 티켓 수정 이전) 로 hard 태스크 전체를 pass@k 로 실행.
# terminus_kira/ 는 호출 전에 c747a64 상태로 복원되어 있어야 한다.
#
# ./run_vanilla.sh [n-concurrent]        # 기본 concurrency 7, n-attempts 3
# N_ATTEMPTS=3 ./run_vanilla.sh 7        # 태스크당 시도 횟수(pass@k)
# TASKS="a b" ./run_vanilla.sh 4         # 특정 태스크만 (스모크 테스트용)
#
# 순정 에이전트는 disable_kira kwarg를 모르므로 --ak 를 넘기지 않는다.

cd "$(dirname "$0")/.."

export VERTEXAI_PROJECT="${VERTEXAI_PROJECT:-our-highway-505510-e5}"
export VERTEXAI_LOCATION="${VERTEXAI_LOCATION:-global}"

N_CONCURRENT="${1:-7}"
N_ATTEMPTS="${N_ATTEMPTS:-3}"

# terminal-bench@2.0 hard 태스크 30개 (data/tasks 로컬 폴더 없이도 돌게 하드코딩).
# 갱신이 필요하면: for t in data/tasks/*/task.toml; do grep -lq 'difficulty = "hard"' "$t" && basename "$(dirname "$t")"; done
HARD_TASKS="bn-fit-modify cancel-async-tasks circuit-fibsqrt configure-git-webserver dna-assembly extract-moves-from-video feal-differential-cryptanalysis feal-linear-cryptanalysis fix-code-vulnerability fix-ocaml-gc gpt2-codegolf install-windows-3.11 llm-inference-batching-scheduler make-doom-for-mips make-mips-interpreter mcmc-sampling-stan model-extraction-relu-logits password-recovery path-tracing-reverse path-tracing polyglot-rust-c protein-assembly regex-chess sam-cell-seg sparql-university torch-pipeline-parallelism torch-tensor-parallelism train-fasttext video-processing write-compressor"

TASK_FLAGS=""
for t in ${TASKS:-$HARD_TASKS}; do TASK_FLAGS="$TASK_FLAGS -t $t"; done

echo "========================================"
echo "VANILLA KIRA / n-attempts=$N_ATTEMPTS (pass@$N_ATTEMPTS) - Starting at $(date)"
echo "Concurrency: $N_CONCURRENT"
echo "========================================"

uv run harbor run \
    --agent-import-path "terminus_kira.terminus_kira:TerminusKira" \
    -d "terminal-bench@2.0" \
    $TASK_FLAGS \
    -m "vertex_ai/gemini-3.7-flash" \
    -e docker \
    -n "$N_CONCURRENT" \
    -k "$N_ATTEMPTS"

echo "========================================"
echo "VANILLA KIRA - Finished at $(date)"
echo "----------------------------------------"
LATEST_JOB=$(ls -td jobs/*/ | head -1)
# pass@k: 태스크별로 k번 시도 중 1번이라도 reward>=1 이면 통과
python3 - "$LATEST_JOB" <<'EOF'
import json, sys
from collections import defaultdict
from pathlib import Path
best = defaultdict(float)   # task -> 최고 reward
cnt = defaultdict(int)
for f in sorted(Path(sys.argv[1]).glob("*/result.json")):
    d = json.load(open(f))
    task = f.parent.name.rsplit("__", 1)[0]
    r = ((d.get("verifier_result") or {}).get("rewards") or {}).get("reward") or 0.0
    best[task] = max(best[task], r)
    cnt[task] += 1
passed = sum(1 for t in best if best[t] >= 1.0)
for t in sorted(best):
    print(f"[{'PASS' if best[t] >= 1.0 else 'FAIL'}] {t}  (best of {cnt[t]}: {best[t]})")
print("----------------------------------------")
print(f"pass@k: {passed}/{len(best)} tasks solved by at least one attempt")
EOF
echo "========================================"
