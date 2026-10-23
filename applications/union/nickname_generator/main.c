#include <furi.h>
#include <furi_hal.h>
#include <gui/gui.h>
#include <input/input.h>
#include <stdlib.h>
#include <notification/notification.h>
#include <notification/notification_messages.h>
#include <string.h>

#define MAX_PARTS           10
#define MAX_NICKNAME_LENGTH 12

typedef struct {
    const char* name;
    const char** parts;
    size_t num_parts;
} NicknameCategory;
// dictionary
const char* classic_parts[] = {
    "Ace",       "Alpha",    "Amazon",      "Angel",     "Apollo",   "Archer",   "Argus",
    "Aries",     "Artemis",  "Assassin",    "Athena",    "Atlas",    "Aurora",   "Avenger",
    "Bandit",    "Baron",    "Basilisk",    "Bat",       "Bear",     "Beast",    "Behemoth",
    "Berserker", "Blade",    "Blaze",       "Blizzard",  "Blitz",    "Blood",    "Bolt",
    "Bomber",    "Bone",     "Bounty",      "Bravo",     "Breaker",  "Breeze",   "Brick",
    "Brimstone", "Brute",    "Bullet",      "Buzz",      "Caesar",   "Caliber",  "Cannon",
    "Captain",   "Cardinal", "Cat",         "Centurion", "Champion", "Chaos",    "Charger",
    "Chaser",    "Chief",    "Chimera",     "Chrome",    "Cipher",   "Claw",     "Cobra",
    "Comet",     "Commando", "Condor",      "Cosmo",     "Cougar",   "Crash",    "Crimson",
    "Crow",      "Crusader", "Crystal",     "Cyclone",   "Dagger",   "Dawn",     "Demon",
    "Destiny",   "Diamond",  "Diesel",      "Dino",      "Discord",  "Diver",    "Doc",
    "Doom",      "Dragon",   "Drake",       "Dread",     "Droid",    "Duke",     "Dusk",
    "Eagle",     "Echo",     "Edge",        "Ember",     "Emperor",  "Enigma",   "Envy",
    "Epsilon",   "Equinox",  "Executioner", "Knight",    "Rogue",    "Warrior",  "Paladin",
    "Ranger",    "Mage",     "Warlock",     "Druid",     "Shadow",   "Mystic",   "Phoenix",
    "Griffin",   "Hydra",    "Minotaur",    "Golem",     "Wraith",   "Specter",  "Phantom",
    "Reaper",    "Voyager",  "Nomad",       "Wanderer",  "Sentinel", "Guardian", "Vanguard",
    "Raider",    "Victor",   "Conqueror",   "Renegade",  "Maverick"};
const char* meme_parts[] = {
    "Doge",
    "Pepe",
    "Troll",
    "Wojak",
    "Chad",
    "Karen",
    "Boomer",
    "Zoomer",
    "Millennial",
    "Stonks",
    "MemeLord",
    "MemeQueen",
    "Leet",
    "Epic",
    "Fail",
    "Noob",
    "Pro",
    "Gamer",
    "Hacker",
    "Wizard",
    "BigBrain",
    "SmolBrain",
    "OkayBoomer",
    "FeelsBadMan",
    "FeelsGoodMan",
    "SadFrog",
    "SuccessKid",
    "DistractedBoyfriend",
    "WomanYellingAtCat",
    "Drakeposting",
    "BuffDoge",
    "Cheems",
    "YOLO",
    "ROFL",
    "LMAO",
    "Bruh",
    "Yeet",
    "Skrrt",
    "Sus",
    "Simp",
    "Cap",
    "NoCap"};
const char* hacker_parts[] = {
    "ZeroCool",
    "Malwarebytes",
    "BitDefender",
    "Kaspersky",
    "Norton",
    "McAfee",
    "Avast",
    "AVG",
    "Malware",
    "Spyware",
    "Ransomware",
    "Firewall",
    "Antivirus",
    "Encryption",
    "Decryption",
    "Hash",
    "Algorithm",
    "Exploit",
    "Vulnerability",
    "Patch",
    "Security",
    "AcidBurn",
    "CrashOverride",
    "TheMentor",
    "LordNikon",
    "Jobe",
    "Razor",
    "Blade",
    "PhantomPhreak",
    "CerealKiller",
    "Iceman",
    "ThePlague",
    "Trinity",
    "Morpheus",
    "Cypher",
    "Neo",
    "AgentSmith",
    "MrRobot",
    "Elliot",
    "Darlene",
    "Root",
    "Mozzie",
    "DarkArmy",
    "DedSec",
    "WatchDogs",
    "AidenPearce",
    "MarcusHolloway",
    "Wrench",
    "Sitara",
    "Josh",
    "Clara",
    "RaymondKenney",
    "SamFisher",
    "SolidSnake",
    "BigBoss",
    "RevolverOcelot",
    "PsychoMantis",
    "GrayFox",
    "VulcanRaven",
    "LiquidSnake",
    "SolidusSnake",
    "Raiden",
    "VenomSnake",
    "Quiet",
    "SkullFace",
    "Zero",
    "TheBoss",
    "TheJoy",
    "TheSorrow",
    "TheEnd",
    "TheFear",
    "TheFury",
    "ThePain",
    "47",
    "Hitman",
    "JohnWick",
    "BabaYaga",
    "TheOperator",
    "Six",
    "Ghost",
    "Nomad",
    "Maverick",
    "Ash",
    "Jager",
    "Bandit",
    "Kapkan",
    "Frost",
    "Valkyrie",
    "Caveira",
    "Blackbeard",
    "Pulse",
    "Doc",
    "Rook",
    "Sledge",
    "Thatcher",
    "Mute",
    "Smoke",
    "Glaze",
    "Fuze",
    "Blitz",
    "IQ",
    "Twitch",
    "Montagne",
    "Legion",
    "Finka",
    "Lion",
    "Dokkaebi",
    "Vigil",
    "Zofia",
    "Ela",
    "Alibi",
    "Maestro",
    "Clash",
    "Kaid",
    "Mozzie",
    "Gridlock",
    "Nøkk",
    "Warden",
    "Goyo",
    "Amaru",
    "Kali",
    "Iana",
    "Zero",
    "Ace",
    "Melusi",
    "Aruni",
    "Thunderbird",
    "Flores",
    "Osa",
    "Thorn",
    "Azami",
    "Solis",
    "Grim",
    "Sens",
    "RAM",
    "Brava",
    "Fenrir",
    "CodeTalker",
    "DigitalGhost",
    "BinaryBeast",
    "CyberWraith",
    "NetRunner",
    "DataDemon",
    "Firewall",
    "IceWall",
    "PacketStorm",
    "LogicBomb",
    "Rootkit",
    "Keylogger",
    "Backdoor",
    "Trojan",
    "Worm",
    "Virus",
    "Malware",
    "Spyware",
    "Adware",
    "Ransomware",
    "Botnet",
    "Phishing",
    "Spoofing",
    "DDoS",
    "BruteForce",
    "SQLInjection",
    "CrossSiteScripting",
    "Exploit",
    "Vulnerability",
    "Cybersecurity",
    "PenetrationTesting",
    "EthicalHacking",
    "WhiteHat",
    "BlackHat",
    "GreyHat",
    "Hacktivist",
    "Cyberpunk",
    "Neuromancer",
    "Wintermute",
    "Case",
    "MollyMillions",
    "Armitage",
    "TessierAshpool",
    "DixieFlatline",
    "TheFinn",
    "Maelcum",
    "GhostInTheShell",
    "Major",
    "Batou",
    "Togusa",
    "Ishikawa",
    "TheLaughingMan",
    "ThePuppetMaster",
    "Project2501",
    "Section9",
    "PublicSecuritySection9",
    "Alita",
    "BattleAngel",
    "Gally",
    "Nova",
    "Vector",
    "Hugo",
    "Zapan",
    "Grewishka",
    "McTeague",
    "DataThief",
    "PixelPusher",
    "BitShifter",
    "ByteMe",
    "NullPointer",
    "SegFault",
    "StackOverflow",
    "HeapUnderflow",
    "BufferOverflow",
    "AccessControlViolation",
    "CyberNinja",
    "DigitalSamurai",
    "CryptoWizard",
    "NetProphet",
    "CodeWarrior",
    "InfoSecGuru",
    "SecurityMaster",
    "HackLord",
    "CyberQueen"};

// Display names only; the word lists above are data and stay in English.
NicknameCategory categories[] = {
    {"Classic", classic_parts, sizeof(classic_parts) / sizeof(classic_parts[0])},
    {"Meme", meme_parts, sizeof(meme_parts) / sizeof(meme_parts[0])},
    {"Hacker", hacker_parts, sizeof(hacker_parts) / sizeof(hacker_parts[0])},
};

uint8_t current_category = 0;
char nickname[MAX_NICKNAME_LENGTH + 1];
//aey
void generate_nickname() {
    do {
        strcpy(nickname, "");

        while(strlen(nickname) < MAX_NICKNAME_LENGTH) {
            // Добавляем часть из словаря
            size_t random_index = rand() % categories[current_category].num_parts;
            size_t part_length = strlen(categories[current_category].parts[random_index]);

            if(strlen(nickname) + part_length <= MAX_NICKNAME_LENGTH) {
                strcat(nickname, categories[current_category].parts[random_index]);
            } else {
                break;
            }

            // С вероятностью 90% добавляем случайную цифру
            if(rand() % 10 < 9 && strlen(nickname) < MAX_NICKNAME_LENGTH) {
                char digit[3]; // Увеличиваем размер массива до 3
                snprintf(
                    digit,
                    sizeof(digit),
                    "%d",
                    rand() % 10); // Используем snprintf для безопасности
                strcat(nickname, digit);
            }
        }
        nickname[MAX_NICKNAME_LENGTH] = '\0';

    } while(strlen(nickname) < 5);
}

//графика
static void draw_callback(Canvas* canvas, void* ctx) {
    FuriMutex* mutex = ctx;
    furi_mutex_acquire(mutex, FuriWaitForever);
    canvas_clear(canvas);
    canvas_set_font(canvas, FontPrimary);
    canvas_draw_str(canvas, 2, 12, "Nickname Generator"); // 12 px glyphs on rows 2..12

    // Category line on rows 16..26: label, then the name between the < > arrows
    // that stand for the Left/Right keys
    char category[32];
    snprintf(category, sizeof(category), "< %s >", categories[current_category].name);
    canvas_draw_str(canvas, 2, 26, "Category:");
    canvas_draw_str(canvas, 2 + canvas_string_width(canvas, "Category:") + 4, 26, category);

    canvas_draw_str_aligned(canvas, 60, 44, AlignCenter, AlignCenter, nickname);

    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str(canvas, 2, 63, "OK:Gen Hold Back:Exit"); // rows 53..63
    furi_mutex_release(mutex);
}
//фури
static void input_callback(InputEvent* input_event, void* ctx) {
    furi_assert(ctx);

    FuriMessageQueue* event_queue = ctx;
    furi_message_queue_put(event_queue, input_event, FuriWaitForever);
}

int32_t nickname_generator_app(void* p) {
    UNUSED(p);

    FuriMessageQueue* event_queue = furi_message_queue_alloc(8, sizeof(InputEvent));
    FuriMutex* mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    current_category = 0;
    generate_nickname();
    NotificationApp* notifications = furi_record_open(RECORD_NOTIFICATION);

    ViewPort* view_port = view_port_alloc();
    view_port_draw_callback_set(view_port, draw_callback, mutex);
    view_port_input_callback_set(view_port, input_callback, event_queue);

    Gui* gui = furi_record_open(RECORD_GUI);
    gui_add_view_port(gui, view_port, GuiLayerFullscreen);

    InputEvent event;

    while(1) {
        FuriStatus event_status = furi_message_queue_get(event_queue, &event, 100);

        if(event_status == FuriStatusOk) {
            if(event.type == InputTypeLong && event.key == InputKeyBack) {
                break;
            }
            bool generated = false;
            furi_mutex_acquire(mutex, FuriWaitForever);
            if(event.type == InputTypeShort) {
                if(event.key == InputKeyOk) {
                    generate_nickname();
                    generated = true;
                } else if(event.key == InputKeyRight) {
                    current_category = (current_category + 1) % 3;
                } else if(event.key == InputKeyLeft) {
                    current_category = (current_category + 2) % 3;
                }
            }
            furi_mutex_release(mutex);
            if(generated) {
                notification_message(notifications, &sequence_blink_magenta_100);
                notification_message(notifications, &sequence_single_vibro);
            }
            view_port_update(view_port);
        }

        view_port_update(view_port);
    }
    //база
    view_port_enabled_set(view_port, false);
    gui_remove_view_port(gui, view_port);
    view_port_free(view_port);
    furi_message_queue_free(event_queue);
    furi_mutex_free(mutex);
    furi_record_close(RECORD_NOTIFICATION);

    furi_record_close(RECORD_GUI);

    return 0;
}
