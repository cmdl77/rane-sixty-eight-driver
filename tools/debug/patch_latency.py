import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """
    mInRing.reset();
    mOutRing.reset();

    size_t prefillBytes = 1024 * kChannels * sizeof(float);
    uint8_t* zeros = (uint8_t*)calloc(1, prefillBytes);
    mOutRing.push(zeros, prefillBytes);
    free(zeros);
"""

text = re.sub(r'mInRing\.reset\(\);\s*mOutRing\.reset\(\);', code, text)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
