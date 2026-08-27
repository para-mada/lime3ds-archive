#include <algorithm>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <memory>
#include <string_view>
#include <thread>
#include <windows.h>
#include <psapi.h>

#include "common/threadsafe_queue.h"
#include "core/rpc/packet.h"

namespace {
void PrintMemory(const char* phase, std::size_t queue_size) {
    PROCESS_MEMORY_COUNTERS_EX counters{};
    counters.cb = sizeof(counters);
    GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters),
                         sizeof(counters));
    constexpr double MiB = 1024.0 * 1024.0;
    std::cout << std::left << std::setw(18) << phase << " queue=" << std::setw(8) << queue_size
              << " private_mib=" << std::fixed << std::setprecision(2)
              << counters.PrivateUsage / MiB << " working_set_mib="
              << counters.WorkingSetSize / MiB << '\n';
}
} // namespace

int main(int argc, char** argv) {
    const std::size_t count = argc > 1 ? std::stoull(argv[1]) : 100000;
    const bool bounded = argc > 2 && std::string_view{argv[2]} == "bounded";
    constexpr std::size_t QueueCapacity = 256;
    Common::SPSCQueue<std::unique_ptr<Core::RPC::Packet>> queue;
    Core::RPC::PacketHeader header{Core::RPC::CURRENT_VERSION, 1,
                                   Core::RPC::PacketType::ReadMemory, 8};
    std::array<u8, Core::RPC::MAX_PACKET_DATA_SIZE> data{};
    const auto noop = [](Core::RPC::Packet&) {};

    std::cout << "sizeof(Packet)=" << sizeof(Core::RPC::Packet)
              << " max_packet_data=" << Core::RPC::MAX_PACKET_DATA_SIZE << '\n';
    PrintMemory("baseline", queue.Size());

    const std::size_t interval = std::max<std::size_t>(count / 10, 1);
    std::size_t dropped = 0;
    for (std::size_t i = 0; i < count; ++i) {
        if (bounded && queue.Size() >= QueueCapacity) {
            ++dropped;
        } else {
            queue.Push(std::make_unique<Core::RPC::Packet>(header, data.data(), noop));
        }
        if ((i + 1) % interval == 0) {
            PrintMemory("enqueue", queue.Size());
        }
    }
    PrintMemory("full", queue.Size());
    std::cout << "accepted=" << queue.Size() << " dropped=" << dropped << '\n';

    std::unique_ptr<Core::RPC::Packet> packet;
    while (queue.Pop(packet)) {
    }
    packet.reset();
    PrintMemory("drained", queue.Size());
    std::this_thread::sleep_for(std::chrono::seconds(2));
    PrintMemory("after_2s", queue.Size());
}
