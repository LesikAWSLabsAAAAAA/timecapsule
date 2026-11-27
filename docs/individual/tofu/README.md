# OpenTofu: индивидуальная работа (Secrets Manager)

Три независимых стека с локальным state:

1. `secrets` — секрет `timecapsule-dev-db`, policy
   `timecapsule-dev-app-secretsmanager` и attachment к существующей роли
   `timecapsule-dev-app-role`. RDS и роль читаются через data sources.
2. `image` — AMI из существующего `timecapsule-dev-app` после того, как из
   его `.env` удалён `DB_PASSWORD` и добавлен `DB_SECRET_ARN`.
3. `app` — ALB и Auto Scaling group по этому AMI; включает RDS SG rule для
   app SG. `run_fleet=false` удаляет почасовые ALB/ASG.

## Порядок

```sh
# 1. Секрет и политика. Пароль передаётся только через env, не в файл.
cd docs/individual/tofu/secrets
tofu init
TF_VAR_db_password='<current app DB password>' tofu apply

# 2. На timecapsule-dev-app: удалить DB_PASSWORD, добавить DB_SECRET_ARN,
#    проверить php bin/check-secret.php и создать AMI.
cd ../image
tofu init
tofu apply -var='ami_name=timecapsule-dev-app-individual-20261127'

# 3. Запустить ASG/ALB.
cd ../app
tofu init
tofu apply -var='run_fleet=true' \
  -var='ami_name=timecapsule-dev-app-individual-20261127'

# 4. После сбора доказательств убрать почасовые ресурсы.
tofu apply -var='run_fleet=false' \
  -var='ami_name=timecapsule-dev-app-individual-20261127'
```

## B4

```sh
cd secrets
tofu apply -var='enable_secret_access=false' \
  -var='db_password=<current app DB password>'
# очистить /dev/shm/timecapsule-db-*.json и перезапустить php-fpm
tofu apply -var='enable_secret_access=true' \
  -var='db_password=<current app DB password>'
```

После `Deny` приложение отдаёт 500; ALB target становится unhealthy.
Фоновые Lambda используют свой env-пароль и продолжают работу.

## Безопасность

`terraform.tfstate`, `*.tfvars`, `.terraform/` исключены из Git. В state
секрет и пароль хранятся в открытом виде — это учебный компромисс. Для
production нужен удалённый backend с шифрованием и ограниченным доступом.
