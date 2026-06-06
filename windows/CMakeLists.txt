cmake_minimum_required(VERSION 3.25)
project(Anime4KUpscaler VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Enable Qt automatic generation tools
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Find Qt6 components
find_package(Qt6 REQUIRED COMPONENTS Widgets Core Gui Svg)

# Gather source and header files
set(SOURCES
    src/main.cpp
    
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
    
    src/viewmodels/AppViewModel.h
    src/viewmodels/AppViewModel.cpp
    src/viewmodels/ProcessingEngine.h
    src/viewmodels/ProcessingEngine.cpp
    src/viewmodels/CompressViewModel.h
    src/viewmodels/CompressViewModel.cpp
    src/viewmodels/StreamOptimizeViewModel.h
    src/viewmodels/StreamOptimizeViewModel.cpp
    
    src/ui/StyleSheet.h
    src/ui/MainWindow.h
    src/ui/MainWindow.cpp
    src/ui/UpscaleTab.h
    src/ui/UpscaleTab.cpp
    src/ui/FileListPanel.h
    src/ui/FileListPanel.cpp
    src/ui/EmptyStateWidget.h
    src/ui/EmptyStateWidget.cpp
    src/ui/ConfigurationPanel.h
    src/ui/ConfigurationPanel.cpp
    src/ui/ModePickerWidget.h
    src/ui/ModePickerWidget.cpp
    src/ui/ProcessingPanel.h
    src/ui/ProcessingPanel.cpp
    src/ui/ProgressRowWidget.h
    src/ui/ProgressRowWidget.cpp
    src/ui/CompressTab.h
    src/ui/CompressTab.cpp
    src/ui/StreamOptimizeTab.h
    src/ui/StreamOptimizeTab.cpp
    src/ui/QualityTuneTab.h
    src/ui/QualityTuneTab.cpp
)

set(RESOURCES
    resources/resources.qrc
)
if(WIN32)
    list(APPEND RESOURCES resources/app.rc)
endif()

# Main Executable target
qt_add_executable(Anime4KUpscaler
    WIN32
    MANUAL_FINALIZATION
    ${SOURCES}
    ${RESOURCES}
)

# Target Link Libraries
target_link_libraries(Anime4KUpscaler PRIVATE
    Qt6::Widgets
    Qt6::Core
    Qt6::Gui
    Qt6::Svg
)

# DXGI for GPU enumeration on Windows
if(WIN32)
    target_link_libraries(Anime4KUpscaler PRIVATE dxgi)
endif()

# Platform specific configurations
if(MSVC)
    target_compile_options(Anime4KUpscaler PRIVATE /W4 /WX- /utf-8)
    # Enable multi-processor compilation
    target_compile_options(Anime4KUpscaler PRIVATE /MP)
endif()

qt_finalize_executable(Anime4KUpscaler)

# Installation/Deployment settings
install(TARGETS Anime4KUpscaler RUNTIME DESTINATION .)

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/vendor/x64/ffmpeg.exe" DESTINATION .)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/vendor/x64/ffprobe.exe" DESTINATION .)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/vendor/x64/realesrgan-ncnn-vulkan.exe" DESTINATION .)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/vendor/x64/models" DESTINATION .)
else()
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/vendor/arm64/ffmpeg.exe" DESTINATION .)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/vendor/arm64/ffprobe.exe" DESTINATION .)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/vendor/arm64/realesrgan-ncnn-vulkan.exe" DESTINATION .)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/vendor/arm64/models" DESTINATION .)
endif()

# Helper message to remind compiling architecture
message(STATUS "Configuring Anime4KUpscaler for Windows target (CMake)")
