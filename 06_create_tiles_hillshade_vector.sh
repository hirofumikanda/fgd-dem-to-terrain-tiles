#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857_hillshade_vector.geojson"
MBTILES_FILE="./dem_3857_hillshade_vector.mbtiles"
PMTILES_FILE="./dem_3857_hillshade_vector.pmtiles"

# tippecanoe設定
MAX_ZOOM=12
MIN_ZOOM=0
LAYER_NAME="hillshade"

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/tiles_hillshade_vector_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Hillshadeベクタータイル生成処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "MBTilesファイル: $MBTILES_FILE"
log "PMTilesファイル: $PMTILES_FILE"
log "ズーム範囲: ${MIN_ZOOM}-${MAX_ZOOM}"
log "レイヤー名: $LAYER_NAME"

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 必要なコマンドの存在確認
if ! command -v tippecanoe &> /dev/null; then
    log "❌ エラー: tippecanoeが見つかりません"
    log "   tippecanoeをインストールしてください"
    log "   https://github.com/mapbox/tippecanoe"
    exit 1
fi

if ! command -v pmtiles &> /dev/null; then
    log "❌ エラー: pmtilesが見つかりません"
    log "   pmtilesをインストールしてください"
    log "   https://github.com/protomaps/go-pmtiles"
    exit 1
fi

# 入力ファイルの基本情報を取得
log "📊 入力ファイル情報:"
file_size=$(du -h "$INPUT_FILE" | cut -f1)
log "   ファイルサイズ: $file_size"

# GeoJSONSeqファイルの基本統計
feature_count=$(wc -l < "$INPUT_FILE")
log "   フィーチャー数: $feature_count"

# サンプルフィーチャーの確認（jqが利用可能な場合）
if command -v jq &> /dev/null; then
    log "📄 フィーチャー属性確認:"
    
    # 最初のフィーチャーからプロパティを取得
    sample_props=$(head -1 "$INPUT_FILE" | jq -r '.properties | keys[]' 2>/dev/null)
    if [ -n "$sample_props" ]; then
        log "   利用可能な属性:"
        echo "$sample_props" | while read prop; do
            log "     - $prop"
        done
    fi
    
    # class属性の分布を確認
    log "📊 class属性の分布:"
    cat "$INPUT_FILE" | jq -r '.properties.class' 2>/dev/null | sort | uniq -c | head -10 | while read count class; do
        log "   クラス $class: $count フィーチャー"
    done
fi

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
log "設定詳細:"
log "   ズーム範囲: ${MIN_ZOOM}-${MAX_ZOOM}"
log "   レイヤー名: $LAYER_NAME"
log "   最適化: Hillshadeベクター用パラメータ"

# tippecanoe実行開始時間を記録
start_time=$(date +%s)

# tippecanoeでHillshadeベクターのMVTタイルを生成
# Hillshadeベクター用の最適化パラメータを使用
tippecanoe \
    -f -P -o "$MBTILES_FILE" \
    -l "$LAYER_NAME" \
    -z "$MAX_ZOOM" \
    -Z "$MIN_ZOOM" \
    -pf -pk \
    --simplification=2 \
    --detect-shared-borders \
    --coalesce-smallest-as-needed \
    --coalesce-densest-as-needed \
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
        
        # サンプルタイルのサイズ情報
        avg_size=$(sqlite3 "$MBTILES_FILE" "SELECT AVG(LENGTH(tile_data)) FROM tiles;" | cut -d'.' -f1)
        max_size=$(sqlite3 "$MBTILES_FILE" "SELECT MAX(LENGTH(tile_data)) FROM tiles;")
        min_size=$(sqlite3 "$MBTILES_FILE" "SELECT MIN(LENGTH(tile_data)) FROM tiles;")
        
        if [ -n "$avg_size" ] && [ -n "$max_size" ] && [ -n "$min_size" ]; then
            log "📊 タイルサイズ統計:"
            log "   平均: ${avg_size} bytes"
            log "   最大: ${max_size} bytes"
            log "   最小: ${min_size} bytes"
        fi
    fi
else
    log "❌ エラー: MVTタイル生成に失敗しました"
    log "tippecanoeのエラー出力を確認してください"
    exit 1
fi

log "🗄️  PMTiles変換中..."
log "設定: MBTiles→PMTiles形式変換"

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
        pmtiles_info=$(pmtiles show "$PMTILES_FILE" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$pmtiles_info" ]; then
            echo "$pmtiles_info" | head -20 | while read line; do
                log "   $line"
            done
        else
            log "   PMTiles詳細情報の取得に失敗しました"
        fi
    fi
    
    # ファイルサイズ比較
    if [ -n "$mbtiles_size" ] && [ -n "$pmtiles_size" ]; then
        log "📊 ファイルサイズ比較:"
        log "   MBTiles: $mbtiles_size"
        log "   PMTiles: $pmtiles_size"
        
        # 圧縮率の計算（概算）
        mbtiles_bytes=$(stat -c%s "$MBTILES_FILE" 2>/dev/null)
        pmtiles_bytes=$(stat -c%s "$PMTILES_FILE" 2>/dev/null)
        
        if [ -n "$mbtiles_bytes" ] && [ -n "$pmtiles_bytes" ] && [ $mbtiles_bytes -gt 0 ]; then
            compression_ratio=$(echo "scale=1; $pmtiles_bytes * 100 / $mbtiles_bytes" | bc -l 2>/dev/null)
            if [ -n "$compression_ratio" ]; then
                log "   圧縮率: ${compression_ratio}% (PMTiles/MBTiles)"
            fi
        fi
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
    log "   ズーム範囲: ${MIN_ZOOM}-${MAX_ZOOM}"
    log "   レイヤー名: $LAYER_NAME"
    log ""
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: PMTiles変換に失敗しました"
    log "pmtilesコマンドのエラー出力を確認してください"
    exit 1
fi