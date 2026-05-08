cmake_minimum_required(VERSION 3.20)

project(MSBASIC-RP6502 ASM)

add_subdirectory(tools)

add_executable(basic)
add_executable(basic1)

# Code fragment to take advantage of RP6502 asset loaded.
# CHRGET loaded into zp $E8-FF followed by run-once cold boot
# logic loaded into bottom of stack.
add_dependencies(basic basic1)
target_link_options(basic1 PRIVATE
    -C ${CMAKE_CURRENT_SOURCE_DIR}/src/msbasic1.cfg
)
set_target_properties(basic1 PROPERTIES
    LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/msbasic1.cfg
)
target_sources(basic1 PRIVATE
    src/chrget.s
)

# basic.rp6502
rp6502_asset(basic help src/help.txt)
rp6502_asset(basic 0x00E8 ${CMAKE_CURRENT_BINARY_DIR}/basic1)
rp6502_executable(basic DATA 0xC000 RESET 0xC000)
target_link_options(basic PRIVATE
    -C ${CMAKE_CURRENT_SOURCE_DIR}/src/msbasic0.cfg
)
set_target_properties(basic PROPERTIES
    LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/msbasic0.cfg
)
target_sources(basic PRIVATE
    src/msbasic.s
)
