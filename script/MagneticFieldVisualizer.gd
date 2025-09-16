extends Node2D

@export_category("Visualization")
@export var vector_color: Color = Color.YELLOW
@export_range(1, 50, 1) var draw_step: int = 16 # ベクトルを描画する間隔（グリッド単位）

@export_group("Vector Scaling", "vector_")
@export var auto_scale: bool = true # ベクトルの長さを自動で調整するか
@export_range(1.0, 100.0) var vector_scale: float = 20.0 # ベクトルの長さの倍率（auto_scale=false）または最大長（auto_scale=true）
@export_group("Arrowhead", "arrowhead_")
@export var arrowhead_draw: bool = true
@export_range(1.0, 20.0) var arrowhead_length: float = 2.0
@export_range(0.0, 90.0) var arrowhead_angle_deg: float = 30.0

# 非常に短いベクトルを描画しないための閾値 (長さの2乗)
const MIN_VECTOR_LENGTH_SQ = 1e-9

# --- 依存コンポーネント ---
# 司令塔(MainController)から設定される
@export var engine: FDTDEngine
@export var texture_rect: TextureRect

# 描画する点の情報を事前に計算して格納する配列
var _draw_points_info: Array[Dictionary] = []
var _is_initialized: bool = false


func _ready():
	# MainControllerがinitialize()を呼び出すのを待つため、
	# 初期化が完了するまでプロセスを無効化しておく。
	set_process(false)


func initialize():
	"""司令塔(MainController)によって依存性が注入された後に呼び出される初期化関数。"""
	# 必要なコンポーネントが設定されているか確認
	if not is_instance_valid(engine):
		push_error("FDTDEngine is not assigned to MagneticFieldVisualizer.")
		return
	if not is_instance_valid(texture_rect):
		push_error("Could not find TextureRect node in the parent simulator.")
		return

	# 描画する点の情報を事前計算する
	_precalculate_draw_points()
	_is_initialized = true
	set_process(true) # 初期化が完了したので、プロセスを開始する

func _process(_delta):
	# 毎フレーム再描画を要求する
	queue_redraw()


func _precalculate_draw_points():
	"""
	ベクトルを描画するグリッド上の点とインデックスを事前に計算し、
	_draw_points_info 配列に格納する。_ready() で一度だけ呼び出す。
	"""
	_draw_points_info.clear()
	var grid_width: int = engine.GRID_WIDTH
	var grid_height: int = engine.GRID_HEIGHT
	if grid_width == 0 or grid_height == 0:
		return

	# 補間に伴う配列の範囲外アクセスを避けるため、ループ範囲を y=1 から開始
	for y in range(1, grid_height - 1, draw_step):
		for x in range(1, grid_width, draw_step):
			var idx = y * grid_width + x
			_draw_points_info.append({"idx": idx, "grid_pos": Vector2(x, y)})

func _prepare_vectors_to_draw() -> Array[Dictionary]:
	"""シミュレーションデータから描画すべきベクトルのリストを作成して返す。"""
	# シミュレータから必要な情報を取得
	var hx: PackedFloat32Array = engine.hx
	var hy: PackedFloat32Array = engine.hy
	if hx.is_empty() or hy.is_empty():
		return []
	
	# 事前計算された描画点がなければ何もしない
	if _draw_points_info.is_empty():
		return []

	var grid_width: int = engine.GRID_WIDTH
	var grid_height: int = engine.GRID_HEIGHT
	var rect_size: Vector2 = texture_rect.size

	# グリッド座標から描画座標への変換スケール
	var coord_scale: Vector2 = rect_size / Vector2(grid_width, grid_height)

	var vectors: Array[Dictionary] = []
	# 事前計算した点のリストをループする
	for point_info in _draw_points_info:
		var idx: int = point_info.idx
		# Yeeグリッドのスタッガード配置を考慮し、磁場ベクトルをEzグリッド中心(i,j)に補間
		var hx_interp = (hx[idx] + hx[idx - grid_width]) * 0.5
		var hy_interp = (hy[idx] + hy[idx - 1]) * 0.5
		var vec_h = Vector2(hx_interp, hy_interp)
		# ベクトルの長さが非常に小さい場合はスキップ
		if vec_h.length_squared() < MIN_VECTOR_LENGTH_SQ:
			continue
		var start_pos = point_info.grid_pos * coord_scale
		vectors.append({"vec": vec_h, "pos": start_pos})
	
	return vectors


func _calculate_draw_scale(vectors: Array[Dictionary]) -> float:
	"""描画データのリストを基に、ベクトルの描画スケールを計算して返す。"""
	if not auto_scale:
		return vector_scale

	var max_h_sq = 0.0
	# 準備したデータから最大値(の2乗)を求める
	for v_data in vectors:
		max_h_sq = max(max_h_sq, v_data.vec.length_squared())

	if max_h_sq > MIN_VECTOR_LENGTH_SQ:
		var max_h = sqrt(max_h_sq)
		# 最大長のベクトルが `vector_scale` の長さで描画されるようにスケールを計算
		return vector_scale / max_h
	
	# ゼロ除算を避け、ベクトルが非常に小さい場合は固定スケールを返す
	return vector_scale


func _draw_single_vector(start_pos: Vector2, end_pos: Vector2, color: Color):
	"""1本のベクトル（線本体と矢印の先端）を描画する。"""
	# ベクトルの本体（線）を描画
	draw_line(start_pos, end_pos, color, 1.0, true) # antialiased = true

	# 矢印の先端を描画
	if not arrowhead_draw:
		return

	# 描画されたベクトルの長さが非常に短い場合、矢印を描画しても見栄えが悪いのでスキップ
	if start_pos.distance_squared_to(end_pos) < 1.0:
		return

	var arrowhead_angle_rad = deg_to_rad(arrowhead_angle_deg)
	var direction = (end_pos - start_pos).normalized()
	var p1 = end_pos - direction.rotated(arrowhead_angle_rad) * arrowhead_length
	var p2 = end_pos - direction.rotated(-arrowhead_angle_rad) * arrowhead_length
	draw_line(end_pos, p1, color, 1.0, true) # antialiased = true
	draw_line(end_pos, p2, color, 1.0, true) # antialiased = true

func _draw():
	# 初期化が完了しているか、engineが有効かを確認
	if not _is_initialized or not is_instance_valid(engine):
		return

	# ステップ1: 描画するベクトルのデータを準備する
	var vectors_to_draw: Array[Dictionary] = _prepare_vectors_to_draw()

	if vectors_to_draw.is_empty():
		return

	# ステップ2: 描画スケールを計算する
	var current_scale: float = _calculate_draw_scale(vectors_to_draw)

	# ステップ3: 準備したデータと計算したスケールを使ってベクトルを1本ずつ描画
	for v_data in vectors_to_draw:
		var start_pos: Vector2 = v_data.pos
		var vec_h: Vector2 = v_data.vec

		# スケールを適用して終点を計算
		var end_pos = start_pos + vec_h * current_scale

		# ヘルパー関数を呼び出してベクトルを描画
		_draw_single_vector(start_pos, end_pos, vector_color)
