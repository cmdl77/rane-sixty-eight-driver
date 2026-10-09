import re
with open("src/midi-agent/main.cpp", "r") as f:
    text = f.read()

code = """static void parse_and_forward_midi(const uint8_t *raw, size_t len) {
    if (!gVirtualSource || len == 0) return;

    // The Rane Sixty-Eight sends raw MIDI bytes padded with garbage.
    // We scan for status bytes (>= 0x80) and extract valid messages.
    size_t i = 1; // Skip Report ID
    
    while (i < len) {
        uint8_t b = raw[i];
        if (b < 0x80) { i++; continue; } // Skip garbage/padding

        if (b == 0xF0) { // SysEx
            size_t j = i + 1;
            while (j < len && raw[j] != 0xF7 && raw[j] < 0x80) j++;
            if (j < len && raw[j] == 0xF7) {
                send_midi(&raw[i], j - i + 1);
                i = j + 1;
            } else {
                i++; // Unterminated, probably garbage `F0`, skip just the `F0`
            }
            continue;
        }

        int n = midi_msg_len(b);
        if (n > 0 && i + n <= len) {
            bool ok = true;
            for (int k = 1; k < n; k++) {
                if (raw[i + k] >= 0x80) { ok = false; break; }
            }
            if (ok) {
                send_midi(&raw[i], (size_t)n);
                i += n;
                continue;
            }
        }
        i++; // Invalid message, skip status byte
    }
}"""

text = re.sub(r'static void parse_and_forward_midi.*?static void signalHandler', code + "\n\nstatic void signalHandler", text, flags=re.DOTALL)

with open("src/midi-agent/main.cpp", "w") as f:
    f.write(text)
