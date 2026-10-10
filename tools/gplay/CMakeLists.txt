cmake_minimum_required(VERSION 3.16)
project(bedrock-gplay CXX)

set(CMAKE_CXX_STANDARD 17)

set(GPLAY_API "${CMAKE_CURRENT_SOURCE_DIR}/../../deps/Google-Play-API")
add_subdirectory("${GPLAY_API}" gplayapi EXCLUDE_FROM_ALL)

add_executable(bedrock-gplay main.cpp "${GPLAY_API}/src/config.cpp")
target_include_directories(bedrock-gplay PRIVATE "${GPLAY_API}/src")
target_link_libraries(bedrock-gplay gplayapi)
