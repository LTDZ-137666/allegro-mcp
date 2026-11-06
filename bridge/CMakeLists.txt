cmake_minimum_required(VERSION 3.15)
project(allegro_ai_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# Cadence Plugin API header (axlplugin.h)
#
# axlplugin.h is (c) Cadence Design Systems and is NOT distributed with this
# repository. Point CADENCE_INCLUDE_DIR at the header directory shipped with
# your own Cadence installation, e.g.
#
#   cmake .. -DCADENCE_INCLUDE_DIR="C:/Cadence/SPB_17.4/tools/dfII/include"
#            -G "Visual Studio 17 2022" -A Win32
#
# Allegro's plugin host is 32-bit, so -A Win32 is normally required.
# ---------------------------------------------------------------------------
if(NOT CADENCE_INCLUDE_DIR)
    message(FATAL_ERROR
        "CADENCE_INCLUDE_DIR is required.
"
        "axlplugin.h belongs to Cadence and cannot be redistributed.
"
        "Pass -DCADENCE_INCLUDE_DIR=<Cadence>/tools/dfII/include")
endif()

if(NOT EXISTS "${CADENCE_INCLUDE_DIR}/axlplugin.h")
    message(FATAL_ERROR "axlplugin.h not found under ${CADENCE_INCLUDE_DIR}")
endif()

add_library(allegro_ai_bridge SHARED
    src/allegro_ai_bridge.cpp
    src/tcp_server.cpp
    src/command_queue.cpp
)

target_include_directories(allegro_ai_bridge PRIVATE
    include
    ${CADENCE_INCLUDE_DIR}
)

if(WIN32)
    target_compile_definitions(allegro_ai_bridge PRIVATE _WINDOWS)
    target_link_libraries(allegro_ai_bridge ws2_32)
    set_target_properties(allegro_ai_bridge PROPERTIES
        PREFIX ""
        SUFFIX ".dll"
    )
elseif(UNIX)
    target_compile_options(allegro_ai_bridge PRIVATE -fPIC)
    set_target_properties(allegro_ai_bridge PROPERTIES
        PREFIX ""
        SUFFIX ".so"
    )
    target_link_libraries(allegro_ai_bridge pthread)
endif()
