import argparse

# 引数を解析する
def parse_arguments():
    parser = argparse.ArgumentParser(description="基盤地図情報XMLのデータ補完スクリプト")
    parser.add_argument("input_file", help="入力XMLファイルのパス")
    parser.add_argument("output_file", help="出力XMLファイルのパス")
    return parser.parse_args()

def fill_missing_data(input_file, output_file, total_rows=843750):
    # ファイルをテキストとして読み込む
    with open(input_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # <gml:tupleList> の開始と終了位置を特定
    start_index = None
    end_index = None

    for i, line in enumerate(lines):
        if "<gml:tupleList>" in line:
            start_index = i
        elif "</gml:tupleList>" in line:
            end_index = i
            break

    if start_index is None or end_index is None:
        print("<gml:tupleList> が見つかりませんでした。")
        return

    # 現在のデータ行を取得
    tuple_list_lines = lines[start_index + 1:end_index]

    # <gml:startPoint> の値を確認して修正し、必要に応じて行を挿入
    for i, line in enumerate(lines):
        if "<gml:startPoint>" in line:
            start_point_value = line.strip().replace("<gml:startPoint>", "").replace("</gml:startPoint>", "")
            x, y = map(int, start_point_value.split())

            if x != 0 or y != 0:
                calculated_rows = x + 1125 * y
                print(f"<gml:startPoint> 修正: {start_point_value} -> 0 0, データなし,-9999. を {calculated_rows} 行挿入")

                # 値を修正
                lines[i] = "<gml:startPoint>0 0</gml:startPoint>\n"

                # データなし行を挿入
                extra_lines = ["データなし,-9999.\n"] * calculated_rows
                tuple_list_lines = extra_lines + tuple_list_lines

    current_count = len(tuple_list_lines)

    # 不足分を計算
    missing_count = total_rows - current_count

    if missing_count > 0:
        print(f"不足している行数: {missing_count} をデータなしで補完")
        # 不足分を補う
        missing_data = ["データなし,-9999.\n"] * missing_count
        tuple_list_lines.extend(missing_data)

    # <gml:tupleList> の内容を更新
    updated_lines = lines[:start_index + 1] + tuple_list_lines + lines[end_index:]

    # 更新された内容を出力ファイルに書き込む
    with open(output_file, "w", encoding="utf-8", newline="") as f:
        f.writelines(updated_lines)

if __name__ == "__main__":
    args = parse_arguments()
    fill_missing_data(args.input_file, args.output_file)
