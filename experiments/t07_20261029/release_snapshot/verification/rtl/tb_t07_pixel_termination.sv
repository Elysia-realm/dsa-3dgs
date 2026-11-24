`timescale 1ns/1ps
module tb_t07_pixel_termination;
  logic clk_i=0,rst_ni=0;always #5 clk_i=~clk_i;
  logic task_valid_i=0,task_ready_o,live_valid_o,live_ready_i=1;
  logic[15:0]task_payload_i=0,live_payload_o;
  logic[7:0]task_block_id_i=0,update_block_id_i=0;
  logic[2:0]task_epoch_id_i=0,update_epoch_id_i=0;
  logic[5:0]task_pixel_i=0;logic update_valid_i=0;
  logic[63:0]update_mask_i=0;logic skipped_pulse_o,block_terminated_pulse_o;
  raster_pixel_termination_filter #(.PAYLOAD_W(16),.BLOCK_W(8),.EPOCH_W(3),.ENTRIES(4))dut(.*);
  logic[63:0]truth[0:255];integer truth_epoch=-1;
  integer ids[0:8191];logic may_skip[0:8191];
  integer head=0,tail=0,skips=0,lives=0,blocks=0,serial=0;
  logic held=0,accepted_at_edge=0;logic[15:0]held_payload;
  // Reference stores all block masks: replacement may lose an optimization,
  // but can never create a skip unsupported by committed semantic state.
  always@(posedge clk_i)begin
    accepted_at_edge=task_valid_i&&task_ready_o;
    if(!rst_ni)begin
      head=0;tail=0;truth_epoch=-1;held=0;
      for(integer k=0;k<256;k=k+1)truth[k]=0;
    end else begin
      if(held&&(!live_valid_o||live_payload_o!==held_payload))$fatal(1,"unstable stalled payload");
      held=live_valid_o&&!live_ready_i;held_payload=live_payload_o;
      if(skipped_pulse_o||(live_valid_o&&live_ready_i))begin
        if(head>=tail)$fatal(1,"completion without accepted task");
        if(skipped_pulse_o)begin
          if(!may_skip[head])$fatal(1,"false skip task=%0d",ids[head]);
          skips=skips+1;
        end else begin
          if(live_payload_o!==16'(ids[head]))$fatal(1,"payload/order mismatch");
          lives=lives+1;
        end
        head=head+1;
      end
      if(block_terminated_pulse_o)blocks=blocks+1;
      if(task_valid_i&&truth_epoch!=int'(task_epoch_id_i))begin
        truth_epoch=int'(task_epoch_id_i);
        for(integer k=0;k<256;k=k+1)truth[k]=0;
      end
      if(update_valid_i&&int'(update_epoch_id_i)==truth_epoch)
        truth[update_block_id_i]=truth[update_block_id_i]|update_mask_i;
      if(task_valid_i&&task_ready_o)begin
        ids[tail]=int'(task_payload_i);may_skip[tail]=truth[task_block_id_i][task_pixel_i];tail=tail+1;
      end
    end
  end
  task automatic tick;begin @(posedge clk_i);#1;end endtask
  task automatic send(input integer b,e,p);
    integer previous_tail;
    begin
      @(negedge clk_i);task_valid_i=1;task_block_id_i=8'(b);task_epoch_id_i=3'(e);
      task_pixel_i=6'(p);serial=serial+1;task_payload_i=16'(serial);
      previous_tail=tail;tick();while(tail==previous_tail)tick();
      @(negedge clk_i);task_valid_i=0;
    end
  endtask
  task automatic drain;
    begin live_ready_i=1;repeat(4)tick();if(head!=tail)$fatal(1,"not drained");end
  endtask
  task automatic upd(input integer b,e,input logic[63:0]m);
    begin @(negedge clk_i);update_valid_i=1;update_block_id_i=8'(b);update_epoch_id_i=3'(e);update_mask_i=m;
      tick();@(negedge clk_i);update_valid_i=0;end
  endtask
  integer old_skips,old_lives;integer seed=32'h370029;
  initial begin
    repeat(2)tick();@(negedge clk_i);rst_ni=1;
    send(2,1,5);drain();
    upd(2,1,64'b1<<5);old_skips=skips;send(2,1,5);drain();
    if(skips!=old_skips+1)$fatal(1,"partial/edge block pixel not skipped");
    send(2,1,6);drain();
    upd(6,1,64'b1<<5);old_lives=lives;send(2,1,5);drain();
    if(lives!=old_lives+1)$fatal(1,"capacity alias did not conservatively miss");
    // Same-cycle update/query bypass.
    @(negedge clk_i);update_valid_i=1;update_block_id_i=3;update_epoch_id_i=1;update_mask_i=64'b1<<7;
    task_valid_i=1;task_block_id_i=3;task_epoch_id_i=1;task_pixel_i=7;serial=serial+1;task_payload_i=16'(serial);
    old_skips=skips;tick();@(negedge clk_i);task_valid_i=0;update_valid_i=0;drain();
    if(skips!=old_skips+1)$fatal(1,"same-cycle update missing");
    // Hold a live response while later updates modify its backing row.
    live_ready_i=0;send(1,1,2);upd(1,1,64'hffff_ffff_ffff_ffff);repeat(4)tick();drain();
    old_skips=skips;
    for(integer p=0;p<64;p=p+1)begin send(1,1,p);drain();end
    if(skips!=old_skips+64)$fatal(1,"full block pixels not skipped");
    // Epoch wrap must not resurrect a stale tag from epoch 1.
    for(integer e=2;e<10;e=e+1)begin send(3,e%8,7);drain();end
    old_lives=lives;send(3,1,7);drain();if(lives!=old_lives+1)$fatal(1,"stale wrap hit");
    // Random traffic uses one epoch; full tags and partial masks are checked.
    for(integer j=0;j<2500;j=j+1)begin
      @(negedge clk_i);
      live_ready_i=($urandom(seed)%4)!=0;
      if(!task_valid_i||accepted_at_edge)begin
        task_valid_i=($urandom(seed)%5)!=0;
        if(task_valid_i)begin serial=serial+1;task_payload_i=16'(serial);
          task_block_id_i=8'($urandom(seed)%32);task_pixel_i=6'($urandom(seed)%64);task_epoch_id_i=1;end
      end
      update_valid_i=($urandom(seed)%3)!=0;update_block_id_i=8'($urandom(seed)%32);
      update_epoch_id_i=($urandom(seed)%8==0)?3'd0:3'd1;update_mask_i=64'b1<<($urandom(seed)%64);
      tick();
    end
    @(negedge clk_i);task_valid_i=0;update_valid_i=0;drain();
    @(negedge clk_i);rst_ni=0;tick();@(negedge clk_i);rst_ni=1;
    old_lives=lives;send(1,1,2);drain();if(lives!=old_lives+1)$fatal(1,"reset retained state");
    $display("PASS T07_PIXEL_TERMINATION skips=%0d lives=%0d blocks=%0d",skips,lives,blocks);$finish;
  end
  initial begin #200000;$fatal(1,"timeout");end
endmodule
