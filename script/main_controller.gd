# main_controller.gd

extends Control

# --- 子ノードへの参照 ---
@onready var texture_rect: TextureRect = $TextureRect
@onready var magnetic_visualizer: Node2D = $MagneticFieldVisualizer

# 計算エンジン(FDTDEngine)のインスタンスを保持するための変数
var engine: FDTDEngine

# このノードが準備できたときに一度だけ呼ばれる
func _ready():
	# 1. FDTDEngineクラスから新しいインスタンス（実体）を作成する
	engine = FDTDEngine.new()
	
	# 2. 作成したエンジンの初期化処理を呼び出す
	engine.initialize()
	
	# SimulationView (TextureRectにアタッチされている) の初期化
	texture_rect.initialize_view(engine)

	# 3. MagneticFieldVisualizerに必要な依存関係（エンジンと描画領域）を注入する
	if is_instance_valid(magnetic_visualizer):
		magnetic_visualizer.engine = engine
		magnetic_visualizer.texture_rect = texture_rect
		magnetic_visualizer.initialize() # 依存性を渡した後に初期化を指示
	
	# 4. 動作確認のため、コンソールにメッセージを出力する
	print("MainController: Ready! FDTD Engine initialized.")


# 毎フレーム呼ばれる（描画更新に適している）
func _process(delta):
	# 描画担当（SimulationView）に、ビューの更新を指示する
	texture_rect.update_view()

# 固定フレームレートで呼ばれる（物理計算に適している）
func _physics_process(delta):
	# 1. 毎フレーム、計算を1ステップ進めるようエンジンに命令する
	engine.step(delta)
	
	# # --- デバッグ用: 計算結果の発散をチェック ---
	# # PackedFloat32Arrayにはmin()/max()がないため、手動で値を探します。
	# var min_val = INF
	# var max_val = -INF
	# for val in engine.ez:
	# 	min_val = min(min_val, val)
	# 	max_val = max(max_val, val)
	# print("Ez min: ", min_val, ", Ez max: ", max_val)

	# 2. 動作確認用（毎フレーム出力されるので、確認後はコメントアウト推奨）
	# print("MainController: Physics Processing frame...")

# マウスのグローバル座標をグリッド座標に変換するヘルパー関数
func get_mouse_grid_pos() -> Vector2i:
	var local_pos = texture_rect.get_local_mouse_position()
	var rect_size = texture_rect.size
	# rect_sizeが0だとゼロ除算エラーになるのを防ぐ
	if rect_size.x == 0 or rect_size.y == 0:
		return FDTDSimulator.INVALID_GRID_POS

	var grid_x = int(local_pos.x / rect_size.x * engine.GRID_WIDTH)
	var grid_y = int(local_pos.y / rect_size.y * engine.GRID_HEIGHT)

	# 範囲チェック
	if grid_x >= 0 and grid_x < engine.GRID_WIDTH and grid_y >= 0 and grid_y < engine.GRID_HEIGHT:
		return Vector2i(grid_x, grid_y)
	else:
		return FDTDSimulator.INVALID_GRID_POS

# 何か入力があったときに呼ばれる
func _input(event):
	# 1. 入力が「マウスボタンのクリック」かどうかを判定する
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var grid_pos = get_mouse_grid_pos()
		if grid_pos != FDTDSimulator.INVALID_GRID_POS:
			# 2. もし左クリックなら、そのグリッド座標に波源を追加するようエンジンに命令する
			engine.add_source(grid_pos.x, grid_pos.y, 5.0) # 強さは仮に5.0
			print("MainController: Source added at grid position ", grid_pos)

	# 3. Rキーが押されたらリセット処理を呼び出す
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_R:
			engine.reset()
			print("MainController: Simulation reset.")
