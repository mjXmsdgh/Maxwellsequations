# fdtd_engine.gd
# シミュレーションの計算ロジックを担当するクラス
# Resourceを継承することで、シーンに依存せずデータとして扱えるようになります。
extends Resource # RefCountedを継承しているため、メモリ管理上有利です
class_name FDTDEngine

# --- 定数 ---
const GRID_WIDTH = 512
const GRID_HEIGHT = 512
const OBSTACLE_PIXEL_VALUE = 128 # 障害物を表すピクセル値 (0-255の中間)

# --- 物理パラメータ ---
const IMP0 = 377.0 # 真空のインピーダンス
const COURANT_NUMBER = 0.5 # FDTD法の安定性を保つための係数 (クーラン数)

# --- シミュレーション用データ配列 ---
var ez: PackedFloat32Array # Z方向の電場
var hx: PackedFloat32Array # X方向の磁場
var hy: PackedFloat32Array # Y方向の磁場

# 媒質の特性を格納する配列
var ca: PackedFloat32Array # 電場更新係数 (Epsilon依存)
var cb: PackedFloat32Array # 電場更新係数 (Sigma依存)

# 障害物情報を格納する配列 (1なら障害物, 0なら何もない)
var obstacle: PackedByteArray


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
	cb.resize(size)

	obstacle.resize(GRID_WIDTH * GRID_HEIGHT)

	# 媒質係数を真空のデフォルト値で埋める
	# (epsilon_r = 1, sigma = 0)
	ca.fill(1.0)
	cb.fill(1.0)
	
	# 障害物情報をクリア (0で埋める)
	obstacle.fill(0)


# シミュレーションを1ステップ進める
func step(_delta):
	# --- ステップA: 磁場の更新 (H-field update) ---
	var h_update_factor = COURANT_NUMBER / IMP0

	# Hxの更新: y方向の差分を取るため、yのループ範囲を1つ狭める
	for y in range(GRID_HEIGHT - 1):
		for x in range(GRID_WIDTH):
			var idx = y * GRID_WIDTH + x
			# 障害物(1)でなければ更新
			if obstacle[idx] == 0:
				hx[idx] -= (ez[idx + GRID_WIDTH] - ez[idx]) * h_update_factor

	# Hyの更新: x方向の差分を取るため、xのループ範囲を1つ狭める
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH - 1):
			var idx = y * GRID_WIDTH + x
			# 障害物(1)でなければ更新
			if obstacle[idx] == 0:
				hy[idx] += (ez[idx + 1] - ez[idx]) * h_update_factor

	# --- ステップB: 電場の更新 (E-field update) ---
	# 更新された磁場(hx, hy)から、次の半ステップの電場(ez)を計算
	var e_update_factor = COURANT_NUMBER * IMP0
	for y in range(1, GRID_HEIGHT):
		for x in range(1, GRID_WIDTH):
			var idx = y * GRID_WIDTH + x
			# 障害物(1)でなければ更新
			if obstacle[idx] == 0:
				var curl_h = (hy[idx] - hy[idx - 1]) - (hx[idx] - hx[idx - GRID_WIDTH])
				ez[idx] += ca[idx] * curl_h * e_update_factor


# シミュレーションをリセットする
func reset():
	# initializeを再実行することで、すべての配列と係数を初期状態に戻す
	initialize()


# 指定した座標に波源を追加する
func add_source(x: int, y: int, value: float):
	# 座標が範囲内かつ障害物でないことを確認
	if x > 0 and x < GRID_WIDTH and y > 0 and y < GRID_HEIGHT:
		var idx = y * GRID_WIDTH + x
		if obstacle[idx] == 0:
			ez[idx] = value


# 2点間に障害物の線を描画する (ブレゼンハムのアルゴリズム)
func add_obstacle_line(start_pos: Vector2i, end_pos: Vector2i):
	var x0 = start_pos.x
	var y0 = start_pos.y
	var x1 = end_pos.x
	var y1 = end_pos.y

	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy

	while true:
		var idx = y0 * GRID_WIDTH + x0
		if idx >= 0 and idx < obstacle.size():
			obstacle[idx] = 1 # 障害物を1として設定
			# 障害物を設定した場所の係数を0にして、場が更新されないようにする
			ca[idx] = 0.0
			cb[idx] = 0.0
			ez[idx] = 0.0 # 電場もクリア

		if x0 == x1 and y0 == y1:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


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
				if obstacle[idx] == 0:
					# Yeeのアルゴリズムにおける係数を設定
					# ここでは損失(sigma)は0と仮定
					ca[idx] = 1.0 / epsilon_r
					cb[idx] = 1.0


# 描画用の画像データを生成して返すインターフェース関数
func get_image_data() -> PackedByteArray:
	var pixels = PackedByteArray()
	pixels.resize(GRID_WIDTH * GRID_HEIGHT)

	for i in range(ez.size()):
		if obstacle[i] == 1:
			# 障害物がある場所は固定値で上書き
			pixels[i] = OBSTACLE_PIXEL_VALUE
		else:
			# 電場の値を -1.0 ~ 1.0 から 0 ~ 255 の範囲に変換
			# ただし、障害物を示す128は避ける
			var value = clampf(ez[i], -1.0, 1.0) # 値が発散しないように制限
			var pixel_value = int((value + 1.0) * 0.5 * 255.0)
			
			if pixel_value == OBSTACLE_PIXEL_VALUE:
				pixel_value += 1 # 障害物と値が被ったら1ずらす
			
			pixels[i] = pixel_value

	return pixels

# 計算結果（電場データ）を外部から取得するためのインターフェース関数
func get_field_data() -> PackedFloat32Array:
	# 生の電場データをそのまま返す
	return ez
