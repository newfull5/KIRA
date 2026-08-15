#!/usr/bin/env python3
"""Dump reward<1 trajectories of a harbor job into per-task markdown.

Usage:
    python run-scripts/dump_failed_trajectories.py <job_dir> <out_dir>

Reads each trial's agent/trajectory.json, and for every trial whose reward is
below 1.0 writes <out_dir>/<task-name>.md in the same format used by the
existing data/failed_trajectories files: one "## Step N" block per agent turn
with its Analysis/Plan text, the tool call, and the terminal observation.
"""
import json
import sys
from pathlib import Path


def render_step(step):
    """Render one agent step to markdown, or None for non-agent steps."""
    if step.get("source") != "agent":
        return None
    out = [f"## Step {step['step_id']}"]
    msg = (step.get("message") or "").strip()
    if msg:
        out.append(msg)

    # An empty response (content_filter block) has no message and no calls; it
    # still renders as a bare step with just the observation, matching the
    # existing failed_trajectories format.
    for c in step.get("tool_calls") or []:
        args = c.get("arguments") or {}
        out.append(f"\n**호출: `{c.get('function_name','')}`**")
        out.append("```")
        if "keystrokes" in args:
            ks = (args.get("keystrokes") or "").rstrip("\n")
            out.append(f"$ {ks}   (wait {args.get('duration', 0)}s)")
        else:
            # Malformed/empty function call — render the raw arguments.
            out.append(str(args))
        out.append("```")

    obs = step.get("observation") or {}
    results = obs.get("results") or []
    content = "\n".join((r.get("content") or "") for r in results).strip()
    if content:
        out.append("**결과:**")
        out.append("```")
        out.append(content)
        out.append("```")
    return "\n".join(out)


def render_trial(trial_dir, task_name, reward, job_name):
    traj = trial_dir / "agent" / "trajectory.json"
    if not traj.exists():
        return None
    steps = json.load(open(traj)).get("steps", [])
    blocks = [f"# {task_name}  (reward={reward}, job={job_name})"]
    for s in steps:
        r = render_step(s)
        if r:
            blocks.append(r)
    return "\n\n".join(blocks) + "\n"


def main():
    job_dir = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    job_name = job_dir.name
    written = []
    for result in sorted(job_dir.glob("*/result.json")):
        trial_dir = result.parent
        task_name = trial_dir.name.split("__")[0]
        d = json.load(open(result))
        reward = ((d.get("verifier_result") or {}).get("rewards") or {}).get("reward") or 0.0
        if reward >= 1.0:
            continue
        md = render_trial(trial_dir, task_name, reward, job_name)
        if md is None:
            print(f"  skip {task_name}: no trajectory.json")
            continue
        (out_dir / f"{task_name}.md").write_text(md)
        written.append(task_name)
    print(f"wrote {len(written)} md to {out_dir}: {', '.join(written)}")


if __name__ == "__main__":
    main()
