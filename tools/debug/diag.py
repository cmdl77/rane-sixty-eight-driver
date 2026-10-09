with open("src/hal/RaneHALPlugin.cpp", "r") as f:
    hal = f.read()

# Add logging inside RaneHAL_DoIOOperation
old_do_io = """    if ((inOperationID == kAudioServerPlugInIOOperationWriteMix || inOperationID == kAudioServerPlugInIOOperationMixOutput)
        && streamID == kObjectID_Stream_Output) {
        const uint64_t sampleTime = (uint64_t)inIOCycleInfo->mOutputTime.mSampleTime;
        StreamEngine::shared().writeOutput(sampleTime, inIOBufferFrameSize, (const float*)ioMainBuffer);
        return noErr;
    }"""

new_do_io = """    if ((inOperationID == kAudioServerPlugInIOOperationWriteMix || inOperationID == kAudioServerPlugInIOOperationMixOutput)
        && streamID == kObjectID_Stream_Output) {
        static uint64_t sWriteCount = 0;
        if (sWriteCount++ % 100 == 0) {
            const float* fbuf = (const float*)ioMainBuffer;
            RLOG("DoIO writeMix: op=0x%08x frames=%u ch0=%.3f ch1=%.3f",
                 inOperationID, inIOBufferFrameSize, fbuf ? fbuf[0] : 0, fbuf ? fbuf[1] : 0);
        }
        const uint64_t sampleTime = (uint64_t)inIOCycleInfo->mOutputTime.mSampleTime;
        StreamEngine::shared().writeOutput(sampleTime, inIOBufferFrameSize, (const float*)ioMainBuffer);
        return noErr;
    }"""

if old_do_io in hal:
    hal = hal.replace(old_do_io, new_do_io)
    with open("src/hal/RaneHALPlugin.cpp", "w") as f:
        f.write(hal)
    print("Patched RaneHALPlugin.cpp")
else:
    print("Could not find old_do_io in RaneHALPlugin.cpp")
