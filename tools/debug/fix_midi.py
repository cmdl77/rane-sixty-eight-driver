import re

with open("src/midi-agent/main.cpp", "r") as f:
    text = f.read()

code = """static void parse_and_forward_midi(const uint8_t *raw, size_t len) {
    if (!gVirtualSource || len == 0) return;
    
    // Rane 68 custom HID format is basically a raw MIDI stream padded with zeros/garbage.
    // We just find every valid MIDI status byte, parse its length, and forward it.
    size_t i = 1; // Skip the HID Report ID
    
    while (i < len) {
        uint8_t b = raw[i];
        if (b < 0x80) { i++; continue; }
        
        if (b == 0xF0) {
            size_t j = i + 1;
            while (j < len && raw[j] != 0xF7 && raw[j] < 0x80) j++;
            if (j < len && raw[j] == 0xF7) {
                send_midi(&raw[i], j - i + 1);
                i = j + 1;
            } else {
                i++; // Just skip the F0
            }
            continue;
        }
        
        int n = midi_msg_len(b);
        if (n > 0 && i + n <= len) {
            bool ok = true;
            for (int k = 1; k < n; k++) if (raw[i + k] >= 0x80) { ok = false; break; }
            if (ok) {
                send_midi(&raw[i], (size_t)n);
                i += n;
                continue;
            }
        }
        i++;
    }
}
"""

text = re.sub(r'static void parse_and_forward_midi.*?static void signalHandler', code + "\nstatic void signalHandler", text, flags=re.DOTALL)

with open("src/midi-agent/main.cpp", "w") as f:
    f.write(text)
