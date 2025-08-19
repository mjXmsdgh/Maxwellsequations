extends Node2D

@export_category("Visualization")
@export var vector_color: Color = Color.YELLOW
@export_range(1, 50, 1) var draw_step: int = 16 # ベクトルを描画する間隔 (グリッド単位)
@export_range(1.0, 100.0) var vector_scale: float = 20.0 # ベクトルの長さの倍率

@export_group("Arrowhead", "arrowhead_")
@export var arrowhead_draw: bool = true
@export_range(1.0, 20.0) var arrowhead_length: float = 8.0
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


func _draw():
	# simulatorと、その中のengineが準備できているか確認
	if not is_instance_valid(simulator):
		return

	# シミュレータから必要な情報を取得
	var hx: PackedFloat32Array = simulator.hx
	var hy: PackedFloat32Array = simulator.hy
	if hx.is_empty() or hy.is_empty():
		return

	var grid_width: int = simulator.grid_width
	var grid_height: int = simulator.grid_height

	if grid_width == 0 or grid_height == 0:
		return

	var rect_size = texture_rect.size

	# グリッド座標から描画座標への変換スケール
	var scale = rect_size / Vector2(grid_width, grid_height)

	var arrowhead_angle_rad = deg_to_rad(arrowhead_angle_deg)

	# グリッドを間引きながらループして、パフォーマンスを確保
	for y in range(0, grid_height, draw_step):
		for x in range(0, grid_width, draw_step):
			var idx = y * grid_width + x

			# 磁場ベクトル H = (Hx, Hy)
			var vec_h = Vector2(hx[idx], hy[idx])

			# ベクトルの長さが非常に小さい場合は描画をスキップして負荷を軽減
			if vec_h.length_squared() < MIN_VECTOR_LENGTH_SQ:
				continue

			var start_pos = Vector2(x, y) * scale
			var end_pos = start_pos + vec_h * vector_scale

			# ベクトルの本体（線）を描画
			draw_line(start_pos, end_pos, vector_color, 1.0, true)

			# 矢印の先端を描画
			if arrowhead_draw:
				var direction = (end_pos - start_pos).normalized()
				var p1 = end_pos - direction.rotated(arrowhead_angle_rad) * arrowhead_length
				var p2 = end_pos - direction.rotated(-arrowhead_angle_rad) * arrowhead_length
				draw_line(end_pos, p1, vector_color, 1.0, true)
				draw_line(end_pos, p2, vector_color, 1.0, true)
