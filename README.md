# Flex & Bison based CMake language parser

## About

This is an experimental [CMake language](https://cmake.org/cmake/help/latest/manual/cmake-language.7.html#bracket-comment) parser that uses Flex & Bison. I used it as a playground for a `command reference` feature, i.e., using command's result as
an argument to another command:
```cmake
f(
    a
    ${g(b c)}
)
```

It takes input, parses it and prints back result in form of pseudo operations, for example:
```cmake
project(${project_name} LANGUAGES CXX)                 
```
translates into
```
[call(project, [get_normal_var(project_name)], LANGUAGES, CXX)]
```
Pseudo operations notation:
Operation name | CMake syntax | Pseudo operation
---------------|--------------|--------------
Command invocation | f(a) | [call(f, a)]
Normal variable reference | ${x} | [get_normal_var(x)]
Cache variable reference | $CACHE{x} | [get_cache_var(x)]
Environment variable reference | $ENV{x} | [get_env_var(x)]
Command reference | ${f(a)} | [result_of([call(f, a)])]

Arguments are represented as plain strings regardless of how their types:
```cmake
f(unquoted "quoted" [[bracket]])
-->
[call(f, unquoted, quoted, bracket)]

```
Comments are not included in the output.

## Usage

The most common use cases are:
- interactive(live) mode. Just run `cmake_parser` and type commands.
- input from file, `cmake_parser -if file_path`.
- evaluation after all input is parsed, `cmake_parser -ep`.
- disable evaluation, `cmake_parser -ed`.

Last two might be useful in file-mode to estimate parse speed or memory usage.
Keep in mind that current configuration is just proof-of-concept, it's not designed for the best performance, additional options should be added/removed for that. To get all options run `cmake_parser --help`.

## Build

```sh
mkdir build
cd build
cmake ..
cmake --build .
```
C++17 compiler is required. 
If Flex 2.6.4 and Bison 3.6.1 are found, they will be used to regenerate scanner/parser files. Otherwise pre-generated files are used. I'm using Ubuntu, actual 
scanner/parser generation hasn't been tested on Windows, only build using 
pre-generated files.

## Differences between this and CMake

My main source of CMake syntax knowledge was [this page](https://cmake.org/cmake/help/latest/manual/cmake-language.7.html#bracket-comment).
However, actual CMake implementation doesn't fully correspond to that BNF.
Thus, some inconsistencies are possible.