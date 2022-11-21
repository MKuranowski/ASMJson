// asmjson
//
// Copyright 2022 Mikolaj Kuranowski
// SPDX-License-Identifier: MIT

#pragma once

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define JSON_ERR_UNEXPECTED_CHAR -1
#define JSON_ERR_NUMBER_TOO_LONG -2
#define JSON_ERR_INVALID_NUMBER -3
#define JSON_ERR_INVALID_STRING -4

enum json_value_kind {
    JSON_NULL,
    JSON_BOOL,
    JSON_INTEGER,
    JSON_DOUBLE,
    JSON_STRING,
    JSON_ARRAY,
    JSON_OBJECT,
};

struct json_value;
struct json_object_entry;

struct json_array {
    struct json_value* arr;
    size_t len;
};

struct json_object {
    struct json_object_entry* arr;
    size_t len;
};

struct json_value {
    enum json_value_kind kind;
    union {
        bool as_bool;
        long as_int;
        double as_double;
        char* as_string;
        struct json_array as_array;
        struct json_object as_object;
    };
};

struct json_object_entry {
    struct json_value value;
    char* key;
};

int json_parse(FILE*, struct json_value*);
void json_dealloc(struct json_value*);


// Calculation of offsets for the assembly implementation
static_assert(sizeof(void*) == 8, "sizeof(void*)");
static_assert(sizeof(long) == 8, "sizeof(long)");
static_assert(sizeof(size_t) == 8, "sizeof(size_t)");
static_assert(sizeof(double) == 8, "sizeof(double)");
static_assert(sizeof(bool) == 1, "sizeof(bool)");
static_assert(sizeof(enum json_value_kind) == 4, "sizeof(enum)");

static_assert(sizeof(struct json_array) == 16, "sizeof(json_array)");
static_assert(offsetof(struct json_array, arr) == 0, "offsetof(json_array, arr)");
static_assert(offsetof(struct json_array, len) == 8, "offsetof(json_array, len)");

static_assert(sizeof(struct json_object) == 16, "sizeof(json_object)");
static_assert(offsetof(struct json_object, arr) == 0, "offsetof(json_object, arr)");
static_assert(offsetof(struct json_object, len) == 8, "offsetof(json_object, len)");

static_assert(sizeof(struct json_value) == 24, "sizeof(json_value)");
static_assert(offsetof(struct json_value, kind) == 0, "offsetof(json_value, kind)");
static_assert(offsetof(struct json_value, as_bool) == 8, "offsetof(json_value, as_bool)");
static_assert(offsetof(struct json_value, as_int) == 8, "offsetof(json_value, as_int)");
static_assert(offsetof(struct json_value, as_double) == 8, "offsetof(json_value, as_double)");
static_assert(offsetof(struct json_value, as_string) == 8, "offsetof(json_value, as_string)");
static_assert(offsetof(struct json_value, as_array) == 8, "offsetof(json_value, as_array)");
static_assert(offsetof(struct json_value, as_object) == 8, "offsetof(json_value, as_object)");

static_assert(sizeof(struct json_object_entry) == 32, "sizeof(json_object_entry)");
static_assert(offsetof(struct json_object_entry, value) == 0, "offsetof(json_object_entry, value)");
static_assert(offsetof(struct json_object_entry, key) == 24, "offsetof(json_object_entry, key)");
