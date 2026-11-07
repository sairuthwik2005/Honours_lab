# sw/Makefile - build C tests for the SoC
#   make                       -> builds every test in tests/
#   make TEST=test_uart        -> builds one test
#   make SIM=1 TEST=test_uart  -> small UART divisor for fast simulation
#
# Output per test: build/<test>.elf, .bin, .hex (load with +BOOT_HEX=...), .dis

CROSS   ?= riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
PYTHON  ?= python3

# Simulation uses a small baud divisor so the run is short.
# It MUST match UART_DIV in tb/soc/tb_soc.sv.
SIM_UART_DIV ?= 63

# Newer GCC needs _zicsr for CSR instructions; older GCC rejects it. Pick automatically.
MARCH   ?= $(shell $(CC) -march=rv32imc_zicsr -mabi=ilp32 -E -x c /dev/null >/dev/null 2>&1 && echo rv32imc_zicsr || echo rv32imc)

CFLAGS   = -march=$(MARCH) -mabi=ilp32 -Os -g -ffreestanding -fno-builtin \
           -nostdlib -nostartfiles -Wall -Wextra -Icommon
ifeq ($(SIM),1)
CFLAGS  += -DUART_DIV_VALUE=$(SIM_UART_DIV)u
endif
LDFLAGS  = -T common/link.ld -Wl,--gc-sections -Wl,--no-warn-rwx-segments

COMMON   = common/crt0.S common/uart.c
TESTS   ?= $(basename $(notdir $(wildcard tests/*.c)))
TEST    ?=

ifneq ($(TEST),)
TESTS := $(TEST)
endif

all: $(addprefix build/,$(addsuffix .hex,$(TESTS)))

build/%.elf: tests/%.c $(COMMON) common/soc.h common/uart.h common/link.ld
	@mkdir -p build
	$(CC) $(CFLAGS) $(LDFLAGS) $(COMMON) $< -o $@
	$(OBJDUMP) -d $@ > build/$*.dis

build/%.bin: build/%.elf
	$(OBJCOPY) -O binary $< $@

build/%.hex: build/%.bin
	$(PYTHON) common/bin2hex.py $< $@

clean:
	rm -rf build

.PHONY: all clean
.PRECIOUS: build/%.elf build/%.bin
