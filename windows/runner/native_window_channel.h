#ifndef RUNNER_NATIVE_WINDOW_CHANNEL_H_
#define RUNNER_NATIVE_WINDOW_CHANNEL_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

void RegisterNativeWindowChannel(
    flutter::FlutterEngine* engine,
    HWND window);

#endif
