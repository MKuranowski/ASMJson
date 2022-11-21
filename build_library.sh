#!/bin/sh
set -ex
nasm -f elf64 -g -o json.o json.s
