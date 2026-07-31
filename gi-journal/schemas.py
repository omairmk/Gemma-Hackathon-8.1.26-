"""The frozen v3.2.1 analysis schema used for live model responses."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

Quality = Literal["good", "limited", "unusable"]
QualityIssue = Literal[
    "blur", "low_light", "glare", "color_cast", "excessive_distance",
    "obstruction", "cropped_subject", "image_too_small", "no_relevant_subject",
    "multiple_subjects", "other",
]
BristolCertainty = Literal["low", "medium", "high", "not_applicable"]
Color = Literal[
    "brown", "light_brown", "dark_brown", "green", "yellow", "orange",
    "red_appearing", "black_appearing", "pale_or_clay_appearing", "mixed",
    "unable_to_assess",
]
FormDescriptor = Literal[
    "separate_hard_lumps", "lumpy_formed", "formed_with_surface_cracks",
    "smooth_formed", "soft_blobs", "mushy_or_ragged", "watery", "fragmented",
    "flattened", "mixed_form", "unable_to_assess",
]
MaterialObservation = Literal["not_observed", "possible", "apparent", "unable_to_assess"]
QUALITY_ISSUE_LABELS = {
    "blur": "blur",
    "low_light": "low light",
    "glare": "glare",
    "color_cast": "color cast",
    "excessive_distance": "excessive distance",
    "obstruction": "obstruction",
    "cropped_subject": "a cropped subject",
    "image_too_small": "an image that is too small",
    "no_relevant_subject": "no relevant subject",
    "multiple_subjects": "multiple subjects",
    "other": "an unspecified image limitation",
}


def unusable_description(issues: list[str]) -> str:
    """The only permitted description for an unusable image: cause, not inference."""
    labels = [QUALITY_ISSUE_LABELS[issue] for issue in issues]
    return "Assessment was not possible: " + ", ".join(labels) + "."


class ImageAssessment(BaseModel):
    model_config = ConfigDict(extra="forbid")
    contains_relevant_subject: bool
    quality: Quality
    quality_issues: list[QualityIssue]
    quality_explanation: str


class VisibleObservations(BaseModel):
    model_config = ConfigDict(extra="forbid")
    apparent_bristol_type: int | None = Field(ge=1, le=7)
    bristol_certainty: BristolCertainty
    primary_color: Color
    secondary_colors: list[Color]
    form_descriptors: list[FormDescriptor]
    red_appearing_material: MaterialObservation
    black_tarry_appearance: MaterialObservation
    mucus_appearing_material: MaterialObservation
    other_visible_features: list[str]


class AnalysisResponse(BaseModel):
    """Appendix A response contract; unknown keys are always rejected."""

    model_config = ConfigDict(extra="forbid")
    schema_version: Literal["1.0"]
    image_assessment: ImageAssessment
    visible_observations: VisibleObservations
    neutral_description: str
    uncertainties: list[str]
    retake_guidance: list[str]

    @field_validator("neutral_description")
    @classmethod
    def description_has_at_most_sixty_words(cls, value: str) -> str:
        if len(value.split()) > 60:
            raise ValueError("neutral_description must contain at most 60 words")
        return value

    @field_validator("retake_guidance")
    @classmethod
    def retake_suggestions_are_nonblank(cls, values: list[str]) -> list[str]:
        if any(not value.strip() for value in values):
            raise ValueError("retake_guidance cannot contain blank suggestions")
        return values

    @model_validator(mode="after")
    def enforce_cross_field_rules(self) -> "AnalysisResponse":
        assessment = self.image_assessment
        visible = self.visible_observations
        if not assessment.contains_relevant_subject and assessment.quality != "unusable":
            raise ValueError("contains_relevant_subject=false requires quality=unusable")
        if assessment.quality == "unusable":
            if not assessment.quality_issues:
                raise ValueError("unusable images require at least one quality issue")
            if visible.apparent_bristol_type is not None:
                raise ValueError("unusable images require apparent_bristol_type=null")
            if visible.bristol_certainty != "not_applicable":
                raise ValueError("unusable images require bristol_certainty=not_applicable")
            if visible.primary_color != "unable_to_assess":
                raise ValueError("unusable images require primary_color=unable_to_assess")
            if visible.secondary_colors:
                raise ValueError("unusable images require no secondary_colors")
            if visible.form_descriptors not in ([], ["unable_to_assess"]):
                raise ValueError("unusable images require unable_to_assess form descriptors")
            materials = (
                visible.red_appearing_material,
                visible.black_tarry_appearance,
                visible.mucus_appearing_material,
            )
            if any(item != "unable_to_assess" for item in materials):
                raise ValueError("unusable images require all material fields unable_to_assess")
            if not 1 <= len(self.retake_guidance) <= 2:
                raise ValueError("unusable images require one or two retake suggestions")
            expected = unusable_description(assessment.quality_issues)
            if self.neutral_description != expected:
                raise ValueError("unusable descriptions must be the constrained quality-issue explanation")
        return self
