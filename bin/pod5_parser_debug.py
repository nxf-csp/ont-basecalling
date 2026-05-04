#!/usr/bin/env python3

from sys import argv
from pod5 import Reader
from json import dumps, load as json_load
#from yaml import safe_load
from pathlib import Path

version = '1.0.1'
'''
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
'''
with open(Path(__file__).parent / 'pores_n_chemistry.json', 'r') as json:
    ont_kits = json_load(json)

def read_pod5(pod5_file:str) -> dict:
    metadata = {}
    with Reader(pod5_file) as reader:
        try:
            # Берём первый рид, читаем его свойства
            read = next(reader.reads())
        except StopIteration:
            return metadata
        # Собираем метадату по свойствам read.run_info, в случае её отсутствия - пишем 'unknown'
        for k,v in {'flow_cell':read.run_info.flow_cell_product_code,
                    'sequencer_type':read.run_info.sequencer_position_type}.items():
            if v:
                metadata[k] = v
        if read.run_info.acquisition_start_time:
            read.run_info.acquisition_start_time
            metadata['created'] = read.run_info.acquisition_start_time.strftime('%d.%m.%Y %H:%M:%S')
        if read.run_info.context_tags:
            for key in ['sample_frequency', 'sequencing_kit']:
                if key in read.run_info.context_tags.keys():
                    metadata[key] = read.run_info.context_tags[key]
            # Вытаскиваем basecall_config_filename для извлечения данных о поре и скорости чтения
            basecall_config_filename = read.run_info.context_tags.get('basecall_config_filename', '')
            if basecall_config_filename:
                bcf_parts = basecall_config_filename.split('_')
                metadata['experiment_type'] = bcf_parts[0]
                metadata['pore'] = bcf_parts[1].replace('.', '')
                metadata['pore_speed'] = bcf_parts[2]
            else:
                print(metadata['sequencing_kit'])
                flow_cell_data = ont_kits['flow_cell'].get(metadata['flow_cell'])
                sequencing_kit_data = ont_kits['sequencing_kit'].get(metadata['sequencing_kit'])

                metadata['experiment_type'] = flow_cell_data.get('experiment_type', 'unknown')
                if 'rna' in metadata['sequencing_kit']:
                    metadata['experiment_type'] = 'rna'
                metadata['pore'] = flow_cell_data.get('pore', 'unknown')
                metadata['pore_speed'] = sequencing_kit_data.get('pore_speed', 'unknown')
        
        # Проверка, что мы имеем все важные данные и они валидны
        for important_key in [
                              'experiment_type',
                              'pore',
                              'pore_speed',
                              'sample_frequency',
                              'sequencing_kit'
                             ]:
            if any([
                    important_key not in metadata.keys(),
                    not data_is_valid(important_key, metadata[important_key])
                  ]):
                return {}
    return metadata

def data_is_valid(key:str, value:str) -> bool:
    validations = {
                   'experiment_type':['dna', 'rna'],
                   'pore':['r941', 'r1041', 'rp4'],
                   'pore_speed':['70bps', '130bps', '260bps', '400bps', '450bps', 'e8', 'e8.2'],
                   'sample_frequency':['3000', '3012', '4000', '5000']
                  }
    if key == 'sequencing_kit':
        if value:
            return True
    if value in validations[key]:
        return True
    return False

if __name__ == '__main__':
    request = argv[1]
    if request == 'version':
        data = version
    else:
        data = dumps(read_pod5(request))
    print(data)