# Attribution and synthetic-data notes

## Synthetic fixtures

Use only intentionally created, non-personal demonstration images. Watermark each image visibly with `SYNTHETIC`. Keep fixture provenance beside the asset:

| Asset | Source/creator | License/permission | Date created/acquired | Intended use | Contains real patient data? |
|---|---|---|---|---|---|
| brown prop | [fill] | [fill] | [fill] | smoke/demo | No (verify) |
| green prop | [fill] | [fill] | [fill] | smoke/demo | No (verify) |

Do not label an image synthetic solely because it was edited, de-identified, or supplied without provenance. Do not commit real health images, EXIF/location-bearing photos, or user-entered journal data.

## Attribution ledger

| Component | Exact name/version | Source URL | License/required notice | Where credited |
|---|---|---|---|---|
| Gemma model | [fill] | [fill] | [fill] | [README/Kaggle] |
| Runtime | [fill] | [fill] | [fill] | [README] |
| Libraries | [fill] | [fill] | [fill] | [NOTICE/README] |
| Icons/fonts/media | [fill] | [fill] | [fill] | [README/demo] |

Before publication, verify the event’s current attribution language and model/runtime license. Never assume model weights may be redistributed: link to official acquisition instructions unless permission is explicit.

## Claim-control notes

Describe only what the completed build and saved evidence show. “Local,” “offline,” and “on-device” are separate claims; each needs its own verification. Privacy language must state actual design limits, including platform backup behavior where applicable. Keep medical framing documentation-only: no diagnosis, cause, treatment, prognosis, risk scoring, or reassurance.
