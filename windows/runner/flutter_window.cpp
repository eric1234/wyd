#include "flutter_window.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <wtsapi32.h>

#include <optional>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"
#include "screen_retriever_windows/screen_retriever_windows_plugin_c_api.h"
#include "window_manager/window_manager_plugin.h"

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
  ConfigurePowerEventChannel();
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
  power_event_sink_.reset();
  if (power_event_channel_) {
    power_event_channel_->SetStreamHandler(nullptr);
    power_event_channel_.reset();
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
    case WM_POWERBROADCAST:
      if (wparam == PBT_APMSUSPEND) {
        SendPowerEvent("sleep");
      }
      break;
    case WM_WTSSESSION_CHANGE:
      if (wparam == WTS_SESSION_LOCK) {
        SendPowerEvent("lock");
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

void FlutterWindow::ConfigurePowerEventChannel() {
  auto* messenger = flutter_controller_->engine()->messenger();
  power_event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, "dev.wyd.tracker/power_events",
          &flutter::StandardMethodCodec::GetInstance());
  power_event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                     events)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            power_event_sink_ = std::move(events);
            return nullptr;
          },
          [this](const flutter::EncodableValue* arguments)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            power_event_sink_.reset();
            return nullptr;
          }));
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

void FlutterWindow::SendPowerEvent(const std::string& event) {
  if (!power_event_sink_) {
    return;
  }

  power_event_sink_->Success(flutter::EncodableValue(event));
}
