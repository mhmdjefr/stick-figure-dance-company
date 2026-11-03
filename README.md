# Stick Figure Dance Company (Webcam + MediaPipe)

Webcam-based adaptation of Project 2 from *Processing 2: Creative Coding Hotshot*,
using MediaPipe Pose instead of Kinect.

## Architecture
See [docs/architecture.md](docs/architecture.md).

## Requirements
- Python 3.9+ (see `vision/requirements.txt`)
- Processing with the `oscP5` library

## Run
1. `cd vision && python3 main.py`
2. Open `processing/StickFigureDance` in Processing and run it.

## Team
TBD

## Credits
- Book: *Processing 2: Creative Coding Hotshot* (Nikolaus Gradwohl)

## Model setup
The pose model is not stored in the repo. Download it once:

    mkdir -p vision/models
    curl -fL -o vision/models/pose_landmarker_lite.task \
      https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
