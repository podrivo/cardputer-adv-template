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

```bash
. ~/esp/esp-idf/export.sh
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/cu.usbmodem* flash monitor   # macOS — adjust port
```

Linux often uses `/dev/ttyACM0`. Put the device in download mode if flash fails (hold G0 / reset per Stamp-S3 docs).

## What the sample does

Clears the LCD, waits for one TCA8418 key press, then draws the key code. That proves display + ADV keyboard wiring.

## Layout

```
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
