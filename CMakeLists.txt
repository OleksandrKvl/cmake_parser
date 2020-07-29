cmake_minimum_required(VERSION 3.11)

project(cmake_parser
    VERSION 1.0
    LANGUAGES CXX
)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}/cmake)
include(utils)

in_source_build_guard()
set_language_standard(CXX 17)
set_default_build_type(Debug)

add_subdirectory(src)
