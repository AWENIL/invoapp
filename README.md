# Invotaxi — приложение водителя (Flutter)

## Бэкенд

Из каталога `invotaxi/backend`:

```text
python manage.py migrate
python manage.py load_mock_data
python manage.py runserver 0.0.0.0:8000
```

Первый тестовый водитель из моков: телефон **`+7 (900) 100-10-10`**. Код OTP в консоли сервера Django (строка вида `OTP для ...: 123456`).

## Запуск приложения

```text
cd driver_app
flutter pub get
flutter run
```

По умолчанию используется **локальный** бэкенд **`http://127.0.0.1:8000`** (мобильное API: `/api/mobile/`, см. `lib/config/env.dart`). Убедитесь, что Django запущен на `0.0.0.0:8000`.

Продакшен API:

```text
flutter run --dart-define=API_BASE_URL=https://api.invotaxi.ukudarov.pro
```

- **Android-эмулятор** к Django на ПК: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000`
- **Физическое устройство** в той же Wi‑Fi: `--dart-define=API_BASE_URL=http://<IP-вашего-ПК>:8000`

## Возможности

- Вход по телефону и OTP (JWT).
- Список заказов водителя, детали заказа, смена статуса поездки.
- Входящие предложения (принять / отклонить).
- Профиль: переключатель «На линии», краткая статистика, выход.
- Экран заказа: **карта маршрута** — на Android/iOS встроенная страница **Яндекс.Карт** с маршрутом A→B; в браузере (web) и на десктопе — полилиния по данным `GET /api/mobile/orders/{id}/route/` на подложке OpenStreetMap, плюс кнопка открытия в приложении Яндекс.Карты.

Документация API: `../backend/MOBILE_API_DOCUMENTATION.md`.
