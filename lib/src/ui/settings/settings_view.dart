import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/domain.dart';
import 'settings_controller.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _reminderIntervalController;
  late final TextEditingController _autocompleteLookbackController;
  late final TextEditingController _responseTimeoutController;
  late final TextEditingController _typingDeferralController;
  late final FocusNode _reminderIntervalFocusNode;
  late final FocusNode _autocompleteLookbackFocusNode;
  late final FocusNode _responseTimeoutFocusNode;
  late final FocusNode _typingDeferralFocusNode;
  SettingsState _state = const SettingsState();

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _reminderIntervalController = TextEditingController(
      text: _state.reminderIntervalMinutes,
    );
    _autocompleteLookbackController = TextEditingController(
      text: _state.autocompleteLookbackDays,
    );
    _responseTimeoutController = TextEditingController(
      text: _state.responseTimeoutMinutes,
    );
    _typingDeferralController = TextEditingController(
      text: _state.typingDeferralSeconds,
    );
    _reminderIntervalFocusNode = FocusNode();
    _autocompleteLookbackFocusNode = FocusNode();
    _responseTimeoutFocusNode = FocusNode();
    _typingDeferralFocusNode = FocusNode();
    _commitOnBlur(_reminderIntervalFocusNode);
    _commitOnBlur(_autocompleteLookbackFocusNode);
    _commitOnBlur(_responseTimeoutFocusNode);
    _commitOnBlur(_typingDeferralFocusNode);
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
    _controllerChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _reminderIntervalController.dispose();
    _autocompleteLookbackController.dispose();
    _responseTimeoutController.dispose();
    _typingDeferralController.dispose();
    _reminderIntervalFocusNode.dispose();
    _autocompleteLookbackFocusNode.dispose();
    _responseTimeoutFocusNode.dispose();
    _typingDeferralFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: _state.saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _state.loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SettingsSection(
                      title: 'Reminders',
                      children: [
                        _numberField(
                          controller: _reminderIntervalController,
                          focusNode: _reminderIntervalFocusNode,
                          label: 'Reminder interval',
                          suffix: 'min',
                          errorField: SettingsField.reminderIntervalMinutes,
                          onChanged: widget.controller.updateReminderInterval,
                        ),
                        const SizedBox(height: 12),
                        _numberField(
                          controller: _responseTimeoutController,
                          focusNode: _responseTimeoutFocusNode,
                          label: 'Unanswered timeout',
                          suffix: 'min',
                          errorField: SettingsField.responseTimeoutMinutes,
                          onChanged: widget.controller.updateResponseTimeout,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsSection(
                      title: 'Suggestions',
                      children: [
                        _numberField(
                          controller: _autocompleteLookbackController,
                          focusNode: _autocompleteLookbackFocusNode,
                          label: 'Autocomplete lookback',
                          suffix: 'days',
                          errorField: SettingsField.autocompleteLookbackDays,
                          onChanged:
                              widget.controller.updateAutocompleteLookback,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsSection(
                      title: 'Activity',
                      children: [
                        _numberField(
                          controller: _typingDeferralController,
                          focusNode: _typingDeferralFocusNode,
                          label: 'Typing deferral',
                          suffix: 'sec',
                          supportingText:
                              _state.capabilities.supportsTypingActivity
                              ? null
                              : 'Unsupported on this platform',
                          errorField: SettingsField.typingDeferralSeconds,
                          enabled: _state.capabilities.supportsTypingActivity,
                          onChanged: widget.controller.updateTypingDeferral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsSection(
                      title: 'Startup',
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Run on Login'),
                          subtitle: Text(
                            _state.capabilities.supportsStartAtLogin
                                ? 'Launch wyd when you sign in.'
                                : 'Unsupported on this platform',
                          ),
                          value: _state.startAtLogin,
                          onChanged: _state.capabilities.supportsStartAtLogin
                              ? (value) => unawaited(
                                  widget.controller.updateStartAtLogin(value),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String suffix,
    required SettingsField errorField,
    required ValueChanged<String> onChanged,
    String? supportingText,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: supportingText,
        errorText: _state.messageFor(errorField),
      ),
      onChanged: onChanged,
      onSubmitted: (_) => unawaited(widget.controller.commitChanges()),
    );
  }

  void _controllerChanged() {
    if (!mounted) {
      return;
    }

    final nextState = widget.controller.state;
    final previousErrorMessage = _state.errorMessage;
    setState(() {
      _state = nextState;
      _syncController(
        _reminderIntervalController,
        nextState.reminderIntervalMinutes,
      );
      _syncController(
        _autocompleteLookbackController,
        nextState.autocompleteLookbackDays,
      );
      _syncController(
        _responseTimeoutController,
        nextState.responseTimeoutMinutes,
      );
      _syncController(
        _typingDeferralController,
        nextState.typingDeferralSeconds,
      );
    });

    final errorMessage = nextState.errorMessage;
    if (errorMessage != null && errorMessage != previousErrorMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text(errorMessage)));
      });
    }
  }

  void _commitOnBlur(FocusNode focusNode) {
    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        unawaited(widget.controller.commitChanges());
      }
    });
  }

  void _syncController(TextEditingController controller, String text) {
    if (controller.text == text) {
      return;
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
