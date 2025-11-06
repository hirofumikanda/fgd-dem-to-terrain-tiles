#!/usr/bin/env python3
import os
import sys
import numpy as np
from PIL import Image

def text_to_terrain_rgb(elevation):
    """標高値をterrain RGB形式に変換"""
    # terrain RGB形式: 標高 = -10000 + ((R * 256 * 256 + G * 256 + B) * 0.1)
    # つまり: (R * 256 * 256 + G * 256 + B) = (標高 + 10000) / 0.1
    
    # 標高値を調整（-10000〜+8388.607mの範囲）
    adjusted_elevation = elevation + 10000.0
    encoded_value = int(adjusted_elevation / 0.1)
    
    # 負の値は0に、最大値を超える場合は最大値に制限
    encoded_value = max(0, min(encoded_value, 2**24 - 1))
    
    # RGB値に分解
    r = (encoded_value >> 16) & 0xFF
    g = (encoded_value >> 8) & 0xFF
    b = encoded_value & 0xFF
    
    return r, g, b

def load_text_tile(file_path):
    """テキストタイルを読み込み"""
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()
        
        data = []
        for line in lines:
            row = [float(x) for x in line.strip().split(',')]
            data.append(row)
        
        return np.array(data, dtype=np.float32)
    except:
        return None

def convert_text_tile_to_png(text_file, png_file):
    """テキストタイルをterrain RGB PNG形式に変換"""
    # テキストタイルを読み込み
    elevation_data = load_text_tile(text_file)
    if elevation_data is None:
        return False
    
    height, width = elevation_data.shape
    
    # RGB画像を作成
    rgb_array = np.zeros((height, width, 3), dtype=np.uint8)
    
    for i in range(height):
        for j in range(width):
            r, g, b = text_to_terrain_rgb(elevation_data[i, j])
            rgb_array[i, j] = [r, g, b]
    
    # PNG画像として保存
    image = Image.fromarray(rgb_array, 'RGB')
    os.makedirs(os.path.dirname(png_file), exist_ok=True)
    image.save(png_file, 'PNG')
    
    return True

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 convert_text_to_terrainrgb.py <input_dir> <output_dir>")
        sys.exit(1)
    
    input_dir = sys.argv[1]
    output_dir = sys.argv[2]
    
    converted_count = 0
    error_count = 0
    
    # 全てのテキストタイルを処理
    for root, dirs, files in os.walk(input_dir):
        for file in files:
            if file.endswith('.txt'):
                # 入力ファイルパス
                text_file = os.path.join(root, file)
                
                # 出力ファイルパス（相対パス構造を保持）
                rel_path = os.path.relpath(text_file, input_dir)
                png_file = os.path.join(output_dir, rel_path.replace('.txt', '.png'))
                
                # 変換実行
                if convert_text_tile_to_png(text_file, png_file):
                    converted_count += 1
                    if converted_count % 100 == 0:
                        print(f"Converted {converted_count} tiles...")
                else:
                    error_count += 1
                    print(f"Error converting {text_file}")
    
    print(f"Conversion completed: {converted_count} tiles converted, {error_count} errors")

if __name__ == "__main__":
    main()