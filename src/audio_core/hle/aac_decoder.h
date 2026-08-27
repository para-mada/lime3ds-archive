// Copyright 2023 Citra Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include "audio_core/hle/decoder.h"

namespace AudioCore::HLE {

using NeAACDecHandle = void*;

class AACDecoder final : public DecoderBase {
public:
    explicit AACDecoder(Memory::MemorySystem& memory);
    ~AACDecoder() override;
    BinaryMessage ProcessRequest(const BinaryMessage& request) override;

private:
    void InitDecoder();
    BinaryMessage Decode(const BinaryMessage& request);

    Memory::MemorySystem& memory;
    NeAACDecHandle decoder = nullptr;
    bool decoder_initialized = false;
    unsigned long sample_rate = 48000;
    u8 num_channels = 2;
};

} // namespace AudioCore::HLE
