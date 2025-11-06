#!/usr/bin/env python3
import os
import sys
import math
import numpy as np
from scipy import ndimage
from multiprocessing import Pool, cpu_count
from functools import partial
import time
import csv

# Try to import GDAL, fallback if not available
try:
    from osgeo import gdal
    HAS_GDAL = True
except ImportError:
    HAS_GDAL = False
    print("Warning: GDAL not available, some functions may not work")

def load_target_tiles(csv_file):
    """CSVファイルから対象タイルIDを読み込み"""
    target_tiles = {}  # {zoom: set((x, y))}
    
    if not os.path.exists(csv_file):
        print(f"Warning: Target tiles CSV file not found: {csv_file}")
        return None
    
    try:
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                z = int(row['z'])
                x = int(row['x'])
                y = int(row['y'])
                
                if z not in target_tiles:
                    target_tiles[z] = set()
                target_tiles[z].add((x, y))
        
        # 統計情報を表示
        total_tiles = sum(len(tiles) for tiles in target_tiles.values())
        print(f"📄 Loaded target tiles from {csv_file}")
        print(f"   Total target tiles: {total_tiles}")
        for zoom in sorted(target_tiles.keys()):
            print(f"   z{zoom}: {len(target_tiles[zoom])} tiles")
        
        return target_tiles
        
    except Exception as e:
        print(f"Error loading target tiles CSV: {e}")
        return None

def deg2num(lat_deg, lon_deg, zoom):
    """緯度経度をタイル座標に変換"""
    lat_rad = math.radians(lat_deg)
    n = 2.0 ** zoom
    xtile = int((lon_deg + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return (xtile, ytile)

def num2deg(xtile, ytile, zoom):
    """タイル座標を緯度経度に変換"""
    n = 2.0 ** zoom
    lon_deg = xtile / n * 360.0 - 180.0
    lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * ytile / n)))
    lat_deg = math.degrees(lat_rad)
    return (lat_deg, lon_deg)

def bilinear_interpolation(data, x, y, width, height):
    """バイリニア補間で標高値を取得"""
    # 座標の整数部分と小数部分を取得
    x1 = int(np.floor(x))
    y1 = int(np.floor(y))
    x2 = min(x1 + 1, width - 1)
    y2 = min(y1 + 1, height - 1)
    
    # 範囲チェック
    if x1 < 0 or y1 < 0 or x1 >= width or y1 >= height:
        return np.nan
    
    # 小数部分
    dx = x - x1
    dy = y - y1
    
    # 4つの角の値を取得
    try:
        v11 = data[y1, x1]  # 左上
        v21 = data[y1, x2]  # 右上
        v12 = data[y2, x1]  # 左下
        v22 = data[y2, x2]  # 右下
        
        # NaNチェック
        if np.isnan(v11) or np.isnan(v21) or np.isnan(v12) or np.isnan(v22):
            # 一部でもNaNがある場合は最近傍を使用
            if dx < 0.5 and dy < 0.5:
                return v11
            elif dx >= 0.5 and dy < 0.5:
                return v21
            elif dx < 0.5 and dy >= 0.5:
                return v12
            else:
                return v22
        
        # バイリニア補間を実行
        # 上辺の補間
        v_top = v11 * (1 - dx) + v21 * dx
        # 下辺の補間
        v_bottom = v12 * (1 - dx) + v22 * dx
        # 縦方向の補間
        result = v_top * (1 - dy) + v_bottom * dy
        
        return result
        
    except IndexError:
        return np.nan

def load_tile_data(tile_file):
    """タイルファイルからデータを読み込み"""
    if not os.path.exists(tile_file):
        return None
    
    try:
        with open(tile_file, 'r') as f:
            lines = f.readlines()
        
        data = []
        for line in lines:
            row = [float(x) for x in line.strip().split(',')]
            data.append(row)
        
        return np.array(data, dtype=np.float32)
    except:
        return None

def save_tile_data(data, tile_file):
    """タイルデータをファイルに保存"""
    os.makedirs(os.path.dirname(tile_file), exist_ok=True)
    
    with open(tile_file, 'w') as f:
        for row in range(data.shape[0]):
            row_values = [f"{data[row, col]:.2f}" for col in range(data.shape[1])]
            f.write(','.join(row_values))
            f.write('\n')

def downsample_tile(parent_tiles, tile_size):
    """4つの親タイルから1つの子タイルをバイリニアリサンプリングで生成"""
    # 4つの親タイルを結合して2x2のタイル配置を作成
    top_row = np.hstack([parent_tiles[0], parent_tiles[1]])  # 左上, 右上
    bottom_row = np.hstack([parent_tiles[2], parent_tiles[3]])  # 左下, 右下
    combined = np.vstack([top_row, bottom_row])
    
    # バイリニア補間でダウンサンプリング
    zoom_factor = tile_size / combined.shape[0]
    downsampled = ndimage.zoom(combined, zoom_factor, order=1)  # order=1はバイリニア補間
    
    # 正確なタイルサイズに調整
    if downsampled.shape[0] != tile_size or downsampled.shape[1] != tile_size:
        # クロッピングまたはパディング
        result = np.zeros((tile_size, tile_size), dtype=np.float32)
        min_h = min(downsampled.shape[0], tile_size)
        min_w = min(downsampled.shape[1], tile_size)
        result[:min_h, :min_w] = downsampled[:min_h, :min_w]
        return result
    
    return downsampled

def generate_text_tiles(input_file, output_dir, min_zoom, max_zoom, tile_size, num_processes=None, target_tiles_csv=None):
    """テキストタイルを生成（ピラミッド方式：z14から開始してリサンプリング）"""
    if not HAS_GDAL:
        print("Error: GDAL is required for this function")
        return False
    
    if num_processes is None:
        num_processes = min(cpu_count(), 8)  # 最大8プロセス
    
    # 対象タイルの読み込み
    target_tiles = None
    if target_tiles_csv:
        target_tiles = load_target_tiles(target_tiles_csv)
        if target_tiles is None:
            print("Warning: Failed to load target tiles, proceeding with full tile generation")
    
    print(f"🚀 Starting text tile generation with {num_processes} processes")
    if target_tiles:
        print(f"🎯 Using target tiles from: {target_tiles_csv}")
    print(f"Opening raster: {input_file}")
    dataset = gdal.Open(input_file, gdal.GA_ReadOnly)
    if not dataset:
        print(f"Error: Could not open {input_file}")
        return False
    
    # ラスターの情報を取得
    geotransform = dataset.GetGeoTransform()
    band = dataset.GetRasterBand(1)
    nodata_value = band.GetNoDataValue()
    
    print(f"Raster size: {dataset.RasterXSize} x {dataset.RasterYSize}")
    print(f"Geotransform: {geotransform}")
    print(f"NoData value: {nodata_value}")
    
    # Web Mercator EPSG:3857の範囲を取得
    minx = geotransform[0]
    maxy = geotransform[3]
    maxx = minx + geotransform[1] * dataset.RasterXSize
    miny = maxy + geotransform[5] * dataset.RasterYSize
    
    print(f"Raster bounds (Web Mercator): {minx}, {miny}, {maxx}, {maxy}")
    
    # Web Mercatorから緯度経度に変換
    def webmercator_to_wgs84(x, y):
        lon = x * 180.0 / 20037508.342789244
        lat = math.atan(math.exp(y * math.pi / 20037508.342789244)) * 360.0 / math.pi - 90.0
        return lat, lon
    
    min_lat, min_lon = webmercator_to_wgs84(minx, miny)
    max_lat, max_lon = webmercator_to_wgs84(maxx, maxy)
    
    print(f"Raster bounds (WGS84): {min_lat}, {min_lon}, {max_lat}, {max_lon}")
    
    total_tiles = 0
    total_start_time = time.time()
    
    # Step 1: 最高解像度（max_zoom、通常z14）のタイルを生成
    print(f"🚀 Generating base tiles at zoom level {max_zoom}")
    base_start_time = time.time()
    base_zoom_tiles = generate_base_zoom_tiles(
        dataset, band, geotransform, nodata_value,
        minx, miny, maxx, maxy, min_lat, min_lon, max_lat, max_lon,
        max_zoom, tile_size, output_dir, num_processes, target_tiles
    )
    base_end_time = time.time()
    total_tiles += base_zoom_tiles
    print(f"✅ Generated {base_zoom_tiles} base tiles at zoom {max_zoom} in {base_end_time - base_start_time:.1f}s")
    
    # Step 2: ピラミッド生成（max_zoom-1からmin_zoomまで）
    for zoom in range(max_zoom - 1, min_zoom - 1, -1):
        print(f"🔄 Generating zoom level {zoom} from zoom {zoom + 1}")
        pyramid_start_time = time.time()
        pyramid_tiles = generate_pyramid_level(output_dir, zoom, zoom + 1, tile_size, target_tiles)
        pyramid_end_time = time.time()
        total_tiles += pyramid_tiles
        print(f"✅ Generated {pyramid_tiles} tiles for zoom {zoom} in {pyramid_end_time - pyramid_start_time:.1f}s")
    
    total_end_time = time.time()
    total_time = total_end_time - total_start_time
    
    print(f"🎉 Total tiles generated: {total_tiles} in {total_time:.1f}s")
    print(f"📊 Average processing speed: {total_tiles / total_time:.1f} tiles/second")
    dataset = None
    return True

def generate_single_base_tile(args):
    """単一のベースタイルを生成（マルチプロセッシング用）"""
    (tx, ty, zoom, tile_size, input_file, output_dir, 
     geotransform, nodata_value, minx, miny, maxx, maxy) = args
    
    try:
        # GDALデータセットを再オープン
        dataset = gdal.Open(input_file, gdal.GA_ReadOnly)
        if not dataset:
            return (tx, ty, False, "Could not open dataset")
        
        band = dataset.GetRasterBand(1)
        
        # タイルの地理的範囲を計算（WGS84）
        north, west = num2deg(tx, ty, zoom)
        south, east = num2deg(tx + 1, ty + 1, zoom)
        
        # WGS84からWeb Mercatorに変換
        def wgs84_to_webmercator(lat, lon):
            x = lon * 20037508.342789244 / 180.0
            y = math.log(math.tan((90.0 + lat) * math.pi / 360.0)) * 20037508.342789244 / math.pi
            return x, y
        
        tile_west_merc, tile_north_merc = wgs84_to_webmercator(north, west)
        tile_east_merc, tile_south_merc = wgs84_to_webmercator(south, east)
        
        # タイルとラスターの重複領域を計算
        overlap_minx = max(tile_west_merc, minx)
        overlap_maxx = min(tile_east_merc, maxx)
        overlap_miny = max(tile_south_merc, miny)
        overlap_maxy = min(tile_north_merc, maxy)
        
        # 重複がない場合はスキップ
        if overlap_minx >= overlap_maxx or overlap_miny >= overlap_maxy:
            dataset = None
            return (tx, ty, False, "No overlap")
        
        # ラスター座標系での範囲を計算
        pixel_minx = max(0, int((overlap_minx - geotransform[0]) / geotransform[1]))
        pixel_maxx = min(dataset.RasterXSize, int((overlap_maxx - geotransform[0]) / geotransform[1]) + 1)
        pixel_miny = max(0, int((overlap_maxy - geotransform[3]) / geotransform[5]))
        pixel_maxy = min(dataset.RasterYSize, int((overlap_miny - geotransform[3]) / geotransform[5]) + 1)
        
        if pixel_minx >= pixel_maxx or pixel_miny >= pixel_maxy:
            dataset = None
            return (tx, ty, False, "Invalid pixel range")
        
        # ラスターデータを読み込み
        width = pixel_maxx - pixel_minx
        height = pixel_maxy - pixel_miny
        
        if width <= 0 or height <= 0:
            dataset = None
            return (tx, ty, False, "Invalid dimensions")
        
        data = band.ReadAsArray(pixel_minx, pixel_miny, width, height)
        
        if data is None:
            dataset = None
            return (tx, ty, False, "Could not read data")
        
        # データをfloat型に変換
        data = data.astype(np.float32)
        
        # NaNや無効値を処理
        if nodata_value is not None:
            data = np.where(data == nodata_value, np.nan, data)
        
        # タイル内でのグリッドポイントを生成
        elevation_grid = np.full((tile_size, tile_size), np.nan, dtype=np.float32)
        
        for i in range(tile_size):
            for j in range(tile_size):
                # グリッドポイントの地理的座標（WGS84）
                point_lat = north - (north - south) * i / (tile_size - 1)
                point_lon = west + (east - west) * j / (tile_size - 1)
                
                # Web Mercator座標に変換
                point_x, point_y = wgs84_to_webmercator(point_lat, point_lon)
                
                # ラスター座標系に変換
                raster_x = (point_x - geotransform[0]) / geotransform[1]
                raster_y = (point_y - geotransform[3]) / geotransform[5]
                
                # ラスター範囲内かチェック
                if (pixel_minx <= raster_x < pixel_maxx and 
                    pixel_miny <= raster_y < pixel_maxy):
                    
                    # ローカル座標に変換（bilinear補間用）
                    local_x = raster_x - pixel_minx
                    local_y = raster_y - pixel_miny
                    
                    # Bilinear補間を実行
                    value = bilinear_interpolation(data, local_x, local_y, width, height)
                    if not np.isnan(value):
                        elevation_grid[i, j] = value
        
        # NaNを0に変換
        elevation_grid = np.where(np.isnan(elevation_grid), 0.0, elevation_grid)
        
        # 全面0.00の場合はタイル出力をスキップ
        if np.all(elevation_grid == 0.0):
            dataset = None
            return (tx, ty, False, "All zeros")
        
        # テキストファイルに保存
        x_dir = os.path.join(output_dir, str(zoom), str(tx))
        os.makedirs(x_dir, exist_ok=True)
        tile_file = os.path.join(x_dir, f"{ty}.txt")
        save_tile_data(elevation_grid, tile_file)
        
        dataset = None
        return (tx, ty, True, "Success")
        
    except Exception as e:
        return (tx, ty, False, f"Error: {str(e)}")

def generate_base_zoom_tiles(dataset, band, geotransform, nodata_value,
                           minx, miny, maxx, maxy, min_lat, min_lon, max_lat, max_lon,
                           zoom, tile_size, output_dir, num_processes=None, target_tiles=None):
    """最高解像度のタイルを元データから並列処理で生成"""
    
    if num_processes is None:
        num_processes = min(cpu_count(), 8)  # 最大8プロセス
    
    print(f"  Using {num_processes} processes for parallel tile generation")
    
    # このズームレベルでのタイル範囲を計算（常に実行）
    min_tile_x, max_tile_y = deg2num(min_lat, min_lon, zoom)
    max_tile_x, min_tile_y = deg2num(max_lat, max_lon, zoom)
    
    # タイル範囲を調整
    min_tile_x = max(0, min_tile_x)
    max_tile_x = min(2**zoom - 1, max_tile_x)
    min_tile_y = max(0, min_tile_y)
    max_tile_y = min(2**zoom - 1, max_tile_y)
    
    print(f"  Tile range: x={min_tile_x}-{max_tile_x}, y={min_tile_y}-{max_tile_y}")
    
    # ラスタ範囲内の全タイル座標のリストを生成
    raster_tile_coords = []
    for tx in range(min_tile_x, max_tile_x + 1):
        for ty in range(min_tile_y, max_tile_y + 1):
            raster_tile_coords.append((tx, ty))
    
    # 対象タイルが指定されている場合は交集合を取る
    if target_tiles and zoom in target_tiles:
        target_tile_set = target_tiles[zoom]
        tile_coords = [(tx, ty) for tx, ty in raster_tile_coords if (tx, ty) in target_tile_set]
        print(f"  Raster tiles: {len(raster_tile_coords)}, Target tiles: {len(target_tile_set)}, Intersection: {len(tile_coords)} tiles")
    else:
        tile_coords = raster_tile_coords
        print(f"  Processing all {len(tile_coords)} tiles in raster range")
    
    zoom_dir = os.path.join(output_dir, str(zoom))
    os.makedirs(zoom_dir, exist_ok=True)
    
    # 全タイルのタスクリストを作成
    tasks = []
    for tx, ty in tile_coords:
        task = (tx, ty, zoom, tile_size, dataset.GetDescription(), output_dir,
               geotransform, nodata_value, minx, miny, maxx, maxy)
        tasks.append(task)
    
    total_tasks = len(tasks)
    print(f"  Processing {total_tasks} tiles...")
    
    successful_tiles = 0
    failed_tiles = 0
    skipped_tiles = 0
    
    start_time = time.time()
    
    # 並列処理でタイル生成
    with Pool(processes=num_processes) as pool:
        # 進捗表示のためチャンクサイズを調整
        chunk_size = max(1, total_tasks // (num_processes * 4))
        
        results = pool.map(generate_single_base_tile, tasks, chunksize=chunk_size)
        
        # 結果を処理
        for i, (tx, ty, success, message) in enumerate(results):
            if success:
                successful_tiles += 1
            elif message == "No overlap" or message == "All zeros":
                skipped_tiles += 1
            else:
                failed_tiles += 1
                if failed_tiles <= 10:  # 最初の10個のエラーのみ表示
                    print(f"    Failed tile {tx}/{ty}: {message}")
            
            # 進捗表示（100タイルごと）
            if (i + 1) % 100 == 0 or i + 1 == total_tasks:
                elapsed = time.time() - start_time
                progress = (i + 1) / total_tasks * 100
                eta = elapsed / (i + 1) * (total_tasks - i - 1) if i > 0 else 0
                print(f"    Progress: {i+1}/{total_tasks} ({progress:.1f}%) - "
                      f"Success: {successful_tiles}, Skipped: {skipped_tiles}, Failed: {failed_tiles} - "
                      f"ETA: {eta:.1f}s")
    
    end_time = time.time()
    total_time = end_time - start_time
    
    print(f"  Completed in {total_time:.1f}s")
    print(f"  Results: {successful_tiles} successful, {skipped_tiles} skipped, {failed_tiles} failed")
    
    return successful_tiles

def generate_pyramid_level(output_dir, target_zoom, source_zoom, tile_size, target_tiles=None):
    """親ズームレベルから子ズームレベルのタイルをリサンプリングで生成"""
    
    source_dir = os.path.join(output_dir, str(source_zoom))
    target_dir = os.path.join(output_dir, str(target_zoom))
    
    if not os.path.exists(source_dir):
        print(f"  Warning: Source zoom directory {source_dir} does not exist")
        return 0
    
    os.makedirs(target_dir, exist_ok=True)
    
    # ソースズームレベルのタイル一覧を取得
    source_tiles = set()
    for x_dir_name in os.listdir(source_dir):
        x_dir_path = os.path.join(source_dir, x_dir_name)
        if os.path.isdir(x_dir_path):
            try:
                tx = int(x_dir_name)
                for tile_file in os.listdir(x_dir_path):
                    if tile_file.endswith('.txt'):
                        ty = int(tile_file[:-4])  # .txtを除去
                        source_tiles.add((tx, ty))
            except ValueError:
                continue
    
    print(f"  Found {len(source_tiles)} source tiles at zoom {source_zoom}")
    
    # ターゲットズームレベルのタイル範囲を計算
    if target_tiles and target_zoom in target_tiles:
        # CSVで指定されたタイルのみを対象とする
        target_tiles_coords = target_tiles[target_zoom]
        print(f"  Using target tiles from CSV: {len(target_tiles_coords)} tiles at zoom {target_zoom}")
    else:
        # ソースタイルから計算
        target_tiles_coords = set()
        for source_tx, source_ty in source_tiles:
            # 親タイルから子タイルの座標を計算
            target_tx = source_tx // 2
            target_ty = source_ty // 2
            target_tiles_coords.add((target_tx, target_ty))
    
    print(f"  Generating {len(target_tiles_coords)} target tiles at zoom {target_zoom}")
    
    generated_count = 0
    
    for target_tx, target_ty in target_tiles_coords:
        # 4つの親タイルの座標
        parent_tiles_coords = [
            (target_tx * 2, target_ty * 2),        # 左上
            (target_tx * 2 + 1, target_ty * 2),    # 右上
            (target_tx * 2, target_ty * 2 + 1),    # 左下
            (target_tx * 2 + 1, target_ty * 2 + 1) # 右下
        ]
        
        # 親タイルのデータを読み込み
        parent_tiles = []
        all_loaded = True
        
        for ptx, pty in parent_tiles_coords:
            parent_file = os.path.join(source_dir, str(ptx), f"{pty}.txt")
            parent_data = load_tile_data(parent_file)
            
            if parent_data is not None:
                parent_tiles.append(parent_data)
            else:
                # 存在しない親タイルは0で埋める
                parent_tiles.append(np.zeros((tile_size, tile_size), dtype=np.float32))
        
        if len(parent_tiles) == 4:
            # ダウンサンプリング実行
            downsampled = downsample_tile(parent_tiles, tile_size)
            
            # 全面0.00の場合はタイル出力をスキップ
            if np.all(downsampled == 0.0):
                continue
            
            # ターゲットタイルを保存
            target_x_dir = os.path.join(target_dir, str(target_tx))
            target_file = os.path.join(target_x_dir, f"{target_ty}.txt")
            save_tile_data(downsampled, target_file)
            
            generated_count += 1
    
    return generated_count

if __name__ == "__main__":
    if len(sys.argv) < 6 or len(sys.argv) > 8:
        print("Usage: python3 generate_text_tiles.py <input_file> <output_dir> <min_zoom> <max_zoom> <tile_size> [num_processes] [target_tiles_csv]")
        print("  num_processes: Number of parallel processes (default: auto-detect, max 8)")
        print("  target_tiles_csv: CSV file with target tile IDs (z,x,y format)")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_dir = sys.argv[2]
    min_zoom = int(sys.argv[3])
    max_zoom = int(sys.argv[4])
    tile_size = int(sys.argv[5])
    
    num_processes = None
    if len(sys.argv) >= 7:
        try:
            num_processes = int(sys.argv[6])
            if num_processes <= 0:
                print("Error: num_processes must be positive")
                sys.exit(1)
        except ValueError:
            # 6番目の引数がCSVファイルの場合
            target_tiles_csv = sys.argv[6]
            num_processes = None
    
    target_tiles_csv = None
    if len(sys.argv) == 8:
        target_tiles_csv = sys.argv[7]
    elif len(sys.argv) == 7 and not sys.argv[6].isdigit():
        target_tiles_csv = sys.argv[6]
        num_processes = None
    
    success = generate_text_tiles(input_file, output_dir, min_zoom, max_zoom, tile_size, num_processes, target_tiles_csv)
    if not success:
        sys.exit(1)