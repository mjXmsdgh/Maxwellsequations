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
	image = Image.create(engine.GRID_WIDTH, engine.GRID_HEIGHT, false, Image.FORMAT_RGBA8)
	_image_texture = ImageTexture.create_from_image(image)
	
	# 3. このノード（TextureRect）にテクスチャを設定
	self.texture = _image_texture
	
	# 4. ピクセルデータを保持する配列をリサイズしておく
	pixels.resize(engine.GRID_WIDTH * engine.GRID_HEIGHT)


func update_view():
	if not is_instance_valid(engine):
		return

	var image_data = image.get_data()
	var ez = engine.ez
	var medium_coeffs = engine.ca # 媒質情報を保持する配列(ca)を取得

	for i in range(ez.size()):
		var ptr = i * 4
		
		# Redチャンネル: 電場Ezの情報を書き込む
		var ez_val = (ez[i] * 0.5 + 0.5) # -1..1 -> 0..1
		image_data[ptr] = int(ez_val * 255.0)
		
		# Greenチャンネル: 媒質係数(ca)の情報を書き込む (ca = 1.0 / n^2)
		var medium_val = medium_coeffs[i] # 1.0(真空) or < 1.0(媒質)
		image_data[ptr + 1] = int(medium_val * 255.0)
		
		# Blue/Alphaチャンネルは未使用
		image_data[ptr + 2] = 0
		image_data[ptr + 3] = 255

	image.set_data(image.get_width(), image.get_height(), false, image.get_format(), image_data)
	texture.update(image)
