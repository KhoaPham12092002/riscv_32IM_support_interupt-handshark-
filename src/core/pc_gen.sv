module pc_gen#(parameter logic [31:0] BOOT_ADDR = 32'h0000_0000)
(input logic clk_i,
input logic rst_i,
input logic branch_taken_i, // 1= jump
input logic [31:0] branch_target_addr_i,
input logic stall_i, // 1 = pause PC

output logic [31:0] pc_o);
logic [31:0] pc_next;

always_comb begin 
	if (stall_i) pc_next = pc_o;
	else if (branch_taken_i) pc_next = branch_target_addr_i;
	else pc_next = pc_o +32'd4 ;
		
end

always_ff @(posedge clk_i or posedge rst_i) begin 
	if (rst_i) pc_o <= BOOT_ADDR;
	else pc_o <= pc_next;
	end
	// DEBUG ONLY: In log ra màn hình khi PC thay đổi
    // synthesis translate_off
    always @(posedge clk_i) begin
        if (!rst_i) begin
            $display("[PC_GEN] Time: %0t | PC: %h | Next: %h | Stall: %b | Branch: %b -> %h",
                     $time, pc_o, pc_next, stall_i, branch_taken_i, branch_target_addr_i);
        end
    end
    // synthesis translate_on


endmodule 
