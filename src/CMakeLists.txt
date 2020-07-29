set(BIN_NAME cmake_parser)

find_package(BISON REQUIRED)
find_package(FLEX REQUIRED)

BISON_TARGET(parser parser.y 
    ${CMAKE_CURRENT_BINARY_DIR}/parser.cpp
    DEFINES_FILE ${CMAKE_CURRENT_BINARY_DIR}/parser.h)

FLEX_TARGET(
    scanner scanner.l ${CMAKE_CURRENT_BINARY_DIR}/scanner.cpp
    DEFINES_FILE ${CMAKE_CURRENT_BINARY_DIR}/scanner.h)

ADD_FLEX_BISON_DEPENDENCY(scanner parser)

add_executable(${BIN_NAME})

target_sources(${BIN_NAME}
    PRIVATE
    main.cpp
    ${BISON_parser_OUTPUTS}
    ${FLEX_scanner_OUTPUTS})

target_include_directories(${BIN_NAME} PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
)