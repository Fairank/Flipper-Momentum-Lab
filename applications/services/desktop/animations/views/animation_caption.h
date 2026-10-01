#pragma once
#include <gui/canvas.h>

typedef enum {
    AnimationCaptionNone,
    AnimationCaptionError,
    AnimationCaptionNoSd,
    AnimationCaptionBattery,
    AnimationCaptionNoDatabase,
    AnimationCaptionSdBad,
    AnimationCaptionSdOk,
    AnimationCaptionUrl,
    AnimationCaptionMail,
} AnimationCaption;

AnimationCaption animation_caption_for_builtin(const char* name);
void animation_caption_draw(Canvas* canvas, AnimationCaption caption, uint8_t y_offset);
void animation_caption_draw_levelup(Canvas* canvas);
