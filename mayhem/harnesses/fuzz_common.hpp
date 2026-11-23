// Shared setup for the OVMS fuzz harnesses: silence OVMS's spdlog loggers once, so per-input
// log lines don't dominate execution time. Done once at init; never changed afterwards.
#pragma once
#include <spdlog/spdlog.h>
static inline void ovms_fuzz_quiet_logs() {
    spdlog::set_level(spdlog::level::off);
    spdlog::apply_all([](std::shared_ptr<spdlog::logger> l) { l->set_level(spdlog::level::off); });
}
