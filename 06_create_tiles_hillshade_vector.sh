#!/bin/bash

# 変数設定
# ズームレベル別入力ファイル設定
declare -A ZOOM_INPUT_FILES=(
    ["z0-3"]="./dem_3857_hillshade_vector_simplified_z0-3.geojson"
    ["z4-7"]="./dem_3857_hillshade_vector_simplified_z4-7.geojson"
    ["z8-9"]="./dem_3857_hillshade_vector_simplified_z8-9.geojson"
    ["z10-11"]="./dem_3857_hillshade_vector_simplified_z10-11.geojson"
    ["z12-13"]="./dem_3857_hillshade_vector_simplified_z12-13.geojson"
)

# ズームレベル別範囲設定
declare -A ZOOM_RANGES=(
    ["z0-3"]="0:3"
    ["z4-7"]="4:7"
    ["z8-9"]="8:9"
    ["z10-11"]="10:11"
    ["z12-13"]="12:13"
)

# 最終出力ファイル
FINAL_MBTILES_FILE="./dem_3857_hillshade_vector_combined.mbtiles"
FINAL_PMTILES_FILE="./dem_3857_hillshade_vector_combined.pmtiles"

# tippecanoe設定（描画パフォーマンス重視）
LAYER_NAME="hillshade"
SIMPLIFICATION_LEVEL=1

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/tiles_hillshade_vector_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Hillshadeベクタータイル生成処理（ズームレベル別最適化）を開始します"
log "最終MBTilesファイル: $FINAL_MBTILES_FILE"
log "最終PMTilesファイル: $FINAL_PMTILES_FILE"
log "レイヤー名: $LAYER_NAME"
log ""
log "📊 ズームレベル別入力ファイル:"
for zoom_range in $(printf '%s\n' "${!ZOOM_INPUT_FILES[@]}" | sort); do
    input_file="${ZOOM_INPUT_FILES[$zoom_range]}"
    zoom_range_text="${ZOOM_RANGES[$zoom_range]}"
    log "   $zoom_range ($zoom_range_text): $(basename "$input_file")"
done

# 入力ファイルの存在確認
log "✅ 入力ファイル存在確認:"
missing_files=0
for zoom_range in "${!ZOOM_INPUT_FILES[@]}"; do
    input_file="${ZOOM_INPUT_FILES[$zoom_range]}"
    if [ ! -f "$input_file" ]; then
        log "❌ エラー: 入力ファイルが存在しません: $input_file"
        missing_files=$((missing_files + 1))
    else
        file_size=$(du -h "$input_file" | cut -f1)
        feature_count=$(wc -l < "$input_file" 2>/dev/null || echo "不明")
        log "   ✅ $zoom_range: $(basename "$input_file") ($file_size, $feature_count フィーチャー)"
    fi
done

if [ $missing_files -gt 0 ]; then
    log "❌ エラー: $missing_files 個のファイルが見つかりません"
    log "   05_create_hillshade_vector.sh を先に実行してください"
    exit 1
fi

# 必要なコマンドの存在確認
if ! command -v tippecanoe &> /dev/null; then
    log "❌ エラー: tippecanoeが見つかりません"
    log "   tippecanoeをインストールしてください"
    log "   https://github.com/mapbox/tippecanoe"
    exit 1
fi

if ! command -v tile-join &> /dev/null; then
    log "❌ エラー: tile-joinが見つかりません"
    log "   tile-joinはtippecanoeに含まれています"
    exit 1
fi

if ! command -v pmtiles &> /dev/null; then
    log "❌ エラー: pmtilesが見つかりません"
    log "   pmtilesをインストールしてください"
    log "   https://github.com/protomaps/go-pmtiles"
    exit 1
fi

# 既存ファイルを削除
for file in "$FINAL_MBTILES_FILE" "$FINAL_PMTILES_FILE"; do
    if [ -f "$file" ]; then
        log "🗑️  既存ファイルを削除: $(basename "$file")"
        rm -f "$file"
        if [ $? -ne 0 ]; then
            log "❌ エラー: 既存ファイル削除に失敗: $(basename "$file")"
            exit 1
        fi
    fi
done

# 中間MBTilesファイルも削除
for zoom_range in "${!ZOOM_INPUT_FILES[@]}"; do
    temp_mbtiles="./temp_${zoom_range}.mbtiles"
    if [ -f "$temp_mbtiles" ]; then
        log "🗑️  既存中間ファイルを削除: $(basename "$temp_mbtiles")"
        rm -f "$temp_mbtiles"
    fi
done

log "🔄 ステップ1: ズームレベル別MVTタイル生成"
log "各ズームレベル帯に最適化されたタイルを個別生成します"

# 各ズームレベル帯でタイルを生成
temp_mbtiles_files=()
zoom_count=0

for zoom_range in $(printf '%s\n' "${!ZOOM_INPUT_FILES[@]}" | sort); do
    zoom_count=$((zoom_count + 1))
    input_file="${ZOOM_INPUT_FILES[$zoom_range]}"
    zoom_range_text="${ZOOM_RANGES[$zoom_range]}"
    temp_mbtiles="./temp_${zoom_range}.mbtiles"
    
    # ズーム範囲を分解
    IFS=':' read -r min_zoom max_zoom <<< "$zoom_range_text"
    
    log ""
    log "🎯 処理中: $zoom_range (${min_zoom}-${max_zoom}) ($zoom_count/${#ZOOM_INPUT_FILES[@]})"
    log "   入力: $(basename "$input_file")"
    log "   出力: $(basename "$temp_mbtiles")"
    
    # ファイル基本情報
    file_size=$(du -h "$input_file" | cut -f1)
    feature_count=$(wc -l < "$input_file" 2>/dev/null || echo "不明")
    log "   ファイルサイズ: $file_size, フィーチャー数: $feature_count"

    # tippecanoe実行開始時間を記録
    start_time=$(date +%s)

    # tippecanoeでズームレベル別MVTタイルを生成
    tippecanoe \
        -f -P -o "$temp_mbtiles" \
        -l "$LAYER_NAME" \
        -z "$max_zoom" \
        -Z "$min_zoom" \
        --simplification="$SIMPLIFICATION_LEVEL" \
        --no-tiny-polygon-reduction \
        --coalesce \
        -pf -pk \
        "$input_file"

    # tippecanoe結果の確認
    if [ $? -eq 0 ] && [ -f "$temp_mbtiles" ]; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log "✅ タイル生成成功: $(basename "$temp_mbtiles") (処理時間: ${duration}秒)"
        
        # MBTilesファイルサイズを表示
        mbtiles_size=$(du -h "$temp_mbtiles" | cut -f1)
        log "📊 MBTilesサイズ: $mbtiles_size"
        
        # タイル数を取得
        if command -v sqlite3 &> /dev/null; then
            tile_count=$(sqlite3 "$temp_mbtiles" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "不明")
            log "📊 生成タイル数: $tile_count"
        fi
        
        # 中間ファイルリストに追加
        temp_mbtiles_files+=("$temp_mbtiles")
    else
        log "❌ エラー: タイル生成に失敗しました ($zoom_range)"
        exit 1
    fi
done

log ""
log "🔗 ステップ2: tile-joinによる結合処理"
log "生成された${#temp_mbtiles_files[@]}個のMBTilesファイルを結合します"

# tile-join実行開始時間を記録
start_time=$(date +%s)

# tile-joinで全てのMBTilesファイルを結合
log "実行コマンド: tile-join -f -o $FINAL_MBTILES_FILE ${temp_mbtiles_files[*]}"
tile-join -f -o "$FINAL_MBTILES_FILE" "${temp_mbtiles_files[@]}"

# tile-join結果の確認
if [ $? -eq 0 ] && [ -f "$FINAL_MBTILES_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ タイル結合成功: $(basename "$FINAL_MBTILES_FILE") (処理時間: ${duration}秒)"
    
    # MBTilesファイルサイズを表示
    final_mbtiles_size=$(du -h "$FINAL_MBTILES_FILE" | cut -f1)
    log "📊 最終MBTilesサイズ: $final_mbtiles_size"
    
    # 統計情報を取得
    if command -v sqlite3 &> /dev/null; then
        log "📄 最終MBTiles情報:"
        sqlite3 "$FINAL_MBTILES_FILE" "SELECT name, value FROM metadata;" | while read line; do
            log "   $line"
        done
        
        # 総タイル数を取得
        total_tile_count=$(sqlite3 "$FINAL_MBTILES_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "不明")
        log "📊 総タイル数: $total_tile_count"
        
        # ズームレベル別タイル数
        log "📊 ズームレベル別タイル数:"
        sqlite3 "$FINAL_MBTILES_FILE" "SELECT zoom_level, COUNT(*) FROM tiles GROUP BY zoom_level ORDER BY zoom_level;" | while read line; do
            zoom=$(echo "$line" | cut -d'|' -f1)
            count=$(echo "$line" | cut -d'|' -f2)
            log "   ズーム $zoom: $count タイル"
        done
        
        # タイルサイズ統計
        avg_size=$(sqlite3 "$FINAL_MBTILES_FILE" "SELECT AVG(LENGTH(tile_data)) FROM tiles;" 2>/dev/null | cut -d'.' -f1)
        max_size=$(sqlite3 "$FINAL_MBTILES_FILE" "SELECT MAX(LENGTH(tile_data)) FROM tiles;" 2>/dev/null)
        min_size=$(sqlite3 "$FINAL_MBTILES_FILE" "SELECT MIN(LENGTH(tile_data)) FROM tiles;" 2>/dev/null)
        
        if [ -n "$avg_size" ] && [ -n "$max_size" ] && [ -n "$min_size" ]; then
            log "📊 タイルサイズ統計:"
            log "   平均: ${avg_size} bytes"
            log "   最大: ${max_size} bytes"
            log "   最小: ${min_size} bytes"
        fi
    fi
    
    # 中間ファイルの削除
    log "🧹 中間ファイルのクリーンアップ"
    for temp_file in "${temp_mbtiles_files[@]}"; do
        if [ -f "$temp_file" ]; then
            rm -f "$temp_file"
            log "   削除: $(basename "$temp_file")"
        fi
    done
else
    log "❌ エラー: タイル結合に失敗しました"
    log "tile-joinのエラー出力を確認してください"
    exit 1
fi

log ""
log "🗄️  ステップ3: PMTiles変換"
log "MBTiles→PMTiles形式変換"

# PMTiles変換開始時間を記録
start_time=$(date +%s)

# pmtiles convertでPMTilesに変換
pmtiles convert "$FINAL_MBTILES_FILE" "$FINAL_PMTILES_FILE"

# PMTiles変換結果の確認
if [ $? -eq 0 ] && [ -f "$FINAL_PMTILES_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ PMTiles変換成功: $(basename "$FINAL_PMTILES_FILE") (処理時間: ${duration}秒)"
    
    # PMTilesファイルサイズを表示
    final_pmtiles_size=$(du -h "$FINAL_PMTILES_FILE" | cut -f1)
    log "📊 最終PMTilesサイズ: $final_pmtiles_size"
    
    # PMTilesの詳細情報
    if command -v pmtiles &> /dev/null; then
        log "📄 PMTiles情報:"
        pmtiles_info=$(pmtiles show "$FINAL_PMTILES_FILE" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$pmtiles_info" ]; then
            echo "$pmtiles_info" | head -20 | while read line; do
                log "   $line"
            done
        else
            log "   PMTiles詳細情報の取得に失敗しました"
        fi
    fi
    
    # ファイルサイズ比較
    if [ -n "$final_mbtiles_size" ] && [ -n "$final_pmtiles_size" ]; then
        log "📊 ファイルサイズ比較:"
        log "   MBTiles: $final_mbtiles_size"
        log "   PMTiles: $final_pmtiles_size"
        
        # 圧縮率の計算（概算）
        mbtiles_bytes=$(stat -c%s "$FINAL_MBTILES_FILE" 2>/dev/null)
        pmtiles_bytes=$(stat -c%s "$FINAL_PMTILES_FILE" 2>/dev/null)
        
        if [ -n "$mbtiles_bytes" ] && [ -n "$pmtiles_bytes" ] && [ $mbtiles_bytes -gt 0 ]; then
            compression_ratio=$(echo "scale=1; $pmtiles_bytes * 100 / $mbtiles_bytes" | bc -l 2>/dev/null)
            if [ -n "$compression_ratio" ]; then
                log "   圧縮率: ${compression_ratio}% (PMTiles/MBTiles)"
            fi
        fi
    fi
    
    log ""
    log "🎉 全処理完了!"
    log ""
    log "📋 最終結果（ズームレベル別最適化済み）:"
    log "   最終MBTiles: $(basename "$FINAL_MBTILES_FILE") ($final_mbtiles_size)"
    log "   最終PMTiles: $(basename "$FINAL_PMTILES_FILE") ($final_pmtiles_size)"
    if [ -n "$total_tile_count" ]; then
        log "   総タイル数: $total_tile_count"
    fi
    log "   レイヤー名: $LAYER_NAME"
    log ""
    log "📊 ズームレベル別最適化設定:"
    for zoom_range in $(printf '%s\n' "${!ZOOM_INPUT_FILES[@]}" | sort); do
        input_file="${ZOOM_INPUT_FILES[$zoom_range]}"
        zoom_range_text="${ZOOM_RANGES[$zoom_range]}"
        if [ -f "$input_file" ]; then
            file_size=$(du -h "$input_file" | cut -f1)
            feature_count=$(wc -l < "$input_file" 2>/dev/null || echo "不明")
            log "   $zoom_range ($zoom_range_text): $feature_count フィーチャー ($file_size)"
        fi
    done
    log ""
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: PMTiles変換に失敗しました"
    log "pmtilesコマンドのエラー出力を確認してください"
    exit 1
fi