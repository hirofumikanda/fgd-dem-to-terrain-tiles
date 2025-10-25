#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857.tif"
CONTOUR_FILE="./dem_3857_contour.geojson"
CONTOUR_INTERVAL=10

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/create_contour_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 等高線作成処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "出力ファイル: $CONTOUR_FILE"
log "等高線間隔: ${CONTOUR_INTERVAL}m"

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 既存の等高線ファイルを削除（存在する場合）
if [ -f "$CONTOUR_FILE" ]; then
    log "🗑️  既存の等高線ファイルを削除: $CONTOUR_FILE"
    rm -f "$CONTOUR_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存等高線ファイルの削除に失敗しました"
        exit 1
    fi
fi

# 入力ファイルの基本情報を取得
log "📊 入力ファイル情報:"
file_size=$(du -h "$INPUT_FILE" | cut -f1)
log "   ファイルサイズ: $file_size"

# DEMの標高統計を取得
log "📊 DEM統計情報:"
dem_stats=$(docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalinfo -stats "$INPUT_FILE" | grep -E "(Minimum|Maximum|Mean|StdDev)")
if [ -n "$dem_stats" ]; then
    echo "$dem_stats" | while read line; do
        log "   $line"
    done
else
    log "   統計情報を取得できませんでした"
fi

log "📏 等高線生成中..."
log "設定: ${CONTOUR_INTERVAL}m間隔, 属性名=elevation, GeoJSONSeq形式"

# 等高線生成開始時間を記録
start_time=$(date +%s)

# gdal_contourで等高線を生成（GeoJSONSeq形式）
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdal_contour \
    -a elevation \
    -i "$CONTOUR_INTERVAL" \
    -f "GeoJSONSeq" \
    "$INPUT_FILE" \
    "$CONTOUR_FILE"

# 等高線生成結果の確認
if [ $? -eq 0 ] && [ -f "$CONTOUR_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ 等高線生成成功: $CONTOUR_FILE (処理時間: ${duration}秒)"
    
    # ファイルサイズを表示
    contour_size=$(du -h "$CONTOUR_FILE" | cut -f1)
    log "📊 等高線ファイルサイズ: $contour_size"
    
    # 等高線の統計情報を取得
    log "📄 等高線統計情報:"
    if command -v jq &> /dev/null; then
        # jqが利用可能な場合、より詳細な統計を取得
        total_features=$(cat "$CONTOUR_FILE" | wc -l)
        log "   総フィーチャー数: $total_features"
        
        # 最小・最大標高を取得（最初と最後の数行から）
        min_elevation=$(head -1 "$CONTOUR_FILE" | jq -r '.properties.elevation // empty' 2>/dev/null)
        max_elevation=$(tail -1 "$CONTOUR_FILE" | jq -r '.properties.elevation // empty' 2>/dev/null)
        
        if [ -n "$min_elevation" ] && [ -n "$max_elevation" ]; then
            log "   標高範囲: ${min_elevation}m - ${max_elevation}m"
        fi
        
        # サンプルフィーチャーを表示
        log "   サンプルフィーチャー（最初の1件）:"
        head -1 "$CONTOUR_FILE" | jq -c . 2>/dev/null | head -c 200 | while read line; do
            log "     $line..."
        done
    else
        # jqが利用できない場合、基本的な統計のみ
        total_features=$(cat "$CONTOUR_FILE" | wc -l)
        log "   総フィーチャー数: $total_features"
        
        # ファイルの最初の数行を表示
        log "   ファイル形式確認（最初の2行）:"
        head -2 "$CONTOUR_FILE" | while read line; do
            log "     $(echo "$line" | head -c 150)..."
        done
    fi
    
    # GeoJSONSeq形式の確認
    first_line=$(head -1 "$CONTOUR_FILE")
    if echo "$first_line" | grep -q '"type":"Feature"'; then
        log "✅ GeoJSONSeq形式（NDJSON）で正しく出力されました"
    else
        log "⚠️  警告: GeoJSONSeq形式ではない可能性があります"
    fi
    
    log "🎉 処理完了!"
    log "   入力ファイル: $INPUT_FILE ($file_size)"
    log "   等高線ファイル: $CONTOUR_FILE ($contour_size)"
    log "   等高線間隔: ${CONTOUR_INTERVAL}m"
    log "   フィーチャー数: $total_features"
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: 等高線生成に失敗しました"
    exit 1
fi