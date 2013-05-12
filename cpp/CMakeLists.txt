CMAKE_MINIMUM_REQUIRED(VERSION 2.6.0)
PROJECT(polyclipping)

SET(CMAKE_BUILD_TYPE "Release" CACHE STRING "Release type")
SET(CMAKE_INSTALL_LIBDIR lib${LIB_SUFFIX})

SET(BUILD_SHARED_LIBS ON CACHE BOOL
    "Build shared libraries (.dll/.so) instead of static ones (.lib/.a)")
ADD_LIBRARY(polyclipping clipper.cpp)

# The header name clipper.hpp is too generic, so install in a subdirectory
INSTALL (FILES clipper.hpp DESTINATION include/polyclipping)
INSTALL (TARGETS polyclipping LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})

SET_TARGET_PROPERTIES(polyclipping PROPERTIES VERSION 10.0.0 SOVERSION 10 )