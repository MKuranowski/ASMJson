#!/bin/sh
set -ex
./test
valgrind --tool=memcheck --leak-check=full ./test
