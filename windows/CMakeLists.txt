cmake_minimum_required(VERSION 3.25)
project(Anime4KUpscaler VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Enable Qt automatic generation tools
set(CMAKE_AUTOMOC ON)
# AUTORCC/AUTOUIC not needed — no .qrc or .ui files in a4k_core

# Find Qt6 components
find_package(Qt6 REQUIRED COMPONENTS Core)

# Gather source and header files
set(SOURCES
    src/models/Models.h
    src/models/Models.cpp
    src/models/CompressModels.h
    src/models/CompressModels.cpp
    src/models/StreamOptimizeModels.h
    src/models/StreamOptimizeModels.cpp

    src/utils/HardwareDetector.h
    src/utils/HardwareDetector.cpp
    src/utils/FFmpegLocator.h
    src/utils/FFmpegLocator.cpp
    src/utils/DurationProbe.h
    src/utils/DurationProbe.cpp
    src/utils/SleepPreventer.h
    src/utils/SleepPreventer.cpp

    src/viewmodels/IPickerService.h
    src/viewmodels/AppViewModel.h
    src/viewmodels/AppViewModel.cpp
    src/viewmodels/ProcessingEngine.h
    src/viewmodels/ProcessingEngine.cpp
    src/viewmodels/CompressViewModel.h
    src/viewmodels/CompressViewModel.cpp
    src/viewmodels/StreamOptimizeViewModel.h
    src/viewmodels/StreamOptimizeViewModel.cpp
)

# a4k_core static library — Qt Core only backend
add_library(a4k_core STATIC ${SOURCES})

target_link_libraries(a4k_core PUBLIC Qt6::Core)

if(WIN32)
    target_link_libraries(a4k_core PUBLIC dxgi)
endif()

if(MSVC)
    target_compile_options(a4k_core PRIVATE /W4 /WX- /utf-8 /MP)
endif()

target_include_directories(a4k_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

# Vendored binaries installed by a4k_app MSBuild project, not here
message(STATUS "Configuring a4k_core static library for Windows target (CMake)")
