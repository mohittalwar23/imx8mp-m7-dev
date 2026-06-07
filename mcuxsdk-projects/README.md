# MCUXpresso SDK Projects

Each subdirectory here contains only the **overlay files** for an MCUXpresso SDK
example — the `.vscode/tasks.json` that adds a deploy task, any `prj.conf` patches,
and optionally a `launch.json`. The full project is not committed (it references
local SDK paths and has large build artifacts).

## How to Use

1. Import the example from your local SDK in MCUXpresso VS Code:
   - Open the MCUXpresso extension → **Import Example from Repository**
   - Select the matching example (e.g. `driver_examples/sai/interrupt_transfer`)
   - MCUXpresso creates the project in your home directory

2. Copy the overlay files from this repo into the newly created project:
   ```bash
   # Example for sai_interrupt_transfer:
   cp mcuxsdk-projects/sai_interrupt_transfer/.vscode/tasks.json \
      ~/evkmimx8mp_sai_interrupt_transfer/.vscode/tasks.json
   ```

3. For `rpmsg_lite_str_echo_rtos`, also copy the prj.conf patches:
   ```bash
   cp mcuxsdk-projects/rpmsg_lite_str_echo_rtos/evkmimx8mp/prj.conf \
      ~/evkmimx8mp_rpmsg_lite_str_echo_rtos_remote/evkmimx8mp/prj.conf
   cp mcuxsdk-projects/rpmsg_lite_str_echo_rtos/prj.conf \
      ~/evkmimx8mp_rpmsg_lite_str_echo_rtos_remote/prj.conf
   ```

## Projects

| Project | SDK path | Deploy method | Status |
|---|---|---|---|
| `hello_world` | `demo_apps/hello_world` | remoteproc | working |
| `sai_interrupt_transfer` | `driver_examples/sai/interrupt_transfer` | TFTP (U-Boot) | working |
| `sai_interrupt_record_playback` | `driver_examples/sai/interrupt_record_playback` | TFTP (U-Boot) | working |
| `sai_low_power_audio` | `demo_apps/sai_low_power_audio` | remoteproc | M7 starts, no audio (SRTM mismatch) |
| `rpmsg_lite_str_echo_rtos` | `multicore_examples/rpmsg_lite_str_echo_rtos/remote` | remoteproc | working |
