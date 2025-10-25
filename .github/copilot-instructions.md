# DEM to Terrain Tiles Pipeline - AI Coding Agent Guide

## Architecture Overview

This is a geospatial data processing pipeline that transforms Japanese DEM10B elevation data into web-ready terrain tiles. The project follows a **6-stage sequential pipeline architecture** with three specialized variants:

- **Terrain RGB Pipeline** (`run_pipeline_terrain_rgb.sh`): ZIP → XML → GeoTIFF → Web Mercator → Terrain RGB → Raster Tiles + MBTiles + PMTiles
- **Hillshade Pipeline** (`run_pipeline_hillshade.sh`): Same 1-4, then → Hillshade → Raster Tiles + MBTiles + PMTiles
- **Contour Pipeline** (`run_pipeline_contour.sh`): Same 1-4, then → Contour Lines → MVT/PMTiles

Each pipeline can be **resumed from any step** using `./run_pipeline_*.sh -s N` (where N=1-6).

## Critical Workflow Patterns

### 1. Logging Convention
Every script follows this **mandatory pattern**:
```bash
LOG_FILE="./logs/script_name_$(date +%Y%m%d_%H%M%S).log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
```
- Individual scripts generate timestamped logs in `./logs/`
- Master pipelines create `./logs/master_*.log` with execution summaries
- Always use emoji prefixes: 🚀 (start), ✅ (success), ❌ (error), 📊 (stats)

### 2. Docker Containerization Pattern
All GDAL operations use containerized commands:
```bash
# Standard pattern for GDAL tools
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdaldem hillshade ...

# Python operations also containerized
docker run --rm -v "$PWD":/work -w /work python:3.9-slim python3 calculate_edge_tiles.py ...
```

### 3. Multi-Format Output Strategy
Recent architectural change: Each variant now generates **multiple distribution formats**:
- **Raster tiles**: Directory structure (`/tiles_*/*.png`)
- **MBTiles**: SQLite format for traditional tile servers (`*.mbtiles`)
- **PMTiles**: Modern cloud-native format (`*.pmtiles`)

## Development Commands

### Essential Commands
```bash
# Run specific pipeline variants
./run_pipeline_terrain_rgb.sh    # Terrain RGB encoding for elevation
./run_pipeline_hillshade.sh      # Hillshade visualization 
./run_pipeline_contour.sh        # Contour line vectors

# Resume from specific step (common during development)
./run_pipeline_*.sh -s 4         # Skip ZIP/XML processing, start from merge
./run_pipeline_*.sh --check      # Pre-flight dependency validation
```

### Pipeline-Specific Debugging
1. Check master log: `./logs/master_*_YYYYMMDD_HHMMSS.log`
2. Individual step logs: `./logs/script_name_YYYYMMDD_HHMMSS.log`
3. Resume with: `./run_pipeline_*.sh -s <failed_step_number>`

## File Naming Conventions (CRITICAL)

### Intermediate Files (Exact Pattern Required)
- `dem_3857.tif` - Reprojected DEM (output of step 4)
- `dem_3857_terrainrgb.tif` - Terrain RGB encoded
- `dem_3857_hillshade.tif` - Hillshade visualization (no quantization)
- `dem_3857_contour.geojson` - Contour lines (GeoJSONSeq format)

### Output Distribution Files
- `tiles_terrainrgb/` - Terrain RGB raster tiles
- `tiles_hillshade/` - Hillshade raster tiles  
- `*.mbtiles` - MBTiles format for each variant
- `*.pmtiles` - PMTiles format for each variant

## External Dependencies (Must Install)

### Python Dependencies
```bash
pip install fgddem-py      # Japanese FGD XML to GeoTIFF conversion
pip install rio-rgbify     # Terrain RGB encoding
pip install mbutil         # MBTiles manipulation
```

### Standalone Tools
- **tippecanoe**: Vector tile generation (install separately)
- **pmtiles**: Modern tile format converter (install separately)
- **Docker**: All GDAL operations containerized

## Project-Specific Patterns

### Variable Configuration Pattern
Scripts use configurable variables at the top:
```bash
# Example from 06_create_tiles_hillshade.sh
MAX_ZOOM=14
MIN_ZOOM=0  
PROCESSES=4  # Configurable parallel processing
TILE_FORMAT="png"
```

### GeoJSONSeq Usage (Not Standard GeoJSON)
The project uses **GeoJSONSeq (NDJSON)** format exclusively:
```bash
# Generate GeoJSONSeq (one feature per line)
gdal_contour -f "GeoJSONSeq" input.tif output.geojson
gdal_polygonize.py -f "GeoJSONSeq" input.tif output.geojson layer_name attribute
```

### Terrain RGB Edge Processing
Unique to this project: automatic edge tile transparency filling:
```bash
# Uses calculate_edge_tiles.py + ImageMagick Docker
# Fills transparent areas with RGB(1,134,160) for ocean color
```

### Performance Optimization Strategies
- **Resumable pipelines**: Can restart from any step
- **Parallel processing**: Configurable `PROCESSES` variable
- **Docker isolation**: Prevents environment conflicts
- **Memory streaming**: Large datasets processed efficiently
- **Compression optimization**: Different strategies per data type

## Data Flow Dependencies

### Step 1-2: Data Preparation
- Requires `./fgd/` with DEM10B ZIP files
- `fill_dem_tuples.py` handles incomplete XML data (fills missing elevations)

### Step 3-4: Conversion & Projection  
- Step 3: Requires processed XMLs in `./xml/`
- Step 4: Requires GeoTIFFs in `./tiff/`, outputs `dem_3857.tif`

### Step 5-6: Format-Specific Processing
- **Terrain RGB**: `dem_3857.tif` → RGB encoding → raster tiles + MBTiles + PMTiles
- **Hillshade**: `dem_3857.tif` → hillshade → raster tiles + MBTiles + PMTiles  
- **Contour**: `dem_3857.tif` → contour lines → MVT tiles + PMTiles

## Recent Architectural Changes

1. **Removed quantization**: Hillshade no longer uses 16-level quantization
2. **Added multi-format output**: All variants now generate raster + MBTiles + PMTiles
3. **Unified raster approach**: Both terrain RGB and hillshade use `gdal2tiles` → `mb-util` → `pmtiles`
4. **Configurable processing**: PROCESSES variable for performance tuning

When modifying scripts, preserve the resumable pipeline pattern, comprehensive logging, and multi-format output strategy - these are critical for production workflows with large datasets.