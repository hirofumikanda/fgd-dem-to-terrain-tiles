#!/bin/bash

# Hillshade Vector パイプラインスクリプト - DEM10BからHillshade ベクタータイルまでの全工程を実行
# 作成日: $(date +%Y-%m-%d)

# 変数設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="./logs"
MASTER_LOG_FILE="$LOG_DIR/master_hillshade_vector_$(date +%Y%m%d_%H%M%S).log"

# スクリプトリスト（実行順）
SCRIPTS=(
    "01_extract_dem10b.sh"
    "02_fill_all_xml.sh" 
    "03_create_geotiff.sh"
    "04_merge_and_reproject.sh"
    "05_create_hillshade_vector.sh"
    "06_create_tiles_hillshade_vector.sh"
)

SCRIPT_DESCRIPTIONS=(
    "DEM10B ZIPファイルの解凍・XML抽出"
    "XMLファイルのfill_dem_tuples処理"
    "XMLからGeoTIFFファイル作成"
    "TIFFファイルの統合・投影変換"
    "Hillshade生成・量子化・ベクトル化"
    "ベクタータイル・MBTiles・PMTiles作成"
)

# ログディレクトリ作成
mkdir -p "$LOG_DIR"

# マスターログ関数
master_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MASTER_LOG_FILE"
}

# 実行時間計算関数
format_duration() {
    local duration=$1
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}時間${minutes}分${seconds}秒"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}分${seconds}秒"
    else
        echo "${seconds}秒"
    fi
}

# スクリプト存在確認
check_scripts() {
    master_log "📋 スクリプトファイルの存在確認..."
    local missing_scripts=0
    
    for script in "${SCRIPTS[@]}"; do
        if [ ! -f "$script" ]; then
            master_log "❌ エラー: スクリプトが見つかりません: $script"
            missing_scripts=$((missing_scripts + 1))
        elif [ ! -x "$script" ]; then
            master_log "⚠️  警告: 実行権限がありません: $script"
            chmod +x "$script"
            if [ $? -eq 0 ]; then
                master_log "✅ 実行権限を付与しました: $script"
            else
                master_log "❌ エラー: 実行権限の付与に失敗: $script"
                missing_scripts=$((missing_scripts + 1))
            fi
        else
            master_log "✅ 確認済み: $script"
        fi
    done
    
    if [ $missing_scripts -gt 0 ]; then
        master_log "❌ $missing_scripts 個のスクリプトに問題があります"
        exit 1
    fi
    
    master_log "✅ すべてのスクリプトが利用可能です"
}

# 実行前確認
pre_execution_check() {
    local start_step=$1
    master_log "🔍 実行前チェック..."
    
    # ステップ1から開始する場合のチェック
    if [ $start_step -eq 1 ]; then
        # 必要なディレクトリ確認
        if [ ! -d "./fgd" ]; then
            master_log "❌ エラー: ./fgd ディレクトリが存在しません"
            master_log "   DEM10B ZIPファイルを配置してください"
            exit 1
        fi
        
        # ZIPファイル確認
        zip_count=$(find "./fgd" -name "*DEM10B.zip" | wc -l)
        if [ $zip_count -eq 0 ]; then
            master_log "❌ エラー: DEM10B.zipファイルが見つかりません"
            exit 1
        fi
        
        master_log "✅ $zip_count 個のDEM10B.zipファイルを確認"
    fi
    
    # ステップ2から開始する場合のチェック
    if [ $start_step -eq 2 ]; then
        if [ ! -d "./xml" ] || [ $(find "./xml" -name "*.xml" | wc -l) -eq 0 ]; then
            master_log "❌ エラー: XMLファイルが見つかりません（ステップ1が未実行）"
            exit 1
        fi
        master_log "✅ XMLファイルを確認（$(find "./xml" -name "*.xml" | wc -l)個）"
    fi
    
    # ステップ3から開始する場合のチェック
    if [ $start_step -eq 3 ]; then
        if [ ! -d "./xml" ] || [ $(find "./xml" -name "*.xml" | wc -l) -eq 0 ]; then
            master_log "❌ エラー: XMLファイルが見つかりません（ステップ1-2が未実行）"
            exit 1
        fi
        master_log "✅ XMLファイルを確認（$(find "./xml" -name "*.xml" | wc -l)個）"
    fi
    
    # ステップ4から開始する場合のチェック
    if [ $start_step -eq 4 ]; then
        if [ ! -d "./tiff" ] || [ $(find "./tiff" -name "*.tif" | wc -l) -eq 0 ]; then
            master_log "❌ エラー: TIFFファイルが見つかりません（ステップ1-3が未実行）"
            exit 1
        fi
        master_log "✅ TIFFファイルを確認（$(find "./tiff" -name "*.tif" | wc -l)個）"
    fi
    
    # ステップ5から開始する場合のチェック
    if [ $start_step -eq 5 ]; then
        if [ ! -f "./dem_3857.tif" ]; then
            master_log "❌ エラー: ./dem_3857.tif が見つかりません（ステップ1-4が未実行）"
            exit 1
        fi
        master_log "✅ 投影変換済みDEMファイルを確認: ./dem_3857.tif"
    fi
    
    # ステップ6から開始する場合のチェック
    if [ $start_step -eq 6 ]; then
        if [ ! -f "./dem_3857_hillshade_vector.geojson" ]; then
            master_log "❌ エラー: ./dem_3857_hillshade_vector.geojson が見つかりません（ステップ1-5が未実行）"
            exit 1
        fi
        master_log "✅ Hillshadeベクターファイルを確認: ./dem_3857_hillshade_vector.geojson"
    fi
    
    # ステップ2以降で必要なfill_dem_tuples.py確認
    if [ $start_step -le 2 ] && [ ! -f "./fill_dem_tuples.py" ]; then
        master_log "❌ エラー: fill_dem_tuples.py が見つかりません"
        exit 1
    fi
    
    # ステップ5-6で必要な外部コマンド確認
    if [ $start_step -le 6 ]; then
        if ! command -v tippecanoe &> /dev/null; then
            master_log "❌ エラー: tippecanoeが見つかりません"
            master_log "   ベクタータイル生成に必要です"
            exit 1
        fi
        
        if ! command -v pmtiles &> /dev/null; then
            master_log "❌ エラー: pmtilesが見つかりません"
            master_log "   PMTiles変換に必要です"
            exit 1
        fi
    fi
    
    master_log "✅ 実行前チェック完了"
}

# メイン実行関数
execute_pipeline() {
    local start_step=${1:-1}  # デフォルトは1から開始
    local total_start_time=$(date +%s)
    local successful_scripts=0
    local failed_scripts=0
    local skipped_scripts=$((start_step - 1))
    
    master_log "🚀 DEM to Hillshade ベクタータイル配信形式 パイプライン開始"
    master_log "開始ステップ: $start_step/${#SCRIPTS[@]}"
    master_log "実行するスクリプト数: $((${#SCRIPTS[@]} - start_step + 1))"
    master_log "マスターログファイル: $MASTER_LOG_FILE"
    master_log "======================================="
    
    # 指定されたステップから実行
    for i in $(seq $((start_step - 1)) $((${#SCRIPTS[@]} - 1))); do
        local script="${SCRIPTS[$i]}"
        local description="${SCRIPT_DESCRIPTIONS[$i]}"
        local step_num=$((i + 1))
        
        master_log ""
        master_log "📍 ステップ $step_num/${#SCRIPTS[@]}: $description"
        master_log "実行スクリプト: $script"
        
        local script_start_time=$(date +%s)
        
        # スクリプト実行
        if ./"$script"; then
            local script_end_time=$(date +%s)
            local script_duration=$((script_end_time - script_start_time))
            local formatted_duration=$(format_duration $script_duration)
            
            master_log "✅ ステップ $step_num 完了: $script ($formatted_duration)"
            successful_scripts=$((successful_scripts + 1))
        else
            local script_end_time=$(date +%s)
            local script_duration=$((script_end_time - script_start_time))
            local formatted_duration=$(format_duration $script_duration)
            
            master_log "❌ ステップ $step_num 失敗: $script ($formatted_duration)"
            master_log "エラー詳細は個別のログファイルを確認してください"
            failed_scripts=$((failed_scripts + 1))
            
            # エラー時の対応
            master_log ""
            master_log "💥 パイプライン実行エラー"
            master_log "失敗したスクリプト: $script"
            master_log "失敗したステップ: $step_num/$((${#SCRIPTS[@]}))"
            break
        fi
        
        master_log "-----------------------------------"
    done
    
    local total_end_time=$(date +%s)
    local total_duration=$((total_end_time - total_start_time))
    local formatted_total_duration=$(format_duration $total_duration)
    
    master_log ""
    master_log "======================================="
    master_log "📊 実行結果サマリー"
    master_log "総実行時間: $formatted_total_duration"
    if [ $skipped_scripts -gt 0 ]; then
        master_log "スキップしたスクリプト: $skipped_scripts (ステップ1-$skipped_scripts)"
    fi
    master_log "成功したスクリプト: $successful_scripts"
    master_log "失敗したスクリプト: $failed_scripts"
    local executed_scripts=$((successful_scripts + failed_scripts))
    if [ $executed_scripts -gt 0 ]; then
        master_log "実行完了率: $((successful_scripts * 100 / executed_scripts))%"
    fi
    
    if [ $failed_scripts -eq 0 ]; then
        master_log "🎉 実行したすべてのステップが正常に完了しました！"
        master_log ""
        master_log "📁 生成された主要ファイル:"
        
        # 生成ファイルの確認
        [ -d "./xml" ] && master_log "   XML ディレクトリ: $(find ./xml -name "*.xml" | wc -l) ファイル"
        [ -d "./tiff" ] && master_log "   TIFF ディレクトリ: $(find ./tiff -name "*.tif" | wc -l) ファイル"
        [ -f "./merged_dem.vrt" ] && master_log "   VRT ファイル: ./merged_dem.vrt"
        [ -f "./dem_3857.tif" ] && master_log "   投影変換済みDEM: ./dem_3857.tif"
        [ -f "./dem_3857_hillshade_vector.geojson" ] && master_log "   Hillshadeベクター: ./dem_3857_hillshade_vector.geojson"
        [ -f "./dem_3857_hillshade_vector.mbtiles" ] && master_log "   MBTiles: ./dem_3857_hillshade_vector.mbtiles"
        [ -f "./dem_3857_hillshade_vector.pmtiles" ] && master_log "   PMTiles: ./dem_3857_hillshade_vector.pmtiles"
        
        master_log ""
        master_log "✨ Hillshade Vector パイプライン正常完了 ✨"
        exit 0
    else
        master_log "⚠️  パイプラインが途中で停止しました"
        master_log "個別のログファイルでエラー詳細を確認してください"
        exit 1
    fi
}

# 使用方法表示
show_usage() {
    echo "使用方法:"
    echo "  $0 [オプション] [開始ステップ]"
    echo ""
    echo "オプション:"
    echo "  -h, --help     この使用方法を表示"
    echo "  -c, --check    事前チェックのみ実行"
    echo "  -l, --list     実行予定のスクリプト一覧を表示"
    echo "  -s, --start N  ステップNから実行開始 (1-6)"
    echo ""
    echo "開始ステップ:"
    echo "  1: DEM10B ZIPファイルの解凍・XML抽出"
    echo "  2: XMLファイルのfill_dem_tuples処理"
    echo "  3: XMLからGeoTIFFファイル作成"
    echo "  4: TIFFファイルの統合・投影変換"
    echo "  5: Hillshade生成・量子化・ベクトル化"
    echo "  6: ベクタータイル・MBTiles・PMTiles作成"
    echo ""
    echo "例:"
    echo "  $0              # 全ステップを実行"
    echo "  $0 -s 3         # ステップ3から実行"
    echo "  $0 --start 5    # ステップ5から実行"
    echo ""
    echo "説明:"
    echo "  DEM10B ZIPファイルからHillshadeのベクタータイル配信形式（MBTiles・PMTiles）までの全工程を自動実行します"
    echo "  実行前に ./fgd ディレクトリにDEM10B.zipファイルを配置してください"
    echo "  途中のステップから開始する場合は、前のステップの出力ファイルが必要です"
    echo ""
}

# スクリプト一覧表示
show_script_list() {
    echo "実行予定スクリプト一覧:"
    echo "========================"
    for i in "${!SCRIPTS[@]}"; do
        local step_num=$((i + 1))
        echo "$step_num. ${SCRIPTS[$i]}"
        echo "   ${SCRIPT_DESCRIPTIONS[$i]}"
        echo ""
    done
}

# 引数解析関数
parse_arguments() {
    local start_step=1
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--check)
                echo "check_mode"
                return
                ;;
            -l|--list)
                show_script_list
                exit 0
                ;;
            -s|--start)
                if [[ -n $2 && $2 =~ ^[1-6]$ ]]; then
                    start_step=$2
                    shift 2
                else
                    echo "エラー: -s/--start には 1-6 の数値を指定してください"
                    exit 1
                fi
                ;;
            [1-6])
                start_step=$1
                shift
                ;;
            *)
                echo "無効なオプション: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "$start_step"
}

# メイン処理
main() {
    local result=$(parse_arguments "$@")
    
    if [ "$result" = "check_mode" ]; then
        master_log "🔍 事前チェックモード"
        check_scripts
        pre_execution_check 1
        master_log "✅ 事前チェック完了"
        exit 0
    fi
    
    local start_step=$result
    
    # 開始ステップの妥当性チェック
    if [ $start_step -lt 1 ] || [ $start_step -gt ${#SCRIPTS[@]} ]; then
        echo "エラー: 開始ステップは 1-${#SCRIPTS[@]} の範囲で指定してください"
        exit 1
    fi
    
    master_log "📋 実行計画:"
    master_log "開始ステップ: $start_step (${SCRIPT_DESCRIPTIONS[$((start_step - 1))]})"
    master_log "実行予定スクリプト: $((${#SCRIPTS[@]} - start_step + 1))個"
    
    # スクリプト確認と事前チェック
    check_scripts
    pre_execution_check $start_step
    
    # パイプライン実行
    execute_pipeline $start_step
}

# スクリプト実行
main "$@"