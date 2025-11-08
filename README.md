# FGD DEM to Terrain Tiles Pipeline

日本の基盤地図情報DEM10Bデータから、Webマップ用の地形タイルを生成するパイプライン処理システムです。

## 概要

このプロジェクトは、国土地理院の基盤地図情報（DEM10B）から、以下の3種類の地形タイルを生成する自動化パイプラインです：

- **Terrain RGBタイル**: 標高データをRGB形式でエンコードしたラスタタイル
- **Hillshadeタイル**: 陰影起伏図のラスタタイル
- **等高線タイル**: 等高線ベクタタイル

各パイプラインは6段階の処理ステップで構成され、任意のステップから再開可能です。

## アーキテクチャ

### パイプライン構成

```
DEM10B ZIP → XML抽出 → GeoTIFF変換 → Web Mercator投影 → [分岐処理] → タイル生成
                                                          ├─ Terrain RGB
                                                          ├─ Hillshade
                                                          └─ 等高線
```

### 出力形式

各バリアントは複数の配信形式を生成します：
- **ラスタタイル**: ディレクトリ構造（`/tiles_*/*.png`）
- **MBTiles**: 従来のタイルサーバー向けSQLite形式（`*.mbtiles`）
- **PMTiles**: モダンなクラウドネイティブ形式（`*.pmtiles`）

## セットアップ

### 前提条件

- Docker
- Python 3.10以上

### 必要なPythonパッケージ

```bash
pip install fgddem-py      # 基盤地図情報XML → GeoTIFF変換
pip install rio-rgbify     # Terrain RGBエンコーディング
```

### 外部ツール

以下のツールを別途インストールしてください：

```bash
# Tippecanoe（ベクタータイル生成）
# https://github.com/felt/tippecanoe のインストール手順に従ってください

# PMTiles（タイル形式変換）
# https://github.com/protomaps/go-pmtiles のインストール手順に従ってください

# mbutil（MBTiles操作）
# https://github.com/mapbox/mbutil のインストール手順に従ってください
```

## 使用方法

### データ準備

1. 国土地理院から基盤地図情報DEM10BのZIPファイルをダウンロード
2. `./fgd/` ディレクトリに配置

```bash
mkdir fgd
# DEM10B ZIPファイルを fgd/ ディレクトリに配置
```

### パイプライン実行

#### 全パイプライン実行

```bash
# Terrain RGBタイル生成（直接変換）
./run_pipeline_terrain_rgb.sh

# Terrain RGBタイル生成（標高テキストタイル経由）
./run_pipeline_terrain_rgb_using_dem_text.sh

# Hillshadeラスタタイル生成
./run_pipeline_hillshade.sh

# 等高線ベクタタイル生成
./run_pipeline_contour.sh
```

#### 途中ステップから再開

```bash
# ステップ4（投影変換）から開始
./run_pipeline_hillshade.sh -s 4

# 事前チェックのみ実行
./run_pipeline_terrain_rgb.sh --check
```

### 処理ステップ（標準パイプライン）

| ステップ | 処理内容 | 出力 |
|---------|---------|------|
| 1 | DEM10B ZIP解凍・XML抽出 | `./xml/` |
| 2 | XMLデータ補完処理 | 補完済みXML |
| 3 | GeoTIFF変換 | `./tiff/` |
| 4 | 統合・Web Mercator投影変換 | `dem_3857.tif` |
| 5 | 形式別変換（Terrain RGB/Hillshade/等高線） | 各形式ファイル |
| 6 | タイル生成・複数形式出力 | ラスタタイル + MBTiles + PMTiles |

### 処理ステップ（標高テキストタイル経由パイプライン）

| ステップ | 処理内容 | 出力 |
|---------|---------|------|
| 1 | DEM10B ZIP解凍・XML抽出 | `./xml/` |
| 2 | XMLデータ補完処理 | 補完済みXML |
| 3 | GeoTIFF変換 | `./tiff/` |
| 4 | 統合・Web Mercator投影変換 | `dem_3857.tif` |
| 5 | 標高テキストタイル生成 | `./tiles_elevation/` |
| 6 | テキストタイルからTerrain RGBタイル変換 | ラスタタイル + MBTiles + PMTiles |

## 標高テキストタイル経由パイプライン

### 概要

`run_pipeline_terrain_rgb_using_dem_text.sh` は、直接Terrain RGB変換とは異なるアプローチで、一度標高データをテキストタイル形式に変換してからTerrain RGBタイルを生成します。

### 特徴・利点

- 事前にbilinearでリサンプリングした標高値テキストタイルを用いることで、隣り合う標高値を平滑化（nearest neighborで生じるズレを回避）
- テキストタイル経由により処理時間が長くなるため、処理のマルチプロセス化及び、日本国土が存在するタイルのみに処理を限定することで処理時間を短縮

### 処理の流れ

```
DEM GeoTIFF → 標高テキストタイル生成 → Terrain RGB PNG変換 → MBTiles/PMTiles出力
    ↓               ↓                      ↓
dem_3857.tif    ./tiles_elevation/    ./tiles_terrainrgb/
                   (*.txt)              (*.png)
```

## 設定

### パフォーマンス調整

各スクリプトの先頭で設定可能：

```bash
# 05_create_terrain_rgb.sh
# rio-rgbifyジョブ数
JOBS=1

# 06_create_tiles_hillshade.sh
# 06_create_tiles_terrain_rgb.sh
# gdal2tiles並列処理数
PROCESSES=4

# 06_create_tiles_hillshade.sh
# 06_create_tiles_terrain_rgb.sh
# 06_create_tiles_contour.sh
# ズームレベル範囲
MAX_ZOOM=14
MIN_ZOOM=0
```

### 等高線設定

```bash
# 05_create_contour.sh
# 等高線間隔（メートル）
CONTOUR_INTERVAL=10

# 06_create_tiles_contour.sh
# レイヤ名
LAYER_NAME="contour"
```

## 出力ファイル

### 主要な中間ファイル

- `dem_3857.tif` - Web Mercator投影変換済みDEM
- `dem_3857_cleaned.tif` - nodata値を0に変換したDEM（Terrain RGB用）
- `dem_3857_terrainrgb.tif` - Terrain RGBエンコード済み
- `dem_3857_hillshade.tif` - Hillshade画像
- `dem_3857_contour.geojson` - 等高線（GeoJSONSeq形式）
- `tiles_elevation/` - 標高値テキストタイル（*.txt）

### 最終出力

- `tiles_terrainrgb/` - Terrain RGBラスタタイル
- `tiles_hillshade/` - Hillshadeラスタタイル
- `dem_3857_terrainrgb.mbtiles` - Terrain RGB MBTiles
- `dem_3857_hillshade.mbtiles` - Hillshade MBTiles
- `dem_3857_contour.mbtiles` - 等高線MBTiles
- `*.pmtiles` - 各形式のPMTiles

## ログとデバッグ

### ログファイル

- 個別スクリプト: `./logs/script_name_YYYYMMDD_HHMMSS.log`
- マスターログ: `./logs/master_*_YYYYMMDD_HHMMSS.log`

### トラブルシューティング

1. マスターログで失敗ステップを確認
2. 該当する個別スクリプトのログを確認
3. 失敗ステップから再開：`./run_pipeline_*.sh -s <ステップ番号>`

## 仕様・制限事項

- **座標系**: 入力EPSG:6668 → 出力EPSG:3857（Web Mercator）
- **データ形式**: GeoJSONSeq（NDJSON）形式を使用
- **Docker使用**: 全GDAL操作はコンテナ内で実行

## ライセンス

- このプロジェクトのスクリプトはMITライセンスの下で公開されています。
- 基盤地図情報の利用については[国土地理院の利用規約](https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html)に従ってください。

## 参考資料

- [国土地理院 基盤地図情報ダウンロードサービス](https://service.gsi.go.jp/kiban/)
- [Mapbox Terrain RGB](https://docs.mapbox.com/data/tilesets/guides/access-elevation-data/#decode-data)
- [PMTiles仕様](https://github.com/protomaps/PMTiles)