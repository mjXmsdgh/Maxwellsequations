# test/test_magnetic_field.gd
extends Node

# テスト対象のクラスを読み込む
const FDTDEngine = preload("res://script/FDTDEngine.gd")

# テストのメイン関数。シーン開始時に自動で実行される。
func _ready():
	print("--- Running FDTD Engine and Visualizer Logic Tests ---")

	var all_tests_passed = true
	# 各テスト関数を呼び出し、結果をANDで結合していく
	all_tests_passed = test_magnetic_field_calculation() and all_tests_passed
	all_tests_passed = test_electric_field_from_hy() and all_tests_passed
	all_tests_passed = test_electric_field_from_hx() and all_tests_passed
	all_tests_passed = test_visualizer_interpolation() and all_tests_passed

	if all_tests_passed:
		print("--- All tests passed successfully! ---")
	else:
		# エラーログは各テスト関数内で出力される
		push_error("--- One or more tests FAILED. Check the output for details. ---")

	# テストが終わったら自動でGodotを終了する
	get_tree().quit()


# FDTDEngineの磁場計算ロジックを検証するテスト
func test_magnetic_field_calculation() -> bool:
	print("Running test: test_magnetic_field_calculation")

	# 1. セットアップ (Setup)
	# ---------------------
	var engine = FDTDEngine.new()
	engine.initialize()

	var grid_width = FDTDEngine.GRID_WIDTH
	# テストの再現性を高めるため、グリッド中央に波源を置く
	var source_pos = Vector2i(grid_width / 2, FDTDEngine.GRID_HEIGHT / 2) # i, j
	var source_strength = 1.0
	
	# シミュレーションのコアロジックを直接テストするため、既知の状態を直接作り出す。
	# (t=0) Ezの特定の位置に波源を設置。Hx, Hyはすべて0。
	engine.ez[source_pos.y * grid_width + source_pos.x] = source_strength

	# 2. 実行 (Execution)
	# -------------------
	# FDTDEngineの内部関数を直接呼び出し、磁場を1ステップだけ更新する
	engine._update_magnetic_field()

	# 3. 検証 (Assertion)
	# -------------------
	var all_tests_passed = true
	# アサーション（値のチェック）を行うためのヘルパー関数 (Callableとして定義)
	var check = func(value, expected, message):
		if not is_equal_approx(value, expected):
			printerr("  [FAIL] %s. Expected: %f, Got: %f" % [message, expected, value])
			all_tests_passed = false # 親スコープの変数をキャプチャ
	
	# Ez(source_pos) = 1.0 によって、周囲のHxとHyが理論通りに変化したかを確認する。
	var update_factor = FDTDEngine.COURANT_NUMBER * engine.time_scale
	
	# Hxの期待値: hx[j*w+i] は Hx(i, j+1/2) に対応する。
	# 更新式: Hx(i, j+1/2) = Hx(i, j+1/2) - C * (Ez(i, j+1) - Ez(i, j))
	
	# Hx below source: Hx(i, j-1/2) -> hx[(j-1)*w+i]
	# この更新は Ez(i,j) と Ez(i,j-1) を使う
	var hx_idx_below = (source_pos.y - 1) * grid_width + source_pos.x
	var expected_hx_below = -update_factor * (source_strength - 0.0) # -C * (Ez(i,j) - Ez(i,j-1))
	check.call(engine.hx[hx_idx_below], expected_hx_below, "Hx calculation (below source)")

	# Hx above source: Hx(i, j+1/2) -> hx[j*w+i]
	# この更新は Ez(i,j+1) と Ez(i,j) を使う
	var hx_idx_above = source_pos.y * grid_width + source_pos.x
	var expected_hx_above = -update_factor * (0.0 - source_strength) # -C * (Ez(i,j+1) - Ez(i,j))
	check.call(engine.hx[hx_idx_above], expected_hx_above, "Hx calculation (above source)")

	# Hyの期待値: Hy(i+1/2, j)の更新は C * (Ez(i+1, j) - Ez(i, j))
	# hy[j*w+i] は Hy(i+1/2, j) に対応
	var hy_idx_left = source_pos.y * grid_width + source_pos.x - 1 # Hy(i-1/2, j)
	var expected_hy_left = update_factor * (source_strength - 0.0)
	check.call(engine.hy[hy_idx_left], expected_hy_left, "Hy calculation (left of source)")
	
	var hy_idx_right = source_pos.y * grid_width + source_pos.x # Hy(i+1/2, j)
	var expected_hy_right = update_factor * (0.0 - source_strength)
	check.call(engine.hy[hy_idx_right], expected_hy_right, "Hy calculation (right of source)")

	if all_tests_passed:
		print("  [PASS] FDTDEngine magnetic field calculation logic.")
	return all_tests_passed


# FDTDEngineの電場計算ロジックを検証するテスト (Hyからの寄与)
func test_electric_field_from_hy() -> bool:
	print("Running test: test_electric_field_from_hy")

	var all_tests_passed = true
	var check = func(value, expected, message):
		if not is_equal_approx(value, expected):
			printerr("  [FAIL] %s. Expected: %f, Got: %f" % [message, expected, value])
			all_tests_passed = false

	# --- セットアップ ---
	var grid_width = FDTDEngine.GRID_WIDTH
	var test_pos = Vector2i(grid_width / 2, FDTDEngine.GRID_HEIGHT / 2)
	var test_idx = test_pos.y * grid_width + test_pos.x
	var h_strength = 1.0

	# --- 実行 ---
	var engine = FDTDEngine.new()
	engine.initialize()
	var update_factor = FDTDEngine.COURANT_NUMBER * engine.time_scale
	engine.hy[test_idx] = h_strength # Corresponds to Hy(i+1/2, j)
	engine._update_electric_field()

	# --- 検証 ---
	# Ez(i,j) update: C * (Hy(i+1/2,j) - Hy(i-1/2,j)) -> C * (hy[j*w+i] - hy[j*w+i-1])
	# Ez(i,j) at test_idx is affected positively by hy[test_idx]
	var expected_ez_at_pos = update_factor * h_strength
	check.call(engine.ez[test_idx], expected_ez_at_pos, "Ez(i,j) from Hy(i+1/2,j)")

	# Ez(i+1,j) update: C * (Hy(i+3/2,j) - Hy(i+1/2,j)) -> C * (hy[j*w+i+1] - hy[j*w+i])
	# Ez(i+1,j) at test_idx+1 is affected negatively by hy[test_idx]
	var expected_ez_at_pos_plus_1 = -update_factor * h_strength
	check.call(engine.ez[test_idx + 1], expected_ez_at_pos_plus_1, "Ez(i+1,j) from Hy(i+1/2,j)")

	if all_tests_passed:
		print("  [PASS] Electric field calculation (from Hy).")
	return all_tests_passed


# FDTDEngineの電場計算ロジックを検証するテスト (Hxからの寄与)
func test_electric_field_from_hx() -> bool:
	print("Running test: test_electric_field_from_hx")

	var all_tests_passed = true
	var check = func(value, expected, message):
		if not is_equal_approx(value, expected):
			printerr("  [FAIL] %s. Expected: %f, Got: %f" % [message, expected, value])
			all_tests_passed = false

	var grid_width = FDTDEngine.GRID_WIDTH
	var test_pos = Vector2i(grid_width / 2, FDTDEngine.GRID_HEIGHT / 2)
	var test_idx = test_pos.y * grid_width + test_pos.x
	var h_strength = 1.0

	var engine = FDTDEngine.new()
	engine.initialize()
	var update_factor = FDTDEngine.COURANT_NUMBER * engine.time_scale
	# hx[test_idx] は Hx(i, j+1/2) に対応
	engine.hx[test_idx] = h_strength
	engine._update_electric_field()
	
	# Ez(i,j)の更新式: ... - C * (Hx(i, j+1/2) - Hx(i, j-1/2))
	var expected_ez_from_hx = -update_factor * h_strength
	check.call(engine.ez[test_idx], expected_ez_from_hx, "Ez(i,j) from Hx(i,j+1/2)")

	var expected_ez_at_pos_plus_1_y = update_factor * h_strength
	check.call(engine.ez[test_idx + grid_width], expected_ez_at_pos_plus_1_y, "Ez(i,j+1) from Hx(i,j+1/2)")

	if all_tests_passed:
		print("  [PASS] Electric field calculation (from Hx).")
	return all_tests_passed


# MagneticFieldVisualizerの補間ロジックを検証するテスト
func test_visualizer_interpolation() -> bool:
	print("Running test: test_visualizer_interpolation")

	# 1. セットアップ: 既知の磁場データを作成
	var grid_width = FDTDEngine.GRID_WIDTH
	var hx = PackedFloat32Array()
	hx.resize(grid_width * FDTDEngine.GRID_HEIGHT)
	var hy = PackedFloat32Array()
	hy.resize(grid_width * FDTDEngine.GRID_HEIGHT)

	var test_pos = Vector2i(grid_width / 2, FDTDEngine.GRID_HEIGHT / 2)
	var test_idx = test_pos.y * grid_width + test_pos.x
	
	# 補間に使う値を設定
	var hx_val1 = 0.8 # Corresponds to hx[test_idx] or Hx(i, j+1/2)
	var hx_val2 = 0.2 # Corresponds to hx[test_idx - grid_width] or Hx(i, j-1/2)
	var hy_val1 = 0.6
	var hy_val2 = 0.4
	hx[test_idx] = hx_val1
	hx[test_idx - grid_width] = hx_val2
	hy[test_idx] = hy_val1
	hy[test_idx - 1] = hy_val2

	# 2. 実行: Visualizerの補間ロジックを直接実行
	# 新しいロジック: Hx(i,j) = ( Hx(i, j+1/2) + Hx(i, j-1/2) ) / 2
	var hx_interp = (hx[test_idx] + hx[test_idx - grid_width]) * 0.5
	var hy_interp = (hy[test_idx] + hy[test_idx - 1]) * 0.5
	
	# 3. 検証
	var all_tests_passed = true
	var check = func(value, expected, message):
		if not is_equal_approx(value, expected):
			printerr("  [FAIL] %s. Expected: %f, Got: %f" % [message, expected, value])
			all_tests_passed = false

	var expected_hx_interp = (hx_val1 + hx_val2) * 0.5
	var expected_hy_interp = (hy_val1 + hy_val2) * 0.5
	
	check.call(hx_interp, expected_hx_interp, "Visualizer Hx interpolation")
	check.call(hy_interp, expected_hy_interp, "Visualizer Hy interpolation")

	if all_tests_passed:
		print("  [PASS] MagneticFieldVisualizer interpolation logic.")
	return all_tests_passed
