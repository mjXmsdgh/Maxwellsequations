extends TextureRect

# --- 依存関係 ---
# MainControllerから注入される
var engine: FDTDEngine

# --- 内部変数 ---
var image: Image
var _image_texture: ImageTexture
var pixels: PackedByteArray

# 描画の初期化処理
# MainControllerから一度だけ呼ばれる
func initialize_view(p_engine: FDTDEngine):
	# 1. 依存関係（計算エンジン）を保存
	engine = p_engine
	
	# 2. 描画用のImageとImageTextureを作成
	# エンジンのグリッドサイズに合わせて作成する
	image = Image.create(engine.GRID_WIDTH, engine.GRID_HEIGHT, false, Image.FORMAT_L8)
	_image_texture = ImageTexture.create_from_image(image)
	
	# 3. このノード（TextureRect）にテクスチャを設定
	self.texture = _image_texture
	
	# 4. ピクセルデータを保持する配列をリサイズしておく
	pixels.resize(engine.GRID_WIDTH * engine.GRID_HEIGHT)

# 毎フレーム呼ばれる描画更新処理
# MainControllerから呼ばれる
func update_view():
	# エンジンがまだ設定されていなければ何もしない
	if not is_instance_valid(engine):
		return
		
	# 1. エンジンから最新の電場データを取得
	var ez_data: PackedFloat32Array = engine.get_field_data()
	
	# 2. 電場データ（-1.0 ~ 1.0）をピクセルデータ（0 ~ 255）に変換
	for i in range(ez_data.size()):
		var value = clampf(ez_data[i], -1.0, 1.0) # 値を-1.0から1.0の範囲に制限
		pixels[i] = int((value + 1.0) * 0.5 * 255.0) # 0から255の範囲にマッピング
		
	# 3. Imageオブジェクトにピクセルデータを一括で設定
	image.set_data(engine.GRID_WIDTH, engine.GRID_HEIGHT, false, Image.FORMAT_L8, pixels)
	
	# 4. ImageTextureを更新して、画面に反映
	_image_texture.update(image)
