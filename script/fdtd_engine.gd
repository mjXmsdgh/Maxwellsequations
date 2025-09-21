# fdtd_engine.gd
# シミュレーションの計算ロジックを担当するクラス
# Resourceを継承することで、シーンに依存せずデータとして扱えるようになります。
extends Resource # RefCountedを継承しているため、メモリ管理上有利です
class_name FDTDEngine

# --- 定数 ---
const GRID_WIDTH = 512
const GRID_HEIGHT = 512

# --- 物理パラメータ ---
const IMP0 = 377.0 # 真空のインピーダンス
const COURANT_NUMBER = 0.5 # FDTD法の安定性を保つための係数 (クーラン数)

# --- シミュレーション用データ配列 ---
var ez: PackedFloat32Array = PackedFloat32Array() # Z方向の電場
var hx: PackedFloat32Array = PackedFloat32Array() # X方向の磁場
var hy: PackedFloat32Array = PackedFloat32Array() # Y方向の磁場

# 媒質の特性を格納する配列
var ca: PackedFloat32Array = PackedFloat32Array() # 電場更新係数 (Epsilon依存)


# 初期化関数
func initialize():
	# 各配列のサイズを確保し、0またはデフォルト値で初期化

	var size = GRID_WIDTH * GRID_HEIGHT
	ez.resize(size)
	ez.fill(0.0)
	hx.resize(size)
	hx.fill(0.0)
	hy.resize(size)
	hy.fill(0.0)
	ca.resize(size)

	# 媒質係数を真空のデフォルト値で埋める
	# (epsilon_r = 1, sigma = 0)
	ca.fill(1.0)


# シミュレーションを1ステップ進める
func step(_delta):
	# --- ステップA: 磁場の更新 (H-field update) ---
	var h_update_factor = COURANT_NUMBER / IMP0

	# Hxの更新: y方向の差分を取るため、yのループ範囲を1つ狭める
	for y in range(GRID_HEIGHT - 1):
		for x in range(GRID_WIDTH):
			var idx = y * GRID_WIDTH + x
			hx[idx] -= (ez[idx + GRID_WIDTH] - ez[idx]) * h_update_factor

	# Hyの更新: x方向の差分を取るため、xのループ範囲を1つ狭める
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH - 1):
			var idx = y * GRID_WIDTH + x
			hy[idx] += (ez[idx + 1] - ez[idx]) * h_update_factor

	# --- ステップB: 電場の更新 (E-field update) ---
	# 更新された磁場(hx, hy)から、次の半ステップの電場(ez)を計算
	var e_update_factor = COURANT_NUMBER * IMP0
	for y in range(1, GRID_HEIGHT):
		for x in range(1, GRID_WIDTH):
			var idx = y * GRID_WIDTH + x
			var curl_h = (hy[idx] - hy[idx - 1]) - (hx[idx] - hx[idx - GRID_WIDTH])
			ez[idx] += ca[idx] * curl_h * e_update_factor


# シミュレーションをリセットする
func reset():
	# initializeを再実行することで、すべての配列と係数を初期状態に戻す
	initialize()


# 指定した座標に波源を追加する
func add_source(x: int, y: int, value: float):
	# 座標が範囲内であることを確認
	if x > 0 and x < GRID_WIDTH and y > 0 and y < GRID_HEIGHT:
		var idx = y * GRID_WIDTH + x
		ez[idx] = value


# 指定した矩形領域に媒質を設定する
func add_medium_rect(start_pos: Vector2i, end_pos: Vector2i, refractive_index: float):
	var x_start = min(start_pos.x, end_pos.x)
	var x_end = max(start_pos.x, end_pos.x)
	var y_start = min(start_pos.y, end_pos.y)
	var y_end = max(start_pos.y, end_pos.y)

	var epsilon_r = refractive_index * refractive_index # 屈折率nの二乗が比誘電率ε_r
	
	for y in range(y_start, y_end + 1):
		for x in range(x_start, x_end + 1):
			if x >= 0 and x < GRID_WIDTH and y >= 0 and y < GRID_HEIGHT:
				var idx = y * GRID_WIDTH + x
				# Yeeのアルゴリズムにおける係数を設定
				# ここでは損失(sigma)は0と仮定
				ca[idx] = 1.0 / epsilon_r
