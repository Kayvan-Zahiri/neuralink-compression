CC ?= cc
CFLAGS ?= -O2 -Wall
all: brainwire
brainwire: brainwire.c
	$(CC) $(CFLAGS) -o brainwire brainwire.c
clean:
	rm -f brainwire
.PHONY: all clean
