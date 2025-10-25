#!/bin/bash

# 変数設定
INPUT_FILE="./dem_3857_terrainrgb.tif"
TILES_DIR="./tiles_terrainrgb"
MBTILES_FILE="./dem_3857_terrainrgb.mbtiles"
PMTILES_FILE="./dem_3857_terrainrgb.pmtiles"

# gdal2tiles設定
ZOOM_LEVELS="0-14"
RESAMPLING="near"
IMAGE_FORMAT="png"
PROCESSES=6

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/tiles_terrainrgb_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 タイル生成処理を開始します"
log "入力ファイル: $INPUT_FILE"
log "タイルディレクトリ: $TILES_DIR"
log "MBTilesファイル: $MBTILES_FILE"
log "PMTilesファイル: $PMTILES_FILE"

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

# 既存の端のタイルリストファイルを削除（存在する場合）
EDGE_TILES_FILE="./edge_tiles.txt"
if [ -f "$EDGE_TILES_FILE" ]; then
    log "🗑️  既存の端のタイルリストファイルを削除: $EDGE_TILES_FILE"
    rm -f "$EDGE_TILES_FILE"
    if [ $? -ne 0 ]; then
        log "❌ エラー: 既存端のタイルリストファイルの削除に失敗しました"
        exit 1
    fi
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

log "🔧 タイル生成中..."
log "設定: ズームレベル=$ZOOM_LEVELS, リサンプリング=$RESAMPLING, プロセス数=$PROCESSES"

# gdal2tiles.pyでタイルを生成
start_time=$(date +%s)
docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdal2tiles.py \
    "$INPUT_FILE" "$TILES_DIR" \
    -z"$ZOOM_LEVELS" --resampling="$RESAMPLING" \
    --xyz --processes="$PROCESSES"

# タイル生成結果の確認
if [ $? -eq 0 ] && [ -d "$TILES_DIR" ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ タイル生成成功: $TILES_DIR"
    log "⏱️  生成時間: ${duration}秒"
    
    # タイル数を確認
    tile_count=$(find "$TILES_DIR" -name "*.png" | wc -l)
    log "📊 生成されたタイル数: $tile_count"
    
    # ディレクトリサイズを確認
    tiles_size=$(du -sh "$TILES_DIR" | cut -f1)
    log "📊 タイルディレクトリサイズ: $tiles_size"
    
    # INPUT_FILEの四隅の座標を取得してタイル座標を算出
    log "🗺️  INPUT_FILEの境界を取得してタイル座標を算出中..."
    
    # 端のタイルリストファイルのパスを定義
    EDGE_TILES_FILE="./edge_tiles.txt"
    
    # gdalinfoを使用してファイルの境界情報を取得（数値形式で取得）
    GDALINFO_OUTPUT=$(docker run --rm -v "$PWD":/work -w /work ghcr.io/osgeo/gdal:alpine-normal-latest gdalinfo "$INPUT_FILE")
    
    # 数値形式の座標を抽出（EPSG:3857 - Web Mercator）
    MIN_X=$(echo "$GDALINFO_OUTPUT" | grep "Upper Left" | sed -n 's/.*(\s*\([0-9.-]*\),.*/\1/p' | tr -d ' ')
    MAX_Y=$(echo "$GDALINFO_OUTPUT" | grep "Upper Left" | sed -n 's/.*,\s*\([0-9.-]*\)).*/\1/p' | tr -d ' ')
    MAX_X=$(echo "$GDALINFO_OUTPUT" | grep "Lower Right" | sed -n 's/.*(\s*\([0-9.-]*\),.*/\1/p' | tr -d ' ')
    MIN_Y=$(echo "$GDALINFO_OUTPUT" | grep "Lower Right" | sed -n 's/.*,\s*\([0-9.-]*\)).*/\1/p' | tr -d ' ')
    
    log "📍 境界座標（EPSG:3857 - Web Mercator）:"
    log "   X範囲: $MIN_X ～ $MAX_X"
    log "   Y範囲: $MIN_Y ～ $MAX_Y"
    
    # Web Mercator座標からタイル座標への変換をPythonスクリプトで実行
    EDGE_TILES=$(docker run --rm -v "$PWD":/work -w /work python:3.9-slim python3 calculate_edge_tiles.py \
        --min-x "$MIN_X" --min-y "$MIN_Y" --max-x "$MAX_X" --max-y "$MAX_Y" --zoom-range "$ZOOM_LEVELS")
    
    # 端のタイル数を確認
    edge_tile_count=$(echo "$EDGE_TILES" | wc -l)
    log "📊 端のタイル数: $edge_tile_count"
    log "🎯 端のタイル例: $(echo "$EDGE_TILES" | head -5 | tr '\n' ' ')..."
    
    # 透過部分を背景色で塗りつぶす処理
    log "🎨 端のタイルの透過部分塗りつぶし処理を開始..."
    log "背景色: RGB(1,134,160)"
    
    start_time=$(date +%s)
    
    # 端のタイルリストをカレントディレクトリに保存
    echo "$EDGE_TILES" > "$EDGE_TILES_FILE"
    log "📄 端のタイルリストを保存: $EDGE_TILES_FILE"
    
    # ImageMagickのDockerイメージを使用して端のタイルの透過部分を塗りつぶし
    # Ubuntu基盤のイメージを使用してシェルコマンドを実行
    docker run --rm -v "$PWD/$TILES_DIR":/tiles -v "$PWD/$EDGE_TILES_FILE":/edge_tiles.txt -w /tiles --entrypoint="" dpokidov/imagemagick:7.1.0-62-ubuntu \
        bash -c '
        # 端のタイルのみを処理
        while read -r tile_path; do
            file="./${tile_path}.png"
            if [ -f "$file" ]; then
                # 透過部分を背景色で塗りつぶし（RGB(1,134,160) = #0186A0）
                magick "$file" -background "#0186A0" -alpha remove -alpha off "$file"
            fi
        done < /edge_tiles.txt
        '
    
    if [ $? -eq 0 ]; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log "✅ 端のタイルの透過部分塗りつぶし処理完了"
        log "⏱️  処理時間: ${duration}秒"
        log "📊 処理されたタイル数: $edge_tile_count"
        
        # 処理後のディレクトリサイズを再確認
        tiles_size_after=$(du -sh "$TILES_DIR" | cut -f1)
        log "📊 処理後タイルディレクトリサイズ: $tiles_size_after"
        
    else
        log "❌ エラー: 透過部分塗りつぶし処理に失敗しました"
        rm -f "$EDGE_TILES_FILE"
        exit 1
    fi
else
    log "❌ エラー: タイル生成に失敗しました"
    exit 1
fi

log "📦 MBTiles形式に変換中..."
log "設定: 画像フォーマット=$IMAGE_FORMAT"

# mb-utilでMBTiles形式に変換
start_time=$(date +%s)
mb-util --image_format="$IMAGE_FORMAT" "$TILES_DIR/" "$MBTILES_FILE"

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
    
    log "🎉 処理完了!"
    log "ログファイル: $LOG_FILE"
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
log "   タイルディレクトリ: $TILES_DIR ($tiles_size, $tile_count tiles)"
log "   MBTilesファイル: $MBTILES_FILE ($mbtiles_size)"
log "   PMTilesファイル: $PMTILES_FILE ($pmtiles_size)"