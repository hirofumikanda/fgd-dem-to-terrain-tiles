#!/usr/bin/env python3
"""
端のタイル座標計算スクリプト

指定されたWeb Mercator境界座標から、各ズームレベルでの端のタイル座標を算出します。
"""

import math
import sys
import argparse


def deg2num(lat_deg, lon_deg, zoom):
    """
    緯度経度からタイル座標への変換
    
    Args:
        lat_deg (float): 緯度（度）
        lon_deg (float): 経度（度）
        zoom (int): ズームレベル
        
    Returns:
        tuple: (x, y) タイル座標
    """
    lat_rad = math.radians(lat_deg)
    n = 2.0 ** zoom
    x = int((lon_deg + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return (x, y)


def mercator_to_latlon(x, y):
    """
    Web Mercator (EPSG:3857) から WGS84 (EPSG:4326) への変換
    
    Args:
        x (float): Web Mercator X座標
        y (float): Web Mercator Y座標
        
    Returns:
        tuple: (lat, lon) 緯度経度
    """
    lon = x / 20037508.342789244 * 180
    lat = y / 20037508.342789244 * 180
    lat = 180 / math.pi * (2 * math.atan(math.exp(lat * math.pi / 180)) - math.pi / 2)
    return (lat, lon)


def calculate_edge_tiles(min_x, min_y, max_x, max_y, zoom_range):
    """
    指定された境界座標から端のタイル座標を算出
    
    Args:
        min_x (float): 最小X座標（Web Mercator）
        min_y (float): 最小Y座標（Web Mercator）
        max_x (float): 最大X座標（Web Mercator）
        max_y (float): 最大Y座標（Web Mercator）
        zoom_range (str): ズームレベル範囲（例: "0-14"）
        
    Returns:
        set: 端のタイル座標セット (z, x, y)
    """
    # Web MercatorからWGS84への変換
    min_lat, min_lon = mercator_to_latlon(min_x, min_y)
    max_lat, max_lon = mercator_to_latlon(max_x, max_y)
    
    # ズームレベル範囲の解析
    zoom_parts = zoom_range.split('-')
    min_zoom = int(zoom_parts[0])
    max_zoom = int(zoom_parts[1])
    
    # 端のタイル座標を格納するセット
    edge_tiles = set()
    
    for z in range(min_zoom, max_zoom + 1):
        # 四隅のタイル座標を取得
        # Web Mercatorタイル座標系ではY座標は北から南に向かって増加
        min_x_tile, min_y_tile = deg2num(max_lat, min_lon, z)  # 左上
        max_x_tile, max_y_tile = deg2num(min_lat, max_lon, z)  # 右下
        
        # 端のタイルを特定（境界の1タイル幅）
        # 上端と下端の全タイル
        for x in range(min_x_tile, max_x_tile + 1):
            edge_tiles.add((z, x, min_y_tile))      # 上端（北側）
            edge_tiles.add((z, x, max_y_tile))      # 下端（南側）
        
        # 左端と右端の全タイル
        for y in range(min_y_tile, max_y_tile + 1):
            edge_tiles.add((z, min_x_tile, y))      # 左端（西側）
            edge_tiles.add((z, max_x_tile, y))      # 右端（東側）
    
    return edge_tiles


def main():
    """メイン関数"""
    parser = argparse.ArgumentParser(description='端のタイル座標を計算')
    parser.add_argument('--min-x', type=float, required=True, help='最小X座標（Web Mercator）')
    parser.add_argument('--min-y', type=float, required=True, help='最小Y座標（Web Mercator）')
    parser.add_argument('--max-x', type=float, required=True, help='最大X座標（Web Mercator）')
    parser.add_argument('--max-y', type=float, required=True, help='最大Y座標（Web Mercator）')
    parser.add_argument('--zoom-range', type=str, required=True, help='ズームレベル範囲（例: 0-14）')
    parser.add_argument('--output', type=str, help='出力ファイル名（指定しない場合は標準出力）')
    
    args = parser.parse_args()
    
    # 端のタイル座標を計算
    edge_tiles = calculate_edge_tiles(
        args.min_x, args.min_y, args.max_x, args.max_y, args.zoom_range
    )
    
    # 結果を出力
    output_lines = []
    for z, x, y in sorted(edge_tiles):
        output_lines.append(f'{z}/{x}/{y}')
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write('\n'.join(output_lines) + '\n')
        print(f"端のタイル座標を {args.output} に出力しました。", file=sys.stderr)
        print(f"タイル数: {len(edge_tiles)}", file=sys.stderr)
    else:
        for line in output_lines:
            print(line)


if __name__ == '__main__':
    main()