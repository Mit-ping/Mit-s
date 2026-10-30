import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/one_tap/reality_profile.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class OneTapHomePage extends HookConsumerWidget {
  const OneTapHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeProfileProvider);
    final status = ref.watch(connectionNotifierProvider);
    final busy = useState(false);
    final canImport = !busy.value && status.hasValue && (status.valueOrNull?.isDisconnected ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('VPN')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (busy.value)
                  const CircularProgressIndicator()
                else if (active.hasValue && active.valueOrNull != null)
                  const ConnectionButton()
                else
                  const Text('Добавьте профиль для подключения'),
                const SizedBox(height: 24),
                const Text('Российские сайты — напрямую\nОстальной трафик — через VPN', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(busy.value ? 'Проверка профиля…' : 'Добавить VLESS + REALITY'),
                  onPressed: !canImport ? null : () async {
                    final input = await showDialog<String>(
                      context: context,
                      builder: (_) => const _ProfileDialog(),
                    );
                    if (input == null || !context.mounted) return;
                    if (!(ref.read(connectionNotifierProvider).valueOrNull?.isDisconnected ?? false)) return;
                    busy.value = true;
                    try {
                      final link = validateRealityProfile(input);
                      final repo = await ref.read(profileRepositoryProvider.future);
                      final result = await repo.addLocal(link, userOverride: const UserOverride(name: 'VPN')).run();
                      if (result.isLeft()) throw const FormatException('Не удалось проверить профиль.');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профиль добавлен')));
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Не удалось добавить профиль VLESS + REALITY. Проверьте ссылку.')),
                        );
                      }
                    } finally {
                      if (context.mounted) busy.value = false;
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog();

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Профиль VPN'),
    content: TextField(
      controller: controller,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(labelText: 'Ссылка vless://'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить')),
    ],
  );
}
