@echo off
setlocal

set "REPO_ROOT=%~dp0..\.."
set "IVERILOG_ROOT=D:\IcarusVerilog\iverilog"
set "IVERILOG=%IVERILOG_ROOT%\bin\iverilog.exe"
set "VVP=%IVERILOG_ROOT%\bin\vvp.exe"
set "OUT_DIR=%REPO_ROOT%\tmp\iverilog"

if not exist "%IVERILOG%" (
    echo ERROR: Icarus Verilog was not found at "%IVERILOG%"
    exit /b 1
)
if not exist "%VVP%" (
    echo ERROR: VVP was not found at "%VVP%"
    exit /b 1
)
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo [1/51] Compile the current gs_accel_top synthesis subset
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -Wimplicit ^
    -I "%REPO_ROOT%\rtl\raster" -s gs_accel_top ^
    -o "%OUT_DIR%\gs_accel_top.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\rv_skid_buffer.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\control\sat_counter_bank.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_resource_mode_table.sv" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_pipeline_event_counters.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_mode_advisor.sv" ^
    "%REPO_ROOT%\rtl\control\apb_regfile.sv" ^
    "%REPO_ROOT%\rtl\sort\depth_group_buffer.sv" ^
    "%REPO_ROOT%\rtl\sort\group_sort_service_gate.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter_shared_compare.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_core.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_shared_mac.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\memory\sram_1r1w_wrapper.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_array.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_cache_backend.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_cache_backend_single.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_cache_backend_4.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit_4.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%REPO_ROOT%\rtl\gs_accel_top.sv"
if errorlevel 1 exit /b 1

echo [2/51] cfg_epoch_ctrl
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_cfg_epoch_ctrl ^
    -o "%OUT_DIR%\tb_cfg_epoch_ctrl.vvp" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" "%~dp0tb_cfg_epoch_ctrl.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_cfg_epoch_ctrl.vvp"
if errorlevel 1 exit /b 1

echo [3/51] apb_regfile
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_apb_regfile ^
    -o "%OUT_DIR%\tb_apb_regfile.vvp" ^
    "%REPO_ROOT%\rtl\control\apb_regfile.sv" "%~dp0tb_apb_regfile.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_apb_regfile.vvp"
if errorlevel 1 exit /b 1

echo [4/51] alpha_block_float_core
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_alpha_block_float_core -o "%OUT_DIR%\tb_alpha_block_float_core.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%~dp0tb_alpha_block_float_core.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_alpha_block_float_core.vvp"
if errorlevel 1 exit /b 1

echo [5/51] blend_fixed_core
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_blend_fixed_core ^
    -o "%OUT_DIR%\tb_blend_fixed_core.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" "%~dp0tb_blend_fixed_core.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_blend_fixed_core.vvp"
if errorlevel 1 exit /b 1

echo [6/51] image_state_store
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_image_state_store ^
    -o "%OUT_DIR%\tb_image_state_store.vvp" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" "%~dp0tb_image_state_store.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_image_state_store.vvp"
if errorlevel 1 exit /b 1

echo [7/51] pixel_termination_mask
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_pixel_termination_mask ^
    -o "%OUT_DIR%\tb_pixel_termination_mask.vvp" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%~dp0tb_pixel_termination_mask.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_pixel_termination_mask.vvp"
if errorlevel 1 exit /b 1

echo [8/51] raster_termination_filter
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_raster_termination_filter ^
    -o "%OUT_DIR%\tb_raster_termination_filter.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%~dp0tb_raster_termination_filter.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_raster_termination_filter.vvp"
if errorlevel 1 exit /b 1

echo [9/51] raster_pair_shell end-to-end with backpressure
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_raster_pair_shell -o "%OUT_DIR%\tb_raster_pair_shell.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%~dp0tb_raster_pair_shell.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_raster_pair_shell.vvp"
if errorlevel 1 exit /b 1

echo [10/51] fixed_div_pipe2
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_fixed_div_pipe2 ^
    -o "%OUT_DIR%\tb_fixed_div_pipe2.vvp" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" "%~dp0tb_fixed_div_pipe2.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_fixed_div_pipe2.vvp"
if errorlevel 1 exit /b 1

echo [11/51] world-to-camera and mean projection
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_projection_primitives ^
    -o "%OUT_DIR%\tb_projection_primitives.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%~dp0tb_projection_primitives.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_projection_primitives.vvp"
if errorlevel 1 exit /b 1

echo [11b/56] world-to-camera rounding, saturation and backpressure
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_world_to_camera_core ^
    -o "%OUT_DIR%\tb_world_to_camera_core.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%~dp0tb_world_to_camera_core.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_world_to_camera_core.vvp"
if errorlevel 1 exit /b 1

echo [11c/57] perspective principal point and independent axis saturation
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_perspective_project_core ^
    -o "%OUT_DIR%\tb_perspective_project_core.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%~dp0tb_perspective_project_core.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_perspective_project_core.vvp"
if errorlevel 1 exit /b 1

echo [12/51] screen covariance
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_screen_covariance_core ^
    -o "%OUT_DIR%\tb_screen_covariance_core.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%~dp0tb_screen_covariance_core.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_screen_covariance_core.vvp"
if errorlevel 1 exit /b 1

echo [13/51] projection lane, bbox, alpha encoding and block-walker backpressure
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_camera_projection_tile_lane ^
    -o "%OUT_DIR%\tb_camera_projection_tile_lane.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%~dp0tb_camera_projection_tile_lane.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_camera_projection_tile_lane.vvp"
if errorlevel 1 exit /b 1

echo [14/51] normalized quaternion, scale and view covariance chain
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_covariance3d_chain ^
    -o "%OUT_DIR%\tb_covariance3d_chain.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%~dp0tb_covariance3d_chain.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_covariance3d_chain.vvp"
if errorlevel 1 exit /b 1

echo [15/51] pipelined integer square root
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_fixed_sqrt_pipe ^
    -o "%OUT_DIR%\tb_fixed_sqrt_pipe.vvp" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%~dp0tb_fixed_sqrt_pipe.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_fixed_sqrt_pipe.vvp"
if errorlevel 1 exit /b 1

echo [16/51] 2D covariance inverse and Cholesky block-float encoder
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_covariance2d_cholesky_encoder ^
    -o "%OUT_DIR%\tb_covariance2d_cholesky_encoder.vvp" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%~dp0tb_covariance2d_cholesky_encoder.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_covariance2d_cholesky_encoder.vvp"
if errorlevel 1 exit /b 1

echo [17/51] raw Gaussian to complete block/alpha descriptor lane
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_raw_gaussian_projection_lane ^
    -o "%OUT_DIR%\tb_raw_gaussian_projection_lane.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%~dp0tb_raw_gaussian_projection_lane.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_raw_gaussian_projection_lane.vvp"
if errorlevel 1 exit /b 1

echo [18/51] enabled-lane round-robin dispatch and locked task arbitration
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_projection_lane_scheduler ^
    -o "%OUT_DIR%\tb_projection_lane_scheduler.vvp" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%~dp0tb_projection_lane_scheduler.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_projection_lane_scheduler.vvp"
if errorlevel 1 exit /b 1

echo [19/51] epoch-safe projection lane-count commit
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_projection_epoch_lane_ctrl ^
    -o "%OUT_DIR%\tb_projection_epoch_lane_ctrl.vvp" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%~dp0tb_projection_epoch_lane_ctrl.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_projection_epoch_lane_ctrl.vvp"
if errorlevel 1 exit /b 1

echo [20/51] integrated dynamic ordered raw-Gaussian projection array
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_raw_gaussian_projection_array ^
    -o "%OUT_DIR%\tb_raw_gaussian_projection_array.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_array.sv" ^
    "%~dp0tb_raw_gaussian_projection_array.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_raw_gaussian_projection_array.vvp"
if errorlevel 1 exit /b 1

echo [21/51] depth grouping and stable group sort chain
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_depth_group_sort_chain ^
    -o "%OUT_DIR%\tb_depth_group_sort_chain.vvp" ^
    "%REPO_ROOT%\rtl\sort\depth_group_buffer.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter.sv" ^
    "%~dp0tb_depth_group_sort_chain.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_depth_group_sort_chain.vvp"
if errorlevel 1 exit /b 1

echo [21b/63] G/P/R/E group-sort service quota and backpressure stability
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_group_sort_service_gate ^
    -o "%OUT_DIR%\tb_group_sort_service_gate.vvp" ^
    "%REPO_ROOT%\rtl\sort\group_sort_service_gate.sv" ^
    "%~dp0tb_group_sort_service_gate.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_group_sort_service_gate.vvp"
if errorlevel 1 exit /b 1

echo [22/51] Gaussian depth prepass and sequence allocation
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_depth_prepass_core ^
    -o "%OUT_DIR%\tb_gaussian_depth_prepass_core.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_core.sv" ^
    "%~dp0tb_gaussian_depth_prepass_core.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_depth_prepass_core.vvp"
if errorlevel 1 exit /b 1

echo [23/51] parallel Gaussian ordered retire
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_ordered_gaussian_retire ^
    -o "%OUT_DIR%\tb_ordered_gaussian_retire.vvp" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%~dp0tb_ordered_gaussian_retire.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_ordered_gaussian_retire.vvp"
if errorlevel 1 exit /b 1

echo [24/51] G/P/R/E resource policy and pipeline event counters
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_resource_control ^
    -o "%OUT_DIR%\tb_gaussian_resource_control.vvp" ^
    "%REPO_ROOT%\rtl\control\sat_counter_bank.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_resource_mode_table.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_pipeline_event_counters.sv" ^
    "%~dp0tb_gaussian_resource_control.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_resource_control.vvp"
if errorlevel 1 exit /b 1

echo [24b/65] physically shared compare/MAC PE, weighted arbitration and backpressure
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_shared_reconfigurable_pe_slice ^
    -o "%OUT_DIR%\tb_shared_reconfigurable_pe_slice.vvp" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%~dp0tb_shared_reconfigurable_pe_slice.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_shared_reconfigurable_pe_slice.vvp"
if errorlevel 1 exit /b 1

echo [24c/67] shared P-client camera-depth MAC versus legacy prepass
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_depth_prepass_shared_mac ^
    -o "%OUT_DIR%\tb_gaussian_depth_prepass_shared_mac.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_core.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_shared_mac.sv" ^
    "%~dp0tb_gaussian_depth_prepass_shared_mac.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_depth_prepass_shared_mac.vvp"
if errorlevel 1 exit /b 1

echo [24d/67] shared G-client stable-key compare versus legacy sorter
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_stable_group_sorter_shared_compare ^
    -o "%OUT_DIR%\tb_stable_group_sorter_shared_compare.vvp" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter_shared_compare.sv" ^
    "%~dp0tb_stable_group_sorter_shared_compare.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_stable_group_sorter_shared_compare.vvp"
if errorlevel 1 exit /b 1

echo [24e/70] shared XYZ projection transform versus local nine-multiplier golden
echo [24f/73] parallel shared-G compare-exchange versus stable insertion golden
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_stable_group_sorter_parallel_shared ^
    -o "%OUT_DIR%\tb_stable_group_sorter_parallel_shared.vvp" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter_shared_compare.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter_parallel_shared.sv" ^
    "%~dp0tb_stable_group_sorter_parallel_shared.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_stable_group_sorter_parallel_shared.vvp"
if errorlevel 1 exit /b 1

"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_world_to_camera_shared_mac ^
    -o "%OUT_DIR%\tb_world_to_camera_shared_mac.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_shared_mac.sv" ^
    "%~dp0tb_world_to_camera_shared_mac.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_world_to_camera_shared_mac.vvp"
if errorlevel 1 exit /b 1

echo [25/51] sorted issue to distributed projection ordered-retire scheduler
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_ordered_projection_lane_scheduler ^
    -o "%OUT_DIR%\tb_ordered_projection_lane_scheduler.vvp" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%~dp0tb_ordered_projection_lane_scheduler.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_ordered_projection_lane_scheduler.vvp"
if errorlevel 1 exit /b 1

echo [26/51] long-window hysteretic G/P/R/E mode advisor
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_mode_advisor ^
    -o "%OUT_DIR%\tb_gaussian_mode_advisor.vvp" ^
    "%REPO_ROOT%\rtl\control\gaussian_mode_advisor.sv" ^
    "%~dp0tb_gaussian_mode_advisor.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_mode_advisor.vvp"
if errorlevel 1 exit /b 1

echo [26b/64] G/P/R/E and balanced long-window advisor workload matrix
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_mode_advisor_workload_matrix ^
    -o "%OUT_DIR%\tb_gaussian_mode_advisor_workload_matrix.vvp" ^
    "%REPO_ROOT%\rtl\control\gaussian_mode_advisor.sv" ^
    "%~dp0tb_gaussian_mode_advisor_workload_matrix.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_mode_advisor_workload_matrix.vvp"
if errorlevel 1 exit /b 1

echo [27/51] view direction normalization for SH
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_view_direction_normalizer ^
    -o "%OUT_DIR%\tb_view_direction_normalizer.vvp" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%~dp0tb_view_direction_normalizer.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_view_direction_normalizer.vvp"
if errorlevel 1 exit /b 1

echo [28/51] degree-3 SH fixed-point color core
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_sh_degree3_color_core ^
    -o "%OUT_DIR%\tb_sh_degree3_color_core.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%~dp0tb_sh_degree3_color_core.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_sh_degree3_color_core.vvp"
if errorlevel 1 exit /b 1

echo [29/51] complete per-Gaussian SH color path
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_sh_color_core ^
    -o "%OUT_DIR%\tb_gaussian_sh_color_core.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_core.sv" ^
    "%~dp0tb_gaussian_sh_color_core.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_sh_color_core.vvp"
if errorlevel 1 exit /b 1

echo [30/51] Gaussian-internal 8x8 block pixel expansion
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_block_pixel_expander ^
    -o "%OUT_DIR%\tb_gaussian_block_pixel_expander.vvp" ^
    "%REPO_ROOT%\rtl\raster\gaussian_shape_block_reject.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_block_pixel_expander.sv" ^
    "%~dp0tb_gaussian_block_pixel_expander.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_block_pixel_expander.vvp"
if errorlevel 1 exit /b 1

echo [30b/58] conservative Gaussian shape block reject
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_shape_block_reject ^
    -o "%OUT_DIR%\tb_gaussian_shape_block_reject.vvp" ^
    "%REPO_ROOT%\rtl\raster\gaussian_shape_block_reject.sv" ^
    "%~dp0tb_gaussian_shape_block_reject.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_shape_block_reject.vvp"
if errorlevel 1 exit /b 1

echo [31/51] ordered block expansion through alpha, blend and termination
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_ordered_block_raster_frontend -o "%OUT_DIR%\tb_ordered_block_raster_frontend.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_shape_block_reject.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_block_pixel_expander.sv" ^
    "%REPO_ROOT%\rtl\raster\ordered_block_raster_frontend.sv" ^
    "%~dp0tb_ordered_block_raster_frontend.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_ordered_block_raster_frontend.vvp"
if errorlevel 1 exit /b 1

echo [32/51] atomic full-Gaussian projection/SH fork
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_projection_sh_fork ^
    -o "%OUT_DIR%\tb_gaussian_projection_sh_fork.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_fifo.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_fork.sv" ^
    "%~dp0tb_gaussian_projection_sh_fork.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_projection_sh_fork.vvp"
if errorlevel 1 exit /b 1

echo [33/51] ordered projection blocks joined with one SH color per Gaussian
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_ordered_projection_sh_join ^
    -o "%OUT_DIR%\tb_ordered_projection_sh_join.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_fifo.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_sh_join.sv" ^
    "%~dp0tb_ordered_projection_sh_join.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_ordered_projection_sh_join.vvp"
if errorlevel 1 exit /b 1

echo [34/51] dynamic parallel projection and SH with ordered per-Gaussian reuse
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_projection_sh_array ^
    -o "%OUT_DIR%\tb_gaussian_projection_sh_array.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\rv_fifo.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_resource_mode_table.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_fork.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_sh_join.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_array.sv" ^
    "%~dp0tb_gaussian_projection_sh_array.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_projection_sh_array.vvp"
if errorlevel 1 exit /b 1

echo [35/51] full ordered Gaussian projection-SH-block-pixel-raster front end
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_gaussian_ordered_render_frontend -o "%OUT_DIR%\tb_gaussian_ordered_render_frontend.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\rv_fifo.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_resource_mode_table.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_fork.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_sh_join.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_gaussian_block_decoder.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_array.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_shape_block_reject.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_block_pixel_expander.sv" ^
    "%REPO_ROOT%\rtl\raster\ordered_block_raster_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_ordered_render_frontend.sv" ^
    "%~dp0tb_gaussian_ordered_render_frontend.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_ordered_render_frontend.vvp"
if errorlevel 1 exit /b 1

echo [36/51] banked full-Gaussian attribute store
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_attribute_store ^
    -o "%OUT_DIR%\tb_gaussian_attribute_store.vvp" ^
    "%REPO_ROOT%\rtl\memory\sram_1r1w_wrapper.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_store.sv" ^
    "%~dp0tb_gaussian_attribute_store.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_attribute_store.vvp"
if errorlevel 1 exit /b 1

echo [37/51] sorted metadata to ordered full-attribute issue
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_ordered_gaussian_attribute_issue ^
    -o "%OUT_DIR%\tb_ordered_gaussian_attribute_issue.vvp" ^
    "%REPO_ROOT%\rtl\memory\sram_1r1w_wrapper.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_store.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_sram_backend.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_attribute_issue.sv" ^
    "%~dp0tb_ordered_gaussian_attribute_issue.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_ordered_gaussian_attribute_issue.vvp"
if errorlevel 1 exit /b 1

echo [38/51] sorted GID fetch through complete ordered render pipeline
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_gaussian_sorted_render_pipeline -o "%OUT_DIR%\tb_gaussian_sorted_render_pipeline.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\rv_fifo.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_resource_mode_table.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\memory\sram_1r1w_wrapper.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_store.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_sram_backend.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_attribute_issue.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_fork.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_sh_join.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_gaussian_block_decoder.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_array.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_shape_block_reject.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_block_pixel_expander.sv" ^
    "%REPO_ROOT%\rtl\raster\ordered_block_raster_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_ordered_render_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_sorted_render_pipeline.sv" ^
    "%~dp0tb_gaussian_sorted_render_pipeline.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_sorted_render_pipeline.vvp"
if errorlevel 1 exit /b 1

echo [39/51] dynamic SH lane dispatch and deliberately out-of-order completion
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_ordered_sh_lane_scheduler ^
    -o "%OUT_DIR%\tb_ordered_sh_lane_scheduler.vvp" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%~dp0tb_ordered_sh_lane_scheduler.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_ordered_sh_lane_scheduler.vvp"
if errorlevel 1 exit /b 1

echo [40/51] replicated fixed-point SH array and one/four-lane equivalence
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_gaussian_sh_color_array ^
    -o "%OUT_DIR%\tb_gaussian_sh_color_array.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_array.sv" ^
    "%~dp0tb_gaussian_sh_color_array.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_sh_color_array.vvp"
if errorlevel 1 exit /b 1

echo [41/51] dynamic raster alpha lanes with ordered completion
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_raster_alpha_lane_array -o "%OUT_DIR%\tb_raster_alpha_lane_array.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%~dp0tb_raster_alpha_lane_array.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_raster_alpha_lane_array.vvp"
if errorlevel 1 exit /b 1

echo [42/51] same-pixel RAW hazard serialization through ordered state commit
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_raster_ordered_same_pixel -o "%OUT_DIR%\tb_raster_ordered_same_pixel.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%~dp0tb_raster_ordered_same_pixel.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_raster_ordered_same_pixel.vvp"
if errorlevel 1 exit /b 1

echo [43/51] frame depth-group-sort-to-render end-to-end integration
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_gaussian_frame_render_pipeline -o "%OUT_DIR%\tb_gaussian_frame_render_pipeline.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\rv_fifo.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_resource_mode_table.sv" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_mode_advisor.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_core.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_shared_mac.sv" ^
    "%REPO_ROOT%\rtl\sort\depth_group_buffer.sv" ^
    "%REPO_ROOT%\rtl\sort\group_sort_service_gate.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter_shared_compare.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_attribute_issue.sv" ^
    "%REPO_ROOT%\rtl\memory\sram_1r1w_wrapper.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_store.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_sram_backend.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_fork.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_sh_join.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_gaussian_block_decoder.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_array.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_shape_block_reject.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_block_pixel_expander.sv" ^
    "%REPO_ROOT%\rtl\raster\ordered_block_raster_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_ordered_render_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_sorted_render_pipeline.sv" ^
    "%REPO_ROOT%\rtl\sort\autonomous_qsu.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_qsu_scratch_dma.sv" ^
    "%REPO_ROOT%\rtl\gaussian_frame_render_pipeline.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_shared_mac.sv" ^
    "%~dp0tb_gaussian_frame_render_pipeline.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_frame_render_pipeline.vvp"
if errorlevel 1 exit /b 1

echo [44/51] frame command and sticky error termination
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_gaussian_frame_error_control -o "%OUT_DIR%\tb_gaussian_frame_error_control.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\rv_fifo.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_resource_mode_table.sv" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_core.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_shared_mac.sv" ^
    "%REPO_ROOT%\rtl\sort\depth_group_buffer.sv" ^
    "%REPO_ROOT%\rtl\sort\group_sort_service_gate.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter_shared_compare.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_attribute_issue.sv" ^
    "%REPO_ROOT%\rtl\memory\sram_1r1w_wrapper.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_store.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_sram_backend.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_fork.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_sh_join.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_gaussian_block_decoder.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_array.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_shape_block_reject.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_block_pixel_expander.sv" ^
    "%REPO_ROOT%\rtl\raster\ordered_block_raster_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_ordered_render_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_sorted_render_pipeline.sv" ^
    "%REPO_ROOT%\rtl\sort\autonomous_qsu.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_qsu_scratch_dma.sv" ^
    "%REPO_ROOT%\rtl\gaussian_frame_render_pipeline.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_shared_mac.sv" ^
    "%~dp0tb_gaussian_frame_error_control.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gaussian_frame_error_control.vvp"
if errorlevel 1 exit /b 1

echo [45/51] APB-controlled frame command, sticky status and IRQ integration
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I "%REPO_ROOT%\rtl\raster" ^
    -s tb_gs_accel_system_top -o "%OUT_DIR%\tb_gs_accel_system_top.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\common\rv_fifo.sv" ^
    "%REPO_ROOT%\rtl\common\fixed_sqrt_pipe.sv" ^
    "%REPO_ROOT%\rtl\control\apb_regfile.sv" ^
    "%REPO_ROOT%\rtl\control\cfg_epoch_ctrl.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_resource_mode_table.sv" ^
    "%REPO_ROOT%\rtl\control\shared_reconfigurable_pe_slice.sv" ^
    "%REPO_ROOT%\rtl\control\gaussian_mode_advisor.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_core.sv" ^
    "%REPO_ROOT%\rtl\sort\gaussian_depth_prepass_shared_mac.sv" ^
    "%REPO_ROOT%\rtl\sort\depth_group_buffer.sv" ^
    "%REPO_ROOT%\rtl\sort\group_sort_service_gate.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter.sv" ^
    "%REPO_ROOT%\rtl\sort\stable_group_sorter_shared_compare.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_retire.sv" ^
    "%REPO_ROOT%\rtl\sort\ordered_gaussian_attribute_issue.sv" ^
    "%REPO_ROOT%\rtl\memory\sram_1r1w_wrapper.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_store.sv" ^
    "%REPO_ROOT%\rtl\memory\gaussian_attribute_sram_backend.sv" ^
    "%REPO_ROOT%\rtl\projection\fixed_div_pipe2.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_core.sv" ^
    "%REPO_ROOT%\rtl\projection\quaternion_scale_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance_view_rotate_core.sv" ^
    "%REPO_ROOT%\rtl\projection\perspective_project_core.sv" ^
    "%REPO_ROOT%\rtl\projection\screen_covariance_core.sv" ^
    "%REPO_ROOT%\rtl\projection\opacity_radius_bound.sv" ^
    "%REPO_ROOT%\rtl\projection\bbox_tile_bounds_core.sv" ^
    "%REPO_ROOT%\rtl\projection\covariance2d_cholesky_encoder.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_tile_task_gen.sv" ^
    "%REPO_ROOT%\rtl\projection\camera_projection_tile_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_lane.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\projection\projection_epoch_lane_ctrl.sv" ^
    "%REPO_ROOT%\rtl\projection\raw_gaussian_projection_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_fork.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_projection_sh_join.sv" ^
    "%REPO_ROOT%\rtl\projection\ordered_gaussian_block_decoder.sv" ^
    "%REPO_ROOT%\rtl\sh\view_direction_normalizer.sv" ^
    "%REPO_ROOT%\rtl\sh\sh_degree3_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_core.sv" ^
    "%REPO_ROOT%\rtl\sh\ordered_sh_lane_scheduler.sv" ^
    "%REPO_ROOT%\rtl\sh\gaussian_sh_color_array.sv" ^
    "%REPO_ROOT%\rtl\projection\gaussian_projection_sh_array.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_bank.sv" ^
    "%REPO_ROOT%\rtl\raster\block_termination_table.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_termination_filter.sv" ^
    "%REPO_ROOT%\rtl\raster\pixel_termination_mask.sv" ^
    "%REPO_ROOT%\rtl\raster\alpha_block_float_core.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_alpha_lane_array.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_store.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit.sv" ^
    "%REPO_ROOT%\rtl\raster\raster_pair_shell.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_shape_block_reject.sv" ^
    "%REPO_ROOT%\rtl\raster\gaussian_block_pixel_expander.sv" ^
    "%REPO_ROOT%\rtl\raster\ordered_block_raster_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_ordered_render_frontend.sv" ^
    "%REPO_ROOT%\rtl\gaussian_sorted_render_pipeline.sv" ^
    "%REPO_ROOT%\rtl\sort\autonomous_qsu.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_qsu_scratch_dma.sv" ^
    "%REPO_ROOT%\rtl\gaussian_frame_render_pipeline.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_camera_config_read_dma.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_gaussian_mean_read_dma.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_cache_backend.sv" ^
    "%REPO_ROOT%\rtl\raster\image_state_cache_backend_single.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_read_engine.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_dual_read_engine.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_write_engine.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_write_buffer.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_writeback_buffer.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_multiwrite_buffer.sv" ^
    "%REPO_ROOT%\rtl\gs_accel_system_top.sv" ^
    "%REPO_ROOT%\rtl\projection\world_to_camera_shared_mac.sv" ^
    "%~dp0tb_gs_accel_system_top.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_gs_accel_system_top.vvp"
if errorlevel 1 exit /b 1

echo [46/51] AXI4 Gaussian mean read DMA burst, backpressure and error behavior
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_gaussian_mean_read_dma ^
    -o "%OUT_DIR%\tb_axi4_gaussian_mean_read_dma.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_gaussian_mean_read_dma.sv" ^
    "%~dp0tb_axi4_gaussian_mean_read_dma.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_gaussian_mean_read_dma.vvp"
if errorlevel 1 exit /b 1

echo [46b/80] AXI4 versioned camera descriptor DMA, 4-KiB split and error handling
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_camera_config_read_dma ^
    -o "%OUT_DIR%\tb_axi4_camera_config_read_dma.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_camera_config_read_dma.sv" ^
    "%~dp0tb_axi4_camera_config_read_dma.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_camera_config_read_dma.vvp"
if errorlevel 1 exit /b 1

echo [46c/80] CAMERA_BASE command snapshot, DMA load and continuation validation
pushd "%REPO_ROOT%"
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -s tb_gs_accel_system_camera_dma ^
    -o "tmp\iverilog\tb_gs_accel_system_camera_dma.vvp" ^
    -f "verification\rtl\system_top_sources.f" ^
    "verification\rtl\tb_gs_accel_system_camera_dma.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_gs_accel_system_camera_dma.vvp"
if errorlevel 1 (popd & exit /b 1)
popd

echo [47/51] AXI mean DMA through APB frame control, render core and IRQ
pushd "%REPO_ROOT%"
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -s tb_gs_accel_system_axi_mean ^
    -o "tmp\iverilog\tb_gs_accel_system_axi_mean.vvp" ^
    -f "verification\rtl\system_top_sources.f" ^
    "verification\rtl\tb_gs_accel_system_axi_mean.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_gs_accel_system_axi_mean.vvp"
if errorlevel 1 (popd & exit /b 1)
popd

echo [48/51] AXI4 sorted-GID complete-attribute record assembly
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_gaussian_attribute_read_engine ^
    -o "%OUT_DIR%\tb_axi4_gaussian_attribute_read_engine.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_gaussian_attribute_read_engine.sv" ^
    "%~dp0tb_axi4_gaussian_attribute_read_engine.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_gaussian_attribute_read_engine.vvp"
if errorlevel 1 exit /b 1

echo [49/51] AXI4 ordered pixel-state writeback and response errors
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_write_engine ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_write_engine.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_write_engine.sv" ^
    "%~dp0tb_axi4_pixel_state_write_engine.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_write_engine.vvp"
if errorlevel 1 exit /b 1

echo [50/51] AXI4 pixel backing-state read and response errors
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_read_engine ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_read_engine.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_read_engine.sv" ^
    "%~dp0tb_axi4_pixel_state_read_engine.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_read_engine.vvp"
if errorlevel 1 exit /b 1

echo [51/57] dual-outstanding AXI4 pixel-state read with out-of-order RID return
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_dual_read_engine ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_dual_read_engine.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_dual_read_engine.sv" ^
    "%~dp0tb_axi4_pixel_state_dual_read_engine.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_dual_read_engine.vvp"
if errorlevel 1 exit /b 1

echo [52/58] randomized dual-read AXI backpressure, ordering and tag integrity
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_dual_read_random ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_dual_read_random.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_dual_read_engine.sv" ^
    "%~dp0tb_axi4_pixel_state_dual_read_random.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_dual_read_random.vvp"
if errorlevel 1 exit /b 1

echo [53/58] direct-mapped write-through image-state cache with configurable tagged MSHRs
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_image_state_cache_backend ^
    -o "%OUT_DIR%\tb_image_state_cache_backend.vvp" ^
    "%REPO_ROOT%\rtl\raster\image_state_cache_backend.sv" ^
    "%~dp0tb_image_state_cache_backend.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_image_state_cache_backend.vvp"
if errorlevel 1 exit /b 1

echo [53b/61] four-entry ordered state window with OOO responses, RAW CAM and ring replacement
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_blend_state_commit_4 ^
    -o "%OUT_DIR%\tb_blend_state_commit_4.vvp" ^
    "%REPO_ROOT%\rtl\common\rv_reg_slice.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_fixed_core.sv" ^
    "%REPO_ROOT%\rtl\raster\blend_state_commit_4.sv" ^
    "%~dp0tb_blend_state_commit_4.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_blend_state_commit_4.vvp"
if errorlevel 1 exit /b 1

echo [53c/61] four physical image-state MSHRs and tagged OOO fill
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_image_state_cache_backend_4 ^
    -o "%OUT_DIR%\tb_image_state_cache_backend_4.vvp" ^
    "%REPO_ROOT%\rtl\raster\image_state_cache_backend_4.sv" ^
    "%~dp0tb_image_state_cache_backend_4.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_image_state_cache_backend_4.vvp"
if errorlevel 1 exit /b 1

echo [53d/61] randomized four-ID AXI read ordering and backpressure
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_quad_read_random ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_quad_read_random.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_quad_read_engine.sv" ^
    "%~dp0tb_axi4_pixel_state_quad_read_random.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_quad_read_random.vvp"
if errorlevel 1 exit /b 1

echo [54/58] ordered pixel-state write buffer and full-tag hazard tracking
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_write_buffer ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_write_buffer.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_write_engine.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_write_buffer.sv" ^
    "%~dp0tb_axi4_pixel_state_write_buffer.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_write_buffer.vvp"
if errorlevel 1 exit /b 1

echo [55/58] dirty-pixel write-back, forwarding, eviction and frame flush
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_writeback_buffer ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_writeback_buffer.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_write_engine.sv" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_writeback_buffer.sv" ^
    "%~dp0tb_axi4_pixel_state_writeback_buffer.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_writeback_buffer.vvp"
if errorlevel 1 exit /b 1

echo [56/58] ordered multi-outstanding AXI4 writes, hazards and response retirement
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_multiwrite_buffer ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_multiwrite_buffer.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_multiwrite_buffer.sv" ^
    "%~dp0tb_axi4_pixel_state_multiwrite_buffer.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_multiwrite_buffer.vvp"
if errorlevel 1 exit /b 1

echo [57/58] randomized independent AW/W backpressure and B-response spacing
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -s tb_axi4_pixel_state_multiwrite_random ^
    -o "%OUT_DIR%\tb_axi4_pixel_state_multiwrite_random.vvp" ^
    "%REPO_ROOT%\rtl\dma\axi4_pixel_state_multiwrite_buffer.sv" ^
    "%~dp0tb_axi4_pixel_state_multiwrite_random.sv"
if errorlevel 1 exit /b 1
"%VVP%" "%OUT_DIR%\tb_axi4_pixel_state_multiwrite_random.vvp"
if errorlevel 1 exit /b 1

echo [58/58] local trained-scene DMA micro-workload through the complete system
pushd "%REPO_ROOT%"
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -s tb_real_dma_workload ^
    -o "tmp\iverilog\tb_real_dma_workload.vvp" ^
    -f "verification\rtl\system_top_sources.f" ^
    "verification\rtl\tb_real_dma_workload.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_real_dma_workload.vvp"
if errorlevel 1 (popd & exit /b 1)

echo [58b/68] legacy prepass/sorter bypass golden on the same DMA workload
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -D TB_USE_SHARED_PE=0 ^
    -s tb_real_dma_workload -o "tmp\iverilog\tb_real_dma_workload_bypass.vvp" ^
    -f "verification\rtl\system_top_sources.f" ^
    "verification\rtl\tb_real_dma_workload.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_real_dma_workload_bypass.vvp"
if errorlevel 1 (popd & exit /b 1)

echo [58c/70] prepass-only shared PE reference with main projection bypassed
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -D TB_USE_SHARED_PROJECTION_PE=0 ^
    -s tb_real_dma_workload -o "tmp\iverilog\tb_real_dma_workload_prepass_only.vvp" ^
    -f "verification\rtl\system_top_sources.f" ^
    "verification\rtl\tb_real_dma_workload.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_real_dma_workload_prepass_only.vvp"
if errorlevel 1 (popd & exit /b 1)
echo [58d/73] parallel sort candidate on the same DMA micro-workload
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -D TB_USE_PARALLEL_GROUP_SORT=1 ^
    -s tb_real_dma_workload -o "tmp\iverilog\tb_real_dma_workload_parallel_sort.vvp" ^
    -f "verification\rtl\system_top_sources.f" "verification\rtl\tb_real_dma_workload.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_real_dma_workload_parallel_sort.vvp"
if errorlevel 1 (popd & exit /b 1)

echo [58e/73] parallel frame candidate including continuation and abort recovery
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -D TB_FRAME_PARALLEL_SORT=1 ^
    -s tb_gaussian_frame_render_pipeline -o "tmp\iverilog\tb_frame_parallel_sort.vvp" ^
    -f "verification\rtl\system_top_sources.f" "verification\rtl\tb_gaussian_frame_render_pipeline.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_frame_parallel_sort.vvp"
if errorlevel 1 (popd & exit /b 1)
echo [74/74] candidate sorter APB snapshots, continuation, clear and modular deltas
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -D TB_SYSTEM_PARALLEL_SORT=1 ^
    -s tb_gs_accel_system_top -o "tmp\iverilog\tb_system_sort_snapshot.vvp" ^
    -f "verification\rtl\system_top_sources.f" "verification\rtl\tb_gs_accel_system_top.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_system_sort_snapshot.vvp"
if errorlevel 1 (popd & exit /b 1)
echo [75/75] four-lane ascending/reverse fastpath frames with state backing model
"%IVERILOG%" -g2012 -DSYNTHESIS -Wall -I rtl\raster -D TB_SYSTEM_PARALLEL_SORT=1 ^
    -D TB_SYSTEM_LANES=4 -D TB_SYSTEM_FASTPATH_TEST=1 ^
    -s tb_gs_accel_system_top -o "tmp\iverilog\tb_system_sort_fastpath_frames.vvp" ^
    -f "verification\rtl\system_top_sources.f" "verification\rtl\tb_gs_accel_system_top.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_system_sort_fastpath_frames.vvp"
if errorlevel 1 (popd & exit /b 1)
echo [76/77] XYZ continuous output turnover with G competition and backpressure
"%IVERILOG%" -g2012 -DSYNTHESIS -D TB_XYZ_STREAMING=1 -s tb_world_to_camera_shared_mac ^
    -o "tmp\iverilog\tb_xyz_turnover_stream.vvp" "rtl\common\rv_reg_slice.sv" ^
    "rtl\projection\world_to_camera_core.sv" "rtl\projection\world_to_camera_shared_mac.sv" ^
    "rtl\control\shared_reconfigurable_pe_slice.sv" "verification\rtl\tb_world_to_camera_shared_mac.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_xyz_turnover_stream.vvp"
if errorlevel 1 (popd & exit /b 1)
echo [77/77] ordered attribute turnover, delayed backend, stalls and error rejection
"%IVERILOG%" -g2012 -DSYNTHESIS -s tb_attribute_issue_turnover ^
    -o "tmp\iverilog\tb_attribute_issue_turnover.vvp" "rtl\sort\ordered_gaussian_attribute_issue.sv" ^
    "verification\rtl\tb_attribute_issue_turnover.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_attribute_issue_turnover.vvp"
if errorlevel 1 (popd & exit /b 1)
echo [78/78] ordered R-blend shared-PE arithmetic with request and output stalls
"%IVERILOG%" -g2012 -DSYNTHESIS -s tb_blend_fixed_shared_pe_core ^
    -o "tmp\iverilog\tb_blend_fixed_shared_pe_core.vvp" "rtl\common\rv_reg_slice.sv" ^
    "rtl\raster\blend_fixed_core.sv" "verification\rtl\tb_blend_fixed_shared_pe_core.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_blend_fixed_shared_pe_core.vvp"
if errorlevel 1 (popd & exit /b 1)
echo [79/79] alpha-zero skip interleaved with same-pixel ordered commits
"%IVERILOG%" -g2012 -DSYNTHESIS -DTB_ALPHA_ZERO_SKIP=1 -I rtl\raster ^
    -s tb_raster_ordered_same_pixel -o "tmp\iverilog\tb_alpha_zero_skip_same_pixel.vvp" ^
    -f "verification\rtl\system_top_sources.f" "verification\rtl\tb_raster_ordered_same_pixel.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_alpha_zero_skip_same_pixel.vvp"
if errorlevel 1 (popd & exit /b 1)
echo [80/80] final RGB888 frame DMA packing, stride, 4KiB split and backpressure
"%IVERILOG%" -g2012 -DSYNTHESIS -s tb_axi4_final_rgb_frame_dma ^
    -o "tmp\iverilog\tb_axi4_final_rgb_frame_dma.vvp" ^
    "rtl\dma\axi4_final_rgb_frame_dma.sv" "verification\rtl\tb_axi4_final_rgb_frame_dma.sv"
if errorlevel 1 (popd & exit /b 1)
"%VVP%" "tmp\iverilog\tb_axi4_final_rgb_frame_dma.vvp"
if errorlevel 1 (popd & exit /b 1)
popd

echo PASS: all configured Icarus Verilog self-checking simulations plus one synthesis compile
exit /b 0




