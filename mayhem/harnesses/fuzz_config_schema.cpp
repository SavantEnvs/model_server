// Fuzzes the OVMS configuration JSON path (src/schema.cpp): the config file / mediapipe subconfig /
// mapping file is parsed with rapidjson and validated against OVMS's JSON schemas with
// validateJsonAgainstSchema, as ModelManager does before reading any model entry.
// Byte 0 selects the schema; the rest is the file content.
#include <cstddef>
#include <cstdint>
#include <string>
#include <rapidjson/document.h>
#include "src/schema.hpp"
#include "src/status.hpp"
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    ovms_fuzz_quiet_logs();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 1)
        return -1;
    std::string content(reinterpret_cast<const char*>(data + 1), size - 1);
    rapidjson::Document doc;
    // parseConfig() parses the file text as a NUL-terminated string the same way.
    if (doc.Parse(content.c_str()).HasParseError())
        return 0;
    const char* schema = nullptr;
    switch (data[0] % 4) {
    case 0: schema = ovms::MODELS_CONFIG_SCHEMA.c_str(); break;
    case 1: schema = ovms::MEDIAPIPE_SUBCONFIG_SCHEMA.c_str(); break;
    case 2: schema = ovms::MODELS_MAPPING_SCHEMA; break;
    case 3: schema = ovms::MODELS_CONFIG_SCHEMA.c_str(); break;
    }
    (void)ovms::validateJsonAgainstSchema(doc, schema, data[0] & 4);
    return 0;
}
