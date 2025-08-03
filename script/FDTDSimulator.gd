extends Node2D

# シミュレーション領域の定義
const GRID_WIDTH = 512  # グリッドの幅
const GRID_HEIGHT = 512 # グリッドの高さ

var time = 0.0

# FDTD法で使用する物理量を格納する配列
# PackedFloat32Arrayは高速な浮動小数点数配列
var ez: PackedFloat32Array = PackedFloat32Array() # 電場 (Ez成分)
var hx: PackedFloat32Array = PackedFloat32Array() # 磁場 (Hx成分)
var hy: PackedFloat32Array = PackedFloat32Array() # 磁場 (Hy成分)

# ノードがシーンツリーに追加されたときに一度だけ呼び出される初期化関数
func _ready():
	# 各配列をグリッドサイズに合わせてリサイズし、全要素を0.0で初期化
	ez.resize(GRID_WIDTH * GRID_HEIGHT)
	hx.resize(GRID_WIDTH * GRID_HEIGHT)
	hy.resize(GRID_WIDTH * GRID_HEIGHT)


func _process(delta):

	time += delta

	# Step A: 現在の電場(ez)を使って、次の瞬間の磁場(hx, hy)を計算
	for y in range(1, GRID_HEIGHT - 1):
		for x in range(1, GRID_WIDTH - 1):
			# ここに磁場を更新する計算式が入る
			var idx = y * GRID_WIDTH + x
			hx[idx] += (ez[idx] - ez[idx - GRID_WIDTH]) # Ezの変化からHxを計算
			hy[idx] += (ez[idx + 1] - ez[idx])         # Ezの変化からHyを計算


	# Step B: 更新された磁場(hx, hy)を使って、次の瞬間の電場(ez)を計算
	for y in range(1, GRID_HEIGHT - 1):
		for x in range(1, GRID_WIDTH - 1):
			# ここに電場を更新する計算式が入る
			var idx = y * GRID_WIDTH + x
			ez[idx] += (hy[idx] - hy[idx - 1]) - (hx[idx] - hx[idx - GRID_WIDTH]) # Hx,Hyの変化からEzを計算


	var center_x = GRID_WIDTH / 2
	var center_y = GRID_HEIGHT / 2
	var center_idx = center_y * GRID_WIDTH + center_x
