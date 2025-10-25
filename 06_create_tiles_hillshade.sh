#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857_hillshade.tif"
TILES_DIR="./tiles_hillshade"
MBTILES_FILE="./dem_3857_hillshade.mbtiles"
PMTILES_FILE="./dem_3857_hillshade.pmtiles"

# gdal2tiles設定
MAX_ZOOM=14
MIN_ZOOM=0
TILE_FORMAT="png"
PROCESSES=4  # 並列処理数

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/tiles_hillshade_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Hillshadeラスタタイル生成処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "出力ディレクトリ: $TILES_DIR"
log "MBTilesファイル: $MBTILES_FILE"
log "PMTilesファイル: $PMTILES_FILE"
log "ズーム範囲: ${MIN_ZOOM}-${MAX_ZOOM}"
log "タイル形式: $TILE_FORMAT"
log "プロセス数: $PROCESSES"

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 入力ファイルの基本情報を取得
log "📊 入力ファイル情報:"
file_size=$(du -h "$INPUT_FILE" | cut -f1)
log "   ファイルサイズ: $file_size"

# 既存のタイルディレクトリを削除（存在する場合）
if [ -d "$TILES_DIR" ]; then
    log "🗑️  既存のタイルディレクトリを削除: $TILES_DIR"
    rm -rf "$TILES_DIR"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存タイルディレクトリの削除に失敗しました"
        exit 1
    fi
fi

# 既存のMBTiles/PMTilesファイルを削除（存在する場合）
for file in "$MBTILES_FILE" "$PMTILES_FILE"; do
    if [ -f "$file" ]; then
        log "🗑️  既存ファイルを削除: $(basename "$file")"
        rm -f "$file"
        if [ $? -ne 0 ]; then
            log "❌ エラー: 既存ファイル削除に失敗: $(basename "$file")"
            exit 1
        fi
    fi
done

log "🗂️  ラスタタイル生成中（gdal2tiles）..."
log "設定: ズーム範囲=${MIN_ZOOM}-${MAX_ZOOM}, 形式=${TILE_FORMAT}, プロセス数=${PROCESSES}"

# gdal2tiles実行開始時間を記録
start_time=$(date +%s)

# gdal2tilesでラスタタイルを生成
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdal2tiles.py \
    -z "${MIN_ZOOM}-${MAX_ZOOM}" \
    --processes="$PROCESSES" \
    --tiledriver=PNG \
    --xyz \
    "$INPUT_FILE" "$TILES_DIR"

# gdal2tiles結果の確認
if [ $? -eq 0 ] && [ -d "$TILES_DIR" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ ラスタタイル生成成功: $TILES_DIR (処理時間: ${duration}秒)"
    
    # タイルディレクトリサイズを表示
    tiles_size=$(du -sh "$TILES_DIR" | cut -f1)
    log "📊 タイルディレクトリサイズ: $tiles_size"
    
    # タイル数を確認
    tile_count=$(find "$TILES_DIR" -name "*.png" | wc -l)
    log "📊 生成されたタイル数: $tile_count"
    
    # ズームレベル別の統計
    log "� ズームレベル別タイル数:"
    for zoom in $(seq $MIN_ZOOM $MAX_ZOOM); do
        if [ -d "$TILES_DIR/$zoom" ]; then
            level_count=$(find "$TILES_DIR/$zoom" -name "*.png" | wc -l)
            log "   ズーム${zoom}: ${level_count}枚"
        fi
    done
    
    # HTMLビューアーの確認
    if [ -f "$TILES_DIR/leaflet.html" ]; then
        log "📄 Leafletビューアー: $TILES_DIR/leaflet.html"
    fi
    if [ -f "$TILES_DIR/googlemaps.html" ]; then
        log "📄 Google Mapsビューアー: $TILES_DIR/googlemaps.html"
    fi
    if [ -f "$TILES_DIR/openlayers.html" ]; then
        log "📄 OpenLayersビューアー: $TILES_DIR/openlayers.html"
    fi
    
else
    log "❌ エラー: ラスタタイル生成に失敗しました"
    exit 1
fi

log "📦 MBTiles変換中（mb-util）..."

# MBTiles変換開始時間を記録
start_time=$(date +%s)

# 必要なコマンドの存在確認
if ! command -v mb-util &> /dev/null; then
    log "❌ エラー: mb-utilが見つかりません"
    log "   以下のコマンドでインストールしてください: pip install mbutil"
    exit 1
fi

# mb-utilでMBTilesに変換
mb-util --image_format=png "$TILES_DIR" "$MBTILES_FILE"

# MBTiles変換結果の確認
if [ $? -eq 0 ] && [ -f "$MBTILES_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ MBTiles変換成功: $MBTILES_FILE (処理時間: ${duration}秒)"
    
    # MBTilesファイルサイズを表示
    mbtiles_size=$(du -h "$MBTILES_FILE" | cut -f1)
    log "📊 MBTilesファイルサイズ: $mbtiles_size"
    
    # MBTilesの詳細情報（存在する場合）
    if command -v sqlite3 &> /dev/null; then
        log "📄 MBTiles情報:"
        sqlite3 "$MBTILES_FILE" "SELECT name, value FROM metadata;" 2>/dev/null | while read line; do
            log "   $line"
        done
        
        # タイル数を取得
        tile_count_mbtiles=$(sqlite3 "$MBTILES_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null)
        log "📊 MBTiles内タイル数: $tile_count_mbtiles"
    fi
else
    log "❌ エラー: MBTiles変換に失敗しました"
    exit 1
fi

log "🗄️  PMTiles変換中..."

# PMTiles変換開始時間を記録
start_time=$(date +%s)

# 必要なコマンドの存在確認
if ! command -v pmtiles &> /dev/null; then
    log "❌ エラー: pmtilesが見つかりません"
    log "   https://github.com/protomaps/go-pmtiles からダウンロードしてください"
    exit 1
fi

# pmtiles convertでPMTilesに変換
pmtiles convert "$MBTILES_FILE" "$PMTILES_FILE"

# PMTiles変換結果の確認
if [ $? -eq 0 ] && [ -f "$PMTILES_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ PMTiles変換成功: $PMTILES_FILE (処理時間: ${duration}秒)"
    
    # PMTilesファイルサイズを表示
    pmtiles_size=$(du -h "$PMTILES_FILE" | cut -f1)
    log "📊 PMTilesファイルサイズ: $pmtiles_size"
    
    # PMTilesの詳細情報
    log "📄 PMTiles情報:"
    pmtiles show "$PMTILES_FILE" 2>/dev/null | head -10 | while read line; do
        log "   $line"
    done
    
    log "🎉 全処理完了!"
    log ""
    log "📋 最終結果:"
    log "   入力ファイル: $INPUT_FILE ($file_size)"
    log "   ラスタタイル: $TILES_DIR ($tiles_size, ${tile_count}枚)"
    log "   MBTiles: $MBTILES_FILE ($mbtiles_size)"
    log "   PMTiles: $PMTILES_FILE ($pmtiles_size)"
    log "   ズーム範囲: ${MIN_ZOOM}-${MAX_ZOOM}"
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: PMTiles変換に失敗しました"
    exit 1
fi