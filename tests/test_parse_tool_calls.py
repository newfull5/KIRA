import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import logging

from terminus_kira.terminus_kira import TerminusKira


def _parse(args, name="execute_commands"):
    agent = TerminusKira.__new__(TerminusKira)
    agent.logger = logging.getLogger("test")
    return agent._parse_tool_calls(
        [{"function": {"name": name, "arguments": args}}]
    )


def test_misnamed_keystrokes_warns_instead_of_silent_noop():
    # The model wrote the key as '"keystrokes"' (quotes included in the name).
    commands, _, feedback, _, _, _ = _parse(
        '{"analysis": "a", "plan": "p", "commands": [{"\\"keystrokes\\"": "ls\\n"}]}'
    )
    assert commands == []
    assert "keystrokes" in feedback and feedback.startswith("WARNINGS:")


def test_valid_call_still_parses():
    commands, _, feedback, analysis, _, _ = _parse(
        '{"analysis": "a", "plan": "p", "commands": [{"keystrokes": "ls\\n", "duration": 2}]}'
    )
    assert feedback == ""
    assert analysis == "a"
    assert [(c.keystrokes, c.duration_sec) for c in commands] == [("ls\n", 2)]


if __name__ == "__main__":
    test_misnamed_keystrokes_warns_instead_of_silent_noop()
    test_valid_call_still_parses()
    print("ok")
