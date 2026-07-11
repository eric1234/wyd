#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <screen_retriever_linux/screen_retriever_linux_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>
#include <window_manager/window_manager_plugin.h>

#include "flutter/generated_plugin_registrant.h"

struct LinuxWindowAttentionTarget {
  GtkWindow* window;
  FlView* view;
};

constexpr int kChildWindowInitialWidth = 380;
constexpr int kChildWindowInitialHeight = 340;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* single_instance_channel;
  FlMethodChannel* linux_window_attention_channel;
  LinuxWindowAttentionTarget primary_attention_target;
  gboolean pending_second_instance_activation;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void single_instance_method_call_cb(FlMethodChannel* channel,
                                           FlMethodCall* method_call,
                                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "consumePendingActivation") == 0) {
    gboolean pending = self->pending_second_instance_activation;
    self->pending_second_instance_activation = FALSE;
    g_autoptr(FlValue) result = fl_value_new_bool(pending);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

static gboolean present_window_for_input(LinuxWindowAttentionTarget* target) {
  if (target == nullptr || target->window == nullptr) {
    return FALSE;
  }

  GtkWindow* window = target->window;
  GtkWidget* window_widget = GTK_WIDGET(window);
  gtk_window_set_accept_focus(window, TRUE);
  gtk_window_set_focus_on_map(window, TRUE);
  gtk_window_set_urgency_hint(window, FALSE);

  if (!gtk_widget_get_realized(window_widget)) {
    gtk_widget_realize(window_widget);
  }

  gtk_window_deiconify(window);
  gtk_widget_show(window_widget);

#ifdef GDK_WINDOWING_X11
  GdkWindow* gdk_window = gtk_widget_get_window(window_widget);
  if (gdk_window != nullptr && GDK_IS_X11_WINDOW(gdk_window)) {
    GdkEventMask events = gdk_window_get_events(gdk_window);
    gdk_window_set_events(
        gdk_window,
        static_cast<GdkEventMask>(events | GDK_PROPERTY_CHANGE_MASK));
    guint32 timestamp = gdk_x11_get_server_time(gdk_window);
    gdk_x11_window_set_user_time(gdk_window, timestamp);
    gtk_window_present_with_time(window, timestamp);
  } else {
    gtk_window_present(window);
  }
#else
  gtk_window_present(window);
#endif

  if (target->view != nullptr) {
    gtk_widget_grab_focus(GTK_WIDGET(target->view));
  }

  return TRUE;
}

static void set_window_urgent(LinuxWindowAttentionTarget* target,
                              gboolean urgent) {
  if (target == nullptr || target->window == nullptr) {
    return;
  }

  gtk_window_set_urgency_hint(target->window, urgent);
}

static void linux_window_attention_method_call_cb(FlMethodChannel* channel,
                                                  FlMethodCall* method_call,
                                                  gpointer user_data) {
  LinuxWindowAttentionTarget* target =
      static_cast<LinuxWindowAttentionTarget*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "presentForInput") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(present_window_for_input(target));
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_strcmp0(method, "setUrgent") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* urgent_value =
        args != nullptr ? fl_value_lookup_string(args, "urgent") : nullptr;
    gboolean urgent =
        urgent_value != nullptr ? fl_value_get_bool(urgent_value) : FALSE;
    set_window_urgent(target, urgent);

    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

static FlMethodChannel* register_linux_window_attention_channel(
    FlBinaryMessenger* messenger,
    LinuxWindowAttentionTarget* target,
    GDestroyNotify target_destroy_notify) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, "dev.wyd.tracker/linux_window_attention",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, linux_window_attention_method_call_cb, target,
      target_destroy_notify);
  return channel;
}

static void register_child_linux_window_attention_channel(
    FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry,
                                                  "WydLinuxWindowAttention");
  FlView* view = fl_plugin_registrar_get_view(registrar);
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!GTK_IS_WINDOW(toplevel)) {
    return;
  }

  LinuxWindowAttentionTarget* target = g_new0(LinuxWindowAttentionTarget, 1);
  target->window = GTK_WINDOW(toplevel);
  target->view = view;

  FlMethodChannel* channel = register_linux_window_attention_channel(
      fl_plugin_registrar_get_messenger(registrar), target, g_free);
  g_object_set_data_full(G_OBJECT(view), "wyd-linux-window-attention-channel",
                         channel, g_object_unref);
}

static void override_child_window_default_size(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry,
                                                  "WydChildWindowDefaults");
  FlView* view = fl_plugin_registrar_get_view(registrar);
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!GTK_IS_WINDOW(toplevel)) {
    return;
  }

  GtkWindow* window = GTK_WINDOW(toplevel);
  // desktop_multi_window defaults every Linux child to 1280x720. Use the
  // smallest role size as a hidden fallback; Dart applies the actual role size
  // before showing the child.
  gtk_window_set_default_size(window, kChildWindowInitialWidth,
                              kChildWindowInitialHeight);
  gtk_window_resize(window, kChildWindowInitialWidth,
                    kChildWindowInitialHeight);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  if (gtk_application_get_windows(GTK_APPLICATION(application)) != nullptr) {
    self->pending_second_instance_activation = TRUE;
    if (self->single_instance_channel != nullptr) {
      fl_method_channel_invoke_method(self->single_instance_channel,
                                      "secondInstanceActivated", nullptr,
                                      nullptr, nullptr, nullptr);
    }
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->primary_attention_target.window = window;

  // Use the bundled logo for Linux window switchers and docks.
  g_autofree gchar* executable_path =
      g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path != nullptr) {
    g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
    g_autofree gchar* icon_path =
        g_build_filename(executable_dir, "data", "flutter_assets", "assets",
                         "app_icon.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      (void)gtk_window_set_icon_from_file(window, icon_path, nullptr);
    }
  }

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "wyd");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "wyd");
  }

  // This app is tray-first, so its first visible window is usually the compact
  // quick-entry popup. Dart-side role configuration resizes report/settings.
  gtk_window_set_default_size(window, 560, 440);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->primary_attention_target.view = view;
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Keep the GTK window hidden at startup. Dart-side window coordination will
  // explicitly show role windows after tray/menu actions.
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(
      [](FlPluginRegistry* registry) {
        override_child_window_default_size(registry);

        // Child windows must not register tray_manager. The tray belongs to the
        // primary process window; registering it in child engines can steal tray
        // menu events from the controller that handles Report/Settings/Exit.
        g_autoptr(FlPluginRegistrar) desktop_multi_window_registrar =
            fl_plugin_registry_get_registrar_for_plugin(
                registry, "DesktopMultiWindowPlugin");
        desktop_multi_window_plugin_register_with_registrar(
            desktop_multi_window_registrar);

        g_autoptr(FlPluginRegistrar) screen_retriever_registrar =
            fl_plugin_registry_get_registrar_for_plugin(
                registry, "ScreenRetrieverLinuxPlugin");
        screen_retriever_linux_plugin_register_with_registrar(
            screen_retriever_registrar);

        g_autoptr(FlPluginRegistrar) url_launcher_registrar =
            fl_plugin_registry_get_registrar_for_plugin(registry,
                                                        "UrlLauncherPlugin");
        url_launcher_plugin_register_with_registrar(url_launcher_registrar);

        g_autoptr(FlPluginRegistrar) window_manager_registrar =
            fl_plugin_registry_get_registrar_for_plugin(
                registry, "WindowManagerPlugin");
        window_manager_plugin_register_with_registrar(window_manager_registrar);

        register_child_linux_window_attention_channel(registry);
      });

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->single_instance_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "dev.wyd.tracker/single_instance", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->single_instance_channel,
                                            single_instance_method_call_cb,
                                            self, nullptr);
  self->linux_window_attention_channel = register_linux_window_attention_channel(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      &self->primary_attention_target, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->single_instance_channel);
  g_clear_object(&self->linux_window_attention_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                      "application-id", APPLICATION_ID, "flags",
                                      static_cast<GApplicationFlags>(0),
                                      nullptr));
}
