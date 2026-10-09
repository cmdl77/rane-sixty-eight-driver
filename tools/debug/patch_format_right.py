import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """static inline int32_t rane_float_to_s32(float v) {
    // 24-bit resolution in a 32-bit slot, RIGHT-justified.
    double d = (double)v;
    if (d >= 1.0) d = 1.0;
    if (d <= -1.0) d = -1.0;
    int32_t val = (int32_t)lrint(d * 8388607.0);
    return val; // Right-justified! (bottom 24 bits)
}

static inline float rane_s32_to_float(const uint8_t* p) {
    // Read bottom 3 bytes, sign extend from 24th bit
    int32_t v = (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16));
    if (v & 0x800000) v |= 0xFF000000;
    return (float)((double)v / 8388608.0);
}
"""

text = re.sub(r'static inline int32_t rane_float_to_s32.*?static inline float rane_s32_to_float[^\}]+}', code, text, flags=re.DOTALL)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
