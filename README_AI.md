# AI-Based Contextual Threat & Risk Detection

Shrimati Setu now includes an AI-based contextual threat and risk detection layer for ambiguous automatic triggers, especially shake detection. The goal is to reduce false SOS events caused by normal movement such as walking, running, dancing, vehicle travel, or accidental phone movement.

This layer never blocks explicit SOS actions. Manual SOS, volume-button SOS, voice distress SOS, timer SOS, and geofence-triggered SOS continue to use the existing emergency workflow.

## Architecture

The mobile app collects a short context window when shake detection reaches the existing threshold. It builds a structured feature vector and sends it to `AIRiskService`.

Risk levels:

- `LOW_RISK`: continue monitoring and do not escalate the ambiguous shake.
- `SUSPICIOUS`: ask the user to confirm safety; no response or emergency response triggers the existing SOS flow.
- `HIGH_RISK`: immediately invoke the existing SOS workflow.

If remote inference is unavailable, times out, returns malformed data, or the device has missing sensor/location data, the app falls back safely. Explicit SOS always remains immediate.

## Flutter Integration

Main files:

- `lib/services/ai_risk_service.dart`: risk context, feature schema, remote inference client, local fallback classifier.
- `lib/screens/home_screen.dart`: inserts AI analysis between shake detection and `_autoSOS()`.
- `lib/services/sos_service.dart`: accepts optional event metadata so AI analysis can be stored with an SOS event.

The AI insertion point is:

```text
Shake detected 3 times
Collect movement/location/context
Analyze risk
LOW_RISK -> continue monitoring
SUSPICIOUS -> ask user to confirm safety
HIGH_RISK -> existing SOS workflow
```

## Input Features

The prototype uses only data already available or realistically available in the current mobile app:

- Trigger type
- Shake count
- Shake intensity
- Shake duration
- Movement variance
- Movement frequency
- Current speed
- Location accuracy
- Location availability
- Geofence violation flag
- Distress voice indicator flag
- Recent automatic trigger count
- Recent SOS count
- Seconds since previous automatic trigger
- Hour of day

The current app does not yet provide a validated known-location classifier, route-change detector, raw distress audio score, or persisted long-term behavioral baseline. Those should be added only after privacy review and real-world validation.

## Dataset

Prototype dataset:

- `dataset/shrimati_safety_dataset.csv`

The dataset includes examples for normal movement, suspicious movement, and high-risk multi-indicator scenarios.

Important: this dataset is a prototype structure, not proof of real-world human behavior. Production use requires properly labelled real-world safety-event data, representative validation, bias review, and field testing.

## Model

The initial supervised machine-learning model is a Random Forest classifier for structured sensor/context features.

ML files:

- `ml/preprocess.py`
- `ml/train_model.py`
- `ml/evaluate_model.py`
- `ml/inference_api.py`
- `ml/requirements.txt`

Preprocessing is stored inside the scikit-learn pipeline, which prevents mismatches between training and inference.

## Train The Model

From the repository root:

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r ml/requirements.txt
python ml/train_model.py
```

Outputs:

- `ml/model/shrimati_risk_model.pkl`
- `ml/model/feature_schema.json`

## Evaluate The Model

```bash
python ml/evaluate_model.py
```

The evaluation prints accuracy, precision, recall, F1 score, and a confusion matrix.

## Run The AI Service

After training:

```bash
python ml/inference_api.py --host 127.0.0.1 --port 8080
```

Test the API:

```bash
curl -X POST http://127.0.0.1:8080/predict ^
  -H "Content-Type: application/json" ^
  -d "{\"features\":{\"trigger_type\":\"shake\",\"shake_count\":3,\"shake_intensity\":15,\"shake_duration_ms\":1800,\"movement_variance\":18,\"movement_frequency\":24,\"speed\":1,\"accuracy\":10,\"location_available\":1,\"geofence_violation\":0,\"distress_voice_detected\":0,\"recent_automatic_trigger_count\":1,\"recent_sos_count\":0,\"seconds_since_previous_trigger\":9999,\"hour_of_day\":21}}"
```

## Connect Flutter To The API

Build or run Flutter with the inference URL:

```bash
flutter run --dart-define=AI_RISK_API_URL=http://YOUR_SERVER:8080/predict
```

If no URL is provided, the app uses the local fallback classifier in `AIRiskService`.

## Firebase Storage

AI metadata is stored only when an analyzed automatic shake escalates to SOS. The metadata is added to the existing `users/{uid}/sos_events` document:

- `ai_risk_level`
- `ai_risk_score`
- `ai_model_version`
- `ai_analysis_timestamp`
- `ai_trigger_type`
- `ai_analysis_source`
- `ai_reason`

Low-risk shake events are not stored by default to minimize unnecessary sensitive data.

## Privacy And Security

The AI layer uses structured movement/location context and does not send raw audio or raw video for risk analysis.

Do not log or hardcode:

- Firebase credentials
- Authentication tokens
- API keys
- Raw audio
- Raw video
- Sensitive personal data

The app currently contains a Google Maps API key in `android/app/src/main/AndroidManifest.xml`. For production, restrict that key in Google Cloud and move sensitive configuration into environment-specific build configuration.

## Failure Handling

Explicit SOS:

- Always immediate.
- AI cannot cancel or delay it.

Automatic shake:

- `LOW_RISK`: suppresses unnecessary escalation.
- `SUSPICIOUS`: asks for confirmation and escalates if the user requests SOS or does not respond.
- `HIGH_RISK`: calls the existing SOS workflow.
- AI timeout, unavailable API, invalid response, missing GPS, or malformed data: falls back to existing safety behavior or local fallback.

## Tests

Run:

```bash
flutter test
```

Covered scenarios include walking, running, dancing, vehicle movement, accidental shake, repeated shaking, unusual movement, geofence risk, multiple emergency indicators, high-risk classification, missing sensor data, missing GPS data, invalid AI response, unavailable AI service, and timeout fallback.

Explicit physical SOS remains covered by architecture: `PowerButtonService` still calls `SOSService.triggerSOS()` directly and does not call the AI gate.

## Future Improvements

- Train with labelled real-world data after consent and privacy review.
- Add calibrated probability thresholds.
- Persist privacy-safe recent trigger counts across app restarts.
- Add safe-zone status from `GeoFenceService` into the feature vector.
- Add on-device model packaging after model size and runtime testing.
- Add backend authentication and rate limiting for the inference API.
- Add model monitoring for false positives and false negatives.
