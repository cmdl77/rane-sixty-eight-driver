with open("src/midi-agent/main.cpp", "r") as f:
    text = f.read()

# Fix the CFRunLoop issue: run CFRunLoop in a dedicated pthread!
old_setup = """    RLOG("Rane MIDI Agent starting...");
    setupMidi();
    setupHIDBridge();"""

new_setup = """    RLOG("Rane MIDI Agent starting...");
    setupMidi();

    // Start HID Bridge on a dedicated thread with its own CFRunLoop!
    pthread_t hidThread;
    pthread_create(&hidThread, nullptr, [](void*) -> void* {
        RLOG("HID RunLoop thread starting...");
        setupHIDBridge();
        CFRunLoopRun();
        return nullptr;
    }, nullptr);"""

if old_setup in text:
    text = text.replace(old_setup, new_setup)
    with open("src/midi-agent/main.cpp", "w") as f:
        f.write(text)
    print("Fixed MIDI thread in main.cpp")
else:
    print("Could not find old_setup in main.cpp")
