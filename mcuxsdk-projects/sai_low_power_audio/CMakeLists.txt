
# Copyright 2026 NXP
#
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 3.22.0)

cmake_path(APPEND conf_file_path ${CMAKE_CURRENT_LIST_DIR} ${board} prj.conf)
set(CONF_FILE ${conf_file_path} ${CONF_FILE})
include(${SdkRootDirPath}/cmake/extension/mcux.cmake)

project(evkmimx8mp_sai_low_power_audio LANGUAGES C CXX ASM PROJECT_BOARD_PORT_PATH ${board_root}/${board}/demo_apps/sai_low_power_audio)

include(${SdkRootDirPath}/CMakeLists.txt)


include(${board}/board_files.cmake)

mcux_add_source(
    SOURCES evkmimx8mp/FreeRTOSConfigBoard.h
            evkmimx8mp/app_srtm.c
            evkmimx8mp/app_srtm.h
            evkmimx8mp/rsc_table.c
            evkmimx8mp/rsc_table.h
            evkmimx8mp/srtm_config.h
            remoteproc/remoteproc.h
            sai_low_power_audio/FreeRTOSConfig.h
            sai_low_power_audio/lpm.c
            sai_low_power_audio/lpm.h
            sai_low_power_audio/rpmsg_config.h
            sai_low_power_audio/sai_low_power_audio.c
            sai_low_power_audio/sai_low_power_audio.h
)

mcux_add_include(
    INCLUDES remoteproc
)
mcux_add_macro(
    CC "-DSRTM_DEBUG_MESSAGE_FUNC=DbgConsole_Printf\
       -DSRTM_DEBUG_VERBOSE_LEVEL=SRTM_DEBUG_VERBOSE_WARN"
    AS "-DNO_CRP"
)

mcux_remove_armgcc_linker_script(
    BASE_PATH ${SdkRootDirPath}
    TARGETS debug release
    LINKER ${device_root}/i.MX/i.MX8MP/MIMX8ML8/gcc/MIMX8ML8xxxLZ_ram.ld
)

mcux_remove_iar_linker_script(
    BASE_PATH ${SdkRootDirPath}
    TARGETS debug release
    LINKER ${device_root}/i.MX/i.MX8MP/MIMX8ML8/iar/MIMX8ML8xxxLZ_ram.icf
)


mcux_add_armgcc_linker_script(
    LINKER linker_files/MIMX8ML8xxxxx_cm7_lpa_ram.ld
    TARGETS debug release
)

mcux_add_iar_linker_script(
    LINKER linker_files/MIMX8ML8xxxxx_cm7_lpa_ram.icf
    TARGETS debug release
)
mcux_remove_configuration(
    TARGETS debug
    TOOLCHAINS iar
    CC "-On"
)

mcux_add_iar_configuration(
    TARGETS debug
    CC "-Om"
)

mcux_remove_configuration(
    TARGETS debug
    TOOLCHAINS armgcc
    CC "-O0"
)

mcux_add_configuration(
    TARGETS debug
    TOOLCHAINS armgcc
    CC "-Os"
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

mcux_add_include(INCLUDES evkmimx8mp sai_low_power_audio)
