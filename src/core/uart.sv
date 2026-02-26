module uart #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  logic       clk_i,
    input  logic       rst_ni,

    // TX Interface (From Core to UART)
    input  logic [7:0] tx_data_i,
    input  logic       tx_valid_i,
    output logic       tx_ready_o,
    output logic       tx_o,

    // RX Interface (From UART to Core)
    output logic [7:0] rx_data_o,
    output logic       rx_valid_o,
    input  logic       rx_ready_i,
    input  logic       rx_i
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    // =========================================================================
    // UART TRANSMITTER (TX)
    // =========================================================================
    typedef enum logic [1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state_t;
    tx_state_t tx_state, tx_next;

    logic [31:0] tx_clk_cnt;
    logic [2:0]  tx_bit_cnt;
    logic [7:0]  tx_shift_reg;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tx_state     <= TX_IDLE;
            tx_clk_cnt   <= 0;
            tx_bit_cnt   <= 0;
            tx_shift_reg <= 8'b0;
            tx_o         <= 1'b1;
        end else begin
            tx_state <= tx_next;
            
            case (tx_state)
                TX_IDLE: begin
                    tx_o       <= 1'b1;
                    tx_clk_cnt <= 0;
                    tx_bit_cnt <= 0;
                    if (tx_valid_i && tx_ready_o) begin
                        tx_shift_reg <= tx_data_i;
                    end
                end

                TX_START: begin
                    tx_o <= 1'b0;
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end

                TX_DATA: begin
                    tx_o <= tx_shift_reg[tx_bit_cnt];
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        tx_bit_cnt <= tx_bit_cnt + 1;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end

                TX_STOP: begin
                    tx_o <= 1'b1;
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end
            endcase
        end
    end

    always_comb begin
        tx_next    = tx_state;
        tx_ready_o = 1'b0;

        case (tx_state)
            TX_IDLE: begin
                tx_ready_o = 1'b1;
                if (tx_valid_i) tx_next = TX_START;
            end
            TX_START: begin
                if (tx_clk_cnt == CLKS_PER_BIT - 1) tx_next = TX_DATA;
            end
            TX_DATA: begin
                if (tx_clk_cnt == CLKS_PER_BIT - 1 && tx_bit_cnt == 7) tx_next = TX_STOP;
            end
            TX_STOP: begin
                if (tx_clk_cnt == CLKS_PER_BIT - 1) tx_next = TX_IDLE;
            end
        endcase
    end

    // =========================================================================
    // UART RECEIVER (RX)
    // =========================================================================
    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t rx_state, rx_next;

    logic [31:0] rx_clk_cnt;
    logic [2:0]  rx_bit_cnt;
    logic [7:0]  rx_shift_reg;
    
    // Double-flop synchronizer to prevent metastability from asynchronous RX input
    logic rx_sync_1, rx_sync_2;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) {rx_sync_2, rx_sync_1} <= 2'b11;
        else         {rx_sync_2, rx_sync_1} <= {rx_sync_1, rx_i};
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_state     <= RX_IDLE;
            rx_clk_cnt   <= 0;
            rx_bit_cnt   <= 0;
            rx_shift_reg <= 8'b0;
            rx_data_o    <= 8'b0;
            rx_valid_o   <= 1'b0;
        end else begin
            rx_state <= rx_next;
            
            // Clear valid signal when core accepts the data
            if (rx_valid_o && rx_ready_i) begin
                rx_valid_o <= 1'b0;
            end

            case (rx_state)
                RX_IDLE: begin
                    rx_clk_cnt <= 0;
                    rx_bit_cnt <= 0;
                end

                RX_START: begin
                    if (rx_clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        rx_clk_cnt <= 0;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end

                RX_DATA: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 0;
                        rx_shift_reg[rx_bit_cnt] <= rx_sync_2;
                        rx_bit_cnt <= rx_bit_cnt + 1;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end

                RX_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 0;
                        rx_data_o  <= rx_shift_reg;
                        rx_valid_o <= 1'b1;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end
            endcase
        end
    end

    always_comb begin
        rx_next = rx_state;

        case (rx_state)
            RX_IDLE: begin
                // Wait for falling edge (Start bit)
                if (rx_sync_2 == 1'b0) rx_next = RX_START;
            end
            RX_START: begin
                // Sample at the middle of the start bit to ensure it's still low
                if (rx_clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                    if (rx_sync_2 == 1'b0) rx_next = RX_DATA;
                    else                   rx_next = RX_IDLE; // False start
                end
            end
            RX_DATA: begin
                if (rx_clk_cnt == CLKS_PER_BIT - 1 && rx_bit_cnt == 7) rx_next = RX_STOP;
            end
            RX_STOP: begin
                // Wait for the middle of the stop bit
                if (rx_clk_cnt == CLKS_PER_BIT - 1) rx_next = RX_IDLE;
            end
        endcase
    end

endmodule