import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/domain.dart';
import '../layout_metrics.dart';
import 'quick_entry_controller.dart';

const _quickEntryPanelMaxWidthRem = 35.0;
const _quickEntryControlsMinFieldWidthRem = 14.0;
const _suggestionRowMinHeightRem = 2.25;

class QuickEntryView extends StatelessWidget {
  const QuickEntryView({super.key, required this.controller});

  final QuickEntryController controller;

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: metrics.insetsAll(0.75),
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
    final metrics = WydLayoutMetrics.of(context);
    final sectionGap = metrics.space(0.75);
    final suggestionLabelGap = metrics.space(0.375);
    final suggestionRowMinHeight = metrics.atLeast(
      36,
      _suggestionRowMinHeightRem,
    );
    final suggestionListMaxHeight =
        defaultAutocompleteSuggestionLimit * suggestionRowMinHeight;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveSuggestionIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveSuggestionIntent(-1),
        SingleActivator(LogicalKeyboardKey.escape):
            _CancelAutocompleteSelectionIntent(),
      },
      child: Actions(
        actions: {
          _MoveSuggestionIntent: CallbackAction<_MoveSuggestionIntent>(
            onInvoke: (intent) {
              widget.controller.moveHighlight(intent.delta);
              return null;
            },
          ),
          _CancelAutocompleteSelectionIntent:
              CallbackAction<_CancelAutocompleteSelectionIntent>(
                onInvoke: (intent) {
                  widget.controller.cancelAutocompleteSelection();
                  return null;
                },
              ),
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: metrics.maxWidth(_quickEntryPanelMaxWidthRem, min: 420),
          ),
          child: Padding(
            padding: metrics.insetsAll(0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTaskControls(context, metrics),
                if (suggestions.isNotEmpty) ...[
                  SizedBox(height: sectionGap),
                  Text(
                    'Recent Tasks',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: suggestionLabelGap),
                  Flexible(
                    child: Material(
                      borderRadius: BorderRadius.circular(metrics.size(0.5)),
                      clipBehavior: Clip.antiAlias,
                      color: colorScheme.surfaceContainer,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: suggestionListMaxHeight,
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
                                alignment: Alignment.centerLeft,
                                constraints: BoxConstraints(
                                  minHeight: suggestionRowMinHeight,
                                ),
                                padding: metrics.insetsSymmetric(
                                  horizontal: 0.75,
                                  vertical: 0.25,
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

  Widget _buildTaskControls(BuildContext context, WydLayoutMetrics metrics) {
    final controlGap = metrics.space(0.75);
    final buttonMinimumSize = Size(
      metrics.atLeast(96, 6),
      metrics.atLeast(48, 3),
    );
    final submitButton = FilledButton(
      style: FilledButton.styleFrom(minimumSize: buttonMinimumSize),
      onPressed: _state.busy ? null : widget.controller.submit,
      child: Text(_state.busy ? 'Submitting...' : 'Submit'),
    );
    final textField = TextField(
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumInlineWidth =
            metrics.size(_quickEntryControlsMinFieldWidthRem) +
            controlGap +
            buttonMinimumSize.width;
        final shouldStack = constraints.maxWidth < minimumInlineWidth;
        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              textField,
              SizedBox(height: controlGap),
              Align(alignment: Alignment.centerRight, child: submitButton),
            ],
          );
        }

        return Row(
          crossAxisAlignment: _state.validationMessage == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Expanded(child: textField),
            SizedBox(width: controlGap),
            submitButton,
          ],
        );
      },
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

final class _CancelAutocompleteSelectionIntent extends Intent {
  const _CancelAutocompleteSelectionIntent();
}
