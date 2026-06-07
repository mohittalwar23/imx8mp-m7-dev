
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
    SOURCES hello_world/pin_mux.c
            hello_world/pin_mux.h
)

mcux_add_include(
    INCLUDES hello_world
)

mcux_add_source(
    SOURCES hello_world/app.h
            hello_world/hardware_init.c
)

mcux_add_include(
    INCLUDES hello_world
)
