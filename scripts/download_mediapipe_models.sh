#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT/assets/mediapipe"

mkdir -p "$DEST_DIR"

download() {
  local name="$1"
  local url="$2"
  echo "Downloading ${name}..."
  curl -L "$url" -o "${DEST_DIR}/${name}"
  echo "Saved to ${DEST_DIR}/${name}"
}

download "face_landmarker.task" \
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"

download "pose_landmarker_lite.task" \
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"

download "selfie_segmenter.tflite" \
  "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite"
