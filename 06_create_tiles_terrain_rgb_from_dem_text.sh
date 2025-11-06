#!/bin/bash

# 変数設定
TEXT_TILES_DIR="./tiles_elevation"
OUTPUT_TILES_DIR="./tiles_terrainrgb"
MBTILES_FILE="./dem_3857_terrainrgb.mbtiles"
PMTILES_FILE="./dem_3857_terrainrgb.pmtiles"

# タイル設定
MAX_ZOOM=14
MIN_ZOOM=0
TILE_SIZE=256
IMAGE_FORMAT="png"

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/tiles_terrainrgb_from_text_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 テキストタイルからterrain RGBタイル生成処理を開始します"
log "入力ディレクトリ: $TEXT_TILES_DIR"
log "出力ディレクトリ: $OUTPUT_TILES_DIR"
log "MBTilesファイル: $MBTILES_FILE"
log "PMTilesファイル: $PMTILES_FILE"
log "ズームレベル: $MIN_ZOOM-$MAX_ZOOM"

# 入力ディレクトリの存在確認
if [ ! -d "$TEXT_TILES_DIR" ]; then
    log "❌ エラー: 入力ディレクトリが存在しません: $TEXT_TILES_DIR"
    exit 1
fi

log "✅ 入力ディレクトリを確認しました"

# 既存の出力ディレクトリを削除（存在する場合）
if [ -d "$OUTPUT_TILES_DIR" ]; then
    log "🗑️  既存の出力ディレクトリを削除: $OUTPUT_TILES_DIR"
    rm -rf "$OUTPUT_TILES_DIR"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存出力ディレクトリの削除に失敗しました"
        exit 1
    fi
fi

# 既存のMBTilesファイルを削除（存在する場合）
if [ -f "$MBTILES_FILE" ]; then
    log "🗑️  既存のMBTilesファイルを削除: $MBTILES_FILE"
    rm -f "$MBTILES_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存MBTilesファイルの削除に失敗しました"
        exit 1
    fi
fi

# 既存のPMTilesファイルを削除（存在する場合）
if [ -f "$PMTILES_FILE" ]; then
    log "🗑️  既存のPMTilesファイルを削除: $PMTILES_FILE"
    rm -f "$PMTILES_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存PMTilesファイルの削除に失敗しました"
        exit 1
    fi
fi

# 出力ディレクトリ作成
mkdir -p "$OUTPUT_TILES_DIR"
if [ $? -ne 0 ]; then
    log "❌ エラー: 出力ディレクトリの作成に失敗しました"
    exit 1
fi

# 必要なコマンドの存在確認
if ! command -v mb-util &> /dev/null; then
    log "❌ エラー: mb-utilが見つかりません"
    exit 1
fi

if ! command -v pmtiles &> /dev/null; then
    log "❌ エラー: pmtilesが見つかりません"
    exit 1
fi

# テキストタイルの総数を確認
total_text_tiles=$(find "$TEXT_TILES_DIR" -name "*.txt" | wc -l)
log "📊 入力テキストタイル数: $total_text_tiles"

# terrain RGB変換スクリプトの存在確認
CONVERT_SCRIPT="./convert_text_to_terrainrgb.py"
if [ ! -f "$CONVERT_SCRIPT" ]; then
    log "❌ エラー: terrain RGB変換スクリプトが存在しません: $CONVERT_SCRIPT"
    exit 1
fi

log "✅ terrain RGB変換スクリプトを確認しました: $CONVERT_SCRIPT"

# terrain RGB変換を実行
log "🎨 テキストタイルをterrain RGB PNG形式に変換中..."
start_time=$(date +%s)

docker run --rm \
    -v "$PWD":/work \
    -w /work \
    python:3.9-slim \
    sh -c "
    pip install --no-cache-dir pillow numpy && \
    python3 $CONVERT_SCRIPT '$TEXT_TILES_DIR' '$OUTPUT_TILES_DIR'
    "

# 変換結果の確認
if [ $? -eq 0 ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ terrain RGB変換成功"
    log "⏱️  変換時間: ${duration}秒"
    
    # 生成されたPNGタイル数を確認
    png_tile_count=$(find "$OUTPUT_TILES_DIR" -name "*.png" | wc -l)
    log "📊 生成されたPNGタイル数: $png_tile_count"
    
    # ディレクトリサイズを確認
    tiles_size=$(du -sh "$OUTPUT_TILES_DIR" | cut -f1)
    log "📊 タイルディレクトリサイズ: $tiles_size"
    
    # 各ズームレベルのタイル数を確認
    log "📊 ズームレベル別タイル数:"
    for zoom in $(seq $MIN_ZOOM $MAX_ZOOM); do
        if [ -d "$OUTPUT_TILES_DIR/$zoom" ]; then
            zoom_tiles=$(find "$OUTPUT_TILES_DIR/$zoom" -name "*.png" 2>/dev/null | wc -l)
            log "   z$zoom: $zoom_tiles タイル"
        fi
    done
else
    log "❌ エラー: terrain RGB変換に失敗しました"
    exit 1
fi

log "📦 MBTiles形式に変換中..."
log "設定: 画像フォーマット=$IMAGE_FORMAT"

# mb-utilでMBTiles形式に変換
start_time=$(date +%s)
mb-util --image_format="$IMAGE_FORMAT" "$OUTPUT_TILES_DIR/" "$MBTILES_FILE"

# MBTiles変換結果の確認
if [ $? -eq 0 ] && [ -f "$MBTILES_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ MBTiles変換成功: $MBTILES_FILE"
    log "⏱️  変換時間: ${duration}秒"
    
    # MBTilesファイルサイズを確認
    mbtiles_size=$(du -h "$MBTILES_FILE" | cut -f1)
    log "📊 MBTilesファイルサイズ: $mbtiles_size"
    
    # MBTilesの詳細情報（存在する場合）
    if command -v sqlite3 &> /dev/null; then
        log "📄 MBTiles情報:"
        sqlite3 "$MBTILES_FILE" "SELECT name, value FROM metadata;" | while read line; do
            log "   $line"
        done
    fi
else
    log "❌ エラー: MBTiles変換に失敗しました"
    exit 1
fi

log "📦 PMTiles形式に変換中..."

# pmtilesでPMTiles形式に変換
start_time=$(date +%s)
pmtiles convert "$MBTILES_FILE" "$PMTILES_FILE"

# PMTiles変換結果の確認
if [ $? -eq 0 ] && [ -f "$PMTILES_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ PMTiles変換成功: $PMTILES_FILE"
    log "⏱️  変換時間: ${duration}秒"
    
    # PMTilesファイルサイズを確認
    pmtiles_size=$(du -h "$PMTILES_FILE" | cut -f1)
    log "📊 PMTilesファイルサイズ: $pmtiles_size"
    
    # PMTilesの詳細情報（存在する場合）
    if command -v pmtiles &> /dev/null; then
        log "📄 PMTiles情報:"
        pmtiles show "$PMTILES_FILE" 2>/dev/null | head -20 | while read line; do
            log "   $line"
        done
    fi
else
    log "❌ エラー: PMTiles変換に失敗しました"
    exit 1
fi

log "🎉 全処理完了!"
log "ログファイル: $LOG_FILE"

log "📋 最終結果:"
log "   タイルディレクトリ: $OUTPUT_TILES_DIR ($tiles_size, $png_tile_count tiles)"
log "   MBTilesファイル: $MBTILES_FILE ($mbtiles_size)"
log "   PMTilesファイル: $PMTILES_FILE ($pmtiles_size)"