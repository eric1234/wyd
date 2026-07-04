#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         UINT second_instance_message = 0);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void ConfigureSingleInstanceChannel();
  void ConfigureLifecycleChannel();
  void ConfigureAcknowledgedPowerEventChannel();
  void RegisterPowerNotifications();
  void UnregisterPowerNotifications();
  void NotifySecondInstanceActivated();
  void RequestTerminationAndWait();
  void SendAcknowledgedPowerEventAndWait(const std::string& event);
  bool InvokeDartMethodAndWait(
      flutter::MethodChannel<flutter::EncodableValue>* channel,
      const std::string& method,
      std::unique_ptr<flutter::EncodableValue> arguments,
      DWORD timeout_ms);

  // The project to run.
  flutter::DartProject project_;

  // Message broadcast by a later process when the app is already running.
  UINT second_instance_message_ = 0;

  bool single_instance_ready_ = false;
  bool pending_second_instance_activation_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      single_instance_channel_;

  bool lifecycle_ready_ = false;
  bool termination_request_in_progress_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      lifecycle_channel_;

  bool power_events_ready_ = false;
  bool power_event_wait_in_progress_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      acknowledged_power_event_channel_;
  HWND power_notification_window_ = nullptr;
  bool power_notifications_registered_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
