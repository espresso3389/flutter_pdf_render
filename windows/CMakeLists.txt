cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "pdf_render")
project(${PROJECT_NAME} LANGUAGES CXX)

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

# sobar; PDF renderer library
if(CMAKE_SIZEOF_VOID_P STREQUAL 8)
  set(sobar_arch "x64")
else()
  set(sobar_arch "x86")
endif()
add_library(sobar STATIC IMPORTED)
set(sobar_libdir "${CMAKE_CURRENT_SOURCE_DIR}/sobar/lib/windows/${sobar_arch}")
set_target_properties(sobar PROPERTIES IMPORTED_LOCATION "${sobar_libdir}/sobar.lib")
set_target_properties(sobar PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/sobar/include")

#
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin sobar)

# List of absolute paths to libraries that should be bundled with the plugin
set(pdf_render_bundled_libraries
  "${sobar_libdir}/sobar.dll"
  PARENT_SCOPE
)
