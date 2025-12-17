# 🚀 Руководство по настройке Low Latency (HFT) Linux
**Цель:** Минимальный джиттер (Jitter), отключение энергосбережения, мгновенная обработка сетевых пакетов.
**Железо:** AMD Ryzen 5000+ / Intel Core.

---

## 0. Диагностика сети (Узнаем имя карты и драйвер)
Прежде чем создавать сервисы, нужно узнать имя интерфейса и возможности драйвера.

1.  **Узнаем имя интерфейса:**
    ```bash
    ip link show
    ```
    *Ищи интерфейс, который НЕ `lo` и имеет состояние `UP` (например, `enp6s0`, `eth0`, `eno1`).*

2.  **Узнаем драйвер:**
    Подставь имя своего интерфейса (например, `enp6s0`):
    ```bash
    ethtool -i enp6s0
    ```
    *   **driver:** `igc` / `r8169` / `e1000e` (важно для выбора команд настройки).
    *   **bus-info:** Адрес шины (полезно, если карт несколько).

---

## 1. BIOS / UEFI (Первый уровень)
Перед загрузкой ОС нужно правильно настроить железо.

*   **Global C-States:** `Auto` или `Enabled` (управляем ими из Linux) или `Disabled` (если BIOS позволяет).
*   **Turbo Boost / Core Performance Boost:** `Enabled`.
*   **Hyper-Threading (SMT):**
    *   Для максимальной скорости одного потока: `Disabled` (меньше шума, больше кэша на поток).
    *   Если нужно много потоков для расчетов: `Enabled`.
*   **Memory Profile (XMP/DOCP):** `Enabled` (максимальная частота RAM критична для HFT).
*   **Virtualization (VT-d / SVM):** `Disabled` (если не используешь VM, это уберет небольшие накладные расходы).

---

## 2. Установка ядра и утилит
В Ubuntu есть готовое ядро. В Debian пропускаем установку ядра, ставим только утилиты.

```bash
# 1. Обновляем репозитории
sudo apt update && sudo apt upgrade -y

# 2. Ставим ядро LowLatency (Только для Ubuntu!)
sudo apt install linux-lowlatency linux-headers-lowlatency

# 3. Ставим утилиты для настройки и мониторинга
# linux-tools нужен для turbostat (правильный мониторинг частоты)
sudo apt install cpufrequtils ethtool msr-tools linux-tools-generic linux-tools-$(uname -r)
```

**После установки ядра — перезагрузка:** `sudo reboot`

---

## 3. Настройка GRUB (Отключение "сна" процессора)
Здесь настройки отличаются для AMD и Intel.

Открой файл: `sudo nano /etc/default/grub`
Найди строку `GRUB_CMDLINE_LINUX_DEFAULT="..."`.

### Вариант А: Для AMD Ryzen (5000/7000/9000)
Заменяем строку на:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash processor.max_cstate=1 idle=nomwait amd_pstate=active"
```
*   `processor.max_cstate=1`: Запрещает глубокий сон, ядра всегда готовы.
*   `idle=nomwait`: Отключает инструкцию `mwait` для простоя (оптимизация для AMD).

### Вариант Б: Для Intel Core / Xeon
Заменяем строку на:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_idle.max_cstate=0 processor.max_cstate=1"
```
*   `intel_idle.max_cstate=0`: Отключает встроенный драйвер сна Intel (самый жесткий метод).

**Применяем:**
```bash
sudo update-grub
```

---

## 4. Фиксация частоты CPU (Governor)
Заставляем процессор всегда работать на максимуме, не дожидаясь нагрузки.

1.  Создаем конфиг:
    `echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils`
2.  Перезапускаем службу (и выключаем демон ondemand, если он есть):
    ```bash
    sudo systemctl disable ondemand 2>/dev/null
    sudo systemctl restart cpufrequtils
    ```
---
## 5. Настройка сетевого стека (Sysctl)
Оптимизируем буферы ядра: меньше очередей — меньше задержка.
Создай файл: `sudo nano /etc/sysctl.d/99-hft.conf`
```ini
# --- Low Latency Network Tuning ---

# Busy Polling (активное ожидание пакетов сокетом)
# Значение в микросекундах (50-100 мкс - хороший старт)
net.core.busy_read = 50
net.core.busy_poll = 50

# Отключаем медленный старт TCP после простоя
net.ipv4.tcp_slow_start_after_idle = 0

# Размеры буферов. Не делаем их гигантскими, чтобы избежать bufferbloat.
# Но достаточными, чтобы не терять пакеты при микровсплесках.
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Быстрый повторный использование TIME-WAIT сокетов
net.ipv4.tcp_tw_reuse = 1
```

Примени: `sudo sysctl -p /etc/sysctl.d/99-hft.conf`

---

## 6. Настройка сетевой карты (Ethtool Service)
Самый капризный этап. Зависит от драйвера.

Создаем сервис: `sudo nano /etc/systemd/system/hft-network-tuning.service`

```ini
[Unit]
Description=HFT Network Tuning (Disable Coalescing)
After=network.target

[Service]
Type=oneshot
# ВАЖНО: Замени enp6s0 на имя своего интерфейса (команда ip a)

# ВАРИАНТ 1: Для Intel I225/I226 (драйвер igc) и некоторых Realtek
# У этих карт "спаренные очереди", нельзя настраивать tx/rx раздельно и adaptive может не работать.
ExecStart=/usr/sbin/ethtool -C enp6s0 rx-usecs 0
# Если падает с ошибкой на 0, поставь rx-usecs 3

# ВАРИАНТ 2: Для серверных карт (Intel X520/X710, Mellanox)
# ExecStart=/usr/sbin/ethtool -C enp6s0 adaptive-rx off adaptive-tx off rx-usecs 0 tx-usecs 0

# Увеличиваем длину очереди TX (чтобы не дропать исходящие при всплеске)
ExecStart=/sbin/ip link set enp6s0 txqueuelen 5000

[Install]
WantedBy=multi-user.target
```

**Активация:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable hft-network-tuning.service
sudo systemctl start hft-network-tuning.service
# Проверка статуса (должен быть success/inactive)
sudo systemctl status hft-network-tuning.service
```

---

## 7. Проверка результата

После перезагрузки (`sudo reboot`) проверяем, что все применилось.

#### А. Проверка режима процессора
Убедись, что частота максимальна и не скачет, а глубокие C-states (энергосбережение) выключены.
```bash
# Текущая частота и режим
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | head -n 1
# Должно вернуть: performance
# Детальный мониторинг (выход через Ctrl+C)
sudo turbostat --interval 1
```
*   **Bzy_MHz:** Должно быть близко к максимуму (или базе).
*   **C3/C6/C7%:** В этих колонках должны быть нули (или прочерки). Это значит, ядра не засыпают.
#### Б. Проверка сетевых задержек
Проверяем, что наши настройки `ethtool` применились сервисом.
```bash
# Замени enp6s0 на свой интерфейс
ethtool -c enp6s0
```

**Что искать в выводе:**
1.  **Adaptive RX:** `off` (Адаптивный режим выключен).
2.  **Adaptive TX:** `off` (Если драйвер поддерживает).
3.  **rx-usecs:** `0` (или `3`, или другое низкое значение, которое ты задал).
4.  **tx-usecs:** `0` (или `3`). *Примечание: на картах с драйвером `igc` этот параметр может не отображаться или дублировать rx.*

Если видишь большие цифры (например, 70, 100) или Adaptive RX: on — значит, Systemd-сервис не сработал или содержит ошибку. Проверь его статус: `sudo systemctl status hft-network-tuning.service`.

---

## 8. Памятка для C# разработчика

В твоем коде настройки Linux бесполезны, если ты не отключишь буферизацию внутри .NET.

```csharp
// 1. Отключаем алгоритм Нейгла (ожидание заполнения пакета)
socket.NoDelay = true; // Для TcpClient
// или
socket.SetSocketOption(SocketOptionLevel.Tcp, SocketOptionName.NoDelay, true);

// 2. Не делай огромные буферы приема в Socket
socket.ReceiveBufferSize = 8192; // Достаточно для HFT сообщений
```
