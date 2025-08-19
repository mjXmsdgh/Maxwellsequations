extends Control

class_name FDTDSimulator

@export_category("Simulation Parameters")
@export var click_strength: float = 5.0 # クリック時の波の強さ

# シミュレーション領域の定義
const GRID_WIDTH = 512  # グリッドの幅
const GRID_HEIGHT = 512 # グリッドの高さ

# 物理・描画定数
const OBSTACLE_DRAW_COLOR: int = 128
const EZ_CLAMP_MIN: float = -1.0
const EZ_CLAMP_MAX: float = 1.0
const GRAYSCALE_MAX: float = 255.0

const INVALID_GRID_POS := Vector2i(-1, -1)

var image: Image # シミュレーション結果を格納する画像データ
var texture: ImageTexture # 画面に表示するためのテクスチャ

var engine: FDTDEngine

# --- Getter Properties for External Access ---
# ビジュアライザーなどの外部ノードが安全に参照できるようにプロパティを公開
var grid_width: int:
	get: return engine.grid_width if is_instance_valid(engine) else 0

var grid_height: int:
	get: return engine.grid_height if is_instance_valid(engine) else 0

var hx: PackedFloat32Array:
	get: return engine.hx if is_instance_valid(engine) else PackedFloat32Array()

var hy: PackedFloat32Array:
	get: return engine.hy if is_instance_valid(engine) else PackedFloat32Array()

var last_mouse_grid_pos: Vector2i = INVALID_GRID_POS # 最後に描画したマウスのグリッド座標


# ノードがシーンツリーに追加されたときに一度だけ呼び出される初期化関数
func _ready():
	# 計算エンジンのインスタンスを作成し、初期化
	engine = FDTDEngine.new()
	engine.initialize(GRID_WIDTH, GRID_HEIGHT)

	# 画像とテクスチャを一度だけ生成
	image = Image.create(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)
	$TextureRect.texture = texture

	# 最初のテクスチャ更新
	_update_texture()

func _process(delta):
	# 物理演算の更新
	engine.step(delta)
	# テクスチャの更新
	_update_texture()


# シミュレーション結果をテクスチャに描画する
func _update_texture():
	var pixels = PackedByteArray()
	pixels.resize(GRID_WIDTH * GRID_HEIGHT)

	var current_ez = engine.ez
	var current_obstacle_map = engine.obstacle_map

	for i in range(current_ez.size()):
		if current_obstacle_map[i] == FDTDEngine.OBSTACLE_VALUE:
			# 障害物は中間の灰色としてエンコード
			pixels[i] = OBSTACLE_DRAW_COLOR
		else:
			# ezの値を EZ_CLAMP_MIN ~ EZ_CLAMP_MAX から 0 ~ GRAYSCALE_MAX の範囲に変換
			var value = clampf(current_ez[i], EZ_CLAMP_MIN, EZ_CLAMP_MAX) # 値が大きくなりすぎないように制限
			pixels[i] = int((value - EZ_CLAMP_MIN) / (EZ_CLAMP_MAX - EZ_CLAMP_MIN) * GRAYSCALE_MAX)

	image.set_data(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_L8, pixels)
	texture.update(image) # 既存のテクスチャを新しい画像データで更新


func reset_simulation():
	engine.reset()
	# テクスチャをクリアして即時反映
	_update_texture()

# マウスのグローバル座標をグリッド座標に変換するヘルパー関数
func get_mouse_grid_pos() -> Vector2i:
	var local_pos = $TextureRect.get_local_mouse_position()
	var rect_size = $TextureRect.size
	# rect_sizeが0だとゼロ除算エラーになるのを防ぐ
	if rect_size.x == 0 or rect_size.y == 0:
		return INVALID_GRID_POS
	var grid_x = int(local_pos.x / rect_size.x * GRID_WIDTH)
	var grid_y = int(local_pos.y / rect_size.y * GRID_HEIGHT)
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
	_handle_obstacle_input(event)
	_handle_source_input(event)

	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_R:
		reset_simulation()
