import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/domain.dart';
import 'quick_entry_controller.dart';

const _suggestionRowHeight = 36.0;
const _suggestionListMaxHeight =
    defaultAutocompleteSuggestionLimit * _suggestionRowHeight;

class QuickEntryView extends StatelessWidget {
  const QuickEntryView({super.key, required this.controller});

  final QuickEntryController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              margin: EdgeInsets.zero,
              child: QuickEntryPanel(controller: controller),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickEntryPanel extends StatefulWidget {
  const QuickEntryPanel({super.key, required this.controller});

  final QuickEntryController controller;

  @override
  State<QuickEntryPanel> createState() => _QuickEntryPanelState();
}

class _QuickEntryPanelState extends State<QuickEntryPanel> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  QuickEntryState _state = const QuickEntryState();

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _textController = TextEditingController(text: _state.text);
    _focusNode = FocusNode();
    widget.controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusTextField());
  }

  @override
  void didUpdateWidget(QuickEntryPanel oldWidget) {
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
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _state.suggestions;
    final colorScheme = Theme.of(context).colorScheme;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveSuggestionIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveSuggestionIntent(-1),
      },
      child: Actions(
        actions: {
          _MoveSuggestionIntent: CallbackAction<_MoveSuggestionIntent>(
            onInvoke: (intent) {
              widget.controller.moveHighlight(intent.delta);
              return null;
            },
          ),
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: _state.validationMessage == null
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: "What's ya doin?",
                          errorText: _state.validationMessage,
                        ),
                        onChanged: widget.controller.updateText,
                        onSubmitted: (_) => widget.controller.submit(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(96, 48),
                      ),
                      onPressed: _state.busy ? null : widget.controller.submit,
                      child: Text(_state.busy ? 'Submitting...' : 'Submit'),
                    ),
                  ],
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Recent Tasks',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: Material(
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      color: colorScheme.surfaceContainer,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: _suggestionListMaxHeight,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = suggestions[index];
                            final highlighted =
                                index == _state.highlightedIndex;
                            return InkWell(
                              onTap: () => widget.controller.acceptSuggestion(
                                index,
                                submitNow: true,
                              ),
                              child: Container(
                                height: _suggestionRowHeight,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: highlighted
                                    ? colorScheme.secondaryContainer
                                    : null,
                                child: Text(
                                  suggestion.taskText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _controllerChanged() {
    final nextState = widget.controller.state;
    if (!mounted) {
      return;
    }

    setState(() {
      _state = nextState;
      if (_textController.text != nextState.text) {
        _textController.value = TextEditingValue(
          text: nextState.text,
          selection: TextSelection.collapsed(offset: nextState.text.length),
        );
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _focusTextField());
  }

  void _focusTextField() {
    if (!mounted || !_state.isOpen) {
      return;
    }

    _focusNode.requestFocus();
    if (_state.selectAllOnOpen && _textController.text.isNotEmpty) {
      _textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _textController.text.length,
      );
    }
  }
}

final class _MoveSuggestionIntent extends Intent {
  const _MoveSuggestionIntent(this.delta);

  final int delta;
}
