#include <Arduino.h>
#include <WiFi.h>
#include <BLEDevice.h>
#include <BLEScan.h>
#include <esp_wifi.h>

// Passive observations only. No advertising, association, injection or device control.
static BLEScan* ble;
static SemaphoreHandle_t outputMutex;
static char mode = 0;
static uint32_t lease = 0, lastWifi = 0;
static bool wifiRunning = false;
static char filter[33] = {0};
struct Seen {
    char kind;
    char id[13];
    uint32_t when;
};
static Seen seen[64] = {};
static unsigned seenCursor = 0, emitted = 0;
static uint32_t windowStart = 0;
static String line;
static bool overflow = false;
static unsigned char lower(unsigned char c) {
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}
static bool contains(const char* text, const char* term) {
    if(!*term) return true;
    for(; *text; text++) {
        size_t i = 0;
        while(term[i] && text[i] && lower(term[i]) == lower(text[i]))
            i++;
        if(!term[i]) return true;
    }
    return false;
}
static void ready() {
    xSemaphoreTake(outputMutex, portMAX_DELAY);
    Serial1.println("NR1,R,ESP32,BW");
    xSemaphoreGive(outputMutex);
}
static void report(char kind, const char* address, int rssi, int channel, const char* name) {
    if(rssi >= 0 || rssi < -127) return;
    char id[13] = {0};
    size_t k = 0;
    for(const char* p = address; *p && k < 12; p++)
        if(isxdigit((unsigned char)*p)) id[k++] = (char)toupper((unsigned char)*p);
    if(k != 12) return;
    xSemaphoreTake(outputMutex, portMAX_DELAY);
    if(!contains(name, filter) && !contains(id, filter)) {
        xSemaphoreGive(outputMutex);
        return;
    }
    uint32_t now = millis();
    if((uint32_t)(now - windowStart) >= 1000) {
        windowStart = now;
        emitted = 0;
    }
    if(emitted >= 40) {
        xSemaphoreGive(outputMutex);
        return;
    }
    for(const auto& s : seen)
        if(s.kind == kind && !strcmp(s.id, id) && (uint32_t)(now - s.when) < 1000) {
            xSemaphoreGive(outputMutex);
            return;
        }
    Seen& s = seen[seenCursor++ % 64];
    s.kind = kind;
    strcpy(s.id, id);
    s.when = now;
    emitted++;
    char hexName[65] = {0};
    size_t n = strnlen(name, 32);
    for(size_t i = 0; i < n; i++)
        snprintf(hexName + i * 2, 3, "%02X", (unsigned char)name[i]);
    char packet[130];
    snprintf(packet, sizeof(packet), "NR1,D,%c,%s,%d,%d,%s", kind, id, rssi, channel, hexName);
    Serial1.println(packet);
    xSemaphoreGive(outputMutex);
}
class Advertisements : public BLEAdvertisedDeviceCallbacks {
    void onResult(BLEAdvertisedDevice device) override {
        auto name = device.getName();
        auto address = device.getAddress().toString();
        report('B', address.c_str(), device.getRSSI(), 0, name.c_str());
    }
};
static Advertisements advertisements;
static void stopScan() {
    mode = 0;
    if(wifiRunning) {
        esp_wifi_scan_stop();
        WiFi.scanDelete();
        wifiRunning = false;
    }
    ble->stop();
    xSemaphoreTake(outputMutex, portMAX_DELAY);
    Serial1.println("NR1,S,STOP");
    xSemaphoreGive(outputMutex);
}
static void process(const String& text) {
    if(text == "NR1,HELLO" || text == "NR1,PING") {
        lease = millis();
        ready();
        return;
    }
    if(text == "NR1,STOP") {
        lease = millis();
        stopScan();
        return;
    }
    if(text == "NR1,SCAN,A" || text == "NR1,SCAN,B" || text == "NR1,SCAN,W") {
        stopScan();
        mode = text[text.length() - 1];
        lease = millis();
        lastWifi = millis() - 8000;
        ready();
        xSemaphoreTake(outputMutex, portMAX_DELAY);
        Serial1.println("NR1,S,RUN");
        xSemaphoreGive(outputMutex);
        return;
    }
    if(text.startsWith("NR1,FILTER,")) {
        String encoded = text.substring(11);
        if(encoded.length() > 64 || (encoded.length() & 1)) return;
        char decoded[33] = {0};
        for(size_t i = 0; i < encoded.length() / 2; i++) {
            char a = encoded[i * 2], b = encoded[i * 2 + 1];
            if(!isxdigit(a) || !isxdigit(b)) return;
            char pair[3] = {a, b, 0};
            decoded[i] = (char)strtoul(pair, nullptr, 16);
            if((unsigned char)decoded[i] < 32) return;
        }
        xSemaphoreTake(outputMutex, portMAX_DELAY);
        memcpy(filter, decoded, sizeof(filter));
        memset(seen, 0, sizeof(seen));
        xSemaphoreGive(outputMutex);
        lease = millis();
        ready();
    }
}
void setup() {
    Serial1.begin(115200, SERIAL_8N1, NR_UART_RX, NR_UART_TX);
    outputMutex = xSemaphoreCreateMutex();
    line.reserve(128);
    WiFi.persistent(false);
    WiFi.setAutoReconnect(false);
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(false, false);
    BLEDevice::init("");
    ble = BLEDevice::getScan();
    ble->setAdvertisedDeviceCallbacks(&advertisements, true);
    ble->setActiveScan(false); // Listen to advertisements without scan requests.
    stopScan();
    ready();
}
void loop() {
    while(Serial1.available()) {
        char c = (char)Serial1.read();
        if(c == '\r') continue;
        if(c == '\n') {
            if(!overflow && line.length()) process(line);
            line = "";
            overflow = false;
        } else if(c < 32 || c > 126 || line.length() >= 127)
            overflow = true;
        else if(!overflow)
            line += c;
    }
    if(mode && (uint32_t)(millis() - lease) > 10000) {
        stopScan();
    }
    if(!mode) {
        delay(10);
        return;
    }
    if(wifiRunning) {
        int n = WiFi.scanComplete();
        if(n >= 0) {
            for(int i = 0; i < n; i++)
                report(
                    'W',
                    WiFi.BSSIDstr(i).c_str(),
                    WiFi.RSSI(i),
                    WiFi.channel(i),
                    WiFi.SSID(i).c_str());
            WiFi.scanDelete();
            wifiRunning = false;
            lastWifi = millis();
        } else if(n == WIFI_SCAN_FAILED) {
            WiFi.scanDelete();
            wifiRunning = false;
            lastWifi = millis();
        }
        delay(10);
        return;
    }
    if((mode == 'A' || mode == 'W') && (uint32_t)(millis() - lastWifi) >= 8000) {
        int state = WiFi.scanNetworks(true, true, true, 120);
        wifiRunning = state == WIFI_SCAN_RUNNING;
        if(!wifiRunning) lastWifi = millis();
    } else if(mode == 'A' || mode == 'B') {
        ble->start(2, false);
        ble->clearResults();
    } else
        delay(10);
}
