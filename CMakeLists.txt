cmake_minimum_required(VERSION 3.20)

# kit.env is the single source of truth for names and ids (the shell scripts source the same file).
file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/kit.env KIT_LINES REGEX "^[A-Z_]+=")
foreach(line IN LISTS KIT_LINES)
    string(REGEX MATCH "^([A-Z_]+)=\"?([^\"]*)\"?$" _ "${line}")
    set(${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
endforeach()
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/VERSION APP_VERSION)
string(STRIP "${APP_VERSION}" APP_VERSION)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS kit.env VERSION)

project(${APP_SLUG} VERSION ${APP_VERSION} LANGUAGES C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

include(FetchContent)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
if(EMSCRIPTEN)  # scripts/build-web.sh
    set(PLATFORM Web CACHE STRING "" FORCE)
    set(GRAPHICS GRAPHICS_API_OPENGL_ES3 CACHE STRING "" FORCE)  # WebGL 2
endif()
FetchContent_Declare(raylib
    GIT_REPOSITORY https://github.com/raysan5/raylib.git
    GIT_TAG ${RAYLIB_TAG}
    GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(raylib)

file(GLOB SOURCES CONFIGURE_DEPENDS src/*.c)
add_executable(game ${SOURCES})
set_target_properties(game PROPERTIES OUTPUT_NAME "${APP_SLUG}")
target_link_libraries(game PRIVATE raylib)
target_compile_options(game PRIVATE -Wall -Wextra -Wno-unused-parameter)
target_compile_definitions(game PRIVATE KIT_APP_NAME="${APP_NAME}" KIT_VERSION="${APP_VERSION}")
if(NOT WIN32)
    target_link_libraries(game PRIVATE m)
endif()

if(WIN32)  # cross-compiled with mingw-w64: scripts/build-windows.sh
    string(REPLACE "." "," APP_VERSION_COMMA "${APP_VERSION},0")
    file(WRITE ${CMAKE_BINARY_DIR}/version.h
        "#define APP_NAME_STR \"${APP_NAME}\"\n#define APP_EXE_STR \"${APP_SLUG}.exe\"\n#define APP_VERSION_STR \"${APP_VERSION}\"\n#define APP_VERSION_COMMA ${APP_VERSION_COMMA}\n")
    enable_language(RC)
    target_sources(game PRIVATE windows/app.rc)
    set_source_files_properties(windows/app.rc PROPERTIES
        INCLUDE_DIRECTORIES "${CMAKE_BINARY_DIR};${CMAKE_SOURCE_DIR}/windows"
        OBJECT_DEPENDS "${CMAKE_BINARY_DIR}/version.h;${CMAKE_SOURCE_DIR}/windows/app.manifest;${CMAKE_SOURCE_DIR}/windows/icon.ico")
    # One self-contained .exe: no mingw runtime DLLs to ship. -mwindows: no console window.
    target_link_options(game PRIVATE -static -mwindows)
endif()

if(EMSCRIPTEN)  # index.{html,js,wasm,data}
    set_target_properties(game PROPERTIES OUTPUT_NAME "index" SUFFIX ".html"
        LINK_DEPENDS "${CMAKE_SOURCE_DIR}/web/shell.html")
    file(GLOB_RECURSE ASSET_FILES CONFIGURE_DEPENDS assets/*)
    set_property(TARGET game APPEND PROPERTY LINK_DEPENDS ${ASSET_FILES})
    target_link_options(game PRIVATE
        -sUSE_GLFW=3 -sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2
        -sALLOW_MEMORY_GROWTH=1 -sFORCE_FILESYSTEM=1 -lidbfs.js
        "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/assets@assets"
        "SHELL:--shell-file ${CMAKE_SOURCE_DIR}/web/shell.html")
endif()
