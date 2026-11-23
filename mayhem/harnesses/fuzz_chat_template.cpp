// Fuzzes the chat-template handling OVMS applies to the Jinja chat template shipped inside a model
// directory (src/llm/io_processing/chat_template/): ChatTemplateAnalyzer::analyze (capability
// probing) and ChatTemplateAdjuster::adjust with both the minja and jinja configurations, which
// rewrite the template text before it is handed to the template engine.
#include <cstddef>
#include <cstdint>
#include <string>
#include "src/llm/io_processing/chat_template/analyzer.hpp"
#include "src/llm/io_processing/chat_template/adjuster.hpp"
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    ovms_fuzz_quiet_logs();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    std::string tmpl(reinterpret_cast<const char*>(data), size);
    (void)ovms::ChatTemplateAnalyzer::analyze(tmpl);
    static const ovms::ChatTemplateAdjuster minja(ovms::ChatTemplateAdjusterConfig::forMinja());
    static const ovms::ChatTemplateAdjuster jinja(ovms::ChatTemplateAdjusterConfig::forJinja());
    std::string a = tmpl;
    minja.adjust(a);
    std::string b = tmpl;
    jinja.adjust(b);
    return 0;
}
