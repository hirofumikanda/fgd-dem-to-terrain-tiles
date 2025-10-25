#!/bin/bash

# 変数設定
SRC_DIR="./fgd"
DST_DIR="./xml"

# ログディレクトリ作成
mkdir -p "./logs"

# ログ設定
LOG_FILE="./logs/extract_dem10b_$(date +%Y%m%d_%H%M%S).log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 DEM10B ZIP解凍処理を開始します"
log "入力ディレクトリ: $SRC_DIR"
log "出力ディレクトリ: $DST_DIR"

# 入力ディレクトリの存在確認
if [ ! -d "$SRC_DIR" ]; then
    log "❌ エラー: 入力ディレクトリが存在しません: $SRC_DIR"
    exit 1
fi

log "✅ 入力ディレクトリを確認しました"

# 出力先ディレクトリを作成（存在しない場合）
mkdir -p "$DST_DIR"
if [ $? -eq 0 ]; then
    log "✅ 出力ディレクトリを準備しました: $DST_DIR"
else
    log "❌ エラー: 出力ディレクトリの作成に失敗しました"
    exit 1
fi

# 対象ZIPファイルをカウント
zip_count=$(find "$SRC_DIR" -type f -name "*DEM10B.zip" | wc -l)
if [ "$zip_count" -eq 0 ]; then
    log "❌ エラー: DEM10B.zipファイルが見つかりません"
    exit 1
fi

log "🔍 $zip_count 個のDEM10B.zipファイルが見つかりました"

# 処理済み/エラーカウンター
processed_count=0
error_count=0

# find で対象ZIPファイルを再帰的に検索し処理
find "$SRC_DIR" -type f -name "*DEM10B.zip" | while read -r zipfile; do
    log "📦 解凍中: $(basename "$zipfile")"
    
    # 一時作業用ディレクトリを作成
    tmpdir=$(mktemp -d)
    if [ $? -ne 0 ]; then
        log "❌ エラー: 一時ディレクトリの作成に失敗: $zipfile"
        error_count=$((error_count + 1))
        continue
    fi
    
    # 解凍
    unzip -q "$zipfile" -d "$tmpdir"
    if [ $? -eq 0 ]; then
        # 解凍した中にある .xml ファイルを出力先にコピー
        xml_files=$(find "$tmpdir" -type f -name "*.xml")
        if [ -n "$xml_files" ]; then
            find "$tmpdir" -type f -name "*.xml" -exec cp {} "$DST_DIR" \;
            if [ $? -eq 0 ]; then
                xml_count=$(echo "$xml_files" | wc -l)
                log "✅ 成功: $(basename "$zipfile") (XMLファイル: $xml_count)"
                processed_count=$((processed_count + 1))
            else
                log "❌ エラー: XMLファイルのコピーに失敗: $zipfile"
                error_count=$((error_count + 1))
            fi
        else
            log "⚠️  警告: XMLファイルが見つかりません: $zipfile"
        fi
    else
        log "❌ エラー: ZIP解凍に失敗: $zipfile"
        error_count=$((error_count + 1))
    fi
    
    # 一時ディレクトリを削除
    rm -rf "$tmpdir"
done

# 結果の確認
xml_output_count=$(find "$DST_DIR" -type f -name "*.xml" | wc -l)
log "📊 処理結果:"
log "   処理対象ZIPファイル: $zip_count"
log "   出力XMLファイル数: $xml_output_count"

if [ "$xml_output_count" -gt 0 ]; then
    log "🎉 完了しました。$DST_DIR にDEM10BのXMLが配置されました。"
    log "ログファイル: $LOG_FILE"
else
    log "❌ エラー: XMLファイルが出力されませんでした"
    exit 1
fi
