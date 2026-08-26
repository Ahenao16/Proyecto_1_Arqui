cmake_minimum_required(VERSION 4.2)

project(driver C ASM_NASM)

set(CMAKE_C_STANDARD 11)

add_executable(driver
        main.c
        kernel_avx2.asm
)

target_compile_options(driver PRIVATE
        $<$<COMPILE_LANGUAGE:C>:-mavx2>
)
