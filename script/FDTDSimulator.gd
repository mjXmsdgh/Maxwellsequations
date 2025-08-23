extends Control

class_name FDTDSimulator

@export_category("Simulation Parameters")
@export var click_strength: float = 5.0 # 右クリック時の波の強さ

@export_category("Plane Wave Source")
@export var source_enabled: bool = true
@export var source_frequency: float = 5.0 # 波源の周波数 (単位はシミュレーションのスケールに依存)
@export_range(0, 1000) var source_x_position: int = 20   # 波源のX座標（グリッド単位）

@export_category("Visualization")
const OBSTACLE_ENCODE_VALUE: int = 128 # 障害物をテクスチャに書き込む際の値 (0-255)
const EZ_CLAMP_MIN: float = -1.0 # 描画時にクランプするezの最小値
const EZ_CLAMP_MAX: float = 1.0

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


# ノードがシーンツリーに追加されたときに一度だけ呼び出される初期化関数
func _ready():
	# 計算エンジンのインスタンスを作成し、初期化
	engine = FDTDEngine.new()
	engine.initialize()

	# 画像とテクスチャを一度だけ生成
	image = Image.create(grid_width, grid_height, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)
	$TextureRect.texture = texture

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
	# L8(グレースケール)フォーマットなので、ピクセルごとに1バイト
	var pixels = PackedByteArray()
	pixels.resize(grid_width * grid_height)

	var current_ez = engine.ez
	var current_obstacle_map = engine.obstacle_map

	for i in range(current_ez.size()):
		if current_obstacle_map[i] == FDTDEngine.OBSTACLE_VALUE:
			# 障害物はシェーダーが認識できるよう特定の値でエンコード
			pixels[i] = OBSTACLE_ENCODE_VALUE
		else:
			# ezの値を[-1, 1]から[0, 255]のグレースケール値に変換(エンコード)
			var value = clampf(current_ez[i], EZ_CLAMP_MIN, EZ_CLAMP_MAX)
			# 範囲変換: [-1, 1] -> [0, 2] -> [0, 1] -> [0, 255]
			var encoded_value = int(((value - EZ_CLAMP_MIN) / (EZ_CLAMP_MAX - EZ_CLAMP_MIN)) * 255.0)
			pixels[i] = encoded_value

	image.set_data(grid_width, grid_height, false, Image.FORMAT_L8, pixels)
	texture.update(image) # 既存のテクスチャを新しい画像データで更新


func reset_simulation():
	
	engine=FDTDEngine.new()
	engine.initialize()
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
	return Vector2i(grid_x, grid_y)

# --- 入力処理 ---

func _handle_obstacle_input(event: InputEvent):
	# --- 左クリックの処理 ---
	# イベントがマウスボタン、かつ左ボタンの場合
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# ボタンが押された瞬間の処理
		if event.is_pressed():
			# 現在のマウス位置をグリッド座標で取得
			var current_pos = get_mouse_grid_pos()
			# 座標が有効なら、クリックした点に障害物を描画
			if current_pos.x >= 0:
				# 点を描画するために、始点と終点を同じ位置にする
				engine.add_obstacle_line(current_pos, current_pos)
			# ドラッグ描画のために、最後のマウス位置を記録
			last_mouse_grid_pos = current_pos
		# ボタンが離された瞬間の処理
		else:
			# 最後のマウス位置をリセットし、ドラッグ描画を終了
			last_mouse_grid_pos = INVALID_GRID_POS

	# --- マウスドラッグの処理 ---
	# イベントがマウス移動、かつ左ボタンが押されている場合
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		# 前回のマウス位置が有効な場合（ドラッグ中）
		if last_mouse_grid_pos.x >= 0:
			# 現在のマウス位置を取得
			var current_pos = get_mouse_grid_pos()
			# 新しい位置が有効で、かつ前回の位置から移動している場合
			if current_pos.x >= 0 and current_pos != last_mouse_grid_pos:
				# 前回の位置から現在の位置まで直線を引く
				engine.add_obstacle_line(last_mouse_grid_pos, current_pos)
				# 最後のマウス位置を更新
				last_mouse_grid_pos = current_pos

func _handle_source_input(event: InputEvent):
	# 波源追加ロジック (右クリック)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		var grid_pos = get_mouse_grid_pos()
		if grid_pos.x >= 0:
			engine.add_source(grid_pos.x, grid_pos.y, click_strength)

func _input(event: InputEvent):
	# 障害物描画の入力（左クリック＆ドラッグ）を処理
	_handle_obstacle_input(event)
	# 波源追加の入力（右クリック）を処理
	_handle_source_input(event)

	# 'R'キーが押されたらシミュレーションをリセット
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_R:
		reset_simulation()
