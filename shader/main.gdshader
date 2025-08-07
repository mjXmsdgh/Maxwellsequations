shader_type canvas_item;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
    // テクスチャからグレースケール値(0.0-1.0)を取得
    float value = texture(TEXTURE, UV).r;

    // 障害物(エンコード値が128/255.0 ≒ 0.5)を灰色で描画
    if (abs(value - 128.0 / 255.0) < 0.002) { // 判定の許容範囲を狭くして、より正確に障害物だけを検出する
        COLOR = vec4(0.5, 0.5, 0.5, 1.0); // 灰色
    } else {
		// 障害物でなければ、波を描画
		// 元の電場の値(-1.0 - 1.0)に復元
		value = value * 2.0 - 1.0;

		vec3 color = vec3(0.0); // 基本は黒
		if (value > 0.0) {
			color.r = value; // プラスなら赤
		} else {
			color.b = -value; // マイナスなら青
		}
		COLOR = vec4(color, 1.0);
    }
}

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
