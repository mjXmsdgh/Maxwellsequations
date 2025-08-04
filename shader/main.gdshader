shader_type canvas_item;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
    // テクスチャからグレースケール値(0.0-1.0)を取得
    float value = texture(TEXTURE, UV).r;
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

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
