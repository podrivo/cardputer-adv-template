# cardputer-adv-template

Minimal [ESP-IDF](https://docs.espressif.com/projects/esp-idf/) starter for the **M5Stack Cardputer ADV** only.

Fork this for games/apps. It is not a full demo and not a template for the original Cardputer (GPIO matrix keyboard). ADV uses a **TCA8418** over I2C — if keys do nothing, you are on the wrong board.

Hardware: [Cardputer ADV](https://docs.m5stack.com/en/core/Cardputer-Adv) (Stamp-S3A / ESP32-S3, 8 MB flash, 1.14" LCD).

## Prerequisites (one-time)

Follow Espressif’s [Linux/macOS setup for ESP-IDF v5.4.2](https://docs.espressif.com/projects/esp-idf/en/v5.4.2/esp32s3/get-started/linux-macos-setup.html). Summary for macOS:

### 0. Homebrew

Install [Homebrew](https://brew.sh) if you do not have it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Also install Xcode CLT if macOS complains about `xcrun`:

```bash
xcode-select --install
```

### 1. Toolchain packages

```bash
brew install cmake ninja dfu-util ccache
```

Optional if `python3` is missing: `brew install python3`.

### 2. Get ESP-IDF v5.4.2

```bash
mkdir -p ~/esp
cd ~/esp
git clone -b v5.4.2 --recursive https://github.com/espressif/esp-idf.git
```

### 3. Install IDF tools

```bash
cd ~/esp/esp-idf
./install.sh esp32s3
```

### 4. Export the environment (every new shell)

```bash
. ~/esp/esp-idf/export.sh
```

You need a USB-C cable and the Cardputer ADV connected for flash/monitor.

## One-time project deps (then offline)

Pin and vendor [M5GFX](https://github.com/m5stack/M5GFX) locally (needs Cardputer ADV board support — **0.2.29+**):

```bash
git clone --branch 0.2.33 --depth 1 https://github.com/m5stack/M5GFX.git components/M5GFX
```

After this, builds do not need the network.

## Build & flash

With Node/npm (scripts load ESP-IDF for you):

```bash
npm run deps              # clone M5GFX once
npm run setup             # idf.py set-target esp32s3 (once per checkout)
npm run build
npm run flash:monitor     # default PORT=/dev/cu.usbmodem101
```

Day-to-day loop after setup: edit → `npm run flash:monitor`. That rebuilds only what changed, flashes, and opens the serial monitor. There is no live reload; avoid `npm run clean` unless the build is broken. Use `npm run monitor` alone when you only need serial output and the device is already flashed.

Other scripts: `npm run flash`, `npm run monitor`, `npm run menuconfig`, `npm run clean`, `npm run bin` (writes merged flash image to `bins/`).

Prebuilt merged image (bootloader + partition table + app, flash at `0x0`):

- [`bins/cardputer_adv_template.bin`](bins/cardputer_adv_template.bin)

Override the serial port:

```bash
PORT=/dev/cu.usbmodem14201 npm run flash:monitor
```

Or call `idf.py` directly after `. ~/esp/esp-idf/export.sh`.

Linux often uses `/dev/ttyACM0`. Put the device in download mode if flash fails (hold G0 / reset per Stamp-S3 docs).

## What the sample does

Clears the LCD, waits for one TCA8418 key press, then draws the key code. That proves display + ADV keyboard wiring.

## Layout

```
package.json          # npm run build / flash / …
scripts/idf.sh        # sources ESP-IDF, runs idf.py
bins/                 # merged .bin (flash at 0x0)
CMakeLists.txt
sdkconfig.defaults    # 8 MB flash, USB Serial/JTAG console
main/app_main.cpp     # hello-world
components/M5GFX/     # after clone (gitignored)
```

## Out of scope

Games, audio/IMU, and dropping a merged `.bin` into an installer catalog.

## Credits

- [M5GFX](https://github.com/m5stack/M5GFX)
- [M5Cardputer-UserDemo `CardputerADV`](https://github.com/m5stack/M5Cardputer-UserDemo/tree/CardputerADV) (fetch → `idf.py build` reference)
- TCA8418 keypad controller (I2C)
