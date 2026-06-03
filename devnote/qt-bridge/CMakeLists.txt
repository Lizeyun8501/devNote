cmake_minimum_required(VERSION 3.16)
project(devnote_qt_bridge VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Try Qt6 first, fallback to Qt5
find_package(Qt6 COMPONENTS Widgets Core Gui QUIET)
if(NOT Qt6_FOUND)
    find_package(Qt5 5.15 REQUIRED COMPONENTS Widgets Core Gui)
    set(QT_LIBS Qt5::Widgets Qt5::Core Qt5::Gui)
    message(STATUS "Using Qt5")
else()
    set(QT_LIBS Qt6::Widgets Qt6::Core Qt6::Gui)
    message(STATUS "Using Qt6")
endif()

set(HEADERS
    include/devnote_qt_bridge.h
)

set(SOURCES
    src/qt_bridge.cpp
)

add_library(devnote_qt_bridge SHARED ${SOURCES} ${HEADERS})

target_include_directories(devnote_qt_bridge PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_link_libraries(devnote_qt_bridge PUBLIC ${QT_LIBS})

# Platform-specific settings
if(WIN32)
    set_target_properties(devnote_qt_bridge PROPERTIES
        PREFIX ""
        SUFFIX ".dll"
    )
elseif(APPLE)
    set_target_properties(devnote_qt_bridge PROPERTIES
        PREFIX "lib"
        SUFFIX ".dylib"
    )
else()
    set_target_properties(devnote_qt_bridge PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
    )
endif()

# Install rules
install(TARGETS devnote_qt_bridge
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)
install(FILES ${HEADERS} DESTINATION include/devnote_qt_bridge)