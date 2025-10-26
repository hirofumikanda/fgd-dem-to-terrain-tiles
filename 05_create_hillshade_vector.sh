#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857.tif"
HILLSHADE_FILE="./dem_3857_hillshade.tif"
QUANTIZED_FILE="./dem_3857_hillshade_quantized.tif"
VECTOR_FILE="./dem_3857_hillshade_vector.geojson"

# 量子化設定（変更可能）
QUANTIZATION_LEVELS=5  # 256段階を5段階に量子化（変更可能）

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/create_hillshade_vector_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Hillshadeベクトル化処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "Hillshadeファイル: $HILLSHADE_FILE"
log "量子化ファイル: $QUANTIZED_FILE"
log "ベクターファイル: $VECTOR_FILE"
log "量子化レベル: $QUANTIZATION_LEVELS段階"

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 既存ファイルを削除（存在する場合）
for file in "$HILLSHADE_FILE" "$QUANTIZED_FILE" "$VECTOR_FILE"; do
    if [ -f "$file" ]; then
        log "🗑️  既存ファイルを削除: $(basename "$file")"
        rm -f "$file"
        if [ $? -ne 0 ]; then
            log "❌ エラー: 既存ファイルの削除に失敗しました: $(basename "$file")"
            exit 1
        fi
    fi
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

# ステップ4: ベクトル化処理
log "🗺️  ステップ4: ベクトル化処理中..."
log "設定: class属性で分類、GeoJSONSeq形式出力"

# ベクトル化処理開始時間を記録
start_time=$(date +%s)

# gdal_polygonize.pyでベクトル化（GeoJSONSeq形式）
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdal_polygonize.py \
    -f "GeoJSONSeq" \
    "$QUANTIZED_FILE" \
    "$VECTOR_FILE" \
    hillshade \
    class

# ベクトル化結果の確認
if [ $? -eq 0 ] && [ -f "$VECTOR_FILE" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ ベクトル化処理成功: $VECTOR_FILE (処理時間: ${duration}秒)"
    
    # ファイルサイズを表示
    vector_size=$(du -h "$VECTOR_FILE" | cut -f1)
    log "📊 ベクターファイルサイズ: $vector_size"
    
    # ベクターファイルの統計情報を取得
    log "📄 ベクターファイル統計情報:"
    total_features=$(cat "$VECTOR_FILE" | wc -l)
    log "   総フィーチャー数: $total_features"
    
    # クラス別統計（jqが利用可能な場合）
    if command -v jq &> /dev/null; then
        log "📊 クラス別統計:"
        cat "$VECTOR_FILE" | jq -r '.properties.class' 2>/dev/null | sort | uniq -c | while read count class; do
            log "   クラス $class: $count フィーチャー"
        done
        
        # サンプルフィーチャーを表示
        log "   サンプルフィーチャー（最初の1件）:"
        head -1 "$VECTOR_FILE" | jq -c . 2>/dev/null | head -c 200 | while read line; do
            log "     $line..."
        done
    else
        # jqが利用できない場合、基本的な統計のみ
        log "   ファイル形式確認（最初の2行）:"
        head -2 "$VECTOR_FILE" | while read line; do
            log "     $(echo "$line" | head -c 150)..."
        done
    fi
    
    # GeoJSONSeq形式の確認
    first_line=$(head -1 "$VECTOR_FILE")
    if echo "$first_line" | grep -q '"type":"Feature"'; then
        log "✅ GeoJSONSeq形式（NDJSON）で正しく出力されました"
    else
        log "⚠️  警告: GeoJSONSeq形式ではない可能性があります"
    fi
    
    # 中間ファイルのクリーンアップ確認
    log "🧹 中間ファイルの保持状況:"
    log "   Hillshade: $HILLSHADE_FILE ($hillshade_size) - 保持"
    log "   量子化済み: $QUANTIZED_FILE ($quantized_size) - 保持"
    log "   ※中間ファイルは検証用に保持されます"
    
    log "🎉 全処理完了!"
    log ""
    log "📋 最終結果:"
    log "   入力ファイル: $INPUT_FILE ($file_size)"
    log "   Hillshadeファイル: $HILLSHADE_FILE ($hillshade_size)"
    log "   量子化ファイル: $QUANTIZED_FILE ($quantized_size)"
    log "   ベクターファイル: $VECTOR_FILE ($vector_size)"
    log "   量子化レベル: ${QUANTIZATION_LEVELS}段階"
    log "   総フィーチャー数: $total_features"
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: ベクトル化処理に失敗しました"
    exit 1
fi