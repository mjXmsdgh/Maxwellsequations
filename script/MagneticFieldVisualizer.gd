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

# FDTDSimulatorノードと、その中のTextureRectへの参照
# @onready を使うことで、シーンの準備完了時に一度だけノードを取得します
@onready var simulator: FDTDSimulator = get_parent()
@onready var texture_rect: TextureRect = simulator.get_node_or_null("TextureRect")


func _ready():
	# 親ノードがFDTDSimulatorであることを確認
	if not simulator is FDTDSimulator:
		push_error("MagneticFieldVisualizer requires a FDTDSimulator node as its parent.")
		set_process(false)
		return

	if not is_instance_valid(texture_rect):
		push_error("Could not find TextureRect node in the parent simulator.")
		set_process(false)
		return

func _process(_delta):
	# 毎フレーム再描画を要求する
	queue_redraw()


func _prepare_vectors_to_draw() -> Array[Dictionary]:
	"""シミュレーションデータから描画すべきベクトルのリストを作成して返す。"""
	# シミュレータから必要な情報を取得
	var hx: PackedFloat32Array = simulator.hx
	var hy: PackedFloat32Array = simulator.hy
	if hx.is_empty() or hy.is_empty():
		return []

	var grid_width: int = simulator.grid_width
	var grid_height: int = simulator.grid_height
	if grid_width == 0 or grid_height == 0:
		return []

	var rect_size: Vector2 = texture_rect.size

	# グリッド座標から描画座標への変換スケール
	var coord_scale: Vector2 = rect_size / Vector2(grid_width, grid_height)

	var vectors: Array[Dictionary] = []
	# 補間に伴う配列の範囲外アクセスを避けるため、ループ範囲を y=1 から開始
	for y in range(1, grid_height - 1, draw_step):
		for x in range(1, grid_width, draw_step):
			var idx = y * grid_width + x

			# Yeeグリッドのスタッガード配置を考慮し、磁場ベクトルをEzグリッド中心(i,j)に補間
			var hx_interp = (hx[idx] + hx[idx - grid_width]) * 0.5
			var hy_interp = (hy[idx] + hy[idx - 1]) * 0.5
			var vec_h = Vector2(hx_interp, hy_interp)

			# ベクトルの長さが非常に小さい場合はスキップ
			if vec_h.length_squared() < MIN_VECTOR_LENGTH_SQ:
				continue

			var start_pos = Vector2(x, y) * coord_scale
			vectors.append({"vec": vec_h, "pos": start_pos})
	
	return vectors


func _draw():
	# simulatorが準備できているか確認
	if not is_instance_valid(simulator):
		return

	# ステップ1: 描画するベクトルのデータを準備する
	var vectors_to_draw: Array[Dictionary] = _prepare_vectors_to_draw()

	if vectors_to_draw.is_empty():
		return

	var max_h = 0.0
	if auto_scale:
		var max_h_sq = 0.0
		# 準備したデータから最大値(の2乗)を求める
		for v_data in vectors_to_draw:
			max_h_sq = max(max_h_sq, v_data.vec.length_squared())

		if max_h_sq > MIN_VECTOR_LENGTH_SQ:
			max_h = sqrt(max_h_sq)

	var arrowhead_angle_rad = deg_to_rad(arrowhead_angle_deg)

	# 準備したデータを使ってベクトルを描画
	for v_data in vectors_to_draw:
			var start_pos: Vector2 = v_data.pos
			var vec_h: Vector2 = v_data.vec
			var end_pos: Vector2

			if auto_scale and max_h > 0:
				# 最大長を基準に長さをスケーリング
				var length = vec_h.length() / max_h * vector_scale
				end_pos = start_pos + vec_h.normalized() * length
			else:
				# 固定倍率でスケーリング
				end_pos = start_pos + vec_h * vector_scale

			# ベクトルの本体（線）を描画
			draw_line(start_pos, end_pos, vector_color, 1.0, true) # antialiased = true

			# 矢印の先端を描画
			if arrowhead_draw:
				var direction = (end_pos - start_pos).normalized()
				var p1 = end_pos - direction.rotated(arrowhead_angle_rad) * arrowhead_length
				var p2 = end_pos - direction.rotated(-arrowhead_angle_rad) * arrowhead_length
				draw_line(end_pos, p1, vector_color, 1.0, true) # antialiased = true
				draw_line(end_pos, p2, vector_color, 1.0, true) # antialiased = true
