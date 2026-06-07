
# Copyright 2026 NXP
#
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 3.22.0)

cmake_path(APPEND conf_file_path ${CMAKE_CURRENT_LIST_DIR} ${board} prj.conf)
set(CONF_FILE ${conf_file_path} ${CONF_FILE})
include(${SdkRootDirPath}/cmake/extension/mcux.cmake)

project(evkmimx8mp_sai_interrupt_record_playback LANGUAGES C CXX ASM PROJECT_BOARD_PORT_PATH ${board_root}/${board}/driver_examples/sai/interrupt_record_playback)

include(${SdkRootDirPath}/CMakeLists.txt)


include(${board}/board_files.cmake)

mcux_add_source(
    SOURCES sai_interrupt_record_playback.c
)

mcux_add_include(
    INCLUDES interrupt_record_playback
)

mcux_add_source(
    SOURCES remoteproc/empty_rsc_table.c
)
if(CONFIG_TOOLCHAIN STREQUAL "armgcc")
	set(__CONVERT_CUSTOM_COMMANDS
        COMMAND
        ${CMAKE_OBJCOPY} ${OBJDUMP_BIN_CMD} --remove-section=.stacktop_and_pc
        ${CMAKE_CURRENT_BINARY_DIR}/${MCUX_SDK_PROJECT_NAME}${CMAKE_EXECUTABLE_SUFFIX}
        ${OBJDUMP_OUT_CMD} ${MCUX_SDK_PROJECT_NAME}.bin
	CACHE STRING "CONVERT_CUSTOM_COMMANDS" FORCE)
endif()

mcux_convert_binary(BINARY ${APPLICATION_BINARY_DIR}/${MCUX_SDK_PROJECT_NAME}.bin)

mcux_add_include(INCLUDES . remoteproc)
