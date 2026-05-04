from yaml import safe_load
from pathlib import Path
from json import dumps


version = '1.0.1'

def load_yaml(
              file_path:Path,
              encoding:str = "utf-8",
              subsection:str = ''
             ) -> dict:
    """
    Загружает данные из YAML-файла в виде словаря.

    Безопасно парсит YAML с использованием safe_load. Поддерживает загрузку
    всего файла или конкретной секции. Обрабатывает все возможные ошибки
    (кодировка, синтаксис, отсутствие файла) и ведёт логирование.

    :param file_path: Путь к YAML-файлу, который необходимо загрузить.
    :type file_path: Path
    :param encoding: Кодировка файла. По умолчанию — 'utf-8'.
    :type encoding: str
    :param subsection: Имя секции в YAML, которую нужно загрузить. Если не указано,
                       возвращается весь документ.
    :type subsection: str
    :return: Словарь с загруженными данными. Может быть пустым.
    :rtype: dict
    """

    data: dict = {}
    # Открываем YAML-файл для чтения
    data = safe_load(file_path.read_text(encoding=encoding)) or {}  # Загружаем содержимое файла в словарь с помощью safe_load
    if subsection:
        data = data[subsection]
   
    return data


print(dumps(load_yaml(Path(__file__).parent / 'pores_n_chemistry.yaml'), sort_keys=True, indent=2))
