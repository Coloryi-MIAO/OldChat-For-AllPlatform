#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include "utils.h"
#include <dwmapi.h>
#include <shellapi.h>

#include "flutter_window.h"


void EnableModernWindowStyle(HWND hwnd) {

  LONG style = GetWindowLong(hwnd, GWL_STYLE);
  style &= ~WS_CAPTION;
  style |= WS_THICKFRAME;
  SetWindowLong(hwnd, GWL_STYLE, style);

  DWM_WINDOW_CORNER_PREFERENCE preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &preference, sizeof(preference));


  BOOL enableBlur = TRUE;
  DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &enableBlur, sizeof(enableBlur));
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"OldChat For AllPlatform", origin, size)) {
    return EXIT_FAILURE;
  }

  HWND hwnd = window.GetHandle();
  EnableModernWindowStyle(hwnd);

  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
