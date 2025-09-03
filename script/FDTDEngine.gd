extends RefCounted
class_name FDTDEngine

# --- 定数 ---
# シミュレーション領域の定義
const GRID_WIDTH = 256#512  # グリッドの幅
const GRID_HEIGHT = 256#512 # グリッドの高さ

# FDTD法の安定性を保つための係数 (クーラン数)
const COURANT_NUMBER = 0.5
const WAVE_FREQUENCY = 8.0 # 波の周波数（値を小さくすると波長が長くなる）

# 障害物マップ用の内部フラグ
const OBSTACLE_FLAG: int = 1
const NO_OBSTACLE_FLAG: int = 0

# --- プロパティ ---
var time: float = 0.0 # シミュレーションの経過時間
var time_scale: float = 0.2 # シミュレーションの速度倍率

# FDTD法で使用する物理量を格納する配列
var ez: PackedFloat32Array # 電場 (Ez成分)
var hx: PackedFloat32Array # 磁場 (Hx成分)
var hy: PackedFloat32Array # 磁場 (Hy成分)
var obstacle_map: PackedByteArray

var center_idx: int # 波源の中心インデックス

# --- コンストラクタ ---
func _init():
	# 各インスタンスが固有の配列を持つように、ここで初期化する
	# (クラスメンバとして初期化すると全インスタンスで共有されてしまうため)
	ez = PackedFloat32Array()
	hx = PackedFloat32Array()
	hy = PackedFloat32Array()
	obstacle_map = PackedByteArray()

# --- 初期化 ---
func initialize():
	var size = GRID_WIDTH * GRID_HEIGHT

	ez.resize(size)
	hx.resize(size)
	hy.resize(size)
	obstacle_map.resize(size)

	center_idx = (GRID_HEIGHT / 2) * GRID_WIDTH + (GRID_WIDTH / 2)
	reset()

# --- 公開メソッド (API) ---

func step(delta: float):
	time += delta * time_scale
	_update_physics()

func reset():
	ez.fill(0.0)
	hx.fill(0.0)
	hy.fill(0.0)
	obstacle_map.fill(NO_OBSTACLE_FLAG)
	time = 0.0

func add_source(grid_x: int, grid_y: int, strength: float):
	if grid_x < 1 or grid_x >= GRID_WIDTH - 1 or grid_y < 1 or grid_y >= GRID_HEIGHT - 1:
		return
	var idx = grid_y * GRID_WIDTH + grid_x
	ez[idx] = strength

func add_obstacle_line(p1: Vector2i, p2: Vector2i):
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
		if x1 >= 0 and x1 < GRID_WIDTH and y1 >= 0 and y1 < GRID_HEIGHT:
			var idx = y1 * GRID_WIDTH + x1
			obstacle_map[idx] = OBSTACLE_FLAG

		if x1 == x2 and y1 == y2:
			break

		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x1 += sx
		if e2 <= dx:
			err += dx
			y1 += sy

# --- 描画データ生成 ---

# シェーダーで障害物として描画するための固定値 (0-255)
const OBSTACLE_DRAW_VALUE: int = 128

func get_image_data() -> PackedByteArray:
	"""
	現在のシミュレーション状態をテクスチャ用のバイト配列に変換します。
	- 電場(ez)の値は -1.0..1.0 から 0..255 の範囲にマッピングされます。
	- 障害物は特別な値 OBSTACLE_DRAW_VALUE (128) としてエンコードされます。
	- 電場の値がエンコード後に 128 にならないように調整し、障害物との衝突を避けます。
	"""
	var data = PackedByteArray()
	data.resize(ez.size())
	for i in range(ez.size()):
		if obstacle_map[i] == OBSTACLE_FLAG:
			data[i] = OBSTACLE_DRAW_VALUE
		else:
			# ez の値 (-1.0 to 1.0) を 0-255 の範囲にマッピング
			var val = clampf(ez[i], -1.0, 1.0)
			var mapped_val = int((val * 0.5 + 0.5) * 255.0)
			if mapped_val == OBSTACLE_DRAW_VALUE:
				mapped_val += 1 # 128 は障害物用に予約されているため、129にずらす
			data[i] = clamp(mapped_val, 0, 255)
	return data

# --- 内部計算ロジック ---

func _update_physics():
	_update_magnetic_field()
	_update_electric_field()
	# 中心に時間変化する波源を設置 (正弦波)
	#ez[center_idx] = sin(time * WAVE_FREQUENCY)

func _update_magnetic_field():
	var update_factor = COURANT_NUMBER * time_scale

	# Hxの更新: Hx(i, j+1/2) = Hx(...) - C * (Ez(i, j+1) - Ez(i, j))
	# ループ範囲: yは0からGRID_HEIGHT-2まで (ez[idx+GRID_WIDTH]にアクセスするため)
	# xは0からGRID_WIDTH-1まで (Hxはグリッドの左右両端にも存在する)
	for y in range(0, GRID_HEIGHT - 1):
		for x in range(0, GRID_WIDTH):
			var idx = y * GRID_WIDTH + x
			var idx_plus_y = idx + GRID_WIDTH
			hx[idx] = hx[idx] - update_factor * (ez[idx_plus_y] - ez[idx])

	# Hyの更新: Hy(i+1/2, j) = Hy(...) + C * (Ez(i+1, j) - Ez(i, j))
	# ループ範囲: yは0からGRID_HEIGHT-1まで (Hyはグリッドの上下両端にも存在する)
	# xは0からGRID_WIDTH-2まで (ez[idx+1]にアクセスするため)
	for y in range(0, GRID_HEIGHT):
		for x in range(0, GRID_WIDTH - 1):
			var idx = y * GRID_WIDTH + x
			var idx_plus_x = idx + 1
			hy[idx] = hy[idx] + update_factor * (ez[idx_plus_x] - ez[idx])

func _update_electric_field():
	var update_factor = COURANT_NUMBER * time_scale

	# 電場の更新。境界(0と-1)を含めないことで、範囲外アクセスを防ぐ。
	# このネストしたループはアルゴリズムを最も直接的に表現しています。
	# もしこれでも稀に不安定な場合、GDScriptのJITコンパイラに関連するエンジン側の問題である可能性が高いです。
	for y in range(1, GRID_HEIGHT - 1):
		for x in range(1, GRID_WIDTH - 1):
			var idx = y * GRID_WIDTH + x
			var idx_minus_x = idx - 1
			var idx_minus_y = idx - GRID_WIDTH
			
			ez[idx] = ez[idx] + update_factor * ((hy[idx] - hy[idx_minus_x]) - (hx[idx] - hx[idx_minus_y]))

			if obstacle_map[idx] == OBSTACLE_FLAG:
				ez[idx] = 0.0
