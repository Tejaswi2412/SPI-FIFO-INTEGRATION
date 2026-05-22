# SPI-FIFO-INTEGRATION
Buffered SPI transmission system in Verilog. A synchronous FIFO queues multiple bytes upfront and a custom 6-state Controller FSM automatically drains them through an SPI Master (Mode 0) one by one — no manual triggering after writes. Verified with Icarus Verilog.
