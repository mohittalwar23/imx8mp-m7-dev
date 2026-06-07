
# Copyright 2026 NXP
#
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 3.22.0)

cmake_path(APPEND conf_file_path ${CMAKE_CURRENT_LIST_DIR} ${board} prj.conf)
set(CONF_FILE ${conf_file_path} ${CONF_FILE})
include(${SdkRootDirPath}/cmake/extension/mcux.cmake)

project(evkmimx8mp_rpmsg_lite_str_echo_rtos_remote LANGUAGES C CXX ASM PROJECT_BOARD_PORT_PATH ${board_root}/${board}/multicore_examples/rpmsg_lite_str_echo_rtos/remote)

include(${SdkRootDirPath}/CMakeLists.txt)


include(${board}/board_files.cmake)

mcux_add_source(
    SOURCES evkmimx8mp/FreeRTOSConfigBoard.h
            evkmimx8mp/rsc_table.c
            evkmimx8mp/rsc_table.h
            evkmimx8mp/srtm_config.h
            remote/rpmsg_config.h
            remoteproc/remoteproc.h
            rpmsg_lite_str_echo_rtos/FreeRTOSConfig.h
)

mcux_add_include(
    INCLUDES evkmimx8mp
             remote
             remoteproc
             rpmsg_lite_str_echo_rtos
)
if(CONFIG_TOOLCHAIN STREQUAL "armgcc")
	set(__CONVERT_CUSTOM_COMMANDS
        COMMAND
        ${CMAKE_OBJCOPY} ${OBJDUMP_BIN_CMD} --remove-section=.stacktop_and_pc
        ${CMAKE_CURRENT_BINARY_DIR}/${MCUX_SDK_PROJECT_NAME}${CMAKE_EXECUTABLE_SUFFIX}
        ${OBJDUMP_OUT_CMD} ${MCUX_SDK_PROJECT_NAME}.bin
	CACHE STRING "CONVERT_CUSTOM_COMMANDS" FORCE)
endif()


mcux_add_source(
    SOURCES main.c
)

mcux_add_include(
    INCLUDES .
)
mcux_add_configuration(
    CC "-D__USE_SHMEM"
)

mcux_add_linker_symbol(
    SYMBOLS "__stack_size__=0x400 \
             __use_shmem__=1 \
             __multicore__=1 \
            "
)

mcux_add_mdk_configuration(
    LD "--library_type=standardlib"
)

mcux_convert_binary(BINARY ${APPLICATION_BINARY_DIR}/${MCUX_SDK_PROJECT_NAME}.bin)

