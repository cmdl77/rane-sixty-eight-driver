with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    lines = f.readlines()

code = """static inline int32_t rane_float_to_s32(float v) {
    double d = (double)v;
    if (d >= 1.0) d = 1.0;
    if (d <= -1.0) d = -1.0;
    // Lower volume by -12dB (factor of 4) to prevent DSP overflow wrap-around!
    int32_t val = (int32_t)lrint(d * 536870911.0);
    return val;
}

static inline float rane_s32_to_float(const uint8_t* p) {
    int32_t v = (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                          ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
    return (float)((double)v / 536870911.0);
}
"""
lines.insert(611, code)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.writelines(lines)
