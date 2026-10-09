import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """static inline int32_t rane_float_to_s32(float v) {
    // Try sending BIG ENDIAN raw IEEE-754 32-bit floats!
    union { float f; int32_t i; } u;
    u.f = v;
    return __builtin_bswap32(u.i);
}

static inline float rane_s32_to_float(const uint8_t* p) {
    union { float f; int32_t i; } u;
    // Read Little Endian then swap to Big Endian (or just read Big Endian directly)
    u.i = (int32_t)((uint32_t)p[3] | ((uint32_t)p[2] << 8) |
                    ((uint32_t)p[1] << 16) | ((uint32_t)p[0] << 24));
    return u.f;
}"""

text = re.sub(r'static inline int32_t rane_float_to_s32.*?static inline float rane_s32_to_float[^\}]+}', code, text, flags=re.DOTALL)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
