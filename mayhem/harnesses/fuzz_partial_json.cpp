// Fuzzes ovms::PartialJsonBuilder (src/llm/io_processing/partial_json_builder.cpp): the incremental
// JSON completer OVMS runs on streamed LLM tool-call arguments. Byte 0 picks how many chunks the
// rest is split into; each chunk is fed with add(), as the streaming output parsers do.
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include "src/llm/io_processing/partial_json_builder.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 1)
        return -1;
    size_t chunks = (data[0] % 8) + 1;
    std::string rest(reinterpret_cast<const char*>(data + 1), size - 1);
    ovms::PartialJsonBuilder builder;
    size_t step = rest.size() / chunks + 1;
    for (size_t off = 0; off < rest.size(); off += step) {
        try {
            builder.add(rest.substr(off, step));
        } catch (const std::exception&) {
            // add() documents std::runtime_error on malformed JSON; the parsers stop the stream there.
            break;
        }
    }
    return 0;
}
