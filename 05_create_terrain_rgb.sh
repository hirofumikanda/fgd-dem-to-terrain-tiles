#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857.tif"
TEMP_FILE="./dem_3857_temp.tif"
CLEANED_FILE="./dem_3857_cleaned.tif"
OUTPUT_FILE="./dem_3857_terrainrgb.tif"
JOBS=1

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/terrain_rgb_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Terrain RGB変換処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "一時ファイル: $TEMP_FILE"
log "修正ファイル: $CLEANED_FILE"
log "出力ファイル: $OUTPUT_FILE"

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 既存の一時ファイルを削除（存在する場合）
if [ -f "$TEMP_FILE" ]; then
    log "🗑️  既存の一時ファイルを削除: $TEMP_FILE"
    rm -f "$TEMP_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存一時ファイルの削除に失敗しました"
        exit 1
    fi
fi

# 既存の出力ファイルを削除（存在する場合）
if [ -f "$OUTPUT_FILE" ]; then
    log "🗑️  既存の出力ファイルを削除: $OUTPUT_FILE"
    rm -f "$OUTPUT_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存ファイルの削除に失敗しました"
        exit 1
    fi
fi

# 既存の修正ファイルを削除（存在する場合）
if [ -f "$CLEANED_FILE" ]; then
    log "🗑️  既存の修正ファイルを削除: $CLEANED_FILE"
    rm -f "$CLEANED_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存修正ファイルの削除に失敗しました"
        exit 1
    fi
fi

# 入力ファイルの基本情報を取得
log "📊 入力ファイル情報:"
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalinfo "$INPUT_FILE" | head -5 | while read line; do
    log "   $line"
done

# gdalwarpでnodata値を0に変換
log "🧹 nodataを0に変換中..."
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalwarp -srcnodata -9999 -dstnodata 0 \
    -ot Float32 -multi -wo NUM_THREADS=ALL_CPUS \
    -co BIGTIFF=YES -co TILED=YES -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 \
    -co BLOCKXSIZE=512 -co BLOCKYSIZE=512 \
    "$INPUT_FILE" "$CLEANED_FILE"

if [ $? -eq 0 ] && [ -f "$CLEANED_FILE" ]; then
    log "✅ nodataを0に変換成功"
else
    log "❌ エラー: nodataの0への変換に失敗しました"
    exit 1
fi

# nodataメタデータを削除
log "🧹 nodataメタデータを削除中..."
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdal_edit.py -unsetnodata "$CLEANED_FILE"

if [ $? -eq 0 ]; then
    log "✅ nodataメタデータ削除成功"
    
    # 修正ファイルの基本情報を表示
    log "📊 変換後ファイル情報:"
    docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalinfo "$CLEANED_FILE" | head -5 | while read line; do
        log "   $line"
    done
else
    log "❌ エラー: nodataメタデータの削除に失敗しました"
    exit 1
fi

log "🎨 Terrain RGBエンコーディング中..."

# rio rgbifyでTerrain RGB形式に変換（修正ファイルを使用）
rio rgbify -j "$JOBS" -b -10000 -i 0.1 \
    "$CLEANED_FILE" "$OUTPUT_FILE" \
    --co BIGTIFF=YES --co TILED=YES --co COMPRESS=DEFLATE --co PREDICTOR=2 --co ZLEVEL=9 \
    --co BLOCKXSIZE=512 --co BLOCKYSIZE=512

# 変換結果の確認
if [ $? -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
    log "✅ Terrain RGB変換成功: $OUTPUT_FILE"
    
    # ファイルサイズを表示
    file_size=$(du -h "$OUTPUT_FILE" | cut -f1)
    log "📊 出力ファイルサイズ: $file_size"
    
    # 出力ファイルの基本情報を取得
    log "📄 出力ファイル情報:"
    docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalinfo "$OUTPUT_FILE" | head -10 | while read line; do
        log "   $line"
    done
    
    log "🎉 処理完了!"
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: Terrain RGB変換に失敗しました"
    exit 1
fi