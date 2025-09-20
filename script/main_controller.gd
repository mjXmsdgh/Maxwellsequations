# main_controller.gd

extends Control

# --- 定数 ---
const INVALID_GRID_POS = Vector2i(-1, -1)

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
	
	# 3. シミュレーションの初期媒質（光ファイバー）を設定する
	_setup_optical_fiber()
	
	# SimulationView (TextureRectにアタッチされている) の初期化
	texture_rect.initialize_view(engine)

	# 3. MagneticFieldVisualizerに必要な依存関係（エンジンと描画領域）を注入する
	if is_instance_valid(magnetic_visualizer):
		magnetic_visualizer.engine = engine
		magnetic_visualizer.texture_rect = texture_rect
		magnetic_visualizer.initialize() # 依存性を渡した後に初期化を指示

	# 4. 動作確認のため、コンソールにメッセージを出力する
	print("MainController: Ready! FDTD Engine initialized.")


# 光ファイバー構造をセットアップする関数
func _setup_optical_fiber():
	# グリッドの中央Y座標
	var center_y = engine.GRID_HEIGHT / 2

	# クラッド（外層）のパラメータ
	var clad_height = 20
	var clad_n = 1.45
	var clad_start = Vector2i(0, center_y - clad_height / 2)
	var clad_end = Vector2i(engine.GRID_WIDTH - 1, center_y + clad_height / 2)

	# コア（内層）のパラメータ
	var core_height = 10
	var core_n = 1.50
	var core_start = Vector2i(0, center_y - core_height / 2)
	var core_end = Vector2i(engine.GRID_WIDTH - 1, center_y + core_height / 2)

	# 媒質を設定（必ずクラッド -> コアの順で描画）
	engine.add_medium_rect(clad_start, clad_end, clad_n)
	engine.add_medium_rect(core_start, core_end, core_n)
	print("Optical fiber setup complete.")


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

# マウスのグローバル座標をグリッド座標に変換するヘルパー関数
func get_mouse_grid_pos() -> Vector2i:
	var local_pos = texture_rect.get_local_mouse_position()
	var rect_size = texture_rect.size
	# rect_sizeが0だとゼロ除算エラーになるのを防ぐ
	if rect_size.x == 0 or rect_size.y == 0:
		return INVALID_GRID_POS

	var grid_x = int(local_pos.x / rect_size.x * engine.GRID_WIDTH)
	var grid_y = int(local_pos.y / rect_size.y * engine.GRID_HEIGHT)

	# 範囲チェック
	if grid_x >= 0 and grid_x < engine.GRID_WIDTH and grid_y >= 0 and grid_y < engine.GRID_HEIGHT:
		return Vector2i(grid_x, grid_y)
	else:
		return INVALID_GRID_POS

# 何か入力があったときに呼ばれる
func _input(event):
	# マウスの左ボタンが「押された」瞬間に一度だけ波源を追加する
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var grid_pos = get_mouse_grid_pos()
		if grid_pos != INVALID_GRID_POS:
			engine.add_source(grid_pos.x, grid_pos.y, 5.0) # 強さは仮に5.0
			print("MainController: Source added at grid position ", grid_pos)

	# Rキーによるリセット処理はイベントベースのまま残す
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_R:
			engine.reset()
			# リセット後にファイバーを再設定
			_setup_optical_fiber()
			print("MainController: Simulation reset.")
