
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
    SOURCES sai_low_power_audio/pin_mux.c
            sai_low_power_audio/pin_mux.h
)

mcux_add_include(
    INCLUDES sai_low_power_audio
)

mcux_add_source(
    SOURCES sai_low_power_audio/app.h
            sai_low_power_audio/hardware_init.c
)

mcux_add_include(
    INCLUDES sai_low_power_audio
)
