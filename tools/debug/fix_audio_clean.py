with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

# Replace the sample packing loop with direct float write
old_pack = """    for (uint32_t f = 0; f < totalFrames; f++) {
        const float* src = &floatFrames[f * kChannels];
        for (uint32_t ch = 0; ch < kWireOutCh; ch++) {
            int32_t v = rane_float_to_s32(src[ch]);
            dst[0] = (uint8_t)(v);
            dst[1] = (uint8_t)(v >> 8);
            dst[2] = (uint8_t)(v >> 16);
            dst[3] = (uint8_t)(v >> 24);
            dst += kWireSubslot;
        }
    }"""

new_pack = """    float* dstFloat = (float*)mOutBuf[slot];
    for (uint32_t f = 0; f < totalFrames; f++) {
        const float* src = &floatFrames[f * kChannels];
        for (uint32_t ch = 0; ch < kWireOutCh; ch++) {
            float v = src[ch];
            if (v > 1.0f) v = 1.0f;
            else if (v < -1.0f) v = -1.0f;
            *dstFloat++ = v;
        }
    }"""

if old_pack in text:
    text = text.replace(old_pack, new_pack)
    with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
        f.write(text)
    print("Replaced sample packing with direct float store")
else:
    print("Could not find old_pack")
