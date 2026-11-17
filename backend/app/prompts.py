import random


def pick_prompt(bank, used_ids, recent_types, rng=random):
    """Pick today's prompt for one island.

    bank: list of dicts like {"id": 1, "type": "photo"}
    used_ids: set of prompt ids this island already got (never repeat)
    recent_types: answer types of the last days, oldest first
    Rule: the same type never comes up more than 2 days in a row.
    """
    blocked_type = None
    if len(recent_types) >= 2 and recent_types[-1] == recent_types[-2]:
        blocked_type = recent_types[-1]

    choices = [
        p for p in bank
        if p["id"] not in used_ids and p["type"] != blocked_type
    ]
    if not choices:
        return None
    return rng.choice(choices)
