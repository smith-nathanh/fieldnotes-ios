<p align="center">
  <img src="Fieldnotes/Fieldnotes/Assets.xcassets/AppIcon.appiconset/Fieldnotes-AppIcon-1024.png" width="104" alt="Fieldnotes app icon">
</p>

<h1 align="center">Fieldnotes</h1>

<p align="center">
  On-device audio and image classification for wildlife using BirdNET v2.4 and BioCAP embeddings.
</p>

Fieldnotes is a native iPhone app designed for on-device audio and image
classification of wildlife species. It listens for nearby calls, identifies
species from sounds and photos, saves representative detections, and lets you
browse a field log by species, outing, place, map, and statistics.

The app is offline-first: classification runs locally on the phone, and saved
clips/photos stay in app storage.

## Build From Xcode

Build and run the app from Xcode, not from `swift run`.

Open:

```sh
open Fieldnotes/Fieldnotes.xcworkspace
```

Use the workspace, not `Fieldnotes.xcodeproj`, because the iOS app uses
CocoaPods for `TensorFlowLiteSwift`.

Then in Xcode:

1. Select the `Fieldnotes` scheme.
2. Choose an iPhone simulator or a physical iPhone.
3. Build and run.

The Swift package in this repo contains shared core logic and tests, but the
full app target, resources, CocoaPods dependency, camera, microphone, maps, and
Core ML/TFLite integrations are built through the Xcode workspace.

## Main Features

- **Listen:** records microphone audio, runs live audio classification, and
  saves accepted detections with short audio clips.
- **Photo:** identifies wildlife from still images and can save photo-backed
  observations into the log.
- **Log:** browses species, outings, places, and mapped detections.
- **Species detail:** shows saved recordings/photos, detection history,
  shareable field cards, and where a species was heard.
- **Statistics:** summarizes detections, species, life-list progress, confidence,
  taxa, and places.
- **Offline storage:** keeps detection metadata in local SQLite and media files
  in app-local storage.

## Models

Audio classification uses BirdNET v2.4 through TensorFlow Lite:

- `BirdNET_GLOBAL_6K_V2.4_Model_FP16.tflite`
- `BirdNET_GLOBAL_6K_V2.4_MData_Model_V2_FP16.tflite`
- fallback metadata model: `BirdNET_GLOBAL_6K_V2.4_MData_Model_FP16.tflite`

The metadata model provides range/season gating from latitude, longitude, and
week when location is available.

Image classification uses BioCAP (`imageomics/biocap`) as an on-device
CLIP-style embedding pipeline:

- Core ML vision encoder: `BioCAPVisionEncoder.mlpackage`
- cached text embeddings: `BioCAPTextEmbeddings.f32`
- species metadata: `BioCAPSpecies.json`

The image path compares a photo embedding against the cached species text
embeddings and stores ranked photo detections using scientific names so they can
merge with BirdNET audio records.

See [Fieldnotes/Fieldnotes/Resources/BioCAP/README.md](Fieldnotes/Fieldnotes/Resources/BioCAP/README.md)
for the committed image-model asset layout and runtime flow.

## Tests

Core package tests:

```sh
swift test
```

Generic iOS build check:

```sh
xcodebuild -workspace Fieldnotes/Fieldnotes.xcworkspace \
  -scheme Fieldnotes \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Repo Layout

- `Fieldnotes/` - iOS app, Xcode workspace, resources, CocoaPods setup.
- `Sources/FieldnotesCore/` - reusable detection models, scoring, persistence
  helpers, audio windowing, and tests.
- `Tests/FieldnotesCoreTests/` - Swift package tests.
- `tools/biocap/` - workstation validation and export tooling for BioCAP.
