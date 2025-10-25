#!/bin/bash

# 変数設定
TIFF_DIR="./tiff"
VRT_FILE="./merged_dem.vrt"
OUTPUT_FILE="./dem_3857.tif"

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/merge_reproject_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 VRT統合・投影変換処理を開始します"
log "入力ディレクトリ: $TIFF_DIR"
log "VRTファイル: $VRT_FILE"
log "出力ファイル: $OUTPUT_FILE"

# Dockerの存在確認
if ! command -v docker &> /dev/null; then
    log "❌ エラー: dockerが見つかりません"
    exit 1
fi

# tiffディレクトリの存在確認
if [ ! -d "$TIFF_DIR" ]; then
    log "❌ エラー: $TIFF_DIR ディレクトリが存在しません"
    exit 1
fi

# tiffファイルの存在確認
tiff_count=$(find "$TIFF_DIR" -type f -name "*.tif" -o -name "*.tiff" | wc -l)
if [ "$tiff_count" -eq 0 ]; then
    log "❌ エラー: $TIFF_DIR に TIFFファイルが見つかりません"
    exit 1
fi

log "🔍 $tiff_count 個のTIFFファイルが見つかりました"

# TIFFディレクトリサイズを表示
tiff_dir_size=$(du -sh "$TIFF_DIR" | cut -f1)
log "📊 入力ディレクトリサイズ: $tiff_dir_size"

# 既存のVRTファイルを削除（存在する場合）
if [ -f "$VRT_FILE" ]; then
    log "🗑️  既存のVRTファイルを削除: $VRT_FILE"
    rm -f "$VRT_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存VRTファイルの削除に失敗しました"
        exit 1
    fi
fi

# 既存の出力ファイルを削除（存在する場合）
if [ -f "$OUTPUT_FILE" ]; then
    log "🗑️  既存の出力ファイルを削除: $OUTPUT_FILE"
    rm -f "$OUTPUT_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存出力ファイルの削除に失敗しました"
        exit 1
    fi
fi

log "📋 VRTファイルを作成中..."
# 処理開始時間を記録
start_time=$(date +%s)

# gdalbuildvrtでVRTファイルを作成
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalbuildvrt "$VRT_FILE" "$TIFF_DIR"/*.tif "$TIFF_DIR"/*.tiff \
-resolution highest 2>/dev/null

if [ $? -eq 0 ] && [ -f "$VRT_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ VRTファイル作成成功: $VRT_FILE (処理時間: ${duration}秒)"
    
    # VRTファイル情報を表示
    vrt_size=$(du -h "$VRT_FILE" | cut -f1)
    log "📊 VRTファイルサイズ: $vrt_size"
else
    log "❌ VRTファイル作成エラー"
    exit 1
fi

log "🌍 Web Mercator (EPSG:3857) に投影変換中..."
log "設定: EPSG:6668 → EPSG:3857, 全CPUを使用"

# 投影変換開始時間を記録
start_time=$(date +%s)

# gdalwarpで3857に投影変換
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalwarp "$VRT_FILE" "$OUTPUT_FILE" \
  -s_srs EPSG:6668 -t_srs EPSG:3857 \
  -r bilinear -multi -wo NUM_THREADS=ALL_CPUS \
  -dstnodata -9999 -ot Float32 \
  -co TILED=YES -co COMPRESS=DEFLATE -co PREDICTOR=3 -co ZLEVEL=9 -co BIGTIFF=YES

if [ $? -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ 投影変換成功: $OUTPUT_FILE (処理時間: ${duration}秒)"
    
    # ファイルサイズを表示
    file_size=$(du -h "$OUTPUT_FILE" | cut -f1)
    log "📊 出力ファイルサイズ: $file_size"
    
    # ファイル情報を表示
    log "📄 ファイル情報:"
    docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalinfo "$OUTPUT_FILE" | head -10 | while read line; do
        log "   $line"
    done
    
    log "🎉 処理完了!"
    log "   VRTファイル: $VRT_FILE"
    log "   最終出力: $OUTPUT_FILE (EPSG:3857)"
    log "ログファイル: $LOG_FILE"
else
    log "❌ 投影変換エラー"
    exit 1
fi