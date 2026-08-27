#include <algorithm>
#include <iomanip>
#include <iostream>
#include <string_view>
#include <windows.h>
#include <psapi.h>

#include <neaacdec.h>

namespace {
void PrintMemory(const char* phase, std::size_t iterations) {
    PROCESS_MEMORY_COUNTERS_EX counters{};
    counters.cb = sizeof(counters);
    GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters),
                         sizeof(counters));
    constexpr double MiB = 1024.0 * 1024.0;
    std::cout << std::left << std::setw(18) << phase << " iterations=" << std::setw(8)
              << iterations << " private_mib=" << std::fixed << std::setprecision(2)
              << counters.PrivateUsage / MiB << " working_set_mib="
              << counters.WorkingSetSize / MiB << '\n';
}
} // namespace

int main(int argc, char** argv) {
    const std::size_t count = argc > 1 ? std::stoull(argv[1]) : 5000;
    const bool close_before_reinit = argc > 2 && std::string_view{argv[2]} == "close-reopen";
    const bool initialize_once = argc > 2 && std::string_view{argv[2]} == "init-once";
    // Seven-byte ADTS header: AAC-LC, 44.1 kHz, stereo, frame length 7.
    unsigned char adts[] = {0xFF, 0xF1, 0x50, 0x80, 0x00, 0xFF, 0xFC};
    NeAACDecHandle decoder = NeAACDecOpen();
    if (!decoder) {
        std::cerr << "NeAACDecOpen failed\n";
        return 1;
    }

    PrintMemory("baseline", 0);
    const std::size_t interval = std::max<std::size_t>(count / 10, 1);
    for (std::size_t i = 0; i < count; ++i) {
        if (close_before_reinit && i != 0) {
            NeAACDecClose(decoder);
            decoder = NeAACDecOpen();
            if (!decoder) {
                std::cerr << "NeAACDecOpen failed at iteration " << i << '\n';
                return 3;
            }
        }
        if (!initialize_once || i == 0) {
            unsigned long sample_rate{};
            unsigned char channels{};
            const long result =
                NeAACDecInit(decoder, adts, sizeof(adts), &sample_rate, &channels);
            if (result < 0) {
                std::cerr << "NeAACDecInit failed at iteration " << i << '\n';
                NeAACDecClose(decoder);
                return 2;
            }
        }
        if ((i + 1) % interval == 0) {
            PrintMemory("reinitialize", i + 1);
        }
    }
    PrintMemory("before_close", count);
    NeAACDecClose(decoder);
    PrintMemory("after_close", count);
}
