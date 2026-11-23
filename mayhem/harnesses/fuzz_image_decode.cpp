// Fuzzes ovms::image_utils::decodeImage (src/image_utils/image_decoder.cpp): the decoder behind
// KServe binary image inputs and OpenAI image_url/base64 content. The stb_image backend is used
// (the optional OpenCV plugin is not shipped), decoding into an NHWC ov::Tensor.
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <openvino/runtime/tensor.hpp>
#include "src/image_utils/image_decoder.hpp"
#include "src/status.hpp"
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    ovms_fuzz_quiet_logs();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    std::string_view buf(reinterpret_cast<const char*>(data), size);
    ov::Tensor tensor;
    ovms::Status st = ovms::image_utils::decodeImage(buf, tensor, ovms::image_utils::ImageDecoder::STB);
    if (st.ok()) {
        // Touch every decoded byte so a short allocation behind the reported shape is caught.
        volatile uint8_t sink = 0;
        const uint8_t* p = static_cast<const uint8_t*>(tensor.data());
        for (size_t i = 0; i < tensor.get_byte_size(); ++i)
            sink ^= p[i];
        (void)sink;
    }
    return 0;
}
