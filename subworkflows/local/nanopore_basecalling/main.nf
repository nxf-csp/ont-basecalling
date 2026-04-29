/*
Сабворкфлоу с функционалом подготовки исходных файлов секвенирования Oxford Nanopore к бэйсколлингу.
В процессе подготовки происходит конвертация (при необходимости) FAST5=>POD5 и из каждого файла извлекаются метаданные.
Затем на основе полученных метаданных формируются массивы файлов, разбитые по типу молекулы (ДНК/РНК) и версии поры (R9.4.1/R10.4.1).
Бэйсколлинг для каждой группы происходит отдельно. Также, при наличии соответствующего флага, происходит бейсколлинг модификаций  
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FAST5_TO_POD5; EXTRACT_POD5_METADATA }             from '../../../modules/local/pod5_actions/main'
include { PREPARE_BASECALLING_COMMANDS; DORADO_BASECALLING } from '../../../modules/local/dorado_basecalling/main'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow NANOPORE_BASECALLING {
    take:
    input_files // read in from --input/--input_dir
    ch_versions
    main:

    // Разбиваем входные файлы по расширениям
    input_files.branch {_meta, file ->
    fast5: file.toString().endsWith('.fast5')
    pod5: file.toString().endsWith('.pod5')}
    .set { ch_branched }

    // Сортируем файлы для конвертации FAST5=>POD5 по размеру (убыв.)
    ch_size_sorted_fast5_files = ch_branched.fast5
        .toSortedList { a, b ->
            b[1].size() <=> a[1].size() 
            }
            .flatten()
            .collate(2)

    // Для предотвращения копирования файлов конвертируем PATH=>String
    ch_size_sorted_fast5_str = ch_size_sorted_fast5_files.map {
        meta, path -> [meta, path.toString()]
    }
    
    // Конвертируем FAST5=>POD5
    FAST5_TO_POD5(ch_size_sorted_fast5_str)

    // Создаём общий канал pod5
    ch_pod5_files = ch_branched.pod5.mix(FAST5_TO_POD5.out.pod5)

    // Для предотвращения копирования файлов конвертируем PATH=>String
    ch_pod5_str = ch_pod5_files.map {
        meta, path -> [meta, path.toString()]
    }

    // Извлекаем метаданные
    EXTRACT_POD5_METADATA(ch_pod5_files)
    EXTRACT_POD5_METADATA.out.pod5_with_metadata.map { meta, pod5_file, json_data ->
        def extracted = json_data instanceof String ? 
            new groovy.json.JsonSlurper().parseText(json_data) : 
            json_data
        def enriched_meta = meta + extracted
        [enriched_meta, file(pod5_file)]
    }
    .set { ch_str_pod5_with_enriched_meta }


    // Метаданные файлов будут сохранены в отдельную таблицу
    ch_source_file_meta = ch_str_pod5_with_enriched_meta.map { meta, pod5_file_str -> 
        def source_file_meta = [
            file_basename: file(pod5_file_str).baseName,
            created:meta.created,
            sample_frequency:meta.sample_frequency,
            sequencing_kit:meta.sequencing_kit,
            experiment_type:meta.experiment_type,
            pore:meta.pore,
            pore_speed:meta.pore_speed,
            flow_cell:meta.flow_cell,
            sequencer_type:meta.sequencer_type
        ]
        source_file_meta
        }

    ch_metadata_tsv = ch_source_file_meta.map { meta ->
        try {
            "${meta.file_basename}\t${meta.created}\t${meta.sample_frequency}\t${meta.sequencing_kit}\t${meta.experiment_type}\t${meta.pore}\t${meta.pore_speed}\t${meta.flow_cell}\t${meta.sequencer_type}"
        } catch (Exception _e) {
            "${meta.file_basename}\t \t \t \t \t \t \t \t "
        }
    }.collectFile(
        name: 'basecalling_source_files_metadata.tsv',
        storeDir: "${params.outdir}/to_DB/",
        newLine: true, 
        seed: "file_basename\tcreated\tsample_frequency\tsequencing_kit\texperiment_type\tpore\tpore_speed\tflow_cell\tsequencer_type"
    )

    
    // Создаём группы файлов по поре, типу исходных молекул, использованных китов (в случае с РНК), характеристикам работы пор
    grouped_pod5s = ch_str_pod5_with_enriched_meta.map { meta, file ->
        def groupKey = [
            experiment_type: meta.experiment_type,
            pore: meta.pore,
            sample_frequency: meta.sample_frequency,
            pore_speed: meta.pore_speed
        ]
        
        if (meta.experiment_type == 'rna') {
            groupKey.sequencing_kit = meta.sequencing_kit
        }
        
        [groupKey, meta, file ]
        }
        .groupTuple(by: 0)
        .map { _groupKey, metas, files ->
        [metas[0], files]}

    // Создаём для каждой группы файлов, имеющий полный набор метаданных, свой набор команд для бейсколлинга
    ch_basecalling_ready_grouped_pod5s = grouped_pod5s
                                    .filter { meta, _files -> meta.pore != null }
    PREPARE_BASECALLING_COMMANDS(ch_basecalling_ready_grouped_pod5s)

    ch_basecalling_tasks = PREPARE_BASECALLING_COMMANDS.out.tasks
        .map {meta, files, jsons -> 
        def jsonList = jsons instanceof List ? jsons : [jsons]
        [meta, files, jsonList]
        }.transpose(by: 2)  // разделяет [meta, files, [json1, json2]] -> [[meta, files, json1], [meta, files, json2]]
        .map { _meta, files, jsonFile ->
            def taskMeta = new groovy.json.JsonSlurper().parse(jsonFile)
            [taskMeta, files]
        }

    // String=>PATH
    ch_basecalling_tasks_files = ch_basecalling_tasks.map { meta, files_str ->
        [meta, files_str.collect {file(it)}]
    }
    // Проводим бейсколлинг
    DORADO_BASECALLING(ch_basecalling_tasks_files)

    ch_versions = ch_versions
                    .mix(FAST5_TO_POD5.out.versions)
                    .mix(EXTRACT_POD5_METADATA.out.versions)
                    .mix(DORADO_BASECALLING.out.versions)

    
    emit:
    ubam         = DORADO_BASECALLING.out.ubam
    used_model   = DORADO_BASECALLING.out.used_model
    metadata_tsv = ch_metadata_tsv
    versions     = ch_versions
}
