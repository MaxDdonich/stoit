# СТОИТ — бэкенд кнопки «Обновить»

Это Cloudflare Worker. Он не хранит токен в сайте: токен лежит в секретах Worker.

## Что делает

- `POST /refresh` — запускает GitHub Actions workflow `update.yml`.
- `GET /status` — отдаёт статус последнего запуска.
- `GET /health` — проверка без секретов.

Лимит: **20 минут** на глобальный запуск и на IP. Повторный запрос вернёт `429` с `Retry-After`.

## Настройка

1. Создайте fine-grained GitHub token:
   - доступ только к репозиторию `MaxDdonich/stoit`;
   - `Actions: Read and write`;
   - `Contents: Read` (достаточно).
2. В Cloudflare создайте Worker `stoit-refresh`.
3. Загрузите `worker.js` или подключите репозиторий.
4. Variables:
   - `GITHUB_REPO=MaxDdonich/stoit`
   - `WORKFLOW_FILE=update.yml`
   - `GITHUB_REF=main`
   - `ALLOWED_ORIGINS=https://maxddonich.github.io,http://localhost:8787`
   - `COOLDOWN_SECONDS=1200`
5. Secret:
   - `GITHUB_TOKEN=<fine-grained token>`
6. По желанию создайте KV namespace и binding `RATE_LIMIT` — тогда общий лимит будет строгим.
7. Скопируйте URL Worker вида `https://stoit-refresh.<account>.workers.dev` в `assets/config.js`:

```js
window.STOIT_CONFIG = {
  refreshApi: "https://stoit-refresh.<account>.workers.dev"
};
```

8. Закоммитьте `assets/config.js` и запустите workflow.

## Проверка

```powershell
curl.exe -i https://stoit-refresh.<account>.workers.dev/health
```

```powershell
curl.exe -i -X POST https://stoit-refresh.<account>.workers.dev/refresh `
  -H "Origin: https://maxddonich.github.io"
```

Первый запрос вернёт `202`, повторный в течение 20 минут — `429`.

## Безопасность

- Токен не попадает во фронтенд.
- Origin проверяется по `ALLOWED_ORIGINS`.
- Есть лимит 20 минут и на IP, и глобальный.
- Токен можно отозвать в любой момент.
- Не добавляйте `.dev.vars` и `.wrangler/` в git.
