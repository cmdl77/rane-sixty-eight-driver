import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """static inline int32_t rane_float_to_s32(float v) {
    double d = (double)v;
    if (d >= 1.0) d = 1.0;
    if (d <= -1.0) d = -1.0;
    int32_t val = (int32_t)lrint(d * 2147483647.0);
    // Convert to BIG ENDIAN 32-bit (swap bytes)
    return __builtin_bswap32(val);
}

static inline float rane_s32_to_float(const uint8_t* p) {
    // Assume BIG ENDIAN
    int32_t v = (int32_t)((uint32_t)p[3] | ((uint32_t)p[2] << 8) |
                          ((uint32_t)p[1] << 16) | ((uint32_t)p[0] << 24));
    return (float)((double)v / 2147483648.0);
}"""

text = re.sub(r'static inline int32_t rane_float_to_s32.*?static inline float rane_s32_to_float[^\}]+}', code, text, flags=re.DOTALL)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
