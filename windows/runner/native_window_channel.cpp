#include "native_window_channel.h"

#include <algorithm>
#include <thread>

void RegisterNativeWindowChannel(flutter::FlutterEngine* engine, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(),
      "oldchat/native_window",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window](const auto& call, auto result) {
        if (call.method_name() != "flashTaskbar") {
          result->NotImplemented();
          return;
        }
        int count = 3;
        if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
          const auto it = args->find(flutter::EncodableValue("count"));
          if (it != args->end()) {
            if (const auto* value = std::get_if<int32_t>(&it->second)) count = *value;
            if (const auto* value = std::get_if<int64_t>(&it->second)) count = static_cast<int>(*value);
          }
        }
        count = std::clamp(count, 1, 8);
        FLASHWINFO info{};
        info.cbSize = sizeof(FLASHWINFO);
        info.hwnd = window;
        info.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
        info.uCount = static_cast<UINT>(count * 2);
        info.dwTimeout = 250;
        FlashWindowEx(&info);
        result->Success();
      });
  channel.release();
}
