# CloudIDE — Frontend

Фронтенд написан на **Flutter** (Dart). Поддерживает мобильные и десктопные платформы. Подключается к бэкенду по HTTP и WebSocket.

---

## Стек и зависимости

| Пакет | Роль |
|---|---|
| `http` | HTTP-запросы к бэкенду |
| `web_socket_channel` | WebSocket (IOWebSocketChannel) |
| `xterm` | Терминал-виджет в редакторе кода |
| `shared_preferences` | Хранение токенов и сессии |
| `flutter/material` | UI-компоненты, темизация |

---

## Конфигурация

Файл `lib/constants.dart`:

```dart
const String kServerIp    = 'http://109.195.27.97:8888';
const String kServerIpWs  = 'ws://109.195.27.97:8888';
const String kRefreshTokenEndpoint = '/auth/refresh';
```

---

## Структура файлов

```
lib/
├── main.dart                         — точка входа, роутинг, загрузка темы
├── constants.dart                    — адреса сервера
│
├── screens/
│   ├── login_screen.dart             — форма входа / регистрации
│   ├── register_screen.dart          — экран регистрации
│   ├── github_auth_screen.dart       — экран привязки GitHub
│   ├── clone_repository_screen.dart  — клонирование GitHub-репо
│   ├── main_screen.dart              — список проектов пользователя
│   ├── create_project_screen.dart    — создание нового проекта
│   ├── code_editor_screen.dart       — редактор кода + терминал
│   └── profile_screen.dart           — профиль пользователя / сессии
│
├── services/
│   ├── auth_service.dart             — login, register, verify-code
│   ├── auth_middleware.dart          — прослойка для защищённых запросов
│   ├── jwt_service.dart              — парсинг и валидация JWT
│   ├── token_refresh_service.dart    — авто-обновление access-токена
│   ├── project_service.dart          — CRUD проектов, clone, start
│   ├── file_service.dart             — файловые операции, GitHub commit
│   └── profile_service.dart         — данные профиля, сессии
│
├── manager/
│   ├── connection_manager.dart       — WebSocket + базовые HTTP-методы
│   └── project_manager.dart         — обёртка: create/connect, навигация
│
├── theme/
│   └── app_theme.dart                — светлая и тёмная темы
│
└── widgets/
    └── terminal_widget.dart          — виджет xterm-терминала
```

---

## Точка входа (`main.dart`)

1. Загружает `SharedPreferences`.
2. Восстанавливает выбранную тему (`light` / `dark`).
3. Если `isLoggedIn == true` и JWT ещё валиден — сразу открывает `/main`, иначе очищает сессию и показывает `/`.

Маршруты приложения:

| Маршрут | Экран | Аргументы |
|---|---|---|
| `/` | `LoginScreen` | — |
| `/main` | `MainScreen` | `userId`, `jwtToken` |
| `/profile` | `ProfileScreen` | `userId`, `jwtToken` |

---

## Сервисы

### `AuthService`
Взаимодействует с `/login`, `/register`, `/verify-code`.

- `login(email, password)` → возвращает `{ userId, token, refreshToken }`. Валидирует access-токен перед сохранением.
- `register(username, email, password)` → `false` — первичная регистрация (код отправлен), `true` — код отправлен повторно (email уже зарегистрирован, но не подтверждён).
- `confirmCode(email, code)` → подтверждает email.

### `JwtHelper` (`jwt_service.dart`)
Чисто клиентская утилита — работает без сети.

- `isTokenValid(token)` — проверяет `exp` в payload, с буфером в 30 секунд.
- `shouldRefreshToken(token)` — `true`, если до истечения < 5 минут.
- `getUserIdFromToken(token)` — читает `user_id` из payload.
- `getTokenExpiry(token)` — возвращает `DateTime` истечения.

### `TokenRefreshService`
Автоматическое обновление access-токена в фоне.

- `startAutoRefresh()` — запускает `Timer.periodic` каждые 60 секунд.
- `stopAutoRefresh()` — останавливает таймер.
- `refreshToken()` — отправляет `POST /auth/refresh` с `refresh_token` из `SharedPreferences`, сохраняет новый access-токен.
- `refreshTokenWithRetry(maxAttempts: 3)` — с экспоненциальной задержкой между попытками.

### `ProjectService`
- `fetchProjects(jwtToken)` → список `Project` из `GET /projects`.
- `createProject(...)` → `POST /project` с именем и списком языков.
- `deleteProject(...)` → `DELETE /project/{name}`.
- `cloneProjectFromGitHub(repoUrl)` → `POST /project/clone`.
- `startContainer(projectName)` → `POST /project/start/{name}`.

### `FileService`
Все методы работают в контексте конкретного `projectName`.

| Метод | Эндпоинт | Описание |
|---|---|---|
| `fetchFileList()` | `GET /project/{name}/files` | Список путей файлов и папок |
| `fetchFileContent(fileName)` | `GET /project/{name}/file?filename=...` | Содержимое файла (UTF-8) |
| `createFile(fileName)` | `POST /project/{name}/file/create` | Создать пустой файл |
| `createFolder(folderPath)` | `POST /project/{name}/folder` | Создать папку |
| `saveFile(fileName, content)` | `POST /project/{name}/file` | Сохранить содержимое |
| `moveFile(oldPath, newPath)` | `POST /project/{name}/move` | Переместить файл/папку |
| `renameFile(oldPath, newPath)` | `POST /project/{name}/move` | Псевдоним для move |
| `deleteFile(fileName)` | `DELETE /project/{name}/file?filename=...` | Удалить файл/папку |
| `fetchChangedFiles()` | `GET /project/{name}/changed-files` | Список изменённых файлов |
| `syncChangedFiles(files)` | `POST /project/{name}/changed-files` | Синхронизировать список |
| `createGitHubCommit(...)` | GitHub API | Коммит в репозиторий |

**Функция `buildFileTree(paths)`** — утилита, которая превращает плоский список путей в дерево `FileNode` для отображения в файловом менеджере.

#### Создание GitHub-коммита (`createGitHubCommit`)
Последовательность вызовов к GitHub API:
1. `GET /repos/{owner}/{repo}/git/refs/heads/main` — получить текущий SHA ветки.
2. Для каждого изменённого файла `POST /git/blobs` — загрузить blob.
3. `POST /git/trees` — создать дерево из blob'ов.
4. `POST /git/commits` — создать коммит.
5. `PATCH /git/refs/heads/main` (или `POST /git/refs` для первого коммита) — обновить ветку.

---

## Менеджеры

### `ConnectionManager`
Низкоуровневый класс, хранит `jwtToken`, `githubToken`, `githubLogin`.

- `login(username, password, updateStatus)` — устаревший метод (в текущей версии логин идёт через `AuthService`).
- `connect(projectName, terminal, updateStatus)` — открывает WebSocket по адресу `ws://.../project/{name}/ws?token=<jwt>`, подключает ввод/вывод к `xterm.Terminal`.
- `createProject(...)` — создание проекта через HTTP.
- `sendCommand(command)` — отправить строку в WebSocket.
- `fetchUserProfile(userId)` — загрузить `github_login` и `github_token` из профиля.

### `ProjectManager`
Обёртка над `ConnectionManager` для конкретного экрана.

- Инициализирует `Terminal(maxLines: 10000)`.
- `createProject(languages)` — берёт имя из `TextEditingController`, вызывает `ConnectionManager.createProject`.
- `connect(context)` — подключается к WebSocket; при успехе (`status.startsWith("Подключено")`) делает `Navigator.push` на `CodeEditorScreen`. При ошибке показывает `SnackBar`.

---

## Хранение сессии (`SharedPreferences`)

| Ключ | Тип | Описание |
|---|---|---|
| `isLoggedIn` | `bool` | Флаг авторизации |
| `userId` | `String` | ID пользователя |
| `jwtToken` | `String` | Access JWT |
| `refreshToken` | `String` | Refresh-токен |
| `themeMode` | `String` | `"light"` / `"dark"` |

---

## Темизация

`AppTheme` предоставляет `lightTheme()` и `darkTheme()`. Тема переключается через `ValueNotifier<ThemeMode> themeNotifier` (глобальный), без перезагрузки приложения.

---

## Экраны

| Экран | Функция |
|---|---|
| `LoginScreen` | Вход по email/паролю, переход к регистрации, GitHub OAuth |
| `RegisterScreen` | Форма регистрации, ввод кода подтверждения email |
| `GitHubAuthScreen` | Привязка GitHub-аккаунта через OAuth |
| `MainScreen` | Список проектов, удаление, переход к редактору, создание проекта |
| `CreateProjectScreen` | Форма создания: имя + выбор языков |
| `CloneRepositoryScreen` | Ввод GitHub URL для клонирования репозитория |
| `CodeEditorScreen` | Редактор кода, файловый менеджер, терминал (`TerminalWidget`), коммит в GitHub |
| `ProfileScreen` | Данные пользователя, список активных сессий, выход |
