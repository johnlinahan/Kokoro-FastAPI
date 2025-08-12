#!/bin/bash

# Get project root directory
# PROJECT_ROOT=$(pwd)

# Set environment variables
export USE_GPU=true
export USE_ONNX=false
# export PYTHONPATH=$PROJECT_ROOT:$PROJECT_ROOT/api
STATE_DIR="${STATE_DIRECTORY:-$HOME/.kokoro-fastapi}"
export MODEL_DIR="$STATE_DIR/models"
export VOICES_DIR=$APP_ROOT/api/src/voices/v1_0
export MIOPEN_FIND_MODE=FAST

esjdklfjasd;k


# Run FastAPI with GPU extras using uv run
# Note: espeak may still require manual installation,
# uv pip install -e ".[gpu]"
# python $APP_ROOT/docker/scripts/download_model.py --output $APP_ROOT/api/src/models/v1_0
python $APP_ROOT/docker/scripts/download_model.py --output $MODEL_DIR/v1_0
uvicorn --app-dir $APP_ROOT api.src.main:app --host 0.0.0.0 --port 8881 # TODO: override port via nix
