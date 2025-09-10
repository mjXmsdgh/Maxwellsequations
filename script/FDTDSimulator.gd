extends Control

class_name FDTDSimulator

@export_category("Simulation Parameters")
@export var click_strength: float = 5.0 # 右クリック時の点波源の強さ

@export_category("Plane Wave Source")
@export var source_enabled: bool = true
@export var source_frequency: float = 5.0 # 波源の周波数 (単位はシミュレーションのスケールに依存)
@export_range(0, 1000) var source_x_position: int = 20   # 波源のX座標（グリッド単位）

@export_category("Drawing Parameters")
@export var drawing_refractive_index: float = 1.5 # 描画する媒質の屈折率 (ガラス相当)

@export_category("Visualization")
const INVALID_GRID_POS := Vector2i(-1, -1)

var image: Image # シミュレーション結果を格納する画像データ
var texture: ImageTexture # 画面に表示するためのテクスチャ

var engine: FDTDEngine

var _time: float = 0.0 # シミュレーション時間

# --- Getter Properties for External Access ---
# ビジュアライザーなどの外部ノードが安全に参照できるようにプロパティを公開
var grid_width: int:
	get: return FDTDEngine.GRID_WIDTH if is_instance_valid(engine) else 0

var grid_height: int:
	get: return FDTDEngine.GRID_HEIGHT if is_instance_valid(engine) else 0

var hx: PackedFloat32Array:
	get: return engine.hx if is_instance_valid(engine) else PackedFloat32Array()

var hy: PackedFloat32Array:
	get: return engine.hy if is_instance_valid(engine) else PackedFloat32Array()

var last_mouse_grid_pos: Vector2i = INVALID_GRID_POS # 最後に描画したマウスのグリッド座標
var _is_drawing_obstacle: bool = false # 障害物を描画中かどうかのフラグ
var _is_drawing_medium: bool = false   # 媒質を描画中かどうかのフラグ


# ノードがシーンツリーに追加されたときに一度だけ呼び出される初期化関数
func _ready():
	# 計算エンジンのインスタンスを作成し、初期化
	engine = FDTDEngine.new()
	engine.initialize()

	# 画像とテクスチャを一度だけ生成
	image = Image.create(grid_width, grid_height, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)
	$TextureRect.texture = texture

	# テクスチャのフィルタリングを「ニアレストネイバー」に設定します。
	# これにより、ピクセル間の色が補間（ブラー）されるのを防ぎ、
	# 127と129の間の値が128（障害物）として誤描画される問題を完全に解決します。
	$TextureRect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# 最初のテクスチャ更新
	_update_texture()

func _physics_process(delta):
	# シミュレーション時間を更新
	# _physics_processは固定時間ステップで呼ばれるため、FDTD計算に適しています。
	_time += delta

	# 物理演算の更新
	engine.step(delta)
	
	# 波源の追加 (物理演算の更新後)
	if source_enabled:
		_add_plane_wave_source()
	
	# テクスチャの更新
	_update_texture()


func _add_plane_wave_source():
	# グリッドの範囲外なら何もしない
	if source_x_position <= 0 or source_x_position >= grid_width - 1:
		return

	# 時間と共に振動する波源の値を計算
	var angular_frequency = 2.0 * PI * source_frequency
	var source_value = sin(angular_frequency * _time)

	# 指定したX座標のラインに沿って、Ezに波源の値を加算する（ソフトソース）
	for y in range(grid_height):
		engine.add_source(source_x_position, y, source_value)

# シミュレーション結果をテクスチャに描画する
func _update_texture():
	# FDTDEngineから、障害物との衝突を回避するようにエンコードされた
	# バイト配列を直接取得します。
	# これにより、描画ロジックがエンジン内にカプセル化され、
	# FDTDSimulatorは描画の詳細を意識する必要がなくなります。
	var pixels: PackedByteArray = engine.get_image_data()
	image.set_data(grid_width, grid_height, false, Image.FORMAT_L8, pixels)
	texture.update(image) # 既存のテクスチャを新しい画像データで更新


func reset_simulation():
	# FDTDEngineの内部状態をリセット（インスタンスの再生成を避ける）
	engine.reset()
	_time = 0.0 # 波源の時間をリセット
	_update_texture()

# マウスのグローバル座標をグリッド座標に変換するヘルパー関数
func get_mouse_grid_pos() -> Vector2i:
	var local_pos = $TextureRect.get_local_mouse_position()
	var rect_size = $TextureRect.size
	# rect_sizeが0だとゼロ除算エラーになるのを防ぐ
	if rect_size.x == 0 or rect_size.y == 0:
		return INVALID_GRID_POS

	var grid_x = int(local_pos.x / rect_size.x * grid_width)
	var grid_y = int(local_pos.y / rect_size.y * grid_height)

	# 範囲チェック
	if grid_x >= 0 and grid_x < grid_width and grid_y >= 0 and grid_y < grid_height:
		return Vector2i(grid_x, grid_y)
	else:
		return INVALID_GRID_POS

# --- 入力処理 ---

func _handle_obstacle_input(event: InputEvent):
	# マウスの左ボタンが押された/離された時の処理
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			# 描画モードを開始
			_is_drawing_obstacle = true
			var current_pos = get_mouse_grid_pos()
			if current_pos != INVALID_GRID_POS:
				# クリックした点に障害物を描画し、開始点として保存
				engine.add_obstacle_line(current_pos, current_pos)
				last_mouse_grid_pos = current_pos
		else:
			# 描画モードを終了
			_is_drawing_obstacle = false
			last_mouse_grid_pos = INVALID_GRID_POS

	# マウスがドラッグされた時の処理 (描画モード中のみ)
	if event is InputEventMouseMotion and _is_drawing_obstacle:
		var current_pos = get_mouse_grid_pos()
		# マウスが新しいグリッドに移動した場合
		if current_pos != INVALID_GRID_POS and current_pos != last_mouse_grid_pos:
			# 前回の位置から現在の位置まで線を描画
			engine.add_obstacle_line(last_mouse_grid_pos, current_pos)
			# 現在位置を更新
			last_mouse_grid_pos = current_pos

func _handle_medium_input(event: InputEvent):
	# マウスの左ボタンが押された/離された時の処理
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			# 媒質描画モードを開始
			_is_drawing_medium = true
			var current_pos = get_mouse_grid_pos()
			if current_pos != INVALID_GRID_POS:
				# クリックした点に媒質を描画し、開始点として保存
				engine.add_medium_line(current_pos, current_pos, drawing_refractive_index)
				last_mouse_grid_pos = current_pos
		else:
			# 媒質描画モードを終了
			_is_drawing_medium = false
			last_mouse_grid_pos = INVALID_GRID_POS

	# マウスがドラッグされた時の処理 (媒質描画モード中のみ)
	if event is InputEventMouseMotion and _is_drawing_medium:
		var current_pos = get_mouse_grid_pos()
		if current_pos != INVALID_GRID_POS and current_pos != last_mouse_grid_pos:
			engine.add_medium_line(last_mouse_grid_pos, current_pos, drawing_refractive_index)
			last_mouse_grid_pos = current_pos

func _handle_source_input(event: InputEvent):
	# 波源追加ロジック (右クリック)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		var grid_pos = get_mouse_grid_pos()
		if grid_pos != INVALID_GRID_POS:
			engine.add_source(grid_pos.x, grid_pos.y, click_strength)

func _input(event: InputEvent):
	# Shiftキーの状態で障害物描画と媒質描画を切り替える
	if event.is_shift_pressed():
		_handle_medium_input(event)
	else:
		_handle_obstacle_input(event)

	# 波源追加の入力（右クリック）はShiftキーの状態に影響されない
	_handle_source_input(event)

	# 'R'キーが押されたらシミュレーションをリセット
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_R:
		reset_simulation()
