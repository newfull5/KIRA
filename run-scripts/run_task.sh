#!/usr/bin/env bash
set -euo pipefail

# ./run_task.sh <task-name>
# DISABLE_KIRA=true ./run_task.sh <task-name>   # KIRA 하네스 끄고 순정 Terminus2로 실행
#
# --agent-import-path  사용할 에이전트 클래스 (module:Class)
# -d                   데이터셋 name@version. 샘플만: terminal-bench-sample@2.0
# -t                   실행할 태스크명 (glob 지원, 예: "build-*")
# -m                   모델 (litellm 형식 provider/model)
# -e                   실행 환경: docker(로컬) | daytona | runloop(클라우드)
# -n                   동시 실행 태스크 수 (--n-concurrent)
# --ak                 에이전트 kwarg. disable_kira=true면 KIRA 오버라이드 전체 우회

cd "$(dirname "$0")/.."  # uv run은 프로젝트 루트에서 실행되어야 함

DISABLE_KIRA="${DISABLE_KIRA:-false}"

echo "========================================"
echo "Task: $1 - Starting at $(date)"
echo "KIRA harness: $([ "$DISABLE_KIRA" = "true" ] && echo OFF || echo ON)"
echo "========================================"

uv run harbor run \
    --agent-import-path "terminus_kira.terminus_kira:TerminusKira" \
    -d "terminal-bench@2.0" \
    -t "$1" \
    -m "anthropic/claude-sonnet-5" \
    -e docker \
    -n 1 \
    --ak disable_kira="$DISABLE_KIRA" \
    --ak temperature=1  # claude-5 계열은 비기본 temperature(0.7)를 400으로 거부

echo "========================================"
echo "Task: $1 - Finished at $(date)"
echo "----------------------------------------"
LATEST_JOB=$(ls -td jobs/*/ | head -1)
python3 - "$LATEST_JOB" <<'EOF'
import json, sys
from pathlib import Path
for f in sorted(Path(sys.argv[1]).glob("*/result.json")):
    r = json.load(open(f)).get("agent_result") or {}
    print(f"{f.parent.name}")
    print(f"  input:  {r.get('n_input_tokens', 0):,}")
    print(f"  output: {r.get('n_output_tokens', 0):,}")
    print(f"  cache:  {r.get('n_cache_tokens', 0):,}")
    cost = r.get("cost_usd")
    print(f"  cost:   ${cost:.4f}" if cost else "  cost:   n/a")
EOF
echo "========================================"
