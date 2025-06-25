#! /bin/bash
# Проверим что был передан аргумент
if [ $# -eq 0 ]; then
        echo "Передайте путь до диска типо /dev/sda"
        exit 0
fi
# Проверка формата аргумента
if [[ ! $1 =~ ^/dev/[a-zA-Z0-9]+$ ]]; then
    echo "Ошибка: Неверный формат устройства. Ожидалось что-то вроде /dev/sda"
    exit 1
fi
# Проверим запуск от имени администратора
if [ ${UID} -ne 0 ]; then
    echo "Ошибка: Скрипт должен быть запущен с правами суперпользователя (root)."
    echo "Используйте sudo или войдите как root."
    exit 1
fi
# Проверим существует ли блочное устройство, если нет создадим через утилиту parted
if [[ -e $1 && -b  $1  ]]; then
    echo "Блочное устроство  $1 существует"
    # Проверка, что устройство не смонтировано
    if  mount | grep -q $1; then
    echo "Ошибка: Устройство $1 уже смонтировано. Размонтируйте его перед выполнением операции."
    exit 1
    fi
else
    echo "Блочного устройства или файла не существует"
    exit 1
fi

if ! parted -s $1 mklabel gpt mkpart primary 0% 100%; then
    echo "Ошибка: Не удалось создать таблицу разделов GPT на устройстве $1."
    exit 1
fi
# Попросим ввести метку
read -p "Введите метку для диска (например, DATA): " LABEL
if [ -z ${LABEL} ]; then
    echo "Ошибка: Метка не может быть пустой."
    exit 1
fi
# Проверка, что метка была введена
if ! mkfs.xfs ${1}1 -L ${LABEL} -f 2>&1 > /dev/null; then
    echo "Ошибка: Не удалось отформатировать раздел в XFS."
    exit 1
fi
# Проверка коректности символов
if [[ ! "${LABEL}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Ошибка: Метка содержит недопустимые символы."
    exit 1
fi
# Попросим ввести путь монтирования
read -p "Введите путь монтирования (например, /tmp/data)" MOUNT_PATH
if [ -z ${MOUNT_PATH} ]; then
    echo "Ошибка: Поле не должно быть пустым"
fi
# Проверка на недопустимые символы
if [[ ! "${MOUNT_PATH}" =~ ^/[-a-zA-Z0-9_/]+$ ]]; then
    echo "Ошибка: Введённый путь содержит недопустимые символы."
    exit 1
fi
# Проверим есть ли такая директория
if [ -d ${MOUNT_PATH} ]; then
    echo "Директория ${MOUNT_PATH} уже существует."
else
    echo "Создаем директорию ${MOUNT_PATH}"
    if ! mkdir -p ${MOUNT_PATH}; then
        echo "Ошибка при создании директории ${MOUNT_PATH}"
        exit 1
    fi
fi
# Монтируем диск в директорию
if ! mount ${1}1 ${MOUNT_PATH} 2>&1 > /dev/null; then
    echo "Ошибка при монтировании диска $1 по пути ${MOUNT_PATH}"
    exit 1
else
    echo "Диск ${1}1 примонтирован в ${MOUNT_PATH}"
fi
# Проверим есть ли запись в /etc/fstab
# Сделаем резервную копию fstab
FSTAB_BACKUP="/etc/fstab.bak"
cp /etc/fstab "$FSTAB_BACKUP" || {
    echo "Ошибка: Не удалось создать резервную копию /etc/fstab."
    exit 1
}
if grep -q $1 /etc/fstab; then
    echo "Монтирование прописано в файлк /etc/fstab"
    exit 1
else
    if ! echo "LABEL=${LABEL} ${MOUNT_PATH} xfs defaults 0 0" >> /etc/fstab; then
        echo "Ошибка"
        mv ${FSTAB_BACKUP} /etc/fstab
        exit 1
    fi
fi
echo "Диск ${1}1 успешно примонтирован ${MOUNT_PATH} и записан в /etc/fstab"
