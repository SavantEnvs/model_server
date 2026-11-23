// Fuzzes the /v3/tokenize request parser (src/tokenize/tokenize_parser.cpp):
// TokenizeParser::validateTokenizeRequest — the "text"/"tokens" input shapes (string, batch,
// token ids, nested arrays), max_length/pad/padding_side parameters — and TokenizeParser::parseInput,
// which the embeddings ("input") and rerank ("documents") handlers share.
// Byte 0 selects the model-length limit and the field; the rest is the JSON request body.
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include "src/tokenize/tokenize_parser.hpp"
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    ovms_fuzz_quiet_logs();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 1)
        return -1;
    uint8_t sel = data[0];
    std::string body(reinterpret_cast<const char*>(data + 1), size - 1);
    rapidjson::Document doc;
    doc.Parse(body.c_str());
    // HttpRestApiHandler rejects bodies that are not a JSON object before any endpoint parser runs
    // (src/http_rest_api_handler.cpp:86).
    if (doc.HasParseError() || !doc.IsObject())
        return 0;
    std::optional<size_t> maxModelLength;
    if (sel & 1)
        maxModelLength = 16u << ((sel >> 1) & 7);
    (void)ovms::TokenizeParser::validateTokenizeRequest(doc, maxModelLength);
    static const char* const fields[] = {"text", "input", "documents", "tokens"};
    (void)ovms::TokenizeParser::parseInput(doc, fields[(sel >> 4) & 3]);
    return 0;
}
