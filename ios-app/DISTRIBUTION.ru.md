# Распространение iOS-приложения

GitHub Actions собирает неподписанный архив `.app.zip` для проверки кода. Установка на iPhone требует действующей подписи Apple для приложения и расширения Network Extension. На Mac с настроенной подписью используйте `./build_ios_app.sh`. Скрипт создаёт `ios-app/build/export/OpenFlux.ipa`.

Bundle ID: `com.p1neapplexpress-saharev.openflux`.
Extension ID: `com.p1neapplexpress-saharev.openflux.tunnel`.
Team ID указан в `ios-app/project.yml`; он должен соответствовать профилям.

После сборки проверьте подключение и переподключение на реальном iPhone.
