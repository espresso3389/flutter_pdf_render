cmake_minimum_required(VERSION 3.4.1)

add_library(bbhelper SHARED c++/directBufferAndroid.cpp)

target_compile_options(bbhelper PRIVATE -DBUILD_FOR_ANDROID)
