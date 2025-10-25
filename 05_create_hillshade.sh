#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857.tif"
HILLSHADE_FILE="./dem_3857_hillshade.tif"

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/create_hillshade_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 Hillshade作成処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "Hillshadeファイル: $HILLSHADE_FILE"

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 既存のhillshadeファイルを削除（存在する場合）
if [ -f "$HILLSHADE_FILE" ]; then
    log "🗑️  既存のhillshadeファイルを削除: $HILLSHADE_FILE"
    rm -f "$HILLSHADE_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存hillshadeファイルの削除に失敗しました"
        exit 1
    fi
fi

# 入力ファイルの基本情報を取得
log "📊 入力ファイル情報:"
file_size=$(du -h "$INPUT_FILE" | cut -f1)
log "   ファイルサイズ: $file_size"

log "🏔️  Hillshade生成中..."
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
    
    log "🎉 処理完了!"
    log "   Hillshadeファイル: $HILLSHADE_FILE ($hillshade_size)"
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: Hillshade生成に失敗しました"
    exit 1
fi