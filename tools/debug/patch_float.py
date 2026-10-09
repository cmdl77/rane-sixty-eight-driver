import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """static inline int32_t rane_float_to_s32(float v) {
    // Try sending raw IEEE-754 32-bit floats!
    union { float f; int32_t i; } u;
    u.f = v;
    return u.i;
}

static inline float rane_s32_to_float(const uint8_t* p) {
    union { float f; int32_t i; } u;
    u.i = (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                    ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
    return u.f;
}"""

text = re.sub(r'static inline int32_t rane_float_to_s32.*?static inline float rane_s32_to_float[^\}]+}', code, text, flags=re.DOTALL)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
