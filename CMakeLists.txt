cmake_minimum_required(VERSION 3.20)

project(MSBASIC-RP6502 ASM)

add_subdirectory(tools)

add_executable(basic)
target_link_options(basic PRIVATE
    -C ${CMAKE_CURRENT_SOURCE_DIR}/src/msbasic.cfg
)
set_target_properties(basic PROPERTIES
    LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/msbasic.cfg
)
target_sources(basic PRIVATE
    src/msbasic.s
)
rp6502_byproducts(basic
    ${CMAKE_CURRENT_BINARY_DIR}/basic.00E8
    ${CMAKE_CURRENT_BINARY_DIR}/basic.1000
    ${CMAKE_CURRENT_BINARY_DIR}/basic.C000
)
rp6502_asset(basic help src/help.txt)
rp6502_asset(basic 0x00E8 ${CMAKE_CURRENT_BINARY_DIR}/basic.00E8)
rp6502_asset(basic 0x1000 ${CMAKE_CURRENT_BINARY_DIR}/basic.1000)
rp6502_asset(basic 0xC000 ${CMAKE_CURRENT_BINARY_DIR}/basic.C000)
rp6502_executable(basic RESET 0x1000)
