import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """
    size_t wantBytes = (size_t)totalFrames * kChannels * sizeof(float);
    size_t poppedBytes = mOutRing.pop((uint8_t*)floatFrames, wantBytes);
    if (poppedBytes < wantBytes) {
        if (mXferErrLogCount.fetch_add(1) < 100) {
            RLOG("Ring buffer underrun! want: %zu, got: %zu", wantBytes, poppedBytes);
        }
        memset((uint8_t*)floatFrames + poppedBytes, 0, wantBytes - poppedBytes);
    }
"""

text = re.sub(r'size_t wantBytes.*?memset.*?}', code, text, flags=re.DOTALL)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
