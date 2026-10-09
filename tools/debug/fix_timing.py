import re
with open("src/transport/IOUSBLibTransport.cpp", "r") as f:
    text = f.read()

code = """
    if (next_f <= bus || (bus + 10) < next_f || force) {
        next_f = bus + 10;
    }
    
    next.store(next_f + 8);
"""
text = re.sub(r'if \(next_f <= bus \|\| \(bus \+ 2\) < next_f \|\| force\) \{\s*next_f = bus \+ 2;\s*\}\s*next\.store\(next_f \+ 1\);', code, text)

with open("src/transport/IOUSBLibTransport.cpp", "w") as f:
    f.write(text)
