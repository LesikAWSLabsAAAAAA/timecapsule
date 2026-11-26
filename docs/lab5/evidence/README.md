# Выводы команд

Файлы `.txt` содержат фактический вывод; номер аккаунта и локальные пути исключаются перед публикацией. PNG строятся из этих же файлов:

```bash
python3 render_terminal.py evidence/02-apply-seven-days.txt evidence/02-apply-seven-days.png
```

Для скрипта нужны Python 3 и `rsvg-convert`. Пароли, дампы SQL, `.tfvars`, state и бинарные планы сюда не добавляются.
