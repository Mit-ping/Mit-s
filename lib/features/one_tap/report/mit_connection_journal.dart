import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

/// Only these fixed events can leave the journal. Never export native text:
/// it may contain keys, profile names, destinations or entire configurations.
enum MitReportCode {
  start('Начало подключения'),
  connected('VPN подключён'),
  waiting('Ожидание ответа сервера'),
  unavailable('Нет доступных серверов'),
  stopping('Отключение VPN'),
  stopped('VPN отключён'),
  failed('Подключение завершилось ошибкой'),
  permission('Нет разрешения на VPN'),
  config('Ошибка конфигурации'),
  timeout('Истекло время ожидания'),
  dns('Ошибка разрешения DNS'),
  tls('Ошибка TLS / сертификата'),
  refused('Соединение отклонено'),
  unreachable('Сеть или сервер недоступны'),
  authentication('Ошибка проверки подлинности'),
  tun('Ошибка VPN-интерфейса'),
  cancelled('Подключение отменено'),
  unknown('Техническая ошибка; подробности скрыты');

  const MitReportCode(this.title);
  final String title;
}

enum MitReportProtocol { vlessReality, amneziaWG, unknown }

class MitReportEvent {
  const MitReportEvent(this.ms, this.code, this.core, this.warning, [this.count = 1]);
  final int ms;
  final MitReportCode code;
  final bool core;
  final bool warning;
  final int count;
  Map<String, Object> toJson() => {'ms': ms, 'code': code.name, 'core': core, 'warning': warning, 'count': count};

  static MitReportEvent fromJson(Map<String, dynamic> value) => MitReportEvent(
    (value['ms'] as int).clamp(0, 31536000000),
    MitReportCode.values.byName(value['code'] as String),
    value['core'] == true,
    value['warning'] == true,
    (value['count'] as int).clamp(1, 999),
  );
}

class MitConnectionAttempt {
  MitConnectionAttempt({required this.id, required this.started, required this.protocol, required this.automatic});
  final String id;
  final DateTime started;
  final MitReportProtocol protocol;
  final bool automatic;
  DateTime? ended;
  final events = <MitReportEvent>[];
  int omitted = 0;
  bool get complete => ended != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'started': started.toUtc().toIso8601String(),
    'ended': ended?.toUtc().toIso8601String(),
    'protocol': protocol.name,
    'automatic': automatic,
    'omitted': omitted,
    'events': events.map((e) => e.toJson()).toList(),
  };

  static MitConnectionAttempt fromJson(Map<String, dynamic> value) {
    final id = value['id'] as String;
    if (!RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(id)) throw const FormatException();
    final attempt = MitConnectionAttempt(
      id: id,
      started: DateTime.parse(value['started'] as String).toUtc(),
      protocol: MitReportProtocol.values.byName(value['protocol'] as String),
      automatic: value['automatic'] == true,
    );
    if (value['ended'] != null) attempt.ended = DateTime.parse(value['ended'] as String).toUtc();
    attempt.omitted = (value['omitted'] as int).clamp(0, 1000000);
    for (final event in (value['events'] as List).take(200)) {
      attempt.events.add(MitReportEvent.fromJson(event as Map<String, dynamic>));
    }
    return attempt;
  }
}

class MitConnectionJournal {
  MitConnectionJournal({this.file, DateTime Function()? now, bool listen = true}) : _now = now ?? DateTime.now {
    ready = _restore();
    if (listen) _subscription = Logger.root.onRecord.listen(_onLog);
  }
  final Future<File> Function()? file;
  final DateTime Function() _now;
  MitConnectionAttempt? _last;
  StreamSubscription<LogRecord>? _subscription;
  Timer? _saveTimer;
  Future<void> _pending = Future.value();
  late final Future<void> ready;
  bool _disposed = false;
  bool _capturing = false;
  bool _connected = false;

  bool get hasConnected => _connected;

  Future<void> _restore() async {
    if (file == null) return;
    try {
      final target = await file!();
      if (await target.exists() && await target.length() <= 65536) {
        final restored = MitConnectionAttempt.fromJson(jsonDecode(await target.readAsString()) as Map<String, dynamic>);
        _last ??= restored; // An asynchronous restore must never replace a new attempt.
      }
    } catch (_) {
      /* Missing/corrupt diagnostics must never block the VPN. */
    }
  }

  void begin({required MitReportProtocol protocol, required bool automatic}) {
    _capturing = true;
    _connected = false;
    _last = MitConnectionAttempt(
      id: const Uuid().v4(),
      started: _now().toUtc(),
      protocol: protocol,
      automatic: automatic,
    );
    add(MitReportCode.start);
    unawaited(flush());
  }

  void add(MitReportCode code, {bool core = false, bool warning = false}) {
    final attempt = _last;
    if (_disposed || !_capturing || attempt == null || attempt.complete) return;
    if (code == MitReportCode.connected) _connected = true;
    final ms = _now().toUtc().difference(attempt.started).inMilliseconds.clamp(0, 31536000000);
    if (attempt.events.isNotEmpty) {
      final last = attempt.events.last;
      if (last.code == code && last.core == core && last.warning == warning && last.count < 999) {
        attempt.events[attempt.events.length - 1] = MitReportEvent(last.ms, code, core, warning, last.count + 1);
        _scheduleSave();
        return;
      }
    }
    if (attempt.events.length == 200) {
      attempt.events.removeAt(1); // Retain the initial event and the most recent failures.
      attempt.omitted++;
    }
    attempt.events.add(MitReportEvent(ms, code, core, warning));
    _scheduleSave();
  }

  void finish(MitReportCode code) {
    if (!_capturing || _last == null || _last!.complete) return;
    add(code, warning: code == MitReportCode.failed);
    _last!.ended = _now().toUtc();
    _capturing = false;
    unawaited(flush());
  }

  void recordError(Object? error) {
    final text = error?.toString() ?? '';
    add(classify(text) ?? MitReportCode.unknown, warning: true);
  }

  void _onLog(LogRecord record) {
    if (!_capturing || _last == null || _last!.complete || record.level < Level.WARNING) return;
    // Inspect bounded text; only the matched enum is kept, never any of the text.
    final code = classify('${record.message} ${record.error ?? ''}');
    if (code != null) add(code, core: record.loggerName.startsWith('core.'), warning: true);
  }

  static MitReportCode? classify(String text) {
    final lower = text.substring(0, text.length.clamp(0, 8192)).toLowerCase();
    if (lower.contains('permission') || lower.contains('access is denied') || lower.contains('not permitted'))
      return MitReportCode.permission;
    if (lower.contains('deadline') || lower.contains('timeout') || lower.contains('timed out'))
      return MitReportCode.timeout;
    if (lower.contains('certificate') || lower.contains('x509') || lower.contains('tls handshake'))
      return MitReportCode.tls;
    if (lower.contains('dns') || lower.contains('no such host') || lower.contains('name resolution'))
      return MitReportCode.dns;
    if (lower.contains('connection refused')) return MitReportCode.refused;
    if (lower.contains('unreachable') || lower.contains('network is down') || lower.contains('no route to host'))
      return MitReportCode.unreachable;
    if (lower.contains('authentication') || lower.contains('unauthorized')) return MitReportCode.authentication;
    if (lower.contains('inbound/tun') || lower.contains('tun interface')) return MitReportCode.tun;
    if (lower.contains('config') && (lower.contains('invalid') || lower.contains('parse') || lower.contains('error')))
      return MitReportCode.config;
    return null;
  }

  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 1), () => unawaited(flush()));
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    final data = _last == null ? null : jsonEncode(_last!.toJson());
    if (file == null || data == null) return _pending;
    _pending = _pending.then((_) async {
      try {
        final target = await file!();
        await target.parent.create(recursive: true);
        final temporary = File('${target.path}.tmp');
        await temporary.writeAsString(data, flush: true);
        await temporary.rename(target.path);
      } catch (_) {
        /* Reports are optional; storage failures cannot stop a connection. */
      }
    });
    return _pending;
  }

  /// A validated copy prevents UI snapshots changing while a save/share sheet is open.
  Future<MitConnectionAttempt?> snapshot() async {
    await ready;
    return _last == null ? null : MitConnectionAttempt.fromJson(_last!.toJson());
  }

  void dispose() {
    unawaited(flush());
    _disposed = true;
    _saveTimer?.cancel();
    unawaited(_subscription?.cancel());
  }
}
