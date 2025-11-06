#!/bin/bash

# DEM標高データからテキストタイル生成スクリプト
# 
# 使用方法:
#   ./05_create_tiles_dem_text.sh
#
# 環境変数で並列処理数を調整可能:
#   DEM_TEXT_PROCESSES=6 ./05_create_tiles_dem_text.sh
#
# 特徴:
#   - z14から開始してピラミッド構築で効率化
#   - マルチプロセッシングでz14の重い処理を高速化
#   - 自動CPU数検出（CPU数の75%、最低2、最大8）
#   - japan_target_tileids.csvで指定されたタイルのみ処理

# 変数設定
INPUT_FILE="./dem_3857.tif"
CLEANED_FILE="./dem_3857_cleaned.tif"
OUTPUT_DIR="./tiles_elevation"
MAX_ZOOM=14
MIN_ZOOM=0
TILE_SIZE=256
TARGET_TILES_CSV="./japan_target_tileids.csv"  # 対象タイルIDのCSVファイル

# 並列処理数を自動計算（CPU数の75%、最低2、最大8）
AVAILABLE_CPUS=$(nproc 2>/dev/null || echo "4")
PROCESSES=$(( (AVAILABLE_CPUS * 3 + 3) / 4 ))  # 75%を計算
PROCESSES=$(( PROCESSES < 2 ? 2 : PROCESSES ))  # 最低2
PROCESSES=$(( PROCESSES > 8 ? 8 : PROCESSES ))  # 最大8

# 環境変数で上書き可能
if [ ! -z "$DEM_TEXT_PROCESSES" ]; then
    PROCESSES="$DEM_TEXT_PROCESSES"
fi

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/dem_text_tiles_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 DEM テキストタイル生成処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "修正ファイル: $CLEANED_FILE"
log "出力ディレクトリ: $OUTPUT_DIR"
log "ズームレベル: $MIN_ZOOM-$MAX_ZOOM"
log "タイルサイズ: ${TILE_SIZE}x${TILE_SIZE}"
log "並列処理数: $PROCESSES (利用可能CPU: $AVAILABLE_CPUS)"
log "対象タイルCSV: $TARGET_TILES_CSV"

# 入力ファイルの存在確認
if [ ! -f "$INPUT_FILE" ]; then
    log "❌ エラー: 入力ファイルが存在しません: $INPUT_FILE"
    exit 1
fi

log "✅ 入力ファイルを確認しました"

# 既存の修正ファイルを削除（存在する場合）
if [ -f "$CLEANED_FILE" ]; then
    log "🗑️  既存の修正ファイルを削除: $CLEANED_FILE"
    rm -f "$CLEANED_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存修正ファイルの削除に失敗しました"
        exit 1
    fi
fi

# 既存の出力ディレクトリを削除（存在する場合）
if [ -d "$OUTPUT_DIR" ]; then
    log "🗑️  既存の出力ディレクトリを削除: $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存出力ディレクトリの削除に失敗しました"
        exit 1
    fi
fi

# 出力ディレクトリ作成
mkdir -p "$OUTPUT_DIR"
if [ $? -ne 0 ]; then
    log "❌ エラー: 出力ディレクトリの作成に失敗しました"
    exit 1
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

# テキストタイル生成スクリプトの存在確認
PYTHON_SCRIPT="./generate_text_tiles.py"
if [ ! -f "$PYTHON_SCRIPT" ]; then
    log "❌ エラー: テキストタイル生成スクリプトが存在しません: $PYTHON_SCRIPT"
    exit 1
fi

# 対象タイルCSVファイルの存在確認
if [ ! -f "$TARGET_TILES_CSV" ]; then
    log "❌ エラー: 対象タイルCSVファイルが存在しません: $TARGET_TILES_CSV"
    exit 1
fi

log "✅ テキストタイル生成スクリプトを確認しました: $PYTHON_SCRIPT"
log "✅ 対象タイルCSVファイルを確認しました: $TARGET_TILES_CSV"

# ピラミッド方式でテキストタイル生成を実行
log "🗺️  ピラミッド方式でテキストタイル生成中..."
log "ズームレベル ${MIN_ZOOM} から ${MAX_ZOOM} まで処理します"
log "🔥 効率化: z${MAX_ZOOM}から開始してリサンプリングでピラミッド構築"
log "⚡ 並列処理: ${PROCESSES}プロセスで高速化"
log "🎯 対象タイル: CSVファイルで指定されたタイルのみ処理"

docker run --rm \
    -v "$PWD":/work \
    -w /work \
    ghcr.io/osgeo/gdal:alpine-normal-latest \
    sh -c "
    apk add --no-cache python3 py3-pip py3-numpy py3-scipy && \
    python3 $PYTHON_SCRIPT '$CLEANED_FILE' '$OUTPUT_DIR' $MIN_ZOOM $MAX_ZOOM $TILE_SIZE $PROCESSES '$TARGET_TILES_CSV'
    "

# 生成結果の確認
if [ $? -eq 0 ]; then
    log "✅ ピラミッド方式テキストタイル生成成功"
    
    # CSVファイルの対象タイル統計を表示
    if [ -f "$TARGET_TILES_CSV" ]; then
        csv_total=$(tail -n +2 "$TARGET_TILES_CSV" | wc -l)
        log "📄 対象タイル数（CSV指定）: $csv_total"
        
        # ズームレベル別の対象タイル数
        log "📊 対象タイル数（ズームレベル別）:"
        for zoom in $(seq $MIN_ZOOM $MAX_ZOOM); do
            csv_zoom_tiles=$(tail -n +2 "$TARGET_TILES_CSV" | awk -F',' -v z=$zoom '$1==z' | wc -l)
            if [ $csv_zoom_tiles -gt 0 ]; then
                log "   z$zoom: $csv_zoom_tiles タイル（対象）"
            fi
        done
    fi
    
    # 実際に生成されたタイル数を確認
    log "📊 実際に生成されたタイル数（ズームレベル別）:"
    for zoom in $(seq $MIN_ZOOM $MAX_ZOOM); do
        if [ -d "$OUTPUT_DIR/$zoom" ]; then
            zoom_tiles=$(find "$OUTPUT_DIR/$zoom" -name "*.txt" 2>/dev/null | wc -l)
            log "   z$zoom: $zoom_tiles タイル（生成済み）"
        fi
    done
    
    # 全体のタイル数を確認
    total_tiles=$(find "$OUTPUT_DIR" -name "*.txt" | wc -l)
    log "📊 総生成タイル数: $total_tiles"
    
    # ディレクトリサイズを表示
    dir_size=$(du -sh "$OUTPUT_DIR" | cut -f1)
    log "📊 出力ディレクトリサイズ: $dir_size"
    
    # 高ズームレベル（z14）の処理が大幅に高速化されたことを示す
    if [ $MAX_ZOOM -ge 14 ]; then
        z14_tiles=$(find "$OUTPUT_DIR/14" -name "*.txt" 2>/dev/null | wc -l)
        if [ $z14_tiles -gt 0 ]; then
            log "⚡ z14高解像度タイル: $z14_tiles タイル（${PROCESSES}プロセス並列処理で高速化）"
        fi
    fi
    
    log "🎯 対象タイル限定処理により大幅な処理時間短縮を実現"
    log "🎉 ピラミッド方式処理完了!"
    log "ログファイル: $LOG_FILE"
    
else
    log "❌ エラー: ピラミッド方式テキストタイル生成に失敗しました"
    exit 1
fi