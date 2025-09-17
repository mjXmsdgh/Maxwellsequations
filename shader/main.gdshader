shader_type canvas_item;

// 色の増幅率。エディタのインスペクターから調整可能になります。
uniform float color_multiplier : hint_range(1.0, 20.0) = 5.0;

void fragment() {
	// Called for every pixel the material is visible on.
	
	// 1. テクスチャからグレースケール値(0.0-1.0)を取得します。
	//    これは simulation_view.gd で 0-255 に変換された値です。
	float value = texture(TEXTURE, UV).r;

	// 2. 元の電場の値(-1.0 to 1.0)に復元します。
	value = value * 2.0 - 1.0;

	// 3. 値に応じて色を決定します。
	vec3 color = vec3(0.0); // 基本は黒
	color.r = max(0.0, value) * color_multiplier;   // プラスの電場なら赤色を強くする
	color.b = max(0.0, -value) * color_multiplier;  // マイナスの電場なら青色を強くする
	COLOR = vec4(color, 1.0);
}
