#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <wtsapi32.h>

#include <atomic>
#include <cstdio>
#include <memory>
#include <optional>
#include <utility>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"
#include "screen_retriever_windows/screen_retriever_windows_plugin_c_api.h"
#include "url_launcher_windows/url_launcher_windows.h"
#include "window_manager/window_manager_plugin.h"

namespace {

constexpr DWORD kLifecycleAcknowledgementTimeoutMs = 4000;
constexpr DWORD kPowerEventAcknowledgementTimeoutMs = 1800;
constexpr UINT kDrainNativeEventsMessage = WM_APP + 0x37;
constexpr UINT_PTR kSessionNotificationRetryTimerId = 0x57594401;
constexpr UINT kSessionNotificationRetryIntervalMs = 1000;
constexpr unsigned int kSessionNotificationRetryLimit = 10;

std::atomic<UINT_PTR> g_next_callback_generation{1};

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

void LogWindowsError(const char* operation, DWORD error) noexcept {
  char buffer[192];
  const int length = std::snprintf(
      buffer, sizeof(buffer), "wyd: %s failed with Windows error %lu.\n",
      operation, static_cast<unsigned long>(error));
  if (length > 0) {
    OutputDebugStringA(buffer);
  }
}

}  // namespace

FlutterWindow::NativeEvent::NativeEvent(std::uint64_t event_id,
                                        NativeEventKind event_kind,
                                        std::string occurred_at,
                                        ULONGLONG event_deadline)
    : id(event_id),
      kind(event_kind),
      occurred_at_utc(std::move(occurred_at)),
      deadline(event_deadline) {}

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

  tearing_down_ = false;
  callback_generation_ = g_next_callback_generation.fetch_add(1);
  drain_target_ =
      std::make_shared<DrainTarget>(GetHandle(), callback_generation_);

  RegisterPlugins(flutter_controller_->engine());
  ConfigureSingleInstanceChannel();
  ConfigureLifecycleEventsChannel();
  RegisterSessionNotifications();
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
    UrlLauncherWindowsRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("UrlLauncherWindows"));
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
  tearing_down_ = true;
  if (drain_target_) {
    drain_target_->window.store(nullptr);
  }
  callback_generation_ = 0;

  UnregisterSessionNotifications();
  native_events_.clear();
  lifecycle_events_ready_ = false;
  if (lifecycle_events_channel_) {
    lifecycle_events_channel_->SetMethodCallHandler(nullptr);
    lifecycle_events_channel_.reset();
  }
  if (single_instance_channel_) {
    single_instance_channel_->SetMethodCallHandler(nullptr);
    single_instance_channel_.reset();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  drain_target_.reset();
  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                               WPARAM const wparam,
                               LPARAM const lparam) noexcept {
  if (message == WM_QUERYENDSESSION) {
    return TRUE;
  }
  if (message == WM_ENDSESSION && wparam == FALSE) {
    return 0;
  }

  try {
    if (second_instance_message_ != 0 && message == second_instance_message_) {
      NotifySecondInstanceActivated();
      return 0;
    }

    switch (message) {
      case kDrainNativeEventsMessage:
        if (wparam == callback_generation_ && !tearing_down_) {
          DrainNativeEvents();
        }
        return 0;
      case WM_TIMER:
        if (session_notification_retry_timer_id_ != 0 &&
            wparam == session_notification_retry_timer_id_) {
          if (KillTimer(session_notification_window_,
                        session_notification_retry_timer_id_) == FALSE) {
            LogWindowsError("KillTimer(session notification retry)",
                            GetLastError());
          }
          session_notification_retry_timer_id_ = 0;
          TryRegisterSessionNotifications();
          return 0;
        }
        break;
      case WM_ENDSESSION:
        EnqueueNativeEventAndWait(NativeEventKind::kTermination,
                                  kLifecycleAcknowledgementTimeoutMs);
        return 0;
      case WM_POWERBROADCAST:
        if (wparam == PBT_APMSUSPEND) {
          EnqueueNativeEventAndWait(NativeEventKind::kSleep,
                                    kPowerEventAcknowledgementTimeoutMs);
          return TRUE;
        }
        break;
      case WM_WTSSESSION_CHANGE:
        if (wparam == WTS_SESSION_LOCK) {
          EnqueueNativeEventAndWait(NativeEventKind::kLock,
                                    kPowerEventAcknowledgementTimeoutMs);
          return 0;
        }
        break;
    }

    // Give Flutter, including plugins, an opportunity to handle window
    // messages.
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
  } catch (...) {
    OutputDebugStringA("wyd: window message handling failed open.\n");
    switch (message) {
      case WM_ENDSESSION:
        return 0;
      case WM_POWERBROADCAST:
        if (wparam == PBT_APMSUSPEND) {
          return TRUE;
        }
        break;
      case WM_WTSSESSION_CHANGE:
        if (wparam == WTS_SESSION_LOCK) {
          return 0;
        }
        break;
      case kDrainNativeEventsMessage:
        return 0;
      case WM_TIMER:
        if (session_notification_retry_timer_id_ != 0 &&
            wparam == session_notification_retry_timer_id_) {
          return 0;
        }
        break;
    }

    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }
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

void FlutterWindow::ConfigureLifecycleEventsChannel() {
  auto* messenger = flutter_controller_->engine()->messenger();
  lifecycle_events_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "dev.wyd.tracker/lifecycle_events",
          &flutter::StandardMethodCodec::GetInstance());
  lifecycle_events_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "lifecycleEventsReady") {
          lifecycle_events_ready_ = true;
          result->Success();
          PostNativeEventDrain();
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::RegisterSessionNotifications() {
  session_notification_window_ = GetHandle();
  if (session_notification_window_ != nullptr) {
    TryRegisterSessionNotifications();
  }
}

void FlutterWindow::TryRegisterSessionNotifications() {
  if (tearing_down_ || session_notifications_registered_ ||
      session_notification_window_ == nullptr) {
    return;
  }

  const BOOL registered = WTSRegisterSessionNotification(
      session_notification_window_, NOTIFY_FOR_THIS_SESSION);
  const DWORD error = registered == FALSE ? GetLastError() : ERROR_SUCCESS;
  if (registered != FALSE) {
    session_notifications_registered_ = true;
    CancelSessionNotificationRegistrationRetry();
    OutputDebugStringA("wyd: session notifications registered.\n");
    return;
  }

  if (error == RPC_S_INVALID_BINDING) {
    ScheduleSessionNotificationRegistrationRetry();
    return;
  }

  CancelSessionNotificationRegistrationRetry();
  LogWindowsError("WTSRegisterSessionNotification", error);
}

void FlutterWindow::ScheduleSessionNotificationRegistrationRetry() {
  if (tearing_down_ || session_notification_retry_timer_id_ != 0 ||
      session_notification_window_ == nullptr) {
    return;
  }

  if (session_notification_retry_count_ >=
      kSessionNotificationRetryLimit) {
    OutputDebugStringA(
        "wyd: session notification registration retries exhausted.\n");
    return;
  }

  session_notification_retry_timer_id_ =
      SetTimer(session_notification_window_,
               kSessionNotificationRetryTimerId,
               kSessionNotificationRetryIntervalMs, nullptr);
  if (session_notification_retry_timer_id_ == 0) {
    const DWORD error = GetLastError();
    LogWindowsError("SetTimer(session notification retry)", error);
  } else {
    ++session_notification_retry_count_;
    OutputDebugStringA(
        "wyd: session notification registration retry scheduled.\n");
  }
}

void FlutterWindow::CancelSessionNotificationRegistrationRetry() {
  if (session_notification_retry_timer_id_ != 0 &&
      session_notification_window_ != nullptr) {
    if (KillTimer(session_notification_window_,
                  session_notification_retry_timer_id_) == FALSE) {
      LogWindowsError("KillTimer(session notification retry)", GetLastError());
    }
    session_notification_retry_timer_id_ = 0;
  }
}

void FlutterWindow::UnregisterSessionNotifications() {
  CancelSessionNotificationRegistrationRetry();

  if (session_notifications_registered_ &&
      session_notification_window_ != nullptr) {
    const BOOL unregistered =
        WTSUnRegisterSessionNotification(session_notification_window_);
    const DWORD error = unregistered == FALSE ? GetLastError() : ERROR_SUCCESS;
    if (unregistered == FALSE) {
      LogWindowsError("WTSUnRegisterSessionNotification", error);
    }
    session_notifications_registered_ = false;
  }

  session_notification_window_ = nullptr;
  session_notification_retry_count_ = 0;
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

void FlutterWindow::EnqueueNativeEventAndWait(NativeEventKind kind,
                                               DWORD timeout_ms) {
  const ULONGLONG received_at = GetTickCount64();
  auto event = std::make_shared<NativeEvent>(
      next_native_event_id_++, kind, CurrentUtcIso8601(),
      received_at + timeout_ms);
  if (kind == NativeEventKind::kTermination) {
    for (const auto& pending : native_events_) {
      pending->waiter_active.store(false);
      NativeEventState state = pending->state.load();
      while (state == NativeEventState::kPending ||
             state == NativeEventState::kAwaitingReply) {
        if (pending->state.compare_exchange_weak(
                state, NativeEventState::kWaitExpired)) {
          break;
        }
      }
    }
    native_events_.push_front(event);
  } else {
    native_events_.push_back(event);
  }
  PostNativeEventDrain();
  WaitForNativeEvent(event);
}

void FlutterWindow::DrainNativeEvents() {
  if (tearing_down_) {
    return;
  }

  while (!native_events_.empty()) {
    const auto event = native_events_.front();
    const NativeEventState state = event->state.load();
    if (state == NativeEventState::kCompleted ||
        state == NativeEventState::kWaitExpired) {
      native_events_.pop_front();
      continue;
    }
    if (state == NativeEventState::kAwaitingReply) {
      return;
    }

    if (!lifecycle_events_ready_ || !lifecycle_events_channel_) {
      return;
    }

    NativeEventState expected = NativeEventState::kPending;
    if (!event->state.compare_exchange_strong(
            expected, NativeEventState::kAwaitingReply)) {
      continue;
    }

    try {
      flutter::EncodableMap arguments;
      arguments[flutter::EncodableValue("kind")] = flutter::EncodableValue(
          event->kind == NativeEventKind::kTermination
              ? "termination"
              : event->kind == NativeEventKind::kLock ? "lock" : "sleep");
      arguments[flutter::EncodableValue("occurredAtUtc")] =
          flutter::EncodableValue(event->occurred_at_utc);

      const auto drain_target = drain_target_;
      const auto complete = [event, drain_target]() noexcept {
        NativeEventState awaiting = NativeEventState::kAwaitingReply;
        if (!event->state.compare_exchange_strong(
                awaiting, NativeEventState::kCompleted)) {
          return;
        }
        const HWND window = drain_target->window.load();
        if (window != nullptr) {
          PostMessage(window, kDrainNativeEventsMessage,
                      drain_target->generation, 0);
        }
      };

      lifecycle_events_channel_->InvokeMethod(
          "lifecycleEvent",
          std::make_unique<flutter::EncodableValue>(arguments),
          std::make_unique<
              flutter::MethodResultFunctions<flutter::EncodableValue>>(
              [complete](const flutter::EncodableValue*) { complete(); },
              [complete](const std::string&, const std::string&,
                         const flutter::EncodableValue*) { complete(); },
              [complete]() { complete(); }));
    } catch (...) {
      NativeEventState awaiting = NativeEventState::kAwaitingReply;
      event->state.compare_exchange_strong(
          awaiting, NativeEventState::kWaitExpired);
      OutputDebugStringA("wyd: native event invocation failed open.\n");
      PostNativeEventDrain();
      return;
    }

    if (!event->waiter_active.load() || GetTickCount64() >= event->deadline) {
      NativeEventState awaiting = NativeEventState::kAwaitingReply;
      if (event->state.compare_exchange_strong(
              awaiting, NativeEventState::kWaitExpired)) {
        PostNativeEventDrain();
      }
    }
    return;
  }
}

void FlutterWindow::ExpireNativeEventsBefore(
    const std::shared_ptr<NativeEvent>& event) {
  for (const auto& candidate : native_events_) {
    if (candidate == event) {
      break;
    }

    candidate->waiter_active.store(false);
    NativeEventState state = candidate->state.load();
    while (state == NativeEventState::kPending ||
           state == NativeEventState::kAwaitingReply) {
      if (candidate->state.compare_exchange_weak(
              state, NativeEventState::kWaitExpired)) {
        break;
      }
    }
  }
}

bool FlutterWindow::ShouldStopNativeEventWait(
    const std::shared_ptr<NativeEvent>& event,
    ULONGLONG now) {
  if (now < earliest_wait_deadline_) {
    return false;
  }
  if (event->kind != NativeEventKind::kTermination ||
      now >= event->deadline || earliest_wait_deadline_ >= event->deadline) {
    return true;
  }

  ExpireNativeEventsBefore(event);
  DrainNativeEvents();
  earliest_wait_deadline_ = event->deadline;
  return false;
}

bool FlutterWindow::WaitForNativeEvent(
    const std::shared_ptr<NativeEvent>& event) noexcept {
  const ULONGLONG previous_deadline = earliest_wait_deadline_;
  if (earliest_wait_deadline_ == 0 ||
      event->deadline < earliest_wait_deadline_) {
    earliest_wait_deadline_ = event->deadline;
  }
  const bool outermost_wait = wait_pump_depth_ == 0;
  ++wait_pump_depth_;

  bool stop_waiting = quit_reposted_;
  while (!stop_waiting && !tearing_down_) {
    const NativeEventState state = event->state.load();
    if (state == NativeEventState::kCompleted ||
        state == NativeEventState::kWaitExpired || quit_consumed_) {
      break;
    }

    ULONGLONG now = GetTickCount64();
    if (ShouldStopNativeEventWait(event, now)) {
      break;
    }

    MSG pending_message{};
    if (PeekMessage(&pending_message, nullptr, 0, 0, PM_NOREMOVE)) {
      if (ShouldStopNativeEventWait(event, GetTickCount64())) {
        break;
      }
      if (!PeekMessage(&pending_message, nullptr, 0, 0, PM_REMOVE)) {
        continue;
      }
      if (pending_message.message == WM_QUIT) {
        if (!quit_consumed_) {
          quit_consumed_ = true;
          quit_wparam_ = pending_message.wParam;
        }
        break;
      }

      TranslateMessage(&pending_message);
      DispatchMessage(&pending_message);
      now = GetTickCount64();
      if (ShouldStopNativeEventWait(event, now)) {
        break;
      }
      continue;
    }

    now = GetTickCount64();
    if (ShouldStopNativeEventWait(event, now)) {
      break;
    }
    const ULONGLONG remaining = earliest_wait_deadline_ - now;
    const DWORD wait_ms = static_cast<DWORD>(remaining);
    const DWORD wait_result = MsgWaitForMultipleObjectsEx(
        0, nullptr, wait_ms, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    if (wait_result == WAIT_FAILED) {
      stop_waiting = true;
    }
  }

  event->waiter_active.store(false);
  NativeEventState awaiting = NativeEventState::kAwaitingReply;
  if (event->state.compare_exchange_strong(
          awaiting, NativeEventState::kWaitExpired)) {
    PostNativeEventDrain();
  }

  --wait_pump_depth_;
  earliest_wait_deadline_ = previous_deadline;
  if (outermost_wait && quit_consumed_ && !quit_reposted_) {
    quit_reposted_ = true;
    PostQuitMessage(static_cast<int>(quit_wparam_));
  }

  return event->state.load() == NativeEventState::kCompleted;
}

void FlutterWindow::PostNativeEventDrain() const noexcept {
  if (!tearing_down_ && drain_target_) {
    const HWND window = drain_target_->window.load();
    if (window != nullptr) {
      PostMessage(window, kDrainNativeEventsMessage,
                  drain_target_->generation, 0);
    }
  }
}
