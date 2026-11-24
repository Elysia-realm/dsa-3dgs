// Observation only. Group each accepted transaction by its own pipeline GID.
`define WORK_FRONT dut.u_frame.u_render.u_render
`define WORK_RASTER dut.u_frame.u_render.u_render.u_raster.u_raster
typedef struct packed {
  longint unsigned blocks, rejected, tasks, commits, terminated;
  logic [15:0] x0,y0,x1,y1;
  logic overflow;
} t08_work_t;
t08_work_t t08_work[int unsigned];
integer work_fd;
string work_path;
longint unsigned work_initial_accepted;
initial begin
  if(!$value$plusargs("WORK_TRACE=%s",work_path))$fatal(1,"missing work trace");
  work_fd=$fopen(work_path,"w");if(work_fd==0)$fatal;
end
task automatic work_sample;
  int unsigned id;
  if(`WORK_FRONT.block_valid && `WORK_FRONT.block_ready && !`WORK_FRONT.block_culled && `WORK_FRONT.keep)begin
    id=`WORK_FRONT.block_gid;
    if(!t08_work.exists(id))t08_work[id]='0;
    t08_work[id].blocks++;
    if(`WORK_FRONT.u_raster.shape_reject_accept)t08_work[id].rejected++;
    t08_work[id].x0=`WORK_FRONT.bbox_x0;t08_work[id].x1=`WORK_FRONT.bbox_x1;
    t08_work[id].y0=`WORK_FRONT.bbox_y0;t08_work[id].y1=`WORK_FRONT.bbox_y1;
    t08_work[id].overflow|=`WORK_FRONT.descriptor_overflow;
  end
  if(`WORK_RASTER.task_valid_i && `WORK_RASTER.task_ready_o)begin
    id=`WORK_RASTER.gid_i;
    if(!t08_work.exists(id))t08_work[id]='0;
    t08_work[id].tasks++;
  end
  if(commit_valid_o && commit_ready_i)begin
    id=commit_gid_o;
    if(!t08_work.exists(id))t08_work[id]='0;
    t08_work[id].commits++;
    if(commit_newly_terminated_o)t08_work[id].terminated++;
  end
endtask
task automatic work_report;
  longint unsigned total;
  total=0;
  foreach(t08_work[id])begin
    total+=t08_work[id].tasks;
    $fdisplay(work_fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
      obs_window,id,t08_work[id].blocks,t08_work[id].rejected,t08_work[id].tasks,
      t08_work[id].commits,t08_work[id].terminated,t08_work[id].x0,t08_work[id].y0,
      t08_work[id].x1,t08_work[id].y1,t08_work[id].overflow);
  end
  if(total!=t07_accepted-work_initial_accepted+64'(`WORK_RASTER.task_valid_i&&`WORK_RASTER.task_ready_o))
    $fatal(1,"per-GID task attribution mismatch");
  $fflush(work_fd);t08_work.delete();
endtask
`undef WORK_FRONT
`undef WORK_RASTER
