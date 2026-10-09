import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """static inline int32_t rane_float_to_s32(float v) {
    double d = (double)v;
    if (d >= 1.0) d = 1.0;
    if (d <= -1.0) d = -1.0;
    int32_t val = (int32_t)lrint(d * 2147483647.0);
    return val & 0xFFFFFF00; // Left-justified 24-bit!
}

static inline float rane_s32_to_float(const uint8_t* p) {
    int32_t v = (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                          ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
    return (float)((double)v / 2147483648.0);
}"""

text = re.sub(r'static inline int32_t rane_float_to_s32.*?static inline float rane_s32_to_float[^\}]+}', code, text, flags=re.DOTALL)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
