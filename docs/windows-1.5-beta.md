# VPN 1.5 beta для Windows

Версия приложения: `1.5.0-beta.1+10500`. Версия пакета MSIX: `1.5.0.1`.
Целевая платформа: Windows x64. Форматы: Setup EXE, MSIX, portable ZIP.

CI и выпуск по тегу собирают только Windows (`windows-only: true`).
Анализ Dart и Flutter-тесты выполняются на Linux до Windows-сборки.
Android, Linux и macOS пакеты, Google Play и TestFlight в этот выпуск не входят.
Сборка или отсутствие любого из трёх Windows-пакетов завершают workflow ошибкой.

## Сборка и выпуск

Нужен Windows-компьютер с Flutter 3.38.5, Visual Studio с компонентами
Desktop development with C++, Git Bash/Make и Inno Setup.
В корне существующего checkout выполните в Git Bash:

```bash
make windows-install-deps
export PATH="$(cygpath -u "$LOCALAPPDATA")/Pub/Cache/bin:$PATH"
make CHANNEL=prod windows-prepare
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
make CHANNEL=prod windows-release
```

Для подписанных пакетов используйте конфигурацию из
[windows-code-signing.md](windows-code-signing.md). Секреты подписи и Sentry
для CI задаются в настройках GitHub Actions; значения в репозиторий не добавляются.

После проверки и отправки изменений тег `v1.5.0-beta.1` запускает Release workflow.
Он публикует prerelease с тремя Windows-пакетами. Обычный CI обновляет `draft`.
Автоматическая публикация происходит только после push в GitHub, локальная
подготовка файлов её не выполняет.

Перед распространением на Windows проверьте установку, запуск, импорт профиля,
подключение VPN, отключение VPN и удаление приложения. Portable ZIP проверьте
отдельно от установленной версии. Сборка в CI не заменяет эти проверки.

Версия 1.5 ниже прежней 5.0. MSIX может отказать в установке поверх 5.0:
сначала экспортируйте профили и удалите прежнюю версию. Эта бета не является
автоматическим обновлением 5.0.

## Сборка без публикации релиза

Добавлен отдельный workflow `Windows beta build (artifacts only)`:
[windows-build.yml](../.github/workflows/windows-build.yml). Он запускается
вручную через Actions (когда workflow зарегистрирован в основной ветке)
или при push в ветку `build/windows-1.5-beta`.

Сборка на `windows-2022` выполняет генерацию, анализ, тесты и упаковку.
После упаковки portable ZIP распаковывается в чистый временный каталог:
сборка проверяет появление окна приложения и отсутствие немедленного завершения.
Эта проверка не устанавливает VPN-соединение.
Результат сохраняется на 14 дней в артефакте
`VPN-1.5.0-beta.1-Windows-x64`:

- `VPN-1.5.0-beta.1-Windows-x64-Setup.exe`;
- `VPN-1.5.0-beta.1-Windows-x64-Portable.zip`;
- `SHA256SUMS.txt`.

Этот workflow имеет только `contents: read`: он не создаёт GitHub Release,
не обновляет `draft` и не публикует облачную среду. EXE и ZIP собираются без
цифровой подписи; Windows может показать предупреждение SmartScreen.
MSIX в эту сборку не входит, так как для обычной установки нужна подпись.

Стабильный архив ядра 4.1.0 не содержит `HiddifyAdmin.exe`, который требуется
Windows-приложению. Отдельная сборка использует совместимый официальный архив
с ID `706285436` и проверяет SHA256
`a4fb3af453371b0a095813e6c7e887872146098c2a535b3f07d969a4c88e00ff`.
При удалении этого архива или изменении содержимого сборка останавливается;
подменять контрольную сумму без проверки нового архива нельзя.
