#!/bin/sh
set -ex
./build_library.sh
cc -Wall -Wextra -Werror -g json.o test.c -o test
