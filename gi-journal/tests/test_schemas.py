import pytest
from pydantic import ValidationError

from schemas import AnalysisResponse, unusable_description


def valid_example() -> dict:
    return {
        "schema_version": "1.0",
        "image_assessment": {
            "contains_relevant_subject": True,
            "quality": "good",
            "quality_issues": [],
            "quality_explanation": "",
        },
        "visible_observations": {
            "apparent_bristol_type": 4,
            "bristol_certainty": "medium",
            "primary_color": "brown",
            "secondary_colors": [],
            "form_descriptors": ["smooth_formed"],
            "red_appearing_material": "not_observed",
            "black_tarry_appearance": "not_observed",
            "mucus_appearing_material": "not_observed",
            "other_visible_features": [],
        },
        "neutral_description": "A smooth, formed, brown stool is visible.",
        "uncertainties": ["Lighting may affect apparent color."],
        "retake_guidance": [],
    }


def unusable_example() -> dict:
    value = valid_example()
    value["image_assessment"] = {
        "contains_relevant_subject": False,
        "quality": "unusable",
        "quality_issues": ["no_relevant_subject"],
        "quality_explanation": "Assessment was not possible because no relevant subject was visible.",
    }
    value["visible_observations"] = {
        "apparent_bristol_type": None,
        "bristol_certainty": "not_applicable",
        "primary_color": "unable_to_assess",
        "secondary_colors": [],
        "form_descriptors": ["unable_to_assess"],
        "red_appearing_material": "unable_to_assess",
        "black_tarry_appearance": "unable_to_assess",
        "mucus_appearing_material": "unable_to_assess",
        "other_visible_features": [],
    }
    value["neutral_description"] = unusable_description(["no_relevant_subject"])
    value["retake_guidance"] = ["Use a well-lit image with the subject in frame."]
    return value


def test_literal_prompt_example_validates():
    assert AnalysisResponse.model_validate(valid_example()).schema_version == "1.0"


def test_unusable_cross_field_rules_enforce():
    assert AnalysisResponse.model_validate(unusable_example()).image_assessment.quality == "unusable"
    bad = unusable_example()
    bad["visible_observations"]["apparent_bristol_type"] = 4
    with pytest.raises(ValidationError):
        AnalysisResponse.model_validate(bad)


def test_invalid_enum_and_extra_field_rejected():
    bad = valid_example()
    bad["visible_observations"]["primary_color"] = "purple"
    with pytest.raises(ValidationError):
        AnalysisResponse.model_validate(bad)
    extra = valid_example()
    extra["unexpected"] = True
    with pytest.raises(ValidationError):
        AnalysisResponse.model_validate(extra)


def test_description_enforces_true_sixty_word_limit():
    valid = valid_example()
    valid["neutral_description"] = "word " * 60
    AnalysisResponse.model_validate(valid)
    invalid = valid_example()
    invalid["neutral_description"] = "word " * 61
    with pytest.raises(ValidationError, match="at most 60 words"):
        AnalysisResponse.model_validate(invalid)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("neutral_description", "Assessment was not possible because no relevant subject was visible."),
        ("retake_guidance", []),
        ("retake_guidance", ["   "]),
        ("retake_guidance", ["Use light.", "Frame subject.", "Remove glare."]),
    ],
)
def test_unusable_description_and_retake_guidance_are_tightly_constrained(field, value):
    invalid = unusable_example()
    invalid[field] = value
    with pytest.raises(ValidationError):
        AnalysisResponse.model_validate(invalid)


def test_unusable_requires_a_quality_issue_and_exact_reason():
    invalid = unusable_example()
    invalid["image_assessment"]["quality_issues"] = []
    invalid["neutral_description"] = "Assessment was not possible:."
    with pytest.raises(ValidationError, match="quality issue"):
        AnalysisResponse.model_validate(invalid)
