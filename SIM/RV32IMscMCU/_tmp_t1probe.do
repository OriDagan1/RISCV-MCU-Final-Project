vsim -quiet -t 1ps work.tb_RV32IMscMCU
quietly set StdArithNoWarnings 1
quietly set NumericStdNoWarnings 1
run 52 us
echo "PROBE reset+init : H5..H0 = [examine -radix bin /tb_RV32IMscMCU/HEX5_o] [examine -radix bin /tb_RV32IMscMCU/HEX4_o] [examine -radix bin /tb_RV32IMscMCU/HEX3_o] [examine -radix bin /tb_RV32IMscMCU/HEX2_o] [examine -radix bin /tb_RV32IMscMCU/HEX1_o] [examine -radix bin /tb_RV32IMscMCU/HEX0_o]  LEDR=[examine -radix hex /tb_RV32IMscMCU/LEDR_o]"
run 51 us
echo "PROBE after KEY1 : H5=[examine -radix bin /tb_RV32IMscMCU/HEX5_o] H4=[examine -radix bin /tb_RV32IMscMCU/HEX4_o]"
run 51 us
echo "PROBE after KEY2 : H3=[examine -radix bin /tb_RV32IMscMCU/HEX3_o] H2=[examine -radix bin /tb_RV32IMscMCU/HEX2_o]"
run 51 us
echo "PROBE after KEY3 : H1=[examine -radix bin /tb_RV32IMscMCU/HEX1_o] H0=[examine -radix bin /tb_RV32IMscMCU/HEX0_o] LEDR=[examine -radix hex /tb_RV32IMscMCU/LEDR_o]"
quit -f
