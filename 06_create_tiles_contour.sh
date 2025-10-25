#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857_contour.geojson"
MBTILES_FILE="./dem_3857_contour.mbtiles"
PMTILES_FILE="./dem_3857_contour.pmtiles"

# tippecanoe設定
MAX_ZOOM=10
MIN_ZOOM=0
LAYER_NAME="contour"

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/tiles_contour_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 等高線タイル生成処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "MBTilesファイル: $MBTILES_FILE"
log "PMTilesファイル: $PMTILES_FILE"

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 必要なコマンドの存在確認
if ! command -v tippecanoe &> /dev/null; then
    log "❌ エラー: tippecanoeが見つかりません"
    exit 1
fi

if ! command -v pmtiles &> /dev/null; then
    log "❌ エラー: pmtilesが見つかりません"
    exit 1
fi

# 入力ファイルの基本情報を取得
log "📊 入力ファイル情報:"
file_size=$(du -h "$INPUT_FILE" | cut -f1)
log "   ファイルサイズ: $file_size"

# GeoJSONSeqファイルの基本統計
feature_count=$(wc -l < "$INPUT_FILE")
log "   フィーチャー数: $feature_count"

# 既存ファイルを削除
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

log "🗂️  MVTタイル生成中（tippecanoe）..."
log "設定: ズーム範囲=${MIN_ZOOM}-${MAX_ZOOM}, レイヤー名=${LAYER_NAME}"

# tippecanoe実行開始時間を記録
start_time=$(date +%s)

# tippecanoeで等高線のMVTタイルを生成
# 等高線用の最適化パラメータを使用
tippecanoe \
    -f -P -o "$MBTILES_FILE" \
    -l "$LAYER_NAME" \
    -z "$MAX_ZOOM" \
    -Z "$MIN_ZOOM" \
    -pf -pk \
    "$INPUT_FILE"

# tippecanoe結果の確認
if [ $? -eq 0 ] && [ -f "$MBTILES_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ MVTタイル生成成功: $MBTILES_FILE (処理時間: ${duration}秒)"
    
    # MBTilesファイルサイズを表示
    mbtiles_size=$(du -h "$MBTILES_FILE" | cut -f1)
    log "📊 MBTilesファイルサイズ: $mbtiles_size"
    
    # MBTilesの詳細情報（存在する場合）
    if command -v sqlite3 &> /dev/null; then
        log "📄 MBTiles情報:"
        sqlite3 "$MBTILES_FILE" "SELECT name, value FROM metadata;" | while read line; do
            log "   $line"
        done
        
        # タイル数を取得
        tile_count=$(sqlite3 "$MBTILES_FILE" "SELECT COUNT(*) FROM tiles;")
        log "📊 生成されたタイル数: $tile_count"
        
        # ズームレベル別タイル数
        log "📊 ズームレベル別タイル数:"
        sqlite3 "$MBTILES_FILE" "SELECT zoom_level, COUNT(*) FROM tiles GROUP BY zoom_level ORDER BY zoom_level;" | while read line; do
            zoom=$(echo "$line" | cut -d'|' -f1)
            count=$(echo "$line" | cut -d'|' -f2)
            log "   ズーム $zoom: $count タイル"
        done
    fi
else
    log "❌ エラー: MVTタイル生成に失敗しました"
    exit 1
fi

log "🗄️  PMTiles変換中..."

# PMTiles変換開始時間を記録
start_time=$(date +%s)

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
    if command -v pmtiles &> /dev/null; then
        log "📄 PMTiles情報:"
        pmtiles show "$PMTILES_FILE" | head -15 | while read line; do
            log "   $line"
        done
    fi
    
    log "🎉 処理完了!"
    log ""
    log "📋 最終結果:"
    log "   入力ファイル: $INPUT_FILE ($file_size, $feature_count フィーチャー)"
    log "   MBTiles: $MBTILES_FILE ($mbtiles_size)"
    log "   PMTiles: $PMTILES_FILE ($pmtiles_size)"
    if [ -n "$tile_count" ]; then
        log "   生成タイル数: $tile_count"
    fi
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: PMTiles変換に失敗しました"
    exit 1
fi