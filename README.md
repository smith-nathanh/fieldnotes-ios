<p align="center">
  <img src="Fieldnotes/Fieldnotes/Assets.xcassets/AppIcon.appiconset/Fieldnotes-AppIcon-1024.png" width="104" alt="Fieldnotes app icon">
</p>

<h1 align="center">Fieldnotes</h1>

<p align="center">
  Record the call. Remember the name.
</p>

Birdsong on a morning walk. An unfamiliar moth at the porch light. Fieldnotes
helps you identify the wildlife you encounter and keep a lasting record of
what you find.

Listen for nearby birds, insects, frogs, and mammals, or identify an animal from
a photo. Fieldnotes saves useful recordings and images, then organizes your
observations into species, outings, trips, places, maps, and statistics—building
a personal field record that grows every time you head outside.

Classification happens entirely on your iPhone using BirdNET and BioCAP. No
network connection is required in the field, and your recordings, photos,
locations, and observations remain in app-local storage.

## Build From Xcode

Build and run the app from Xcode, not from `swift run`. A fresh checkout needs
Xcode, CocoaPods, Python 3, the CocoaPods dependencies, and the versioned BioCAP
asset bundle:

```sh
cd Fieldnotes
pod install
cd ..
python3 tools/biocap/install_ios_assets.py
```

The BioCAP installer downloads the pinned production bundle from the project's
GitHub release, verifies the archive and every contained file with SHA-256, and
installs it under `Fieldnotes/Fieldnotes/Resources/BioCAP/`.

Open:

```sh
open Fieldnotes/Fieldnotes.xcworkspace
```

Use the workspace, not `Fieldnotes.xcodeproj`, because the iOS app uses
CocoaPods for `TensorFlowLiteSwift`.

Then in Xcode:

1. Select the `Fieldnotes` scheme.
2. Choose an iPhone simulator or a physical iPhone.
3. For a physical phone, open the Fieldnotes target's **Signing & Capabilities**,
   choose your Apple development team, and use a unique bundle identifier if
   Xcode says the existing one is unavailable.
4. Build and run. A physical phone is recommended for camera, microphone, and
   real-time performance testing.

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

BirdNET's model weights are provided under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) for
noncommercial use. BioCAP is MIT-licensed. See the
[BirdNET model notice](Fieldnotes/Fieldnotes/Resources/Models/BirdNET_NOTICE.md)
and [BioCAP notice](Fieldnotes/Fieldnotes/Resources/BioCAP/THIRD_PARTY_NOTICES.md)
for attribution and full terms.

Image classification uses BioCAP (`imageomics/biocap`) as an on-device
CLIP-style retrieval pipeline. Fieldnotes exports the BioCAP vision encoder to
Core ML and precomputes the text side of the model for a deduplicated catalog of
52,762 animal species observed across the United States:

- Core ML vision encoder: `BioCAPVisionEncoder.mlpackage`
- cached text embeddings: `BioCAPTextEmbeddings.f32`
- species metadata: `BioCAPSpecies.json`

Each species is embedded once using BioCAP's 81-prompt zero-shot ensemble. The
catalog also stores compact state and region membership derived from iNaturalist.
By default, the app searches species recorded in the detected or selected state;
the user can broaden that search to one of nine U.S. regions or all of the United
States. This reduces implausible matches without pretending that wildlife ranges
stop at state lines.

At runtime, the app crops and embeds the photo, filters eligible catalog rows,
and computes cosine similarity against the cached normalized text embeddings.
Scientific names are the shared key, so saved photo observations merge with
BirdNET audio records for the same species. Similarity scores rank candidates;
they are not calibrated probabilities.

See [Fieldnotes/Fieldnotes/Resources/BioCAP/README.md](Fieldnotes/Fieldnotes/Resources/BioCAP/README.md)
for the asset-build history, validation gates, packaging format, distribution,
and runtime flow.

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

## License

The original Fieldnotes source code is available under the [MIT License](LICENSE).
Third-party models, fonts, and other bundled assets are not covered by that
license and remain under their accompanying terms and notices.

## Repo Layout

- `Fieldnotes/` - iOS app, Xcode workspace, resources, CocoaPods setup.
- `Sources/FieldnotesCore/` - reusable detection models, scoring, persistence
  helpers, audio windowing, and tests.
- `Tests/FieldnotesCoreTests/` - Swift package tests.
- `tools/biocap/` - workstation validation and export tooling for BioCAP.
