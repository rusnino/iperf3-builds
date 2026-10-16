# iperf3-builds: автоматическая сборка релизов esnet/iperf

## Intent (зачем)

Создать GitHub-репозиторий `rusnino/iperf3-builds`, который автоматически отслеживает релизы upstream-проекта [esnet/iperf](https://github.com/esnet/iperf) и собирает готовые бинарные файлы `iperf3` для Linux x86_64. Репозиторий избавляет от необходимости вручную компилировать iperf3 на целевых системах (например, в Cisco IOS-XE guestshell) и предоставляет артефакты в виде GitHub Releases.

## Goals (что должно работать)

1. **Автоматическая проверка новых релизов** — раз в сутки GitHub Actions проверяет последний релиз `esnet/iperf`.
2. **Сборка двух вариантов бинарника** для Linux x86_64:
   - **static** — собран с musl, максимально переносимый, не требует системных библиотек.
   - **dynamic** — собран с glibc в старом окружении (Ubuntu 20.04 / CentOS Stream 8), чтобы работать на системах с более старой glibc.
3. **Автоматический GitHub Release** — при обнаружении нового upstream-релиза создаётся релиз в `rusnino/iperf3-builds`:
   - Тег совпадает с upstream-версией полностью, включая `v`-префикс (например, `v3.17.1`).
   - Release notes копируются из upstream-релиза.
   - К релизу прикрепляются архивы `iperf3-{version}-linux-x86_64-static.tar.gz` и `iperf3-{version}-linux-x86_64-dynamic.tar.gz`.
   - Публикуется файл `SHA256SUMS`.
4. **Поддержка stable и pre-release/rc** — workflow реагирует на любой релиз в upstream, помечая rc/pre-release соответственно в GitHub.
5. **Возможность ручного запуска** — workflow можно запустить вручную для любого тега/версии iperf3.

## Non-goals (что не делаем сейчас)

- Сборка под macOS, Windows, ARM и другие архитектуры (оставляем для будущего расширения).
- Подпись релизов PGP/Sigstore (только SHA256-чексуммы).
- Создание deb/rpm-пакетов (только архивы с бинарником).
- Автоматическое открытие PR/issues в upstream.

## Anti-goals (что сделало бы проект хуже)

- Сборка динамического бинарника на новом Ubuntu без учёта совместимости с CentOS Stream 8 — бинарник не запустится в guestshell.
- Публикация артефактов только как GitHub Actions artifacts — их сложно скачивать и они не версионируются.
- Игнорирование pre-release-версий — пользователь хочет видеть rc-сборки.

## Constraints (ограничения)

- GitHub Actions runner — `ubuntu-latest` для musl-сборки, `ubuntu-20.04` (или контейнер CentOS Stream 8) для dynamic-сборки.
- Доступ к GitHub API — используется встроенный `GITHUB_TOKEN` для всех вызовов GitHub API, включая проверку upstream-релизов.
- `gh` CLI уже авторизован под аккаунтом `rusnino`.

## Ключевые решения

### 1. Проверка новых релизов

Workflow `release-watcher.yml` запускается по cron (`0 4 * * *`) и через `workflow_dispatch`.

Логика:
1. Запрашивает список релизов `esnet/iperf` через GitHub API с использованием `GITHUB_TOKEN` (для надёжности и избежания rate limits).
2. Берёт последние 10 upstream-релизов (stable + pre-release/rc).
3. Для каждого релиза проверяет, существует ли в `rusnino/iperf3-builds` тег с таким же именем (например, `v3.17.1`). Теги совпадают с upstream полностью.
4. Для каждого отсутствующего тега запускает workflow сборки.

**Backfill:** при первом запуске (или если много релизов пропущено) собираются до 10 последних upstream-релизов.

### 2. Сборка static-бинарника (musl)

- Контейнер `alpine:latest` или установленный `musl-tools`.
- Собирается `./configure --disable-shared --enable-static-bin` (или аналогичные флаги iperf3).
- Готовый бинарник упаковывается в tar.gz с README.

### 3. Сборка dynamic-бинарника (glibc)

- GitHub Actions runner `ubuntu-20.04` (glibc 2.31) — компромисс между стабильностью runner и совместимостью с CentOS Stream 8 (glibc 2.28).
- Альтернатива: сборка в контейнере `quay.io/centos/centos:stream8` для максимальной совместимости.
- Решение: использовать `ubuntu-20.04` как более простой вариант; если потребуется более старая glibc — перейти на CentOS Stream 8 контейнер.

### 4. Имена файлов и Release

- Тег: `v3.17.1` (совпадает с upstream полностью, включая `v`-префикс).
- Файлы (version без `v` в имени файла):
  - `iperf3-3.17.1-linux-x86_64-static.tar.gz`
  - `iperf3-3.17.1-linux-x86_64-dynamic.tar.gz`
  - `SHA256SUMS`
- Release title: `iperf3 v3.17.1 builds`
- Release notes: копия из upstream-релиза.
- Pre-release флаг: переносится из upstream.

### 5. Обработка ошибок сборки

Если хотя бы один из двух вариантов (static или dynamic) не собрался, весь релиз считается неудачным. GitHub Release не создаётся, артефакты не публикуются. Workflow падает с ошибкой, чтобы команда могла разобраться и сделать сборку надёжной.

### 6. Получение исходного кода iperf3

Для любого upstream-тега (stable или rc) используется `git clone --branch <tag> --depth 1 https://github.com/esnet/iperf.git`, после чего запускается `autoreconf -fi` и `./configure ...`. Это работает и для обычных релизов, и для rc/pre-release тегов, у которых может не быть официального tarball.

### 7. Содержимое архива

Каждый `.tar.gz` содержит директорию `iperf3-{version}-linux-x86_64-{static|dynamic}/` с файлами:
- `iperf3` — собранный бинарник;
- `README.md` — краткая инструкция и примечание о типе сборки (static/dynamic);
- `LICENSE` — копия upstream-лицензии.

## Что оставлено на усмотрение строителя

- Точные флаги `configure` для iperf3 (проверить в upstream-документации).
- Использовать ли отдельный reusable workflow для сборки.
- Нужно ли добавлять `.gitattributes`, `LICENSE`, `README.md` в репозиторий.
- Окончательный выбор окружения для dynamic-сборки: `ubuntu-20.04` vs CentOS Stream 8 контейнер (по умолчанию — `ubuntu-20.04` как более простой вариант).

## Предполагаемый план реализации

1. Создать пустой репозиторий `rusnino/iperf3-builds` через `gh repo create`.
2. Добавить файлы:
   - `.github/workflows/release-watcher.yml`
   - `.github/workflows/build-release.yml`
   - `README.md`
   - `scripts/build-static.sh`
   - `scripts/build-dynamic.sh`
3. Запушить в `main`.
4. Вручную запустить workflow для последней версии iperf3, чтобы проверить.
5. Проверить, что релиз создался и бинарники работают.
