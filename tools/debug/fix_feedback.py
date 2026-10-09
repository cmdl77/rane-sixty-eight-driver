import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """
        uint32_t cnt = 0;
        if (act > 0 && kWireInFrameBytes > 0) {
            cnt = act / kWireInFrameBytes;
        }
"""

text = re.sub(r'uint32_t cnt = 0;\s*if \(stride > 0 && act >= stride\) \{\s*cnt = act / stride;\s*\} else if \(act > 0 && kWireInFrameBytes > 0\) \{\s*cnt = act / kWireInFrameBytes;\s*\}', code, text)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
