"""Execute the production scroll formatter/drawer with host canvas substitutes."""

from pathlib import Path
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]


class WidgetScrollUTF8Tests(unittest.TestCase):
    def test_wrapping_scroll_limits_alignment_and_tiny_width(self):
        source = (
            ROOT
            / "applications/services/gui/modules/widget_elements/widget_element_text_scroll.c"
        ).read_text(encoding="utf-8")
        source = source[
            source.index("#define WIDGET_ELEMENT") : source.index(
                "static bool widget_element_text_scroll_input("
            )
        ]
        source = source.replace(
            "ARRAY_DEF(TextScrollLineArray, TextScrollLineArray, M_POD_OPLIST) //-V658",
            r"""
typedef struct {TextScrollLineArray v[64];size_t n;} Lines;
typedef Lines TextScrollLineArray_t[1];
typedef struct {Lines* a;size_t i;} Iterator;
typedef Iterator TextScrollLineArray_it_t[1];
static size_t TextScrollLineArray_size(Lines* a) {return a->n;}
static void TextScrollLineArray_push_back(Lines* a,TextScrollLineArray v) {assert(a->n<64);a->v[a->n++]=v;}
static TextScrollLineArray* TextScrollLineArray_get(Lines* a,size_t i) {assert(i<a->n);return &a->v[i];}
static void TextScrollLineArray_it(Iterator* it,Lines* a) {it->a=a;it->i=0;}
static bool TextScrollLineArray_end_p(Iterator* it) {return it->i==it->a->n;}
static void TextScrollLineArray_next(Iterator* it) {it->i++;}
static TextScrollLineArray* TextScrollLineArray_ref(Iterator* it) {return &it->a->v[it->i];}
""",
        )
        utf8 = (
            (ROOT / "applications/services/gui/utf8_internal.h")
            .read_text(encoding="utf-8")
            .replace("#pragma once", "")
        )
        native_test(
            r"""
#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#define MAX(a,b) ((a)>(b)?(a):(b))
#define furi_assert assert
#define FuriWaitForever 0
typedef int Font;
typedef int Align;
enum {FontPrimary,FontSecondary,FontKeyboard,AlignLeft,AlignCenter,AlignRight,AlignTop};
typedef struct {int height,leading_default,descender;} CanvasFontParameters;
typedef int Canvas;
typedef struct {char s[2048];} FuriString;
typedef struct {void* model;int model_mutex;} WidgetElement;
static void furi_mutex_acquire(int x,int t) {(void)x;(void)t;}
static void furi_mutex_release(int x) {(void)x;}
static FuriString* furi_string_alloc(void) {return calloc(1,sizeof(FuriString));}
static FuriString* furi_string_alloc_set(FuriString* s) {FuriString* t=furi_string_alloc();strcpy(t->s,s->s);return t;}
static void furi_string_free(FuriString* s) {free(s);}
static void furi_string_reset(FuriString* s) {s->s[0]=0;}
static const char* furi_string_get_cstr(FuriString* s) {return s->s;}
static char furi_string_get_char(FuriString* s,size_t i) {return s->s[i];}
static void furi_string_right(FuriString* s,size_t i) {assert(i<=strlen(s->s));memmove(s->s,s->s+i,strlen(s->s+i)+1);}
static void furi_string_cat_str(FuriString* s,const char* v) {assert(strlen(s->s)+strlen(v)<sizeof(s->s));strcat(s->s,v);}
static void canvas_set_font(Canvas* c,Font f) {*c=f;}
static const CanvasFontParameters* canvas_get_font_params(Canvas* c,Font f) {(void)c;(void)f;static const CanvasFontParameters p={6,9,2};return &p;}
"""
            + utf8
            + r"""
static size_t canvas_glyph_width(Canvas* c,uint16_t cp) {(void)c;return gui_utf8_is_cjk(cp)?12:5;}
static int drawn,last_x,last_y,limit_y,bar_total;
static void canvas_draw_str_aligned(Canvas* c,int x,int y,Align h,Align v,const char* s) {
    (void)c;(void)h;(void)v;
    assert(y+(gui_utf8_has_cjk(s)?12:8)<=limit_y);
    last_x=x;last_y=y;drawn++;
}
static void elements_scrollbar_pos(Canvas* c,int x,int y,int h,int p,int n) {(void)c;(void)x;(void)y;(void)h;(void)p;bar_total=n;}
"""
            + source
            + r"""
static void setup(WidgetElementTextScrollModel* m,WidgetElement* e,const char* s,int width,int height) {
    memset(m,0,sizeof(*m));m->x=10;m->y=4;m->width=width;m->height=height;
    m->text=furi_string_alloc();strcpy(m->text->s,s);e->model=m;e->model_mutex=0;
    drawn=0;bar_total=0;limit_y=m->y+m->height;
}
static void cleanup(WidgetElementTextScrollModel* m) {
    for(size_t i=0;i<m->line_array->n;i++)furi_string_free(m->line_array->v[i].text);
    furi_string_free(m->text);
}
int main(void) {
    assert(gui_utf8_is_ascii("abc"));
    assert(gui_utf8_prev_start("中文",6)==3);
    assert(gui_utf8_offset("中文",1)==3);
    assert(gui_utf8_line_height(8,"中文")==12);
    Canvas c=0;WidgetElement e;WidgetElementTextScrollModel m;
    setup(&m,&e,"中文测试中文测试",24,25);
    widget_element_text_scroll_draw(&c,&e);
    assert(m.line_array->n==4 && drawn==2 && m.scroll_pos_total==3 && bar_total==3);
    for(size_t i=0;i<4;i++)assert(strlen(m.line_array->v[i].text->s)==6);
    m.scroll_pos_current=2;drawn=0;widget_element_text_scroll_draw(&c,&e);
    assert(drawn==2 && last_y==17);cleanup(&m);
    setup(&m,&e,"\033c\033#中文\nA\n中文",24,40);
    widget_element_text_scroll_draw(&c,&e);
    assert(drawn==3 && m.scroll_pos_total==1);
    assert(m.line_array->v[0].font==FontPrimary && m.line_array->v[1].font==FontSecondary);
    m.scroll_pos_current=0;m.height=12;limit_y=16;drawn=0;
    widget_element_text_scroll_draw(&c,&e);assert(drawn==1 && last_x==22);cleanup(&m);
    setup(&m,&e,"中文",1,12);widget_element_text_scroll_draw(&c,&e);
    assert(m.line_array->n==2 && drawn==1 && m.scroll_pos_total==2);cleanup(&m);
    setup(&m,&e,"abcde\n\n",10,26);widget_element_text_scroll_draw(&c,&e);
    assert(m.line_array->n==5 && drawn==3 && m.scroll_pos_total==3);
    assert(!strcmp(m.line_array->v[0].text->s,"ab"));cleanup(&m);
    setup(&m,&e,"",20,8);widget_element_text_scroll_draw(&c,&e);
    assert(m.line_array->n==1 && m.scroll_pos_total==1 && drawn==1);cleanup(&m);
    setup(&m,&e,"\xE4",20,8);widget_element_text_scroll_draw(&c,&e);
    assert(m.line_array->n==1 && drawn==1);cleanup(&m);
    return 0;
}
"""
        )
