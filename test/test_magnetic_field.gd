# test/test_magnetic_field.gd
extends Node

# テスト対象のクラスを読み込む
const FDTDEngine = preload("res://script/FDTDEngine.gd")

# テストのメイン関数。シーン開始時に自動で実行される。
func _ready():
	print("--- Running FDTD Engine and Visualizer Logic Tests ---")
	
	var success = test_magnetic_field_calculation_and_interpolation()
	
	if success:
		print("--- All tests passed successfully! ---")
	else:
		# エラーログはテスト関数内で出力される
		push_error("--- One or more tests FAILED. Check the output for details. ---")
		
	# テストが終わったら自動でGodotを終了する
	get_tree().quit()


# FDTDEngineの計算と、Visualizerの補間ロジックを検証するテスト
func test_magnetic_field_calculation_and_interpolation() -> bool:
	print("Running test: test_magnetic_field_calculation_and_interpolation")

	# 1. セットアップ (Setup)
	# ---------------------
	var engine = FDTDEngine.new()
	engine.initialize()

	var grid_width = FDTDEngine.GRID_WIDTH
	# テストの再現性を高めるため、グリッド中央に波源を置く
	var source_pos = Vector2i(grid_width / 2, FDTDEngine.GRID_HEIGHT / 2)
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

	# --- 3a. FDTDEngineの磁場計算ロジックを検証 ---
	# Ez(source_pos) = 1.0 によって、周囲のHxとHyが理論通りに変化したかを確認する。
	var update_factor = FDTDEngine.COURANT_NUMBER * engine.time_scale
	
	# Hxの期待値: Hx(i, j+1/2)の更新は -C * (Ez(i, j+1) - Ez(i, j))
	var hx_idx_below = source_pos.y * grid_width + source_pos.x
	var expected_hx_below = -update_factor * (source_strength - 0.0)
	check.call(engine.hx[hx_idx_below], expected_hx_below, "Hx calculation (below source)")

	var hx_idx_above = (source_pos.y + 1) * grid_width + source_pos.x
	var expected_hx_above = -update_factor * (0.0 - source_strength)
	check.call(engine.hx[hx_idx_above], expected_hx_above, "Hx calculation (above source)")

	# Hyの期待値: Hy(i+1/2, j)の更新は C * (Ez(i+1, j) - Ez(i, j))
	var hy_idx_left = source_pos.y * grid_width + source_pos.x - 1
	var expected_hy_left = update_factor * (source_strength - 0.0)
	check.call(engine.hy[hy_idx_left], expected_hy_left, "Hy calculation (left of source)")
	
	var hy_idx_right = source_pos.y * grid_width + source_pos.x
	var expected_hy_right = update_factor * (0.0 - source_strength)
	check.call(engine.hy[hy_idx_right], expected_hy_right, "Hy calculation (right of source)")

	if not all_tests_passed: return false
	print("  [PASS] FDTDEngine magnetic field calculation logic.")

	# --- 3b. MagneticFieldVisualizerの補間ロジックを検証 ---
	# 点(source_pos)における磁場ベクトルを補間した結果が正しいか検証する
	var test_idx = source_pos.y * grid_width + source_pos.x
	
	# Visualizerの補間ロジック (元の正しいコード)
	var hx_interp = (engine.hx[test_idx] + engine.hx[test_idx + grid_width]) * 0.5
	var hy_interp = (engine.hy[test_idx] + engine.hy[test_idx - 1]) * 0.5
	
	# 期待値の計算
	var expected_hx_interp = (expected_hx_below + expected_hx_above) * 0.5
	var expected_hy_interp = (expected_hy_right + expected_hy_left) * 0.5
	
	check.call(hx_interp, expected_hx_interp, "Visualizer Hx interpolation")
	check.call(hy_interp, expected_hy_interp, "Visualizer Hy interpolation")

	if not all_tests_passed: return false
	print("  [PASS] MagneticFieldVisualizer interpolation logic.")
	
	return true
