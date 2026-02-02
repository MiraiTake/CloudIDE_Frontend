import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';

class TerminalWidget extends StatefulWidget {
  final Terminal terminal;
  final Function(Terminal) onTerminalCreated;

  const TerminalWidget({
    Key? key,
    required this.terminal,
    required this.onTerminalCreated,
  }) : super(key: key);

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  late final TerminalController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  
  bool get _isWindows => !kIsWeb && Platform.isWindows;
  
  // Для Windows используем буфер вывода
  String _outputText = '';
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    
    if (_isWindows) {
      // Для Windows периодически обновляем вывод
      _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _updateOutput();
      });
      widget.onTerminalCreated(widget.terminal);
    } else {
      // Для других платформ стандартная инициализация
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            widget.onTerminalCreated(widget.terminal);
          }
        });
      });
    }
  }

  void _updateOutput() {
    if (!mounted) return;
    
    try {
      final buffer = widget.terminal.buffer;
      final StringBuffer newOutput = StringBuffer();
      
      // Читаем все строки из буфера
      for (int i = 0; i < buffer.lines.length; i++) {
        final line = buffer.lines[i];
        newOutput.writeln(line.toString());
      }
      
      final newText = newOutput.toString();
      if (newText != _outputText) {
        setState(() {
          _outputText = newText;
        });
        
        // // Автоскролл вниз
        // WidgetsBinding.instance.addPostFrameCallback((_) {
        //   if (_scrollController.hasClients) {
        //     _scrollController.animateTo(
        //       _scrollController.position.maxScrollExtent,
        //       duration: const Duration(milliseconds: 100),
        //       curve: Curves.easeOut,
        //     );
        //   }
        // });
      }
    } catch (e) {
      debugPrint('Ошибка чтения буфера: $e');
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _focusNode.dispose();
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _sendInput() {
    final text = _inputController.text;
    if (text.isNotEmpty) {
      widget.terminal.textInput(text + '\n');
      _inputController.clear();
      _focusNode.requestFocus();
    }
  }

  void _copyAll() {
    if (_outputText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _outputText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скопировано в буфер обмена'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  Future<void> _pasteClipboard() async {
    try {
      final clip = await Clipboard.getData('text/plain');
      final text = clip?.text;
      if (text != null && text.isNotEmpty) {
        widget.terminal.paste(text);
      }
    } catch (e) {
      debugPrint('Ошибка при вставке: $e');
    }
  }

  void _clearOutput() {
    if (mounted) {
      setState(() {
        _outputText = '';
      });
      // Отправляем команду очистки терминала
      widget.terminal.textInput('clear\n');
    }
  }

  void _handleKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.isControlPressed && event.isShiftPressed) {
        if (event.logicalKey == LogicalKeyboardKey.keyC) {
          _copyAll();
        } else if (event.logicalKey == LogicalKeyboardKey.keyV) {
          _pasteClipboard();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        _sendInput();
      } else if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyL) {
        _clearOutput();
      }
    }
  }

  void _showContextMenu(Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('Скопировать всё'),
            ],
          ),
          onTap: _copyAll,
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.paste, size: 18),
              SizedBox(width: 8),
              Text('Вставить'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, _pasteClipboard),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.clear_all, size: 18),
              SizedBox(width: 8),
              Text('Очистить'),
            ],
          ),
          onTap: _clearOutput,
        ),
      ],
    );
  }

  Widget _buildWindowsTerminal() {
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _handleKey,
      autofocus: true,
      child: Container(
        color: Colors.black,
        child: Column(
          children: [
            // Заголовок с подсказками
            Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'Windows Terminal',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white70, size: 16),
                    onPressed: _copyAll,
                    tooltip: 'Скопировать всё (Ctrl+Shift+C)',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear_all, color: Colors.white70, size: 16),
                    onPressed: _clearOutput,
                    tooltip: 'Очистить (Ctrl+L)',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            // Область вывода
            Expanded(
              child: GestureDetector(
                onSecondaryTapDown: (details) {
                  _showContextMenu(details.globalPosition);
                },
                onLongPressStart: (details) {
                  _showContextMenu(details.globalPosition);
                },
                child: Container(
                  color: Colors.black,
                  width: double.infinity,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      _outputText.isEmpty ? 'Ожидание вывода...' : _outputText,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: _outputText.isEmpty ? Colors.grey : Colors.white,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Строка ввода
            Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const Text(
                    '❯ ',
                    style: TextStyle(
                      color: Colors.green,
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Введите команду...',
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                      onSubmitted: (_) => _sendInput(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.green, size: 18),
                    onPressed: _sendInput,
                    tooltip: 'Отправить (Enter)',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardTerminal() {
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _handleKey,
      child: Stack(
        children: [
          TerminalView(
            widget.terminal,
            controller: _controller,
            keyboardType: TextInputType.visiblePassword,
            autofocus: false,
            backgroundOpacity: 0.8,
            onSecondaryTapDown: (details, offset) {
              _showContextMenu(details.globalPosition);
            },
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (details) {
                _showContextMenu(details.globalPosition);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isWindows ? _buildWindowsTerminal() : _buildStandardTerminal();
  }
}