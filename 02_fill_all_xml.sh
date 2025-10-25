#!/bin/bash

# 変数設定
INPUT_DIR="./xml"
PYTHON_SCRIPT="./fill_dem_tuples.py"

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/fill_xml_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 XML fill_dem_tuples処理を開始します"
log "入力ディレクトリ: $INPUT_DIR"
log "Pythonスクリプト: $PYTHON_SCRIPT"

# 入力ディレクトリの存在確認
if [ ! -d "$INPUT_DIR" ]; then
    log "❌ エラー: 入力ディレクトリが存在しません: $INPUT_DIR"
    exit 1
fi

# Pythonスクリプトの存在確認
if [ ! -f "$PYTHON_SCRIPT" ]; then
    log "❌ エラー: Pythonスクリプトが存在しません: $PYTHON_SCRIPT"
    exit 1
fi

log "✅ 必要なファイルを確認しました"

# Python3の存在確認
if ! command -v python3 &> /dev/null; then
    log "❌ エラー: python3が見つかりません"
    exit 1
fi

# 対象XMLファイルをカウント
xml_count=$(find "$INPUT_DIR" -type f -name "*.xml" | wc -l)
if [ "$xml_count" -eq 0 ]; then
    log "❌ エラー: XMLファイルが見つかりません"
    exit 1
fi

log "🔍 $xml_count 個のXMLファイルが見つかりました"

# 処理済み/エラーカウンター
processed_count=0
error_count=0

# XML ファイルをすべて処理
find "$INPUT_DIR" -type f -name "*.xml" | while read -r xmlfile; do
    log "🔧 処理中: $(basename "$xmlfile")"
    
    # バックアップ作成（オプション）
    backup_file="${xmlfile}.backup"
    cp "$xmlfile" "$backup_file"
    
    if [ $? -eq 0 ]; then
        log "💾 バックアップ作成: $(basename "$backup_file")"
    else
        log "⚠️  警告: バックアップ作成に失敗: $(basename "$xmlfile")"
    fi
    
    # fill_dem_tuples.pyを実行
    python3 "$PYTHON_SCRIPT" "$xmlfile" "$xmlfile"
    
    if [ $? -eq 0 ]; then
        log "✅ 成功: $(basename "$xmlfile")"
        processed_count=$((processed_count + 1))
        
        # バックアップファイルを削除（成功時）
        rm -f "$backup_file"
    else
        log "❌ エラー: $(basename "$xmlfile")"
        error_count=$((error_count + 1))
        
        # エラー時はバックアップから復元
        if [ -f "$backup_file" ]; then
            mv "$backup_file" "$xmlfile"
            log "🔄 バックアップから復元: $(basename "$xmlfile")"
        fi
    fi
done

log "📊 処理結果:"
log "   処理対象XMLファイル: $xml_count"
log "   成功: $processed_count"
log "   エラー: $error_count"

if [ "$error_count" -eq 0 ]; then
    log "🎉 すべてのXMLに fill_dem_tuples.py を適用しました。"
    log "ログファイル: $LOG_FILE"
else
    log "⚠️  一部のファイルでエラーが発生しました"
    exit 1
fi
