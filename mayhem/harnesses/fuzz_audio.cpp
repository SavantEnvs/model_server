// Fuzzes ovms::audio_utils (src/audio/audio_utils.cpp): the speech-to-text upload decoders —
// dr_wav / dr_mp3, channel downmix and resampling — exactly as the /v3/audio endpoints call them.
// Byte 0 selects the entry point, the rest is the uploaded audio file.
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string_view>
#include "src/audio/audio_utils.hpp"
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    ovms_fuzz_quiet_logs();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 1)
        return -1;
    uint8_t sel = data[0];
    std::string_view buf(reinterpret_cast<const char*>(data + 1), size - 1);
    try {
        switch (sel % 5) {
        case 0: ovms::audio_utils::readWav(buf); break;
        case 1: ovms::audio_utils::readMp3(buf); break;
        case 2: ovms::audio_utils::readWithoutResample(buf, "wav"); break;
        case 3: ovms::audio_utils::readWithoutResample(buf, "mp3"); break;
        case 4:
            if (ovms::audio_utils::isWavBuffer(buf))
                ovms::audio_utils::readWav(buf, 8000);
            else
                ovms::audio_utils::readMp3(buf, 8000);
            break;
        }
    } catch (const std::runtime_error&) {
        // The documented rejection of invalid audio; the HTTP layer turns it into a 400.
    }
    return 0;
}
