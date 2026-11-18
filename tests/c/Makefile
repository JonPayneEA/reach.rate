# Builds and runs the standalone C tests for the evaluation kernel.
# Strict flags on purpose: the core must stay portable C99.
CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra -Wpedantic -Werror -O2

test_core: test_core.c ../../src/reach_core.c ../../src/reach_core.h
	$(CC) $(CFLAGS) -o $@ test_core.c ../../src/reach_core.c -lm

.PHONY: check clean
check: test_core
	./test_core

clean:
	rm -f test_core
