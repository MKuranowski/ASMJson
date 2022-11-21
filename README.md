asmjson
=======

JSON parser written in assembly (x86-64 nasm to be specific).

See the C header for program signature. In general `json_parse` is used to parse JSON data,
and after the end of processing `json_dealloc` is used to free memory allocated
for strings, arrays and objects.


Limitations
-----------

- Unicode escape sequences in strings (`\uHHHH`) are not supported (TODO: add support for those)
- Only numbers up to 255 digits are supported
- Only numbers understood by `strtol` or `strtod` can be correctly parsed
- JSON data must be provided as a `FILE*`. POSIX [fmemopen](https://manpages.debian.org/stable/manpages-dev/fmemopen.3.en.html)
    can be used for parsing strings.

Otherwise, asmjson should be able to parse any valid JSON file.


Tests
-----

```console
$ ./build_tests.sh
$ ./run_tests.sh
```

Tests are run on their own first, to see if everything works correctly.
Afterwards, they are run again with valgrind to check for any memory leaks.


License
-------

[MIT](LICENSE)
