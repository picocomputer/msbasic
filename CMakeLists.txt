cmake_minimum_required(VERSION 3.20)

project(MSBASIC-RP6502 ASM)

add_subdirectory(tools)

add_executable(basic)

# Standalone CHRGET routine, packaged as a numeric-address asset that
# the OS loads to $0000 (the ZPCHRGET-segment slot reserved in
# src/rp6502.cfg / src/zeropage.s) at boot — no cold-boot copy needed.
add_executable(chrget src/chrget.s)
add_dependencies(basic chrget)
target_link_options(chrget PRIVATE
    -C ${CMAKE_CURRENT_SOURCE_DIR}/src/chrget.cfg
)
set_target_properties(chrget PROPERTIES
    LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/chrget.cfg
)

rp6502_asset(basic help src/help.txt)
rp6502_asset(basic 0x0000 ${CMAKE_CURRENT_BINARY_DIR}/chrget)
rp6502_executable(basic DATA 0xC000 RESET 0xC000)

target_link_options(basic PRIVATE
    -C ${CMAKE_CURRENT_SOURCE_DIR}/src/msbasic.cfg
)

set_target_properties(basic PROPERTIES
    LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/msbasic.cfg
)

target_include_directories(basic PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src/mist64
)

target_sources(basic PRIVATE
    src/msbasic.s
)
