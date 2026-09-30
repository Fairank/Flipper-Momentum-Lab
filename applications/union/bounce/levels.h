#pragma once

/*
 * Bounce level maps. One char per 8x8 tile:
 *   '#' brick            'S' start position
 *   'O' ring (2 tiles tall: tile below must be empty)
 *   'o' ring sunk in water (tile below must be '~')
 *   'E' exit door segment (solid until every ring is collected)
 *   'C' checkpoint       '+' extra life
 *   '^' floor spike      'v' ceiling spike
 *   'J' spring pad       '~' water
 *   'M' spiker moving left/right, 'N' spiker moving up/down
 *   'm' / 'n' same spikers, starting in water
 * All rows of a level must have the same length.
 */

#include <stdint.h>

typedef struct {
    const char* name;
    uint8_t height;
    const char* const* rows;
} LevelDef;

/* 1. First Bounce */
static const char* const level1_rows[] = {
    "########################################",
    "#                                     E#",
    "#                                     E#",
    "#             O                       E#",
    "#                             O       E#",
    "#      O                 ##           E#",
    "#S               ##      ##           E#",
    "########################################",
};

/* 2. Thorns */
static const char* const level2_rows[] = {
    "########################################################",
    "#                                                     E#",
    "#                                                     E#",
    "#            O                       O                E#",
    "#                        C                            E#",
    "#     O                 ###    O              O       E#",
    "#S          ^^^        #####             ^^       ^^  E#",
    "########################################################",
};

/* 3. Spring Tower */
static const char* const level3_rows[] = {
    "############################################################",
    "#                    +                                    E#",
    "#                  O                                      E#",
    "#                                                         E#",
    "#                ######                     O             E#",
    "#                #    #                                   E#",
    "#         O      #    #      C                            E#",
    "#                #    #    #####~~~~~~~~~~~#####          E#",
    "#S         J    J#    # J  #####~~~~~~~~~~~#####    ^^    E#",
    "############################################################",
};

/* 4. Spikers */
static const char* const level4_rows[] = {
    "################################################################",
    "#                    N                               N        E#",
    "#                                +                            E#",
    "#           O                                           O     E#",
    "#                               #                             E#",
    "#               ##      O      ###           ##               E#",
    "#S     #   M    ##          C #####     M    ##   N           E#",
    "################################################################",
};

/* 5. The Climb */
static const char* const level5_rows[] = {
    "####################",
    "#E      O          #",
    "#E           +     #",
    "################   #",
    "#                  #",
    "#         O        #",
    "#    C      ^^     #",
    "#   #############J##",
    "#                  #",
    "#        O         #",
    "#     ^^           #",
    "##J#############   #",
    "#                  #",
    "#       O          #",
    "#S                 #",
    "#################J##",
};

/* 6. Deep Water */
static const char* const level6_rows[] = {
    "############################################################",
    "#                                                         E#",
    "#                                            O            E#",
    "#                                                         E#",
    "#S                                                        E#",
    "####                         C              ####          E#",
    "####~~~~~~~~~~~~n~~~~~~~~~~#####~~~~~~~~~~~~####          E#",
    "####~~~~o~~~~~~~~~~~~~~~~~~#####~~~~~~o~~~~~####          E#",
    "####~~~~~~~~~~~~~~~~~~~~~~~#####~~~~~~~~~~~~####    ^^    E#",
    "#################################################J##########",
};

/* 7. Spike Alley */
static const char* const level7_rows[] = {
    "########################################################################",
    "#                     ############                              O     E#",
    "#                     ############                                    E#",
    "#       O             ############                                    E#",
    "#                     ############                                    E#",
    "#                        v O v                                        E#",
    "#S     ^^     ^^                    C  ^^^##^^^     #   M   #         E#",
    "################################################################J#######",
};

/* 8. Grand Finale */
static const char* const level8_rows[] = {
    "################################################################################################",
    "#                                                                           N                 E#",
    "#                                                                                             E#",
    "#                                                                                             E#",
    "#                                                                                             E#",
    "#                                  O                                                          E#",
    "#                                                               O                             E#",
    "#    O                        ############                                                    E#",
    "#            #~~~~~~~~n~~#       vv      #                                                    E#",
    "#          ###~~~~~o~~~~~#               #                   ###  ###               O         E#",
    "# S  ^^  #####~~~~~~~~~~~#            +  #    C #   M    # ^^^^^^^^^^^^         N             E#",
    "############################J###############J###################################################",
};

static const LevelDef levels[] = {
    {"初次弹跳", 8, level1_rows},
    {"荆棘", 8, level2_rows},
    {"弹簧塔", 10, level3_rows},
    {"刺球", 8, level4_rows},
    {"攀登", 16, level5_rows},
    {"深水", 10, level6_rows},
    {"尖刺走廊", 8, level7_rows},
    {"最终关卡", 12, level8_rows},
};

#define LEVEL_COUNT (sizeof(levels) / sizeof(levels[0]))
