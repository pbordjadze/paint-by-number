"""The play piece supplies a brief and a single guardian's next-move prompt."""
import json


def prompt(brief, guardian, screenshot, state, history):
    return (f"{brief}\n\nYour charter ({guardian['name']}):\n{guardian['charter_text']}\n\n"
            f"Latest screenshot: {screenshot}\nState:\n{json.dumps(state, ensure_ascii=False)}\n"
            f"Recent turns:\n{json.dumps(history, ensure_ascii=False)}\n\n"
            'Return exactly one move and a one-line reason as JSON matching reply_schema. '
            'Moves use do: fill with a positive area number; tap with an accessibility label; '
            'drag with from/to {x,y} in screenshot pixels and positive steps; wait with '
            'nonnegative seconds; or screenshot with no other fields. Area numbers start at 1.')
