shader_type canvas_item;

// 色の増幅率。エディタのインスペクターから調整可能になります。
uniform float color_multiplier : hint_range(1.0, 50.0) = 5.0;

// 描画色
const vec4 OBSTACLE_COLOR = vec4(1.0, 1.0, 1.0, 1.0); // 障害物: 灰色
const vec4 MEDIUM_COLOR   = vec4(0.3, 0.3, 0.3, 1.0); // 媒質: 薄い灰色

// 予約された描画値
const float OBSTACLE_VALUE = 0.0;
const float MEDIUM_VALUE   = 128.0;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	// テクスチャから値(0.0-1.0)を取得し、元の8bit整数値(0-255)に復元
	float value = texture(TEXTURE, UV).r;
	float raw_value = round(value * 255.0);

	if (raw_value == OBSTACLE_VALUE) {
		COLOR = OBSTACLE_COLOR;
	} else {
		vec3 final_color = vec3(0.0);

		// 媒質の中かどうかを判定 (値が128以上か)
		if (raw_value >= MEDIUM_VALUE) {
			// 媒質の背景色を設定
			final_color = MEDIUM_COLOR.rgb;
			// 128を引いて、元の電場の値(1-127)に戻す
			value = (raw_value - MEDIUM_VALUE) / 127.0;
		} else {
			// 真空中の場合、元の値(1-127)を0.0-1.0の範囲に戻す
			value = raw_value / 127.0;
		}

		// 電場の値 (-1.0 to 1.0) に復元
		value = value * 2.0 - 1.0;

		// 波の色を計算し、背景色に加算（ブレンド）する
		final_color.r += max(0.0, value) * color_multiplier;   // プラスなら赤を加算
		final_color.b += max(0.0, -value) * color_multiplier; // マイナスなら青を加算
		COLOR = vec4(final_color, 1.0);
	}
}

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
