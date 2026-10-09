lines = open("src/transport/IOUSBLibTransport.cpp").read().split('\n')
for i, line in enumerate(lines):
    if line.startswith("static inline float rane_s32_to_float"):
        lines.insert(i + 7, "}")
        break
with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write('\n'.join(lines))
