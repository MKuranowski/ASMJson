#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "json.h"

char const* describe_json_err(int status) {
    switch (status) {
        case 0:
            return "JSON_SUCCESS";
        case -1:
            return "JSON_ERR_UNEXPECTED_CHAR";
        case -2:
            return "JSON_ERR_NUMBER_TOO_LONG";
        case -3:
            return "JSON_ERR_INVALID_NUMBER";
        case -4:
            return "JSON_ERR_INVALID_STRING";
        default:
            return "JSON_ERR_UNKNOWN";
    }
}

#define DECLARE_JSON_TEST(number, name, expected_kind, failed_v_check)                          \
    void name() {                                                                               \
        struct json_value v;                                                                    \
        FILE* f = fopen("test_fixtures/" #name ".json", "r");                                   \
        int status;                                                                             \
                                                                                                \
        if (!f) {                                                                               \
            printf("not ok " #number " - " #name "\n  ---\n  failed: fopen (%m)\n  ...\n");     \
            return;                                                                             \
        }                                                                                       \
                                                                                                \
        if ((status = json_parse(f, &v))) {                                                     \
            printf("not ok " #number " - " #name "\n  ---\n  failed: json_parse (%s)\n  ...\n", \
                   describe_json_err(status));                                                  \
            fclose(f);                                                                          \
            return;                                                                             \
        }                                                                                       \
                                                                                                \
        if (v.kind != expected_kind) {                                                          \
            printf("not ok " #number " - " #name "\n  ---\n  failed: v.kind != " #expected_kind \
                   "\n  ...\n");                                                                \
            fclose(f);                                                                          \
            return;                                                                             \
        }                                                                                       \
                                                                                                \
        if (failed_v_check) {                                                                   \
            printf("not ok " #number " - " #name "\n  ---\n  failed: " #failed_v_check          \
                   "\n  ...\n");                                                                \
            json_dealloc(&v);                                                                   \
            fclose(f);                                                                          \
            return;                                                                             \
        }                                                                                       \
                                                                                                \
        fclose(f);                                                                              \
        json_dealloc(&v);                                                                       \
        printf("ok " #number " - " #name "\n");                                                 \
        return;                                                                                 \
    }

#define DECLARE_JSON_ERROR_TEST(number, name, expected_err)                                 \
    void name() {                                                                           \
        struct json_value v;                                                                \
        FILE* f = fopen("test_fixtures/" #name ".json", "r");                               \
        int status;                                                                         \
                                                                                            \
        if (!f) {                                                                           \
            printf("not ok " #number " - " #name "\n  ---\n  failed: fopen (%m)\n  ...\n"); \
            return;                                                                         \
        }                                                                                   \
                                                                                            \
        if ((status = json_parse(f, &v)) != expected_err) {                                 \
            printf("not ok " #number " - " #name                                            \
                   "\n  ---\n  failed: json_parse (%s), expected %s\n  ...\n",              \
                   describe_json_err(status), describe_json_err(expected_err));             \
            if (status == 0) json_dealloc(&v);                                              \
            fclose(f);                                                                      \
            return;                                                                         \
        }                                                                                   \
                                                                                            \
        fclose(f);                                                                          \
        printf("ok " #number " - " #name "\n");                                             \
        return;                                                                             \
    }

#define check(expr) \
    if (!(expr)) return true

bool array_simple_incorrect(struct json_value* v) {
    check(v->as_array.len == 4L);

    check(v->as_array.arr[0].kind == JSON_STRING);
    check(strcmp(v->as_array.arr[0].as_string, "foo") == 0);

    check(v->as_array.arr[1].kind == JSON_STRING);
    check(strcmp(v->as_array.arr[1].as_string, "bar") == 0);

    check(v->as_array.arr[2].kind == JSON_INTEGER);
    check(v->as_array.arr[2].as_int == 803L);

    check(v->as_array.arr[3].kind == JSON_NULL);
    return false;
}

bool object_simple_incorrect(struct json_value* v) {
    check(v->as_object.len == 3L);

    // Keys
    check(strcmp(v->as_object.arr[0].key, "foo") == 0);
    check(strcmp(v->as_object.arr[1].key, "bar") == 0);
    check(strcmp(v->as_object.arr[2].key, "baz") == 0);

    // Values
    check(v->as_object.arr[0].value.kind == JSON_INTEGER);
    check(v->as_object.arr[0].value.as_int == 1);

    check(v->as_object.arr[1].value.kind == JSON_STRING);
    check(strcmp(v->as_object.arr[1].value.as_string, "spam") == 0);

    check(v->as_object.arr[2].value.kind == JSON_NULL);

    return false;
}

bool complex_incorrect(struct json_value* v) {
    // Check the top level object
    check(v->kind == JSON_OBJECT);
    check(v->as_object.len == 2L);
    struct json_object_entry* arr = v->as_object.arr;

    // Check the "status" key
    check(strcmp(arr[0].key, "status") == 0);
    check(arr[0].value.kind == JSON_STRING);
    check(strcmp(arr[0].value.as_string, "ok") == 0);

    // Check the "stops" key
    check(strcmp(arr[1].key, "stops") == 0);
    check(arr[1].value.kind == JSON_ARRAY);
    check(arr[1].value.as_array.len == 3);
    struct json_value* stops = arr[1].value.as_array.arr;

    // Verify every stop
    for (register size_t i = 0; i < 3; ++i) {
        // Check that the stop was parsed correctly
        check(stops[i].kind == JSON_OBJECT);
        check(stops[i].as_object.len == 3L);
        struct json_object_entry* stop = stops[i].as_object.arr;

        // Verify the ID
        check(strcmp(stop[0].key, "id") == 0);
        check(stop[0].value.kind == JSON_INTEGER);
        check(stop[0].value.as_int == (int64_t)i);

        // Verify the code
        check(strcmp(stop[1].key, "code") == 0);
        if (i == 0) {
            check(stop[1].value.kind == JSON_NULL);
        } else {
            check(stop[1].value.kind == JSON_STRING);
            check(strcmp(stop[1].value.as_string, (i == 1 ? "B" : "C")) == 0);
        }

        // Verify the position
        check(strcmp(stop[2].key, "position") == 0);
        check(stop[2].value.kind == JSON_OBJECT);
        check(stop[2].value.as_object.len == 2L);
        struct json_object_entry* position = stop[2].value.as_object.arr;

        // Verify latitude
        check(strcmp(position[0].key, "lat") == 0);
        check(position[0].value.kind == JSON_DOUBLE);
        check(position[0].value.as_double == 1.0);

        // Verify longitude
        check(strcmp(position[1].key, "lon") == 0);
        check(position[1].value.kind == JSON_DOUBLE);
        check(position[1].value.as_double == 1.0);
    }

    return false;
}

DECLARE_JSON_TEST(1, literals_null, JSON_NULL, false)
DECLARE_JSON_TEST(2, literals_true, JSON_BOOL, v.as_bool != true)
DECLARE_JSON_TEST(3, literals_false, JSON_BOOL, v.as_bool != false)

DECLARE_JSON_TEST(4, numbers_exp, JSON_DOUBLE, v.as_double != 0.5)
DECLARE_JSON_TEST(5, numbers_frac_exp, JSON_DOUBLE, v.as_double != 1.0)
DECLARE_JSON_TEST(6, numbers_fraction, JSON_DOUBLE, v.as_double != 69.420)
DECLARE_JSON_TEST(7, numbers_int, JSON_INTEGER, v.as_int != 420L)
DECLARE_JSON_TEST(8, numbers_zero, JSON_INTEGER, v.as_int != 0L)
DECLARE_JSON_TEST(9, numbers_zero_double, JSON_DOUBLE, v.as_double != 0.0)

DECLARE_JSON_TEST(10, strings_empty, JSON_STRING, strcmp(v.as_string, ""))
DECLARE_JSON_TEST(11, strings_simple, JSON_STRING, strcmp(v.as_string, "foo bar baz"))
DECLARE_JSON_TEST(12, strings_escapes, JSON_STRING, strcmp(v.as_string, "\"\\/\b\f\n\r\t"))

DECLARE_JSON_TEST(13, array_empty, JSON_ARRAY, v.as_array.len != 0L)
DECLARE_JSON_TEST(14, array_simple, JSON_ARRAY, array_simple_incorrect(&v))

DECLARE_JSON_TEST(15, object_empty, JSON_OBJECT, v.as_object.len != 0L)
DECLARE_JSON_TEST(16, object_simple, JSON_OBJECT, object_simple_incorrect(&v))

DECLARE_JSON_TEST(17, complex, JSON_OBJECT, complex_incorrect(&v))

DECLARE_JSON_ERROR_TEST(18, strings_no_leak, JSON_ERR_UNEXPECTED_CHAR)
DECLARE_JSON_ERROR_TEST(19, array_no_leak, JSON_ERR_UNEXPECTED_CHAR)
DECLARE_JSON_ERROR_TEST(20, object_no_leak1, JSON_ERR_UNEXPECTED_CHAR)
DECLARE_JSON_ERROR_TEST(21, object_no_leak2, JSON_ERR_UNEXPECTED_CHAR)

int main() {
    printf("TAP version 14\n1..21 # json\n");
    literals_null();
    literals_true();
    literals_false();

    numbers_exp();
    numbers_frac_exp();
    numbers_fraction();
    numbers_int();
    numbers_zero();
    numbers_zero_double();

    strings_empty();
    strings_simple();
    strings_escapes();

    array_empty();
    array_simple();

    object_empty();
    object_simple();

    complex();

    strings_no_leak();
    array_no_leak();
    object_no_leak1();
    object_no_leak2();
}
