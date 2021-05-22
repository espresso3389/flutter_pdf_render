cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "pdf_render")
project(${PROJECT_NAME} LANGUAGES CXX)

include(ExternalProject)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "pdf_render_plugin")

add_library(${PLUGIN_NAME} SHARED
  "pdf_render_plugin.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

ExternalProject_Add(
  "sobar-win-x64"
  PREFIX "sobar"
  URL https://github.com/espresso3389/sobar_pdf/releases/download/r14/sobar-windows-x64-r14-4947e8.zip
  URL_HASH SHA512=d13ebef178bb8ff455ec375bf7e9f74863d0fbc77eee7b12b4b8004ae3cef11ba4ce9eda94e2d88c859457dfb0085d15b809d4fcfb93fefd63159c44d1de9956
  CONFIGURE_COMMAND ""
  BUILD_COMMAND ""
  INSTALL_COMMAND ""
)

# List of absolute paths to libraries that should be bundled with the plugin
set(pdf_render_bundled_libraries
  "${CMAKE_CURRENT_BINARY_DIR}/sobar/src/sobar-win-x64/lib/windows/x64/sobar.dll"
  PARENT_SCOPE
)
