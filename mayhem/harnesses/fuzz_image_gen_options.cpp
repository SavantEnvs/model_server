// Fuzzes the /v3/images/generations request parser (src/image_gen/imagegenutils.cpp), in the order
// ImageGenCalculator::Process runs it on the untrusted JSON body (http_image_gen_calculator.cc:350-370):
// getPromptField, getImageGenerationRequestOptions (size/width/height, n, steps, strength, guidance,
// response_format, unknown-field rejection, lora_alphas, then ensureAcceptableAndDefaultsSetRequestOptions
// incl. the static-reshape checks), parseLoraAlphasOverride and validateLoraAlphasForModel.
// Byte 0 selects the node configuration (a graph setting, not request data); the rest is the JSON body.
// The pipeline args are built per input, so no state survives between inputs.
#include <cstddef>
#include <cstdint>
#include <string>
#include <variant>
#include <vector>
#include "src/image_gen/imagegenutils.hpp"
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    ovms_fuzz_quiet_logs();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 1)
        return -1;
    const uint8_t sel = data[0];
    std::string body(reinterpret_cast<const char*>(data + 1), size - 1);
    rapidjson::Document doc;
    doc.Parse(body.c_str());
    // The calculator rejects a body that fails to parse or is not an object before any parser runs
    // (http_image_gen_calculator.cc:350-355).
    if (doc.HasParseError() || !doc.IsObject())
        return 0;

    // Node configuration: the defaults of image_gen_calculator.proto (max_resolution 4096x4096,
    // max_num_images_per_prompt 10, default/max_num_inference_steps 50/100), with the optional
    // settings switched on by the selector byte.
    ovms::ImageGenPipelineArgs args;
    args.maxResolution = {4096, 4096};
    args.maxNumImagesPerPrompt = 10;
    args.defaultNumInferenceSteps = 50;
    args.maxNumInferenceSteps = 100;
    if (sel & 2)
        args.defaultResolution = ovms::resolution_t{512, 512};
    if (sel & 4)
        args.nativeResolution = ovms::resolution_t{1024, 1024};
    if (sel & 8)
        args.staticReshapeSettings = ovms::StaticReshapeSettingsArgs({{512, 512}, {1024, 768}}, 1, 7.5f);
    if (sel & 16)
        args.seed = 42;
    std::vector<std::string> aliases;
    if (sel & 32) {
        args.loraAdapters = {{"style", "/m/style.safetensors"}, {"detail", "/m/detail.safetensors", 0.5f}};
        args.compositeLoraAdapters["mix"] = {{"style", 0.7f}, {"detail", std::nullopt}};
        aliases = {"style", "detail", "mix"};
    }
    const bool hasDynamicAdapters = sel & 1;

    (void)ovms::getPromptField(doc);
    auto options = ovms::getImageGenerationRequestOptions(doc, args, hasDynamicAdapters);
    auto alphas = ovms::parseLoraAlphasOverride(doc);
    if (std::holds_alternative<ovms::LoraAlphaMap>(alphas)) {
        auto model = ovms::getStringFromPayload(doc, "model");
        std::string modelName;
        if (std::holds_alternative<std::optional<std::string>>(model) && std::get<std::optional<std::string>>(model))
            modelName = *std::get<std::optional<std::string>>(model);
        (void)ovms::validateLoraAlphasForModel(modelName, std::get<ovms::LoraAlphaMap>(alphas), aliases,
            args.compositeLoraAdapters);
    }
    return 0;
}
