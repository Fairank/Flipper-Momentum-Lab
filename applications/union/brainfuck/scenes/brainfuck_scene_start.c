#include "../brainfuck_i.h"
enum SubmenuIndex {
    SubmenuIndexNew,
    SubmenuIndexOpen,
    SubmenuIndexLearn,
    SubmenuIndexAbout,
};

void brainfuck_scene_start_submenu_callback(void* context, uint32_t index) {
    BFApp* brainfuck = context;
    view_dispatcher_send_custom_event(brainfuck->view_dispatcher, index);
}
void brainfuck_scene_start_on_enter(void* context) {
    BFApp* brainfuck = context;

    Submenu* submenu = brainfuck->submenu;
    submenu_add_item(
        submenu, "新建", SubmenuIndexNew, brainfuck_scene_start_submenu_callback, brainfuck);
    submenu_add_item(
        submenu, "打开", SubmenuIndexOpen, brainfuck_scene_start_submenu_callback, brainfuck);
    submenu_add_item(
        submenu, "教程", SubmenuIndexLearn, brainfuck_scene_start_submenu_callback, brainfuck);
    submenu_add_item(
        submenu, "关于", SubmenuIndexAbout, brainfuck_scene_start_submenu_callback, brainfuck);

    submenu_set_selected_item(
        submenu, scene_manager_get_scene_state(brainfuck->scene_manager, brainfuckSceneStart));
    view_dispatcher_switch_to_view(brainfuck->view_dispatcher, brainfuckViewMenu);
}

bool brainfuck_scene_start_on_event(void* context, SceneManagerEvent event) {
    BFApp* brainfuck = context;
    bool consumed = false;

    if(event.type == SceneManagerEventTypeCustom) {
        if(event.event == SubmenuIndexNew) {
            scene_manager_next_scene(brainfuck->scene_manager, brainfuckSceneFileCreate);
            consumed = true;
        } else if(event.event == SubmenuIndexOpen) {
            scene_manager_next_scene(brainfuck->scene_manager, brainfuckSceneFileSelect);
            consumed = true;
        } else if(event.event == SubmenuIndexLearn) {
            text_box_set_text(
                brainfuck->text_box,
                "BF 的程序空间是一个长 128 个单元的一维数组，语言由八条指令组成:\n\n"
                "'>': 数据指针加一(指向右边的下一个单元)。\n\n"
                "'<': 数据指针减一(指向左边的下一个单元)。\n\n"
                "'+': 数据指针所指的字节加一。\n\n"
                "'-': 数据指针所指的字节减一。\n\n"
                "'.': 输出数据指针所指的字节。\n\n"
                "',': 读入一个字节，存入数据指针所指的字节。\n\n"
                "'[': 若数据指针所指的字节为零，指令指针不再前进到下一条指令，而是跳到匹配的 ']' 之后的指令；若不为零，括号内的代码会循环执行，直到该字节变为 0。\n");
            scene_manager_next_scene(brainfuck->scene_manager, brainfuckSceneExecEnv);
            consumed = true;
        } else if(event.event == SubmenuIndexAbout) {
            text_box_set_text(
                brainfuck->text_box,
                "FlipperBrainfuck\n\nF0 Brainfuck 解释器\n作者: github.com/Nymda");
            scene_manager_next_scene(brainfuck->scene_manager, brainfuckSceneExecEnv);
            consumed = true;
        }
        scene_manager_set_scene_state(brainfuck->scene_manager, brainfuckSceneStart, event.event);
    }

    return consumed;
}

void brainfuck_scene_start_on_exit(void* context) {
    BFApp* brainfuck = context;
    submenu_reset(brainfuck->submenu);
}
