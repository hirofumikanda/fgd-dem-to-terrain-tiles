#!/bin/bash

# Docker環境でPythonスクリプトを実行
# Usage: ./generate_text_tiles_docker.sh <input_file> <output_dir> <min_zoom> <max_zoom> <tile_size>

if [ $# -ne 5 ]; then
    echo "Usage: $0 <input_file> <output_dir> <min_zoom> <max_zoom> <tile_size>"
    echo "Example: $0 dem_3857_cleaned.tif ./tiles_dem_text_pyramid 10 14 256"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_DIR="$2"
MIN_ZOOM="$3"
MAX_ZOOM="$4"
TILE_SIZE="$5"

LOG_FILE="./logs/generate_text_tiles_docker_$(date +%Y%m%d_%H%M%S).log"
mkdir -p logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Starting Docker-based text tile generation"
log "Input file: $INPUT_FILE"
log "Output directory: $OUTPUT_DIR"
log "Zoom range: $MIN_ZOOM to $MAX_ZOOM"
log "Tile size: $TILE_SIZE"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run in Docker with GDAL and Python scientific stack
docker run --rm \
    -v "$PWD":/work \
    -w /work \
    ghcr.io/osgeo/gdal:alpine-normal-latest \
    sh -c "
    apk add --no-cache python3 py3-pip py3-numpy py3-scipy && \
    python3 generate_text_tiles.py '$INPUT_FILE' '$OUTPUT_DIR' $MIN_ZOOM $MAX_ZOOM $TILE_SIZE
    " 2>&1 | tee -a "$LOG_FILE"

if [ $? -eq 0 ]; then
    log "✅ Text tile generation completed successfully"
else
    log "❌ Text tile generation failed"
    exit 1
fi