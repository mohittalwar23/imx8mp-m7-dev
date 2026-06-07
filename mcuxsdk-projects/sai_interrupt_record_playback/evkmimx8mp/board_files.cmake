
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
    SOURCES interrupt_record_playback/pin_mux.c
            interrupt_record_playback/pin_mux.h
)

mcux_add_include(
    INCLUDES interrupt_record_playback
)

mcux_add_source(
    SOURCES interrupt_record_playback/app.h
            interrupt_record_playback/hardware_init.c
)

mcux_add_include(
    INCLUDES interrupt_record_playback
)
