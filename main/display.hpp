#pragma once

// Thin display API — keeps M5GFX out of other translation units.

void display_init();
void display_show_prompt();
void display_show_kbd_error();
void display_show_key(const char *line);
