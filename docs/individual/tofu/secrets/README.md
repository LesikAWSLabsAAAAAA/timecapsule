# Individual work: Secrets Manager stack

This stack creates:

- `timecapsule-dev-db` — the application database password;
- `timecapsule-dev-app-secretsmanager` — a least-privilege customer-managed policy;
- the policy attachment to the existing `timecapsule-dev-app-role`.

The stack reads the existing RDS instance and IAM role; it does not create or
change them. The secret contains the full connection shape, but the PHP
application currently reads only `password`; host, port, database and user
remain in environment variables.

## Apply

Use the current application DB password, not the RDS master password:

```sh
cd docs/individual/tofu/secrets
tofu init
TF_VAR_db_password='<current timecapsule password>' tofu apply
tofu output
```

The password is sensitive and will be stored in the local `terraform.tfstate`.
State, `.tfvars` and `.terraform/` are ignored by Git. Do not publish them.

## B4 failure exercise

The policy document switches from an `Allow` statement to an explicit `Deny`:

```sh
tofu apply -var='enable_secret_access=false'
# clear the app cache / restart PHP, then request /health
tofu apply -var='enable_secret_access=true'
```

The allow statement is limited to the secret ARN, `eu-central-1` and HTTPS.
The deny variant is used only for the exercise; it is not a production policy.

## Destroy

```sh
tofu destroy
```

`recovery_window_in_days = 0` allows immediate deletion of the secret during
the lab. For a production secret use a recovery window and a rotation plan.
