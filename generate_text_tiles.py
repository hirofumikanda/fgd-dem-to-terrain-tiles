#!/usr/bin/env python3
import os
import sys
import math
from osgeo import gdal
import numpy as np

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

def generate_text_tiles(input_file, output_dir, min_zoom, max_zoom, tile_size):
    """テキストタイルを生成"""
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
    
    for zoom in range(min_zoom, max_zoom + 1):
        print(f"Processing zoom level {zoom}")
        
        # このズームレベルでのタイル範囲を計算
        min_tile_x, max_tile_y = deg2num(min_lat, min_lon, zoom)
        max_tile_x, min_tile_y = deg2num(max_lat, max_lon, zoom)
        
        # タイル範囲を調整
        min_tile_x = max(0, min_tile_x)
        max_tile_x = min(2**zoom - 1, max_tile_x)
        min_tile_y = max(0, min_tile_y)
        max_tile_y = min(2**zoom - 1, max_tile_y)
        
        print(f"  Tile range: x={min_tile_x}-{max_tile_x}, y={min_tile_y}-{max_tile_y}")
        
        zoom_dir = os.path.join(output_dir, str(zoom))
        os.makedirs(zoom_dir, exist_ok=True)
        
        zoom_tiles = 0
        
        for tx in range(min_tile_x, max_tile_x + 1):
            x_dir = os.path.join(zoom_dir, str(tx))
            os.makedirs(x_dir, exist_ok=True)
            
            for ty in range(min_tile_y, max_tile_y + 1):
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
                    continue
                
                # ラスター座標系での範囲を計算
                pixel_minx = max(0, int((overlap_minx - geotransform[0]) / geotransform[1]))
                pixel_maxx = min(dataset.RasterXSize, int((overlap_maxx - geotransform[0]) / geotransform[1]) + 1)
                pixel_miny = max(0, int((overlap_maxy - geotransform[3]) / geotransform[5]))
                pixel_maxy = min(dataset.RasterYSize, int((overlap_miny - geotransform[3]) / geotransform[5]) + 1)
                
                if pixel_minx >= pixel_maxx or pixel_miny >= pixel_maxy:
                    continue
                
                # ラスターデータを読み込み
                width = pixel_maxx - pixel_minx
                height = pixel_maxy - pixel_miny
                
                if width <= 0 or height <= 0:
                    continue
                
                data = band.ReadAsArray(pixel_minx, pixel_miny, width, height)
                
                if data is None:
                    continue
                
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
                            
                            # ローカル座標に変換
                            local_x = int(raster_x - pixel_minx)
                            local_y = int(raster_y - pixel_miny)
                            
                            if (0 <= local_x < width and 0 <= local_y < height):
                                value = data[local_y, local_x]
                                if not np.isnan(value):
                                    elevation_grid[i, j] = value
                
                # NaNを0に変換
                elevation_grid = np.where(np.isnan(elevation_grid), 0.0, elevation_grid)
                
                # テキストファイルに保存（256行×256列）
                tile_file = os.path.join(x_dir, f"{ty}.txt")
                with open(tile_file, 'w') as f:
                    for row in range(tile_size):
                        row_values = [f"{elevation_grid[row, col]:.2f}" for col in range(tile_size)]
                        f.write(','.join(row_values))
                        f.write('\n')
                
                zoom_tiles += 1
                total_tiles += 1
        
        print(f"  Generated {zoom_tiles} tiles for zoom {zoom}")
    
    print(f"Total tiles generated: {total_tiles}")
    dataset = None
    return True

if __name__ == "__main__":
    if len(sys.argv) != 6:
        print("Usage: python3 generate_text_tiles.py <input_file> <output_dir> <min_zoom> <max_zoom> <tile_size>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_dir = sys.argv[2]
    min_zoom = int(sys.argv[3])
    max_zoom = int(sys.argv[4])
    tile_size = int(sys.argv[5])
    
    success = generate_text_tiles(input_file, output_dir, min_zoom, max_zoom, tile_size)
    if not success:
        sys.exit(1)