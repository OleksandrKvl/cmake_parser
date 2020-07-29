include_guard(GLOBAL)

# sets required standard without extensions
macro(set_language_standard language standard)
    set(CMAKE_${language}_STANDARD ${standard})
    set(CMAKE_${language}_STANDARD_REQUIRED YES)
    set(CMAKE_${language}_EXTENSIONS NO)
endmacro()

# disallows build in source directory
function(in_source_build_guard)
    if(${CMAKE_SOURCE_DIR} STREQUAL ${CMAKE_BINARY_DIR})
        message(FATAL_ERROR "In-source builds are not allowed.")
    endif()
endfunction()

# sets build type that is used in absence of CMAKE_BUILD_TYPE
# has no effect on multi-configuration generators
macro(set_default_build_type type)
    if(NOT CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE ${type})
    endif()
endmacro()
