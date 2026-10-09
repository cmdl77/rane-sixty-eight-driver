import re
with open("src/midi-agent/main.cpp", "r") as f:
    text = f.read()

code = """
static uint8_t gPrevReport[64] = {0};

static void parse_and_forward_midi(const uint8_t *raw, size_t len) {
    if (!gVirtualSource || len == 0) return;
    for (size_t i = 1; i < len && i < 64; i++) {
        uint8_t b = raw[i];
        if (b != gPrevReport[i]) {
            gPrevReport[i] = b;
            uint8_t cc[3] = { 0xB0, (uint8_t)(i & 0x7F), (uint8_t)(b & 0x7F) };
            send_midi(cc, 3);
            if (gHIDReportCount.load() < 5000) {
                RLOG("Mapped HID byte %d (val %02X) to CC", (int)i, b);
            }
        }
    }
}
"""

text = re.sub(r'static void parse_and_forward_midi\(const uint8_t \*raw, size_t len\) \{.*?\n\}\n', code, text, flags=re.DOTALL)

with open("src/midi-agent/main.cpp", "w") as f:
    f.write(text)
