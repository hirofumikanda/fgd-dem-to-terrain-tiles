#!/bin/bash

# 変数設定
XML_DIR="./xml"
TIFF_DIR="./tiff"

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/create_geotiff_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 GeoTIFF作成処理を開始します"
log "入力ディレクトリ: $XML_DIR"
log "出力ディレクトリ: $TIFF_DIR"

# 入力ディレクトリの存在確認
if [ ! -d "$XML_DIR" ]; then
    log "❌ エラー: 入力ディレクトリが存在しません: $XML_DIR"
    exit 1
fi

log "✅ 入力ディレクトリを確認しました"

# fgddemコマンドの存在確認
if ! command -v fgddem &> /dev/null; then
    log "❌ エラー: fgddemコマンドが見つかりません"
    exit 1
fi

# 出力先ディレクトリを作成（存在しない場合）
mkdir -p "$TIFF_DIR"
if [ $? -eq 0 ]; then
    log "✅ 出力ディレクトリを準備しました: $TIFF_DIR"
else
    log "❌ エラー: 出力ディレクトリの作成に失敗しました"
    exit 1
fi

# 対象XMLファイルをカウント
xml_count=$(find "$XML_DIR" -type f -name "*.xml" | wc -l)
if [ "$xml_count" -eq 0 ]; then
    log "❌ エラー: XMLファイルが見つかりません"
    exit 1
fi

log "🔍 $xml_count 個のXMLファイルが見つかりました"

# 処理済み/エラーカウンター
processed_count=0
error_count=0

# XMLディレクトリ内のすべてのXMLファイルを処理
find "$XML_DIR" -type f -name "*.xml" | while read -r xmlfile; do
    log "🗺️  処理中: $(basename "$xmlfile")"
    
    # 処理開始時間を記録
    start_time=$(date +%s)
    
    # fgddemコマンドを実行してGeoTIFFファイルを作成
    fgddem "$xmlfile" "$TIFF_DIR/"
    
    if [ $? -eq 0 ]; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log "✅ 成功: $(basename "$xmlfile") (処理時間: ${duration}秒)"
        processed_count=$((processed_count + 1))
        
        # 作成されたTIFFファイルを確認
        tiff_files=$(find "$TIFF_DIR" -name "*.tif" -newer "$xmlfile" 2>/dev/null)
        if [ -n "$tiff_files" ]; then
            tiff_count=$(echo "$tiff_files" | wc -l)
            log "   作成されたTIFFファイル: $tiff_count"
        fi
    else
        log "❌ エラー: $(basename "$xmlfile")"
        error_count=$((error_count + 1))
    fi
done

# 最終結果の確認
tiff_output_count=$(find "$TIFF_DIR" -type f -name "*.tif" | wc -l)
tiff_dir_size=$(du -sh "$TIFF_DIR" | cut -f1)

log "📊 処理結果:"
log "   処理対象XMLファイル: $xml_count"
log "   成功: $processed_count"
log "   エラー: $error_count"
log "   出力TIFFファイル数: $tiff_output_count"
log "   出力ディレクトリサイズ: $tiff_dir_size"

if [ "$tiff_output_count" -gt 0 ]; then
    log "🎉 すべてのXMLファイルからGeoTIFFファイルの作成が完了しました。"
    log "出力先: $TIFF_DIR"
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: TIFFファイルが作成されませんでした"
    exit 1
fi