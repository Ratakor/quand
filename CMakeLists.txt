# cmake -B build && cmake --build build
cmake_minimum_required(VERSION 4.1)
project(quand VERSION 0.4.1)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED On)
# set(CMAKE_CXX_EXTENSIONS Off)

add_executable(${PROJECT_NAME}
               src/main.cpp
               src/utils.cpp
              )
target_compile_definitions(${PROJECT_NAME} PUBLIC VERSION="${CMAKE_PROJECT_VERSION}")
