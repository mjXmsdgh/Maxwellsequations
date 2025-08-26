extends RefCounted
class_name FDTDEngine

# --- 定数 ---
# シミュレーション領域の定義
const GRID_WIDTH = 256#512  # グリッドの幅
const GRID_HEIGHT = 256#512 # グリッドの高さ

# FDTD法の安定性を保つための係数 (クーラン数)
const COURANT_NUMBER = 0.5
const WAVE_FREQUENCY = 8.0 # 波の周波数（値を小さくすると波長が長くなる）

const OBSTACLE_VALUE: int = 1

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
	obstacle_map.fill(0)
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
			obstacle_map[idx] = OBSTACLE_VALUE

		if x1 == x2 and y1 == y2:
			break

		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x1 += sx
		if e2 <= dx:
			err += dx
			y1 += sy

# --- 内部計算ロジック ---

func _update_physics():
	_update_magnetic_field()
	_update_electric_field()
	# 中心に時間変化する波源を設置 (正弦波)
	#ez[center_idx] = sin(time * WAVE_FREQUENCY)

func _update_magnetic_field():
	var update_factor = COURANT_NUMBER * time_scale
	for y in range(1, GRID_HEIGHT - 1):
		# Hxの更新: Hx(i, j+1/2)はEz(i, j+1)とEz(i, j)から計算される
		# ループ範囲がHyと異なる場合があるが、ここでは簡単化のため同じループで処理
		for x in range(1, GRID_WIDTH - 1): # 本来は for x in range(0, GRID_WIDTH -1)
			var idx = y * GRID_WIDTH + x
			# Hxの更新式を、より標準的なYeeグリッドの定義に修正
			# Hx(i, j+1/2)の更新は -C * (Ez(i, j+1) - Ez(i, j))
			hx[idx] = hx[idx] - update_factor * (ez[idx + GRID_WIDTH] - ez[idx])
			# Hyの更新式は元々標準的な定義と一致していた
			# Hy(i+1/2, j)の更新は C * (Ez(i+1, j) - Ez(i, j))
			hy[idx] = hy[idx] + update_factor * (ez[idx + 1] - ez[idx])

func _update_electric_field():
	var update_factor = COURANT_NUMBER * time_scale
	for y in range(1, GRID_HEIGHT - 1):
		for x in range(1, GRID_WIDTH - 1):
			var idx = y * GRID_WIDTH + x

			# Hxのインデックス定義の変更に伴い、Ezの更新式も修正
			# dHx/dy は Hx(i, j+1/2) - Hx(i, j-1/2) -> hx[idx] - hx[idx - GRID_WIDTH]
			ez[idx] = ez[idx] + update_factor * ((hy[idx] - hy[idx - 1]) - (hx[idx] - hx[idx - GRID_WIDTH]))

			if obstacle_map[idx] == OBSTACLE_VALUE:
				ez[idx] = 0.0
