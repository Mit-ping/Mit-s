import 'package:flutter/material.dart';
import 'package:hiddify/features/one_tap/report/mit_error_report.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MitErrorReportPage extends ConsumerStatefulWidget {
  const MitErrorReportPage({super.key});
  @override
  ConsumerState<MitErrorReportPage> createState() => _MitErrorReportPageState();
}

class _MitErrorReportPageState extends ConsumerState<MitErrorReportPage> {
  bool working = false;

  Future<void> export(MitErrorReport report, {required bool share}) async {
    if (working) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? const Rect.fromLTWH(0, 0, 1, 1) : box.localToGlobal(Offset.zero) & box.size;
    setState(() => working = true);
    try {
      final exporter = ref.read(mitReportExporterProvider);
      if (share) {
        await exporter.share(report, origin);
      } else {
        final saved = await exporter.save(report);
        if (mounted && saved) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Отчёт сохранён. Можно поделиться им в Telegram.')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              share
                  ? 'Не удалось открыть отправку. Сохраните отчёт и прикрепите файл в Telegram.'
                  : 'Не удалось сохранить отчёт. Попробуйте «Поделиться».',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(mitErrorReportProvider);
    final value = report.asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Отчёт об ошибке')),
      bottomNavigationBar: value == null
          ? null
          : SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('mit-save-report'),
                          onPressed: working ? null : () => export(value, share: false),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Скачать отчёт'),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('mit-share-report'),
                          onPressed: working ? null : () => export(value, share: true),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Поделиться'),
                        ),
                      ],
                    ),
                  ),
                  if (working) const LinearProgressIndicator(),
                ],
              ),
            ),
      body: SafeArea(
        child: report.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Не удалось подготовить отчёт.'),
                TextButton(onPressed: () => ref.invalidate(mitErrorReportProvider), child: const Text('Повторить')),
              ],
            ),
          ),
          data: (value) => Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Журнал последнего подключения без ключей, адресов и посещённых сайтов. Нажмите «Поделиться» и выберите Telegram.',
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SelectableText(value.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
