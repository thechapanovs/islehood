from app.prompts import pick_prompt

BANK = [
    {"id": 1, "type": "tap"},
    {"id": 2, "type": "tap"},
    {"id": 3, "type": "photo"},
    {"id": 4, "type": "one_line"},
    ]


def test_never_repeats_a_used_prompt():
    for _ in range(100):
        picked = pick_prompt(BANK, used_ids={1, 2, 3}, recent_types=[])
        assert picked["id"] == 4


def test_blocks_a_third_day_of_the_same_type():
    for _ in range(100):
        picked = pick_prompt(BANK, used_ids=set(), recent_types=["tap", "tap"])
        assert picked["type"] != "tap"


def test_allows_same_type_after_only_one_day():
    picked = pick_prompt(BANK, used_ids={3, 4}, recent_types=["photo", "tap"])
    assert picked["type"] == "tap"


def test_returns_none_when_bank_is_used_up():
    assert pick_prompt(BANK, used_ids={1, 2, 3, 4}, recent_types=[]) is None