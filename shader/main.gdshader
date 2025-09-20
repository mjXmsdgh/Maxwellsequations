shader_type canvas_item;

// 色の増幅率。エディタのインスペクターから調整可能になります。
uniform float color_multiplier : hint_range(1.0, 20.0) = 10.0;
// 媒質を可視化するための色。インスペクターから変更可能。
uniform vec4 medium_tint : source_color = vec4(0.15, 0.2, 0.15, 1.0);

void fragment() {
	// Called for every pixel the material is visible on.
	
	// 1. テクスチャから各チャンネルの値(0.0-1.0)を取得します。
	vec4 tex_data = texture(TEXTURE, UV);
	float ez_value = tex_data.r;      // Rチャンネル: 電場の値
	float medium_value = tex_data.g;  // Gチャンネル: 媒質の情報 (1.0 / 屈折率)

	// 2. 元の電場の値(-1.0 to 1.0)に復元します。
	ez_value = ez_value * 2.0 - 1.0;

	// 3. 値に応じて色を決定します。
	vec3 wave_color = vec3(0.0); // 基本は黒
	wave_color.r = max(0.0, ez_value) * color_multiplier;   // プラスの電場なら赤色を強くする
	wave_color.b = max(0.0, -ez_value) * color_multiplier;  // マイナスの電場なら青色を強くする
	
	// 4. 媒質の可視化: medium_valueが1.0未満なら媒質が存在する
	//    step(x, y)は x > y なら 0.0, そうでなければ 1.0 を返す
	float is_medium = 1.0 - step(0.999, medium_value);
	
	// 5. 電場の色と媒質の色を合成する
	COLOR = vec4(wave_color + medium_tint.rgb * is_medium, 1.0);
}
