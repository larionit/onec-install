#!/bin/bash

# Ссылка на устанавливаемый скрипт
target_script_url=https://raw.githubusercontent.com/larionit/onec-install/dev/onec-install.sh

# Ссылка на этот установочный скрипт (нужно в случае повышения привелегий через sudo)
setup_script_url=https://raw.githubusercontent.com/larionit/onec-install/dev/setup.sh

# Временный файл для этого установочного скрипта (нужно в случае повышения привелегий через sudo)
temp_setup_script=$(mktemp)

# Загрузка этого установочного скрипта (нужно в случае повышения привелегий через sudo)
curl -fsSL "$setup_script_url" -o "$temp_setup_script"

# Повышение привелегий
if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$temp_setup_script" "$@"
fi

# Задаем имя для создаваемой директории (берем имя устанавливаемого скрипта без расширения)
target_script_name=$(basename "$target_script_url")
target_script_dir_name="${target_script_name%.*}"
target_script_dir="/opt/${target_script_dir_name}"
target_script_path="$target_script_dir/$target_script_name"

# Переименовываем файл, если он уже существует, если нет - создаем директорию.
if [ -f "$target_script_path" ]; then
    time=$(date +%G_%m_%d_%H_%M_%S)
    cp "$target_script_path" "$target_script_path.old.$time"
else
    mkdir $target_script_dir
fi

# Загружаем устанавливаемый скрипт
curl -fsSL "$target_script_url" -o "$target_script_path"

# Выдаем права на запуск
chmod +x "$target_script_path"

# Задаем путь для символической ссылки
target_script_symlink="/usr/local/bin/${target_script_name%.*}"

# Создаем символическую ссылку
if [ ! -L "$target_script_symlink" ]; then
    ln -s "$target_script_path" "$target_script_symlink"
fi

# Запускаем устанавливаемый скрипт
bash "$target_script_path"

# Удаление временного файла установочного скрипта
rm -f "$temp_setup_script"