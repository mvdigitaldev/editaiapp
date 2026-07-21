# Baixa modelos MediaPipe para assets/mediapipe/
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$destDir = Join-Path $root "assets\mediapipe"

$models = @(
    @{
        Name = "face_landmarker.task"
        Url  = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"
    },
    @{
        Name = "pose_landmarker_lite.task"
        Url  = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
    }
)

if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

foreach ($model in $models) {
    $destFile = Join-Path $destDir $model.Name
    Write-Host "Downloading $($model.Name)..."
    Invoke-WebRequest -Uri $model.Url -OutFile $destFile -UseBasicParsing
    Write-Host "Saved to $destFile"
}
