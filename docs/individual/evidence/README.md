# Доказательства индивидуальной работы

Все материалы получены на стенде `eu-central-1` после применения
`docs/individual/tofu/secrets`, `image` и `app`. Номер аккаунта в скриншотах
и текстах заменён на `<account>`; значения секрета и пароли не публикуются.
Тестовый пользователь `individual-secrets-1795739589@example.com` —
синтетический.

| Файл | Что показывает |
| --- | --- |
| `01-app-wall-secretsmanager.png` | Публичная стена с капсулой, созданной приложением, которое читает пароль из Secrets Manager |
| `02-app-health-ok.png` | `/health` → 200, `credentials: secretsmanager` |
| `03-secretsmanager-console.png` | Секрет `timecapsule-dev-db` в консоли; значение не раскрыто |
| `04-app-failure-500.png` | B4: пользователь видит 500 после `Deny` в policy |
| `05-app-failure-health-500.png` | B4: `/health` → 500, `credentials: error` |
| `06-app-recovered.png` | После возврата `Allow` и замены ASG-инстансов `/health` → 200 |
| `07-opener-b4.json` | Lambda opener открыл капсулу во время сбоя веб-приложения |
| `08-b4-background-job.txt` | Капсула №11 и уведомление, созданные opener во время B4 |
| `09-b4-target-health.txt` | HTTP 500, `unhealthy` targets и независимая работа статики/Lambda |
| `10-baseline-inventory.txt` | Инвентаризация 6 исторических мест и 5 действующих копий до ротации |
| `11-secret-measurements.txt` | 3 → 43 символа, 138–346 мс холодного чтения, 0–1 мс из кэша, `/health` |
| `12-b4-access-denied.txt` | `AccessDeniedException`, HTTP 500 и `unhealthy` targets |
| `13-old-password-rejected.txt` | Старый пароль отвергается PostgreSQL |

## Как повторяли B4

```sh
cd docs/individual/tofu/secrets
TF_VAR_db_password='<current app DB password>' \
  tofu apply -var='enable_secret_access=false'
# на ASG-инстансах:
sudo rm -f /dev/shm/timecapsule-db-*.json
sudo systemctl restart php-fpm
curl -i http://<alb-dns>/health
```

Затем вернули `enable_secret_access=true`, очистили кэш и заменили инстансы
ASG, чтобы получить свежие credentials. IAM eventual consistency и кэш
300 с описаны в ADR-0008.
