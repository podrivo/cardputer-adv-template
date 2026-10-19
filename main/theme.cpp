#include "theme.hpp"

// RGB565 (same values as LovyanGFX TFT_*). Edit these for quick visual iteration.
uint16_t theme_col_bg = 0xF800;     // blue
uint16_t theme_col_fg = 0xFFFF;     // white
uint16_t theme_col_err = 0xF800;    // red
uint16_t theme_col_ok_bg = 0x03E0;  // dark green

const char *theme_title = "Hello world!";
const char *theme_prompt = "Press any key...";
const char *theme_kbd_error = "No TCA8418";
