`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  model_adcs7476.v -- behavioural model of the Pmod MIC3 ADC for simulation
//
//  Reproduces the datasheet serial behaviour (ADCS7476, section 7.3):
//   * the analog input is sampled at the falling edge of CS
//   * SDATA leaves tri-state t3 after CS falls and presents the first
//     leading zero; every FALLING SCLK edge launches the next bit after
//     t_DACC (four leading zeros, then DB11..DB0)
//   * after the 16th falling edge SDATA goes to tri-state (modelled as 'z')
//   * a protocol monitor flags CS rising early and more than 16 clocks.
//  `analog_code` is the 12-bit code the test bench wants "sampled".
// ============================================================================
module model_adcs7476 (
    input  wire        cs_n,
    input  wire        sclk,
    output wire        sdata,
    input  wire [11:0] analog_code,
    output reg  [31:0] conversions,
    output reg  [31:0] protocol_errors
);
    reg  [15:0] frame;
    reg  [4:0]  nfall;
    reg         drive;
    reg         bit_val;
    reg         started;      // a conversion is in progress (ignores the X->1 edge at power-up)
    real        t_dacc = 30.0;   // ns, datasheet max 40 ns at 3 V

    assign sdata = drive ? bit_val : 1'bz;

    initial begin
        drive = 0; bit_val = 0; nfall = 0; frame = 0; conversions = 0; protocol_errors = 0; started = 0;
    end

    // conversion start: sample now
    always @(negedge cs_n) begin
        frame = {4'b0000, analog_code};
        nfall = 0;
        started = 1;
        #20 drive = 1;               // t3: out of tri-state with the first leading zero
        bit_val = frame[15];
    end

    always @(negedge sclk) begin
        if (!cs_n) begin
            nfall = nfall + 1;
            if (nfall < 16) begin
                #(t_dacc) bit_val = frame[15 - nfall];
            end else if (nfall == 16) begin
                #(t_dacc) drive = 0;   // tri-state after the 16th falling edge
                conversions = conversions + 1;
            end else begin
                protocol_errors = protocol_errors + 1;   // more than 16 clocks
            end
        end
    end

    always @(posedge cs_n) begin
        if (started && nfall != 16) protocol_errors = protocol_errors + 1;
        started = 0;
        drive = 0;
    end
endmodule
`default_nettype wire
