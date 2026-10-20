#include "pch_display.hpp"

#include "display.hpp"
#include "theme.hpp"

namespace {

M5GFX display;

} // namespace

void display_init()
{
    display.init();
    display.setRotation(1);
}

void display_show_prompt()
{
    display.fillScreen(theme_col_bg);
    display.setTextColor(theme_col_fg, theme_col_bg);
    display.setTextSize(2);
    display.setCursor(8, 40);
    display.print(theme_title);
    display.setTextSize(1);
    display.setCursor(8, 80);
    display.print(theme_prompt);
}

void display_show_kbd_error()
{
    display.setCursor(8, 100);
    display.setTextColor(theme_col_err, theme_col_bg);
    display.print(theme_kbd_error);
}

void display_show_key(const char *line)
{
    display.fillScreen(theme_col_ok_bg);
    display.setTextColor(theme_col_fg, theme_col_ok_bg);
    display.setTextSize(2);
    display.setCursor(8, 50);
    display.print(line);
}
