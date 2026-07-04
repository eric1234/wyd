#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <wtsapi32.h>

#include <cstdio>
#include <memory>
#include <optional>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"
#include "screen_retriever_windows/screen_retriever_windows_plugin_c_api.h"
#include "window_manager/window_manager_plugin.h"

namespace {

constexpr DWORD kLifecycleAcknowledgementTimeoutMs = 5000;
constexpr DWORD kPowerEventAcknowledgementTimeoutMs = 1800;
constexpr DWORD kMessagePumpIntervalMs = 25;

struct MethodCallWaitState {
  bool completed = false;
};

std::string CurrentUtcIso8601() {
  SYSTEMTIME system_time;
  GetSystemTime(&system_time);

  char buffer[25];
  std::snprintf(buffer, sizeof(buffer), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
                static_cast<unsigned int>(system_time.wYear),
                static_cast<unsigned int>(system_time.wMonth),
                static_cast<unsigned int>(system_time.wDay),
                static_cast<unsigned int>(system_time.wHour),
                static_cast<unsigned int>(system_time.wMinute),
                static_cast<unsigned int>(system_time.wSecond),
                static_cast<unsigned int>(system_time.wMilliseconds));
  return std::string(buffer);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             UINT second_instance_message)
    : project_(project), second_instance_message_(second_instance_message) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  ConfigureSingleInstanceChannel();
  ConfigureLifecycleChannel();
  ConfigureAcknowledgedPowerEventChannel();
  RegisterPowerNotifications();
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    auto* registry = flutter_view_controller->engine();
    // Child windows must not register tray_manager. The tray belongs to the
    // primary process window; registering it in child engines can steal tray
    // menu events from the controller that handles Report/Settings/Exit.
    DesktopMultiWindowPluginRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("DesktopMultiWindowPlugin"));
    ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
    WindowManagerPluginRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("WindowManagerPlugin"));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Keep the resident window hidden at startup. Dart opens the quick-entry,
  // report, and settings roles explicitly when the tray app is ready.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  UnregisterPowerNotifications();
  power_events_ready_ = false;
  if (acknowledged_power_event_channel_) {
    acknowledged_power_event_channel_->SetMethodCallHandler(nullptr);
    acknowledged_power_event_channel_.reset();
  }
  lifecycle_ready_ = false;
  if (lifecycle_channel_) {
    lifecycle_channel_->SetMethodCallHandler(nullptr);
    lifecycle_channel_.reset();
  }
  if (single_instance_channel_) {
    single_instance_channel_->SetMethodCallHandler(nullptr);
    single_instance_channel_.reset();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                               WPARAM const wparam,
                               LPARAM const lparam) noexcept {
  if (second_instance_message_ != 0 && message == second_instance_message_) {
    NotifySecondInstanceActivated();
    return 0;
  }

  switch (message) {
    case WM_QUERYENDSESSION:
      return TRUE;
    case WM_ENDSESSION:
      if (wparam == TRUE) {
        RequestTerminationAndWait();
      }
      return 0;
    case WM_POWERBROADCAST:
      if (wparam == PBT_APMSUSPEND) {
        SendAcknowledgedPowerEventAndWait("sleep");
        return TRUE;
      }
      break;
    case WM_WTSSESSION_CHANGE:
      if (wparam == WTS_SESSION_LOCK) {
        SendAcknowledgedPowerEventAndWait("lock");
        return 0;
      }
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::ConfigureSingleInstanceChannel() {
  auto* messenger = flutter_controller_->engine()->messenger();
  single_instance_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "dev.wyd.tracker/single_instance",
          &flutter::StandardMethodCodec::GetInstance());
  single_instance_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "consumePendingActivation") {
          single_instance_ready_ = true;
          const bool pending = pending_second_instance_activation_;
          pending_second_instance_activation_ = false;
          result->Success(flutter::EncodableValue(pending));
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::ConfigureLifecycleChannel() {
  auto* messenger = flutter_controller_->engine()->messenger();
  lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "dev.wyd.tracker/lifecycle",
          &flutter::StandardMethodCodec::GetInstance());
  lifecycle_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "lifecycleReady") {
          lifecycle_ready_ = true;
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::ConfigureAcknowledgedPowerEventChannel() {
  auto* messenger = flutter_controller_->engine()->messenger();
  acknowledged_power_event_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "dev.wyd.tracker/power_events_ack",
          &flutter::StandardMethodCodec::GetInstance());
  acknowledged_power_event_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "powerEventsReady") {
          power_events_ready_ = true;
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::RegisterPowerNotifications() {
  power_notification_window_ = GetHandle();
  if (power_notification_window_ == nullptr) {
    return;
  }

  power_notifications_registered_ =
      WTSRegisterSessionNotification(power_notification_window_,
                                     NOTIFY_FOR_THIS_SESSION) != FALSE;
}

void FlutterWindow::UnregisterPowerNotifications() {
  if (!power_notifications_registered_ || power_notification_window_ == nullptr) {
    return;
  }

  WTSUnRegisterSessionNotification(power_notification_window_);
  power_notifications_registered_ = false;
  power_notification_window_ = nullptr;
}

void FlutterWindow::NotifySecondInstanceActivated() {
  pending_second_instance_activation_ = true;
  if (!single_instance_ready_ || !single_instance_channel_) {
    return;
  }

  single_instance_channel_->InvokeMethod(
      "secondInstanceActivated",
      std::make_unique<flutter::EncodableValue>());
  pending_second_instance_activation_ = false;
}

void FlutterWindow::RequestTerminationAndWait() {
  if (!lifecycle_ready_ || !lifecycle_channel_ ||
      termination_request_in_progress_) {
    return;
  }

  termination_request_in_progress_ = true;
  InvokeDartMethodAndWait(lifecycle_channel_.get(), "terminationRequested",
                          std::make_unique<flutter::EncodableValue>(),
                          kLifecycleAcknowledgementTimeoutMs);
  termination_request_in_progress_ = false;
}

void FlutterWindow::SendAcknowledgedPowerEventAndWait(
    const std::string& event) {
  if (!power_events_ready_ || !acknowledged_power_event_channel_ ||
      power_event_wait_in_progress_) {
    return;
  }

  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("event")] = flutter::EncodableValue(event);
  arguments[flutter::EncodableValue("occurredAtUtc")] =
      flutter::EncodableValue(CurrentUtcIso8601());

  power_event_wait_in_progress_ = true;
  InvokeDartMethodAndWait(
      acknowledged_power_event_channel_.get(), "powerEvent",
      std::make_unique<flutter::EncodableValue>(arguments),
      kPowerEventAcknowledgementTimeoutMs);
  power_event_wait_in_progress_ = false;
}

bool FlutterWindow::InvokeDartMethodAndWait(
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const std::string& method,
    std::unique_ptr<flutter::EncodableValue> arguments,
    DWORD timeout_ms) {
  if (channel == nullptr) {
    return false;
  }

  auto wait_state = std::make_shared<MethodCallWaitState>();
  channel->InvokeMethod(
      method, std::move(arguments),
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [wait_state](const flutter::EncodableValue*) {
            wait_state->completed = true;
          },
          [wait_state](const std::string&, const std::string&,
                       const flutter::EncodableValue*) {
            wait_state->completed = true;
          },
          [wait_state]() { wait_state->completed = true; }));

  const ULONGLONG deadline = GetTickCount64() + timeout_ms;
  bool repost_quit = false;
  WPARAM quit_wparam = 0;

  while (!wait_state->completed) {
    MSG message;
    while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        repost_quit = true;
        quit_wparam = message.wParam;
        wait_state->completed = true;
        break;
      }

      TranslateMessage(&message);
      DispatchMessage(&message);
      if (wait_state->completed) {
        break;
      }
    }

    if (wait_state->completed) {
      break;
    }

    const ULONGLONG now = GetTickCount64();
    if (now >= deadline) {
      break;
    }

    const ULONGLONG remaining = deadline - now;
    const DWORD wait_ms = remaining < kMessagePumpIntervalMs
                              ? static_cast<DWORD>(remaining)
                              : kMessagePumpIntervalMs;
    MsgWaitForMultipleObjectsEx(0, nullptr, wait_ms, QS_ALLINPUT,
                                MWMO_INPUTAVAILABLE);
  }

  if (repost_quit) {
    PostQuitMessage(static_cast<int>(quit_wparam));
  }

  return wait_state->completed;
}
