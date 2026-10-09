import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

text = text.replace('if (kr != kIOReturnSuccess && mXferErrLogCount.fetch_add(1) < 50) {', 'if (kr != kIOReturnSuccess && mXferErrLogCount.fetch_add(1) < 50) {')

# Add a trace to see what frames we are sending
code = """
    if (mXferErrLogCount.fetch_add(1) % 1000 == 0) {
        RLOG("OUT submit: bal=%d total=%u", mFbBalance.load(), totalFrames);
    }
    uint8_t* dst = mOutBuf[slot];
"""
text = text.replace('uint8_t* dst = mOutBuf[slot];', code)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
