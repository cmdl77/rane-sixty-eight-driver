import re
with open("scripts/install.sh", "r") as f:
    text = f.read()

text = re.sub(r'su -l.*RaneMIDIAgent.*?&\' \|\| true', '', text)

with open("scripts/install.sh", "w") as f:
    f.write(text)
