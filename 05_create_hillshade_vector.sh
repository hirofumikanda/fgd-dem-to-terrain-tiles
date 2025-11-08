#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857.tif"
HILLSHADE_FILE="./dem_3857_hillshade.tif"
QUANTIZED_FILE="./dem_3857_hillshade_quantized.tif"
# ズームレベル別出力ファイルは動的に生成

# 量子化設定（変更可能）
QUANTIZATION_LEVELS=5  # 256段階を5段階に量子化（描画パフォーマンス重視）

# ズームレベル別フィルタリング設定（変更可能）
# ズームレベル帯別にSIEVE_THRESHOLDとMAPSHAPER_SIMPLIFYを最適化
declare -A ZOOM_CONFIGS=(
    ["z0-3"]="2000,0.2"     # 粗い詳細度、大きな簡略化
    ["z4-7"]="1000,0.1"     # 中程度の詳細度
    ["z8-9"]="400,0.04"     # やや詳細
    ["z10-11"]="200,0.02"   # 詳細
    ["z12-13"]="100,0.01"   # 最高詳細度
)

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/create_hillshade_vector_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Hillshadeベクトル化処理（ズームレベル別最適化）を開始します"
log "入力ファイル: $INPUT_FILE"
log "Hillshadeファイル: $HILLSHADE_FILE"
log "量子化ファイル: $QUANTIZED_FILE"
log "量子化レベル: $QUANTIZATION_LEVELS段階"
log ""
log "📊 ズームレベル別設定:"
for zoom_range in "${!ZOOM_CONFIGS[@]}"; do
    IFS=',' read -r sieve simplify <<< "${ZOOM_CONFIGS[$zoom_range]}"
    log "   $zoom_range: SIEVE=$sieve, MAPSHAPER=$simplify"
done

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 既存ファイルを削除（存在する場合）
for file in "$HILLSHADE_FILE" "$QUANTIZED_FILE"; do
    if [ -f "$file" ]; then
        log "🗑️  既存ファイルを削除: $(basename "$file")"
        rm -f "$file"
        if [ $? -ne 0 ]; then
            log "❌ エラー: 既存ファイルの削除に失敗しました: $(basename "$file")"
            exit 1
        fi
    fi
done

# ズームレベル別出力ファイルを削除
for zoom_range in "${!ZOOM_CONFIGS[@]}"; do
    sieved_file="./dem_3857_hillshade_sieved_${zoom_range}.tif"
    vector_file="./dem_3857_hillshade_vector_${zoom_range}.geojson"
    simplified_file="./dem_3857_hillshade_vector_simplified_${zoom_range}.geojson"
    
    for file in "$sieved_file" "$vector_file" "$simplified_file"; do
        if [ -f "$file" ]; then
            log "🗑️  既存ファイルを削除: $(basename "$file")"
            rm -f "$file"
        fi
    done
done

# 入力ファイルの基本情報を取得
log "📊 入力ファイル情報:"
file_size=$(du -h "$INPUT_FILE" | cut -f1)
log "   ファイルサイズ: $file_size"

# ステップ1: Hillshade生成
log "🏔️  ステップ1: Hillshade生成中..."
log "設定: デフォルト設定（太陽角度315°、仰角45°）"

# hillshade生成開始時間を記録
start_time=$(date +%s)

# gdaldem hillshadeでhillshadeを生成
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdaldem hillshade "$INPUT_FILE" "$HILLSHADE_FILE" \
    -z 1.0 -s 1.0 -az 315 -alt 45 \
    -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2

# hillshade生成結果の確認
if [ $? -eq 0 ] && [ -f "$HILLSHADE_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ Hillshade生成成功: $HILLSHADE_FILE (処理時間: ${duration}秒)"
    
    # ファイルサイズを表示
    hillshade_size=$(du -h "$HILLSHADE_FILE" | cut -f1)
    log "📊 Hillshadeファイルサイズ: $hillshade_size"
else
    log "❌ エラー: Hillshade生成に失敗しました"
    exit 1
fi

# ステップ2: Hillshadeの統計情報取得
log "📊 ステップ2: Hillshade統計情報取得中..."

# Hillshadeの統計を取得
hillshade_stats=$(docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalinfo -stats "$HILLSHADE_FILE" | grep -E "(Minimum|Maximum|Mean|StdDev)")
if [ -n "$hillshade_stats" ]; then
    log "📊 Hillshade統計情報:"
    echo "$hillshade_stats" | while read line; do
        log "   $line"
    done
    
    # 最小値と最大値を抽出（量子化計算のため）
    min_value=$(echo "$hillshade_stats" | grep "Minimum" | sed 's/.*Minimum=\([0-9.]*\).*/\1/')
    max_value=$(echo "$hillshade_stats" | grep "Maximum" | sed 's/.*Maximum=\([0-9.]*\).*/\1/')
    
    if [ -n "$min_value" ] && [ -n "$max_value" ]; then
        log "   値の範囲: $min_value - $max_value"
        
        # 量子化間隔を計算
        range=$(echo "$max_value - $min_value" | bc -l)
        interval=$(echo "scale=6; $range / $QUANTIZATION_LEVELS" | bc -l)
        log "   量子化間隔: $interval (${QUANTIZATION_LEVELS}段階)"
    else
        log "⚠️  警告: 統計値の解析に失敗しました。デフォルト設定を使用します"
        min_value=0
        max_value=255
        interval=$(echo "scale=6; 255 / $QUANTIZATION_LEVELS" | bc -l)
    fi
else
    log "⚠️  警告: 統計情報を取得できませんでした。デフォルト設定を使用します"
    min_value=0
    max_value=255
    interval=$(echo "scale=6; 255 / $QUANTIZATION_LEVELS" | bc -l)
fi

# ステップ3: 量子化処理
log "🔢 ステップ3: Hillshadeの量子化処理中..."
log "設定: ${QUANTIZATION_LEVELS}段階量子化（間隔: $interval）"

# 量子化処理開始時間を記録
start_time=$(date +%s)

# gdal_calcで量子化処理
# 各ピクセル値を量子化レベルに変換する計算式
quantize_expr="(A - $min_value) / $interval"
quantize_expr="maximum(0, minimum($((QUANTIZATION_LEVELS - 1)), round($quantize_expr)))"

docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdal_calc.py \
    -A "$HILLSHADE_FILE" \
    --outfile="$QUANTIZED_FILE" \
    --calc="$quantize_expr" \
    --type=Byte \
    --co TILED=YES --co COMPRESS=LZW --co PREDICTOR=2

# 量子化結果の確認
if [ $? -eq 0 ] && [ -f "$QUANTIZED_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ 量子化処理成功: $QUANTIZED_FILE (処理時間: ${duration}秒)"
    
    # ファイルサイズを表示
    quantized_size=$(du -h "$QUANTIZED_FILE" | cut -f1)
    log "📊 量子化ファイルサイズ: $quantized_size"
    
    # 量子化後の統計を確認
    quantized_stats=$(docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalinfo -stats "$QUANTIZED_FILE" | grep -E "(Minimum|Maximum|Mean|StdDev)")
    if [ -n "$quantized_stats" ]; then
        log "📊 量子化後統計情報:"
        echo "$quantized_stats" | while read line; do
            log "   $line"
        done
    fi
else
    log "❌ エラー: 量子化処理に失敗しました"
    exit 1
fi

# ステップ4-6: ズームレベル別最適化処理
log "🔄 ステップ4-6: ズームレベル別最適化処理を開始"
log "処理対象: ${#ZOOM_CONFIGS[@]} つのズームレベル帯"

# 各ズームレベル設定でベクター化を実行
zoom_count=0
for zoom_range in $(printf '%s\n' "${!ZOOM_CONFIGS[@]}" | sort); do
    zoom_count=$((zoom_count + 1))
    
    # 設定値を分解
    IFS=',' read -r SIEVE_THRESHOLD MAPSHAPER_SIMPLIFY <<< "${ZOOM_CONFIGS[$zoom_range]}"
    
    # ファイル名を設定
    SIEVED_FILE="./dem_3857_hillshade_sieved_${zoom_range}.tif"
    VECTOR_FILE="./dem_3857_hillshade_vector_${zoom_range}.geojson"
    SIMPLIFIED_FILE="./dem_3857_hillshade_vector_simplified_${zoom_range}.geojson"
    
    log ""
    log "🎯 処理中: $zoom_range ($zoom_count/${#ZOOM_CONFIGS[@]})"
    log "   SIEVE_THRESHOLD: $SIEVE_THRESHOLD ピクセル"
    log "   MAPSHAPER_SIMPLIFY: $MAPSHAPER_SIMPLIFY"
    log "   出力ファイル: $(basename "$SIMPLIFIED_FILE")"

    # ステップ4a: 微小ポリゴン削除（gdal_sieve.py）
    log "🔍 ステップ4a-${zoom_range}: 微小ポリゴン削除処理中..."
    
    # フィルタリング処理開始時間を記録
    start_time=$(date +%s)

    # gdal_sieve.pyで微小ポリゴンを削除
    docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdal_sieve.py \
        -st "$SIEVE_THRESHOLD" \
        -8 \
        "$QUANTIZED_FILE" \
        "$SIEVED_FILE"

    # フィルタリング結果の確認
    if [ $? -eq 0 ] && [ -f "$SIEVED_FILE" ]; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log "✅ 微小ポリゴン削除成功: $(basename "$SIEVED_FILE") (処理時間: ${duration}秒)"
        
        # ファイルサイズを表示
        sieved_size=$(du -h "$SIEVED_FILE" | cut -f1)
        log "📊 フィルタリング後ファイルサイズ: $sieved_size"
    else
        log "❌ エラー: 微小ポリゴン削除処理に失敗しました ($zoom_range)"
        continue
    fi

    # ステップ5a: ベクトル化処理
    log "🗺️  ステップ5a-${zoom_range}: ベクトル化処理中..."
    
    # ベクトル化処理開始時間を記録
    start_time=$(date +%s)

    # gdal_polygonize.pyでベクトル化（GeoJSONSeq形式）
    docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdal_polygonize.py \
        -f "GeoJSONSeq" \
        "$SIEVED_FILE" \
        "$VECTOR_FILE" \
        hillshade \
        class

    # ベクトル化結果の確認
    if [ $? -eq 0 ] && [ -f "$VECTOR_FILE" ]; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log "✅ ベクトル化処理成功: $(basename "$VECTOR_FILE") (処理時間: ${duration}秒)"
        
        # ファイルサイズを表示
        vector_size=$(du -h "$VECTOR_FILE" | cut -f1)
        log "📊 ベクターファイルサイズ: $vector_size"
        
        # フィーチャー数を取得
        total_features=$(cat "$VECTOR_FILE" | wc -l)
        log "📄 フィーチャー数: $total_features"
    else
        log "❌ エラー: ベクトル化処理に失敗しました ($zoom_range)"
        continue
    fi

    # ステップ6a: ジオメトリ簡略化（mapshaper）
    log "🎛️  ステップ6a-${zoom_range}: ジオメトリ簡略化処理中..."
    
    # 簡略化処理開始時間を記録
    start_time=$(date +%s)

    # mapshaperの存在確認（初回のみ）
    if [ $zoom_count -eq 1 ] && ! command -v mapshaper &> /dev/null; then
        log "⚠️  警告: mapshaperが見つかりません。npmでインストールを試行します..."
        if command -v npm &> /dev/null; then
            npm install -g mapshaper
            if [ $? -ne 0 ]; then
                log "❌ エラー: mapshaperのインストールに失敗しました"
                exit 1
            fi
        else
            log "❌ エラー: npmが見つかりません。mapshaperを手動でインストールしてください"
            exit 1
        fi
    fi

    # GeoJSONSeq形式を標準GeoJSON形式に変換してから簡略化
    temp_geojson="./temp_hillshade_vector_${zoom_range}.geojson"
    
    # GeoJSONSeq を標準GeoJSONに変換
    echo '{"type":"FeatureCollection","features":[' > "$temp_geojson"
    cat "$VECTOR_FILE" | sed 's/$/,/' | sed '$ s/,$//' >> "$temp_geojson"
    echo ']}' >> "$temp_geojson"

    if [ ! -f "$temp_geojson" ]; then
        log "❌ エラー: GeoJSON変換に失敗しました ($zoom_range)"
        continue
    fi

    # mapshaperで簡略化実行
    mapshaper "$temp_geojson" \
        -simplify "$MAPSHAPER_SIMPLIFY" keep-shapes \
        -clean \
        -o format=geojson "$SIMPLIFIED_FILE"

    # 一時ファイルを削除
    rm -f "$temp_geojson"

    # 簡略化結果の確認
    if [ $? -eq 0 ] && [ -f "$SIMPLIFIED_FILE" ]; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log "✅ ジオメトリ簡略化成功: $(basename "$SIMPLIFIED_FILE") (処理時間: ${duration}秒)"
        
        # ファイルサイズを表示
        simplified_size=$(du -h "$SIMPLIFIED_FILE" | cut -f1)
        log "📊 簡略化後ファイルサイズ: $simplified_size"
        
        # 簡略化前後のサイズ比較
        vector_size_mb=$(du -m "$VECTOR_FILE" | cut -f1)
        simplified_size_mb=$(du -m "$SIMPLIFIED_FILE" | cut -f1)
        if [ "$vector_size_mb" -gt 0 ]; then
            size_reduction=$((100 - (simplified_size_mb * 100 / vector_size_mb)))
            log "📊 ファイルサイズ削減: ${size_reduction}% (${vector_size_mb}MB → ${simplified_size_mb}MB)"
        fi
        
        # 簡略化後の統計情報（jqが利用可能な場合）
        if command -v jq &> /dev/null; then
            simplified_features=$(jq '.features | length' "$SIMPLIFIED_FILE" 2>/dev/null)
            if [ -n "$simplified_features" ]; then
                log "📊 簡略化後フィーチャー数: $simplified_features"
                
                # フィーチャー削減率
                if [ "$total_features" -gt 0 ]; then
                    feature_reduction=$((100 - (simplified_features * 100 / total_features)))
                    log "📊 フィーチャー削減率: ${feature_reduction}% ($total_features → $simplified_features)"
                fi
            fi
        fi
        
        # 標準GeoJSONからGeoJSONSeqに再変換
        final_output="./dem_3857_hillshade_vector_final_${zoom_range}.geojson"
        jq -c '.features[]' "$SIMPLIFIED_FILE" > "$final_output" 2>/dev/null
        
        if [ -f "$final_output" ]; then
            mv "$final_output" "$SIMPLIFIED_FILE"
            log "✅ GeoJSONSeq形式に変換完了"
        else
            log "⚠️  警告: GeoJSONSeq変換に失敗。標準GeoJSON形式で保持"
        fi
        
        log "✅ $zoom_range 処理完了"
    else
        log "❌ エラー: ジオメトリ簡略化処理に失敗しました ($zoom_range)"
        continue
    fi
done

log ""
log "🎉 全ズームレベル処理完了!"
log ""
log "📋 最終結果:"
log "   入力ファイル: $INPUT_FILE ($file_size)"
log "   Hillshadeファイル: $HILLSHADE_FILE ($hillshade_size)"
log "   量子化ファイル: $QUANTIZED_FILE ($quantized_size)"
log "   量子化レベル: ${QUANTIZATION_LEVELS}段階"
log ""
log "📊 ズームレベル別出力ファイル:"
for zoom_range in $(printf '%s\n' "${!ZOOM_CONFIGS[@]}" | sort); do
    simplified_file="./dem_3857_hillshade_vector_simplified_${zoom_range}.geojson"
    if [ -f "$simplified_file" ]; then
        file_size=$(du -h "$simplified_file" | cut -f1)
        log "   $zoom_range: $(basename "$simplified_file") ($file_size)"
    else
        log "   $zoom_range: ❌ 作成失敗"
    fi
done
log ""
log "ログファイル: $LOG_FILE"