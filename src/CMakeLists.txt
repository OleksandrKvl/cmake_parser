set(BIN_NAME cmake_parser)

add_executable(${BIN_NAME})

find_package(BISON 3.6.1)
find_package(FLEX 2.6.4)

if(FLEX_FOUND AND BISON_FOUND)
    BISON_TARGET(parser parser.y 
        ${CMAKE_CURRENT_BINARY_DIR}/parser.cpp
        DEFINES_FILE ${CMAKE_CURRENT_BINARY_DIR}/parser.h)

    FLEX_TARGET(
        scanner scanner.l ${CMAKE_CURRENT_BINARY_DIR}/scanner.cpp
        DEFINES_FILE ${CMAKE_CURRENT_BINARY_DIR}/scanner.h)

    ADD_FLEX_BISON_DEPENDENCY(scanner parser)

    set(GENERATED_DIR ${CMAKE_CURRENT_BINARY_DIR})
else()
    set(GENERATED_DIR ${CMAKE_CURRENT_SOURCE_DIR}/pre_generated)
    set(BISON_parser_OUTPUTS ${GENERATED_DIR}/parser.cpp)
    set(FLEX_scanner_OUTPUTS ${GENERATED_DIR}/scanner.cpp)
endif()

target_sources(${BIN_NAME}
    PRIVATE
    main.cpp
    ${BISON_parser_OUTPUTS}
    ${FLEX_scanner_OUTPUTS})

target_include_directories(${BIN_NAME} PRIVATE
    ${GENERATED_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR})