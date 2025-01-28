#!/bin/sh

# Цвета для вывода сообщений
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m' # Желтый цвет
NC='\033[0m' # Без цвета

# Версия скрипта
VERSION="1.5.1"

# Вывод версии скрипта
printf "${GREEN}Версия скрипта: $VERSION${NC}\n"

# Функция для вывода справки
show_help() {
    printf "${GREEN}Использование: ${GREEN}./install_xray.sh ${YELLOW}{command}${NC}\n\n"
    printf "${GREEN}Команды:${NC}\n"
    printf "  ${YELLOW}update|-u [version]${NC} - Обновить Xray. Если версия не указана, будет выполнено обновление до последней доступной версии.\n"
    printf "  ${YELLOW}recover|-r${NC}          - Восстановить Xray из резервной копии.\n"
    printf "  ${YELLOW}task HH:MM day${NC}      - Запланировать обновление Xray. Если day = 8, то задание будет выполнено ежедневно.\n"
    printf "  ${YELLOW}task 0${NC}              - Удалить запланированное обновление.\n"
    printf "  ${YELLOW}help|-h${NC}             - Показать это сообщение.\n"
}

# Функция для отключения обновлений Xkeen
disable_xkeen_update() {
    printf "${YELLOW}Отключение автоматических обновлений Xkeen...${NC}\n"
    
    # Отключение обновлений Xkeen с помощью команды xkeen -dxc без вывода сообщений
    xkeen -dxc > /dev/null 2>&1
    
    printf "${GREEN}Автоматическое обновление Xray через Xkeen отключено, чтобы предотвратить откат до версии 1.8.4.${NC}\n"
}

# Определите архитектуру процессора
ARCH=$(uname -m)
printf "${GREEN}Определенная архитектура: $ARCH${NC}\n"

# Дополнительная информация о процессоре для проверки
lscpu | grep -E 'Architecture|Model name|CPU(s)'

# Проверка аргумента командной строки
ACTION=$1

if [ "$ACTION" = "task" ]; then
    TIME=$2
    DAY=$3

    # Если введено время 0, удаляем задачу cron
    if [ "$TIME" = "0" ]; then
        crontab -l | grep -v './install_xray.sh update' | crontab -
        printf "${GREEN}Все задачи обновления Xray удалены.${NC}\n"
        exit 0
    fi

    # Преобразование формата времени
    if echo "$TIME" | grep -Eq '^[0-9]{1,2}:[0-9]{1,2}$'; then
        MINUTE=$(echo "$TIME" | cut -d':' -f2)
        HOUR=$(echo "$TIME" | cut -d':' -f1)
    else
        printf "${RED}Укажите корректное время (HH:MM или H:M).${NC}\n"
        exit 1
    fi

    # Проверка корректности дня недели (0-7 для дней недели, 8 для ежедневного выполнения)
    if [ "$DAY" -lt 0 ] || [ "$DAY" -gt 8 ]; then
        printf "${RED}Укажите корректный день (0-7 для дней недели или 8 для ежедневного выполнения).${NC}\n"
        exit 1
    fi

    # Если день 8, заменяем его на * для ежедневного выполнения
    if [ "$DAY" -eq 8 ]; then
        DAY="*"
    elif [ "$DAY" -eq 7 ]; then
        DAY=0
    fi

    # Удаление старых задач cron с `./install_xray.sh update`
    crontab -l | grep -v './install_xray.sh update' | crontab -

    # Добавление новой задачи в cron
    (crontab -l 2>/dev/null; echo "$MINUTE $HOUR * * $DAY ./install_xray.sh update") | crontab -

    # Определение названия дня
    DAY_NAME=""
    case $DAY in
        0) DAY_NAME="воскресенье" ;;
        1) DAY_NAME="понедельник" ;;
        2) DAY_NAME="вторник" ;;
        3) DAY_NAME="среда" ;;
        4) DAY_NAME="четверг" ;;
        5) DAY_NAME="пятница" ;;
        6) DAY_NAME="суббота" ;;
        *) DAY_NAME="ежедневно" ;;
    esac

    printf "${GREEN}Задача обновления Xray запланирована на $TIME в день $DAY_NAME.${NC}\n"

elif [ "$ACTION" = "update" ] || [ "$ACTION" = "-u" ]; then
    VERSION_ARG=$2

    if [ -n "$VERSION_ARG" ]; then
        VERSION_PATH="v$VERSION_ARG"
        URL_BASE="https://github.com/XTLS/Xray-core/releases/download/$VERSION_PATH"
    else
        VERSION_PATH="latest"
        URL_BASE="https://github.com/XTLS/Xray-core/releases/latest/download"
    fi

    case $ARCH in
        "aarch64")
            URL="$URL_BASE/Xray-linux-arm64-v8a.zip"
            ARCHIVE="Xray-linux-arm64-v8a.zip"
            ;;
        "mips"|"mipsle")
            URL="$URL_BASE/Xray-linux-mips32le.zip"
            ARCHIVE="Xray-linux-mips32le.zip"
            ;;
        "mips64")
            URL="$URL_BASE/Xray-linux-mips64.zip"
            ARCHIVE="Xray-linux-mips64.zip"
            ;;
        "mips64le")
            URL="$URL_BASE/Xray-linux-mips64le.zip"
            ARCHIVE="Xray-linux-mips64le.zip"
            ;;
        *)
            printf "${RED}Неизвестная архитектура: $ARCH${NC}\n"
            exit 1
            ;;
    esac

    # Остановка xkeen
    printf "${GREEN}Остановка xkeen...${NC}\n"
    xkeen -stop

    # Убедитесь, что /opt/sbin существует
    mkdir -p /opt/sbin

    # Создайте директорию для резервных копий, если она не существует
    BACKUP_DIR="/opt/backups"
    mkdir -p $BACKUP_DIR

    # Проверка наличия резервной копии в /opt/backups
    BACKUP_FILE="$BACKUP_DIR/xray_backup_v1.8.4"
    
    if [ -f /opt/sbin/xray ]; then
        if [ ! -f "$BACKUP_FILE" ]; then
            printf "${GREEN}Архивация существующего файла xray...${NC}\n"
            mv /opt/sbin/xray "$BACKUP_FILE"
        else
            printf "${YELLOW}Резервная копия с именем xray_backup_v1.8.4 уже существует.${NC}\n"
        fi
    fi

    # Скачайте архив
    printf "${GREEN}Скачивание $ARCHIVE...${NC}\n"
    curl -s -S -L -o /tmp/$ARCHIVE $URL

    # Извлечение только нужного файла из архива
    printf "${GREEN}Извлечение xray из $ARCHIVE...${NC}\n"
    TEMP_DIR=$(mktemp -d)
    unzip -j /tmp/$ARCHIVE xray -d $TEMP_DIR

    # Перемещение только нужного файла в /opt/sbin
    printf "${GREEN}Перемещение xray в /opt/sbin...${NC}\n"
    mv $TEMP_DIR/xray /opt/sbin/xray

    # Установка прав на исполняемый файл
    printf "${GREEN}Установка прав доступа...${NC}\n"
    chmod 755 /opt/sbin/xray

    # Удаление временной директории и архива
    printf "${GREEN}Очистка...${NC}\n"
    rm -rf $TEMP_DIR
    rm /tmp/$ARCHIVE

    # Запуск xkeen
    printf "${GREEN}Запуск xkeen...${NC}\n"
    xkeen -start

    # Вызов функции для отключения обновлений только после успешного завершения установки/обновления
    disable_xkeen_update

    printf "${GREEN}Обновление завершено.${NC}\n"

elif [ "$ACTION" = "recover" ] || [ "$ACTION" = "-r" ]; then
    # Остановка xkeen
    printf "${GREEN}Остановка xkeen...${NC}\n"
    xkeen -stop

    # Проверка наличия резервной копии
    BACKUP_FILE="/opt/backups/xray_backup_v1.8.4"

    if [ -f "$BACKUP_FILE" ]; then
        printf "${GREEN}Восстановление оригинального файла xray...${NC}\n"
        mv "$BACKUP_FILE" /opt/sbin/xray

        # Установка прав доступа
        chmod 755 /opt/sbin/xray
    else
        printf "${RED}Резервная копия не найдена. Восстановление невозможно.${NC}\n"
        exit 1
    fi

    # Запуск xkeen
    printf "${GREEN}Запуск xkeen...${NC}\n"
    xkeen -start

    printf "${GREEN}Восстановление завершено.${NC}\n"
else
    show_help
    exit 0
fi
