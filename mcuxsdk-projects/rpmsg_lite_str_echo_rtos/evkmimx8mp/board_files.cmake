
# Copyright 2026 NXP
#
# SPDX-License-Identifier: BSD-3-Clause

mcux_add_configuration(
    CC "-DSDK_DEBUGCONSOLE=1"
    CX "-DSDK_DEBUGCONSOLE=1"
)


mcux_add_source(
    SOURCES evkmimx8mp/board.c
            evkmimx8mp/board.h
)

mcux_add_include(
    INCLUDES evkmimx8mp
)

mcux_add_source(
    SOURCES evkmimx8mp/clock_config.c
            evkmimx8mp/clock_config.h
)

mcux_add_include(
    INCLUDES evkmimx8mp
)

mcux_add_source(
    SOURCES remote/pin_mux.c
            remote/pin_mux.h
)

mcux_add_include(
    INCLUDES remote
)

mcux_add_source(
    SOURCES remote/app.h
            remote/hardware_init.c
)

mcux_add_include(
    INCLUDES remote
)
