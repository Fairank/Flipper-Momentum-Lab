#include "animation_caption.h"
#include <string.h>

AnimationCaption animation_caption_for_builtin(const char* name) {
    if(!name) return AnimationCaptionNone;
    static const char* const names[] = {
        "L1_AnimationError_128x64",
        "L1_NoSd_128x49",
        "L1_BadBattery_128x47",
        "L0_NoDb_128x51",
        "L0_SdBad_128x51",
        "L0_SdOk_128x51",
        "L0_Url_128x51",
        "L0_NewMail_128x51",
    };
    for(size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
        if(!strcmp(name, names[i])) return (AnimationCaption)(i + 1);
    }
    return AnimationCaptionNone;
}

// Replace text regions at draw time; stock artwork and source PNGs remain intact.
// These labels are included in the boot font so SD errors never need a working SD.
void animation_caption_draw(Canvas* canvas, AnimationCaption caption, uint8_t y) {
    if(caption == AnimationCaptionNone) return;
    canvas_set_font(canvas, FontSecondary);
    canvas_set_color(canvas, ColorWhite);
    if(caption == AnimationCaptionError) {
        canvas_draw_box(canvas, 0, 0, 128, 64);
        canvas_set_color(canvas, ColorBlack);
        canvas_draw_str_aligned(canvas, 64, 12, AlignCenter, AlignBottom, "Animation load error");
        canvas_draw_str_aligned(canvas, 64, 26, AlignCenter, AlignBottom, "See serial logs");
        canvas_draw_str_aligned(canvas, 64, 40, AlignCenter, AlignBottom, "Hold OK");
        canvas_draw_str_aligned(canvas, 64, 54, AlignCenter, AlignBottom, "to try another anim");
        return;
    }
    if(caption == AnimationCaptionNoSd) {
        canvas_draw_box(canvas, 38, y + 18, 52, 64 - y - 18);
        canvas_set_color(canvas, ColorBlack);
        canvas_draw_str_aligned(canvas, 63, y + 29, AlignCenter, AlignBottom, "Insert");
        canvas_draw_str_aligned(canvas, 63, y + 43, AlignCenter, AlignBottom, "SD card");
        return;
    }
    if(caption == AnimationCaptionBattery) {
        canvas_draw_box(canvas, 0, y + 34, 128, 13);
        canvas_set_color(canvas, ColorBlack);
        canvas_draw_str_aligned(
            canvas, 64, y + 46, AlignCenter, AlignBottom, "Battery status error");
        return;
    }
    const char* first;
    const char* second;
    bool more = false;
    switch(caption) {
    case AnimationCaptionNoDatabase:
        first = "SD card has no";
        second = "database";
        more = true;
        break;
    case AnimationCaptionSdBad:
        first = "SD card";
        second = "mount failed";
        break;
    case AnimationCaptionSdOk:
        first = "Will save data";
        second = "to SD card";
        break;
    case AnimationCaptionUrl:
        first = "Please visit";
        second = "flipp.dev/upd";
        break;
    case AnimationCaptionMail:
        first = "New";
        second = "mail";
        more = true;
        break;
    default:
        return;
    }
    const bool mail = caption == AnimationCaptionMail;
    const uint8_t x = mail ? 84 : 39;
    const uint8_t center = mail ? 106 : 83;
    canvas_draw_box(canvas, x, y, 128 - x, 64 - y);
    canvas_set_color(canvas, ColorBlack);
    canvas_draw_str_aligned(canvas, center, y + 12, AlignCenter, AlignBottom, first);
    canvas_draw_str_aligned(canvas, center, y + 25, AlignCenter, AlignBottom, second);
    canvas_draw_rframe(canvas, 84, y + 30, 44, 16, 2);
    canvas_draw_str_aligned(
        canvas, 106, y + 43, AlignCenter, AlignBottom, more ? "More >" : "OK >");
}

void animation_caption_draw_levelup(Canvas* canvas) {
    canvas_set_color(canvas, ColorBlack);
    canvas_draw_box(canvas, 80, 0, 48, 64);
    canvas_set_color(canvas, ColorWhite);
    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str_aligned(canvas, 104, 26, AlignCenter, AlignBottom, "Level");
    canvas_draw_str_aligned(canvas, 104, 40, AlignCenter, AlignBottom, "up");
    canvas_draw_rframe(canvas, 84, 46, 44, 17, 2);
    canvas_draw_str_aligned(canvas, 106, 59, AlignCenter, AlignBottom, "OK >");
    canvas_set_color(canvas, ColorBlack);
}
