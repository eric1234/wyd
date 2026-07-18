#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <atomic>
#include <cstdint>
#include <deque>
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
  enum class NativeEventKind {
    kLock,
    kSleep,
    kTermination,
  };

  enum class NativeEventState {
    kPending,
    kAwaitingReply,
    kCompleted,
    kWaitExpired,
  };

  struct NativeEvent {
    NativeEvent(std::uint64_t event_id,
                NativeEventKind event_kind,
                std::string occurred_at,
                ULONGLONG event_deadline);

    const std::uint64_t id;
    const NativeEventKind kind;
    const std::string occurred_at_utc;
    const ULONGLONG deadline;
    std::atomic<NativeEventState> state{NativeEventState::kPending};
    std::atomic<bool> waiter_active{true};
  };

  struct CallbackContext {
    CallbackContext() noexcept { InitializeSRWLock(&lock); }

    SRWLOCK lock{};
    HWND window = nullptr;
    UINT_PTR generation = 0;
    bool valid = false;
  };

  void ConfigureSingleInstanceChannel();
  void ConfigureLifecycleChannel();
  void ConfigureAcknowledgedPowerEventChannel();
  void RegisterSessionNotifications();
  void TryRegisterSessionNotifications();
  void ScheduleSessionNotificationRegistrationRetry();
  void CancelSessionNotificationRegistrationRetry();
  void UnregisterSessionNotifications();
  static void CALLBACK OnTerminalServicesReady(void* context,
                                                BOOLEAN timed_out);
  static bool PostCallbackMessage(
      const std::shared_ptr<CallbackContext>& context,
      UINT message,
      UINT_PTR generation) noexcept;
  void NotifySecondInstanceActivated();
  void EnqueueNativeEventAndWait(NativeEventKind kind, DWORD timeout_ms);
  void DrainNativeEvents();
  void ExpireNativeEventsBefore(const std::shared_ptr<NativeEvent>& event);
  bool ShouldStopNativeEventWait(
      const std::shared_ptr<NativeEvent>& event,
      ULONGLONG now);
  bool WaitForNativeEvent(const std::shared_ptr<NativeEvent>& event) noexcept;
  void PostNativeEventDrain() const noexcept;

  // The project to run.
  flutter::DartProject project_;

  // Message broadcast by a later process when the app is already running.
  UINT second_instance_message_ = 0;

  bool single_instance_ready_ = false;
  bool pending_second_instance_activation_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      single_instance_channel_;

  bool lifecycle_ready_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      lifecycle_channel_;

  bool power_events_ready_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      acknowledged_power_event_channel_;

  std::deque<std::shared_ptr<NativeEvent>> native_events_;
  std::uint64_t next_native_event_id_ = 1;
  unsigned int wait_pump_depth_ = 0;
  ULONGLONG earliest_wait_deadline_ = 0;
  bool quit_consumed_ = false;
  bool quit_reposted_ = false;
  WPARAM quit_wparam_ = 0;
  bool tearing_down_ = false;
  UINT_PTR callback_generation_ = 0;
  std::shared_ptr<CallbackContext> callback_context_;

  HWND session_notification_window_ = nullptr;
  bool session_notifications_registered_ = false;
  bool terminal_services_ready_event_observed_ = false;
  HANDLE terminal_services_ready_event_ = nullptr;
  HANDLE terminal_services_ready_wait_ = nullptr;
  UINT_PTR session_notification_retry_timer_id_ = 0;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
