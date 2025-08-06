extends Control

@export_category("Simulation Parameters")
@export var click_strength: float = 5.0 # クリック時の波の強さ

# シミュレーション領域の定義
const GRID_WIDTH = 512  # グリッドの幅（解像度を上げる）
const GRID_HEIGHT = 512 # グリッドの高さ（解像度を上げる）

# FDTD法の安定性を保つための係数 (クーラン数)
# 2Dの場合、この値は 1/sqrt(2) (約0.707) 以下である必要があります
const COURANT_NUMBER = 0.5
const WAVE_FREQUENCY = 8.0 # 波の周波数（値を小さくすると波長が長くなる）

var time = 0.0


var image: Image
var texture: ImageTexture

# FDTD法で使用する物理量を格納する配列
# PackedFloat32Arrayは高速な浮動小数点数配列
var ez: PackedFloat32Array = PackedFloat32Array() # 電場 (Ez成分)
var hx: PackedFloat32Array = PackedFloat32Array() # 磁場 (Hx成分)
var hy: PackedFloat32Array = PackedFloat32Array() # 磁場 (Hy成分)
var center_idx: int # 波源の中心インデックス

# ノードがシーンツリーに追加されたときに一度だけ呼び出される初期化関数
func _ready():
	# 各配列をグリッドサイズに合わせてリサイズし、全要素を0.0で初期化
	ez.resize(GRID_WIDTH * GRID_HEIGHT)
	hx.resize(GRID_WIDTH * GRID_HEIGHT)
	hy.resize(GRID_WIDTH * GRID_HEIGHT)

	image = Image.create(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)
	$TextureRect.texture = texture

	# 波源のインデックスを一度だけ計算して保存
	center_idx = (GRID_HEIGHT / 2) * GRID_WIDTH + (GRID_WIDTH / 2)

func _process(delta):

	time += delta

	# Step A: 現在の電場(ez)を使って、次の瞬間の磁場(hx, hy)を計算
	for y in range(1, GRID_HEIGHT - 1):
		for x in range(1, GRID_WIDTH - 1):
			# ここに磁場を更新する計算式が入る
			var idx = y * GRID_WIDTH + x
			hx[idx] = hx[idx] - COURANT_NUMBER * (ez[idx] - ez[idx - GRID_WIDTH])
			hy[idx] = hy[idx] + COURANT_NUMBER * (ez[idx + 1] - ez[idx])


	# Step B: 更新された磁場(hx, hy)を使って、次の瞬間の電場(ez)を計算
	for y in range(1, GRID_HEIGHT - 1):
		for x in range(1, GRID_WIDTH - 1):
			# ここに電場を更新する計算式が入る
			var idx = y * GRID_WIDTH + x

			if idx == center_idx:
				continue

			ez[idx] = ez[idx] + COURANT_NUMBER * ((hy[idx] - hy[idx - 1]) - (hx[idx + GRID_WIDTH] - hx[idx]))


	# sin波を生成して中央の電場を揺らす
	#ez[center_idx] = sin(time * WAVE_FREQUENCY) # ハードソース：値を加算ではなく、直接上書きする

	var pixels = PackedByteArray()
	pixels.resize(GRID_WIDTH * GRID_HEIGHT)

	for i in range(ez.size()):
		# ezの値を -1.0 ~ 1.0 から 0 ~ 255 の範囲に変換
		var value = clampf(ez[i], -1.0, 1.0) # 値が大きくなりすぎないように制限
		pixels[i] = int((value + 1.0) * 0.5 * 255.0)

	image.set_data(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_L8, pixels)
	texture.update(image) # 既存のテクスチャを新しい画像データで更新


# 波源を追加する関数
# grid_x, grid_y: 波源のグリッド座標
# strength: 設定する電場の強さ
func add_source(grid_x: int, grid_y: int, strength: float):
	# 座標がグリッド範囲外なら何もしない
	if grid_x < 1 or grid_x >= GRID_WIDTH - 1 or grid_y < 1 or grid_y >= GRID_HEIGHT - 1:
		return

	var idx = grid_y * GRID_WIDTH + grid_x
	ez[idx] = strength # 電場を直接設定（ハードソース）

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		# TextureRectのローカル座標に変換
		var local_pos = $TextureRect.get_local_mouse_position()
		var rect_size = $TextureRect.size

		# グリッド座標に変換（TextureRectのサイズでスケーリング）
		var grid_x = int(local_pos.x / rect_size.x * GRID_WIDTH)
		var grid_y = int(local_pos.y / rect_size.y * GRID_HEIGHT)

		# 波源を追加する関数を呼び出す
		add_source(grid_x, grid_y, click_strength)
