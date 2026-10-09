import re
with open("src/hal/RaneHALPlugin.cpp", "r") as f:
    text = f.read()

text = text.replace('const Float64 kSupportedRates[] = { 48000.0, 44100.0 };', 'const Float64 kSupportedRates[] = { 48000.0 };')
text = text.replace('const UInt32 kNumRates = 2;', 'const UInt32 kNumRates = 1;')

with open("src/hal/RaneHALPlugin.cpp", "w") as f:
    f.write(text)
