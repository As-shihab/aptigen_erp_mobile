import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../data/ai_local_prefs.dart';
import '../data/ai_models.dart';
import '../data/ai_service.dart';
import '../data/ai_voice_service.dart';
import 'widgets/ai_sessions_sheet.dart';

/// Aptigen AI — same backend/behavior as desktop's `HeaderAiPopover.tsx`
/// (streamed word-by-word replies, session history, per-turn structured
/// `rows` rendered as a table, voice input/output), as a full-screen page
/// rather than a popover/portal dialog (mobile has no room for a permanent
/// sessions rail — sessions live behind the History icon instead, same idea
/// as the desktop "small" popover mode's slide-down panel). The admin-only
/// "Train the AI" flow isn't ported (gated behind a backend env flag most
/// workplaces don't have on anyway); voice sticks to mute on/off — desktop's
/// tone/style/voice-name pickers aren't essential day to day.
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final _service = AiService(ApiClient());
  final _voiceService = AiVoiceService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  int? _userId;
  int? _sessionId;
  bool _typing = false;
  bool _listening = false;
  bool _muted = false;
  bool _loadingHistory = true;
  List<AiChatMessage> _messages = [];

  String get _helloText => 'Hello! How can I help you?';

  @override
  void initState() {
    super.initState();
    _init();
    _voiceService.isMuted().then((value) {
      if (mounted) setState(() => _muted = value);
    });
  }

  @override
  void dispose() {
    _voiceService.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final user = await AuthService(ApiClient()).getStoredUser();
    _userId = user?.id;
    final lastSessionId = await AiLocalPrefs.getLastSessionId();
    if (lastSessionId != null) {
      try {
        final history = await _service.loadSessionHistory(lastSessionId);
        if (!mounted) return;
        setState(() {
          _messages = history.isEmpty ? [AiChatMessage(role: 'ai', text: _helloText)] : history;
          _sessionId = lastSessionId;
        });
        _loadingHistory = false;
        return;
      } catch (_) {
        // stale/deleted session — fall through to a fresh chat
      }
    }
    if (!mounted) return;
    setState(() {
      _messages = [AiChatMessage(role: 'ai', text: _helloText)];
      _sessionId = null;
      _loadingHistory = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final question = _textController.text.trim();
    if (question.isEmpty || _typing) return;
    setState(() {
      _messages.add(AiChatMessage(role: 'user', text: question));
      _typing = true;
    });
    _textController.clear();
    _scrollToBottom();

    var aiMessageAdded = false;
    try {
      final result = await _service.askStream(
        question: question,
        sessionId: _sessionId,
        onTextUpdate: (text) {
          if (!mounted) return;
          setState(() {
            if (!aiMessageAdded) {
              _typing = false;
              _messages.add(AiChatMessage(role: 'ai', text: text));
              aiMessageAdded = true;
            } else {
              _messages.last.text = text;
            }
          });
          _scrollToBottom();
        },
      );
      if (!mounted) return;
      setState(() {
        _sessionId = result.sessionId > 0 ? result.sessionId : _sessionId;
        if (aiMessageAdded) {
          _messages.last.text = result.fullText;
          _messages.last.rows = result.rows;
        } else {
          _messages.add(AiChatMessage(role: 'ai', text: result.fullText, rows: result.rows));
        }
      });
      await AiLocalPrefs.setLastSessionId(_sessionId);
      unawaited(_voiceService.speak(result.fullText));
    } catch (error) {
      if (!mounted) return;
      final detail = error.toString();
      final isRateLimited = RegExp('rate.?limit|429|quota|too many requests', caseSensitive: false).hasMatch(detail);
      setState(() {
        _typing = false;
        if (!aiMessageAdded) {
          _messages.add(AiChatMessage(
            role: 'ai',
            text: isRateLimited
                ? "I'm getting rate-limited by the AI provider right now — please wait a bit and try again."
                : 'Something went wrong reaching the AI assistant. Please try again.',
          ));
        }
      });
    }
    _scrollToBottom();
  }

  /// Mirrors desktop's `toggleVoice` — tap once to start listening (live
  /// transcript fills the input box), tap again to stop early; a final
  /// result auto-sends, same as `recog.onresult`'s `if (isFinal) send(...)`.
  Future<void> _toggleListening() async {
    if (_listening) {
      await _voiceService.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    // Stop any in-progress reply speech first — it would otherwise talk
    // over the mic input.
    unawaited(_voiceService.stopSpeaking());
    setState(() => _listening = true);
    final started = await _voiceService.startListening(
      onResult: (text, isFinal) {
        if (!mounted) return;
        _textController.text = text;
        _textController.selection = TextSelection.collapsed(offset: text.length);
        if (isFinal) {
          setState(() => _listening = false);
          if (text.trim().isNotEmpty) _send();
        }
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      },
    );
    if (!started && mounted) setState(() => _listening = false);
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);
    await _voiceService.setMuted(next);
  }

  void _newChat() {
    setState(() {
      _messages = [AiChatMessage(role: 'ai', text: _helloText)];
      _sessionId = null;
      _typing = false;
    });
    AiLocalPrefs.setLastSessionId(null);
  }

  Future<void> _openSessions() async {
    if (_userId == null) return;
    final result = await showAiSessionsSheet(context, userId: _userId!, currentSessionId: _sessionId);
    if (result == null) return;
    if (result.id == 0) {
      _newChat();
      return;
    }
    setState(() => _loadingHistory = true);
    try {
      final history = await _service.loadSessionHistory(result.id);
      if (!mounted) return;
      setState(() {
        _messages = history.isEmpty ? [AiChatMessage(role: 'ai', text: _helloText)] : history;
        _sessionId = result.id;
      });
      await AiLocalPrefs.setLastSessionId(result.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load this chat.')));
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _AiAvatar(size: 32),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Aptigen AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(_typing ? 'Thinking…' : 'Online · Ready', style: TextStyle(fontSize: 11, color: AppColors.slate600)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_muted ? Icons.volume_off_outlined : Icons.volume_up_outlined),
            tooltip: _muted ? 'Unmute AI voice' : 'Mute AI voice',
            onPressed: _toggleMute,
          ),
          IconButton(icon: const Icon(Icons.add_comment_outlined), tooltip: 'New chat', onPressed: _newChat),
          IconButton(icon: const Icon(Icons.history), tooltip: 'Chats', onPressed: _openSessions),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    itemCount: _messages.length + (_typing ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) return const _TypingIndicator();
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
          ),
          _InputBar(controller: _textController, onSend: _send, enabled: !_typing, listening: _listening, onMicTap: _toggleListening),
        ],
      ),
    );
  }
}

class _AiAvatar extends StatelessWidget {
  final double size;
  const _AiAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).cardColor, border: Border.all(color: AppColors.slate400.withValues(alpha: 0.25)), boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.15), blurRadius: 6, spreadRadius: 1)]),
      child: Image.asset('assets/icon/app_logo.png', fit: BoxFit.contain),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AiChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.role == 'user') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(18).copyWith(bottomRight: const Radius.circular(4))),
                child: Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35)),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiAvatar(size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.text.isNotEmpty)
                  Text(message.text, style: const TextStyle(fontSize: 13.5, height: 1.45)),
                if (message.rows.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _AiResultTable(rows: message.rows),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiResultTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _AiResultTable({required this.rows});

  String _label(String key) => key.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  String _cell(dynamic value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'Yes' : 'No';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final keys = rows.first.keys.toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(border: Border.all(color: AppColors.slate400.withValues(alpha: 0.25))),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 34,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: keys.map((k) => DataColumn(label: Text(_label(k), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)))).toList(),
              rows: rows.map((row) => DataRow(cells: keys.map((k) => DataCell(Text(_cell(row[k]), style: const TextStyle(fontSize: 11)))).toList())).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _AiAvatar(size: 26),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Row(
                children: List.generate(3, (i) {
                  final t = (_controller.value + i * 0.18) % 1.0;
                  final scale = 0.6 + (t < 0.5 ? t * 2 : (1 - t) * 2) * 0.4;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Transform.scale(scale: scale, child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle))),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final bool listening;
  final VoidCallback onMicTap;
  const _InputBar({required this.controller, required this.onSend, required this.enabled, required this.listening, required this.onMicTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: listening ? AppColors.brand : AppColors.slate400.withValues(alpha: 0.3), width: listening ? 1.5 : 1),
                ),
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(border: InputBorder.none, hintText: listening ? 'Listening…' : 'Ask Aptigen AI…', isDense: true),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onMicTap,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: listening ? AppColors.error : Theme.of(context).cardColor, shape: BoxShape.circle, border: listening ? null : Border.all(color: AppColors.slate400.withValues(alpha: 0.3))),
                child: Icon(listening ? Icons.mic_off : Icons.mic_none, color: listening ? Colors.white : AppColors.slate600, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: enabled ? onSend : null,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: enabled ? AppColors.brand : AppColors.slate400.withValues(alpha: 0.3), shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
