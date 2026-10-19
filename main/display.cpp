#include "display.hpp"

#define M5GFX_BOARD lgfx::boards::board_M5CardputerADV
#include <M5GFX.h>

namespace {

constexpr uint16_t COL_BG = TFT_BLUE;
constexpr uint16_t COL_FG = TFT_WHITE;
constexpr uint16_t COL_ERR = TFT_RED;
constexpr uint16_t COL_OK_BG = TFT_DARKGREEN;

M5GFX display;

} // namespace

void display_init()
{
    display.init();
    display.setRotation(1);
}

void display_show_prompt()
{
    display.fillScreen(COL_BG);
    display.setTextColor(COL_FG, COL_BG);
    display.setTextSize(2);
    display.setCursor(8, 40);
    display.print("Hello world!");
    display.setTextSize(1);
    display.setCursor(8, 80);
    display.print("Press any key...");
}

void display_show_kbd_error()
{
    display.setCursor(8, 100);
    display.setTextColor(COL_ERR, COL_BG);
    display.print("No TCA8418");
}

void display_show_key(const char *line)
{
    display.fillScreen(COL_OK_BG);
    display.setTextColor(COL_FG, COL_OK_BG);
    display.setTextSize(2);
    display.setCursor(8, 50);
    display.print(line);
}
