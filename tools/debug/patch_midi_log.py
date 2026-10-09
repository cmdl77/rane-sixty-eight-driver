import re
with open("src/midi-agent/main.cpp", "r") as f:
    text = f.read()

code = """
            if (ok) {
                send_midi(&raw[i], (size_t)n);
                char hex[32] = {0};
                for (int m=0; m<n; m++) snprintf(hex+m*3, 4, "%02X ", raw[i+m]);
                RLOG("Sent MIDI: %s", hex);
                i += n;
                continue;
            }
"""

text = re.sub(r'if \(ok\) \{\s*send_midi.*?i \+= n;\s*continue;\s*\}', code, text, flags=re.DOTALL)

with open("src/midi-agent/main.cpp", "w") as f:
    f.write(text)
