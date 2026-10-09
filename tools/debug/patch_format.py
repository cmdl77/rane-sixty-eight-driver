import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """static inline int32_t rane_float_to_s32(float v) {
    // 24-bit resolution in a 32-bit slot, left-justified.
    // In UAC2, 24-bit in 32-bit slot is usually left-justified (top 24 bits hold data).
    // Let's do left-justified (multiply by 2147483647.0 and zero out bottom byte to be safe).
    // Wait, if we just multiply by 2^31 - 1, the top 24 bits are inherently correct.
    // If the DAC ignores the bottom 8 bits, we are fine.
    // BUT what if it is right-justified? 
    // Usually Rane uses 24-bit right-justified? No, standard is left.
    // Let's just output 24-bit left justified explicitly.
    double d = (double)v;
    if (d >= 1.0) d = 1.0;
    if (d <= -1.0) d = -1.0;
    int32_t val = (int32_t)lrint(d * 2147483647.0);
    return val & 0xFFFFFF00; // Left-justified, bottom 8 bits zeroed!
}

static inline float rane_s32_to_float(const uint8_t* p) {
    // Assume left-justified 24-bit or 32-bit (same thing for floats if we cast)
    int32_t v = (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                          ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
    return (float)((double)v / 2147483648.0);
}
"""

text = re.sub(r'static inline int32_t rane_float_to_s32.*?static inline float rane_s32_to_float[^\}]+}', code, text, flags=re.DOTALL)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
