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
var obstacle_map: PackedByteArray
var last_mouse_grid_pos: Vector2i = Vector2i(-1, -1) # 最後に描画したマウスのグリッド座標


# ノードがシーンツリーに追加されたときに一度だけ呼び出される初期化関数
func _ready():
	# 各配列をグリッドサイズに合わせてリサイズし、全要素を0.0で初期化
	ez.resize(GRID_WIDTH * GRID_HEIGHT)
	hx.resize(GRID_WIDTH * GRID_HEIGHT)
	hy.resize(GRID_WIDTH * GRID_HEIGHT)
	obstacle_map.resize(GRID_WIDTH * GRID_HEIGHT)

	image = Image.create(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)
	$TextureRect.texture = texture

	# 波源のインデックスを一度だけ計算して保存
	center_idx = (GRID_HEIGHT / 2) * GRID_WIDTH + (GRID_WIDTH / 2)

func _process(delta):
	time += delta

	# 物理演算の更新
	_update_physics()

	# sin波を生成して中央の電場を揺らす
	#ez[center_idx] = sin(time * WAVE_FREQUENCY)

	# テクスチャの更新
	_update_texture()

# FDTD法の計算を実行する
func _update_physics():
	_update_magnetic_field()
	_update_electric_field()

# Step A: 現在の電場(ez)を使って、次の瞬間の磁場(hx, hy)を計算
func _update_magnetic_field():
	for y in range(1, GRID_HEIGHT - 1):
		for x in range(1, GRID_WIDTH - 1):
			var idx = y * GRID_WIDTH + x
			hx[idx] = hx[idx] - COURANT_NUMBER * (ez[idx] - ez[idx - GRID_WIDTH])
			hy[idx] = hy[idx] + COURANT_NUMBER * (ez[idx + 1] - ez[idx])

# Step B: 更新された磁場(hx, hy)を使って、次の瞬間の電場(ez)を計算
func _update_electric_field():
	for y in range(1, GRID_HEIGHT - 1):
		for x in range(1, GRID_WIDTH - 1):
			var idx = y * GRID_WIDTH + x

			if idx == center_idx:
				continue

			ez[idx] = ez[idx] + COURANT_NUMBER * ((hy[idx] - hy[idx - 1]) - (hx[idx + GRID_WIDTH] - hx[idx]))

			if obstacle_map[idx] == 1:
				ez[idx] = 0.0


# シミュレーション結果をテクスチャに描画する
func _update_texture():
	var pixels = PackedByteArray()
	pixels.resize(GRID_WIDTH * GRID_HEIGHT)

	for i in range(ez.size()):
		if obstacle_map[i] == 1:
			# 障害物は中間の灰色(128)としてエンコード
			pixels[i] = 128
		else:
			# ezの値を -1.0 ~ 1.0 から 0 ~ 255 の範囲に変換
			var value = clampf(ez[i], -1.0, 1.0) # 値が大きくなりすぎないように制限
			pixels[i] = int((value + 1.0) * 0.5 * 255.0)

	image.set_data(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_L8, pixels)
	texture.update(image) # 既存のテクスチャを新しい画像データで更新


# 波源を追加する関数 (ハードソース)
# grid_x, grid_y: 波源のグリッド座標
# strength: 設定する電場の強さ
func add_source(grid_x: int, grid_y: int, strength: float):
	# 座標がグリッド範囲外なら何もしない
	if grid_x < 1 or grid_x >= GRID_WIDTH - 1 or grid_y < 1 or grid_y >= GRID_HEIGHT - 1:
		return

	var idx = grid_y * GRID_WIDTH + grid_x
	ez[idx] = strength # 電場を直接設定（ハードソース）

# マウスのグローバル座標をグリッド座標に変換するヘルパー関数
func get_mouse_grid_pos() -> Vector2i:
	var local_pos = $TextureRect.get_local_mouse_position()
	var rect_size = $TextureRect.size
	# rect_sizeが0だとゼロ除算エラーになるのを防ぐ
	if rect_size.x == 0 or rect_size.y == 0:
		return Vector2i(-1, -1)
	var grid_x = int(local_pos.x / rect_size.x * GRID_WIDTH)
	var grid_y = int(local_pos.y / rect_size.y * GRID_HEIGHT)
	return Vector2i(grid_x, grid_y)

# ブレゼンハムのアルゴリズムを使って、2点間に障害物の直線を引く
func draw_obstacle_line(p1: Vector2i, p2: Vector2i):
	var x1 = p1.x
	var y1 = p1.y
	var x2 = p2.x
	var y2 = p2.y

	var dx = abs(x2 - x1)
	var sx = 1 if x1 < x2 else -1
	var dy = -abs(y2 - y1)
	var sy = 1 if y1 < y2 else -1
	var err = dx + dy

	while true:
		# 座標がグリッド範囲内かチェック
		if x1 >= 0 and x1 < GRID_WIDTH and y1 >= 0 and y1 < GRID_HEIGHT:
			var idx = y1 * GRID_WIDTH + x1
			obstacle_map[idx] = 1

		if x1 == x2 and y1 == y2:
			break

		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x1 += sx
		if e2 <= dx:
			err += dx
			y1 += sy

func _input(event):
	# --- 障害物描画ロジック ---
	# 左ボタンが押された瞬間
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			var current_pos = get_mouse_grid_pos()
			if current_pos.x >= 0: # 有効な座標かチェック
				draw_obstacle_line(current_pos, current_pos) # 1ピクセルだけ描画
			last_mouse_grid_pos = current_pos
		else: # ボタンが離された時
			last_mouse_grid_pos = Vector2i(-1, -1) # 追跡をリセット

	# 左ボタンが押されたままマウスが動いた場合
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if last_mouse_grid_pos.x >= 0: # ドラッグが開始されているかチェック
			var current_pos = get_mouse_grid_pos()
			if current_pos.x >= 0 and current_pos != last_mouse_grid_pos:
				draw_obstacle_line(last_mouse_grid_pos, current_pos)
				last_mouse_grid_pos = current_pos

	# --- 波源追加ロジック ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		var grid_pos = get_mouse_grid_pos()
		if grid_pos.x >= 0:
			add_source(grid_pos.x, grid_pos.y, click_strength)
