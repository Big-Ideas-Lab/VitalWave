# VitalWave-v0 firmware (protocol 3)

Current nRF52840 firmware for the VitalWave recording app. Supports BLE session
control, accelerometer/gyroscope, temperature/humidity, four-colour PPG, button
markers, and the mandatory charger policy. Older firmware examples remain in
sibling directories.

## Build

Requires Python 3 and Arm GNU Toolchain (`arm-none-eabi-gcc`,
`arm-none-eabi-objcopy`, and `arm-none-eabi-size`) on PATH.
From this directory:

```sh
python3 tools/setup_sdk.py
python3 build.py
```

The setup script downloads and checksum-verifies Nordic nRF5 SDK 17.1.0.
Build outputs are `build/vitalwave_v0.hex` and `build/manifest.json`.
Use **vitalwave_v0.hex**, which includes S140 7.2.0 and the MBR;
`application.hex` alone does not include them. SDK downloads and generated
build files are excluded from Git.

## Program before final assembly

Program the populated PCB before installing it in the watch enclosure, while
its SWD connections are accessible. Use J-Link with VTref, GND and SWD connected;
select NRF52840_XXAA, SWD, 100 kHz. With J-Link Commander launched from this directory:

```text
loadfile "build/vitalwave_v0.hex"
r
g
```

Follow the board power/wiring instructions in the setup guide. Keep charging
input unplugged during programming and initial optical checks; use battery
power and leave UART VCC disconnected. Never move the PPG ribbon while powered.
Do not mass erase as a routine programming step. Check that the board starts
and advertises `VitalWave-v0` before final enclosure assembly.

## Checks and limitations

```sh
sh tools/run_tests.sh
```

These host tests cover session/configuration handling, charger policy, and PPG
register/FIFO handling. They do not validate physical hardware or signal quality.
The build manifest retains `hardware_validation: pending`.

The charger policy sets nominal 240 mA charging and 4.080 V regulation. The board
has no real battery-temperature monitoring through TS; register checks do not
measure actual charging current. On-board power/charging validation is still
required. PPG timestamps are reconstructed, and colours are sampled sequentially.
See [PROTOCOL.md](PROTOCOL.md) for frame layouts and supported rates.

## Third-party components

Nordic nRF5 SDK 17.1.0 and S140 7.2.0 are downloaded separately and used for Nordic
nRF52840 hardware. Review `vendor/nRF5_SDK_17.1.0_ddde560/license.txt`, its
`documentation/licenses.txt`, and component notices. Preserve applicable Nordic
license notices when distributing combined firmware binaries.
