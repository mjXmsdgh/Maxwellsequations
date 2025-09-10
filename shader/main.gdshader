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
		COLOR = OBSTACLE_COLOR; // 障害物を描画
	} else if (raw_value == MEDIUM_VALUE) {
		COLOR = MEDIUM_COLOR;   // 媒質を描画
	} else {
		// 電場の波を描画
		// 元の電場の値(-1.0 - 1.0)に復元
		value = value * 2.0 - 1.0;

		vec3 color = vec3(0.0); // 基本は黒
		color.r = max(0.0, value) * color_multiplier;   // プラスなら赤（増幅）
		color.b = max(0.0, -value) * color_multiplier; // マイナスなら青（増幅）
		COLOR = vec4(color, 1.0);
	}
}

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
