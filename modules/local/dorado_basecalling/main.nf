/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    МОДУЛЬ: DORADO_BASECALLING
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Бейсколлинг POD5 файлов без выравнивания, с генерацией UBAM. Если версия поры 10.4.1 и не используется fast-модель, бейсколлинг проводится в duplex формате
    Входы: id образца, POD5 файлы, версия поры
    Выходы: UBAM, использованная модель для бейсколлинга, версия dorado
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process PREPARE_BASECALLING_COMMANDS {
    tag "${meta.experiment_type}_${meta.pore}_${meta.sequencing_kit}_${meta.sample_frequency}_${meta.pore_speed}"
    label 'process_low'

    input:
    tuple val(meta), path(files)
    
    output:
    tuple val(meta), path(files), path("tasks_*.json"), emit: tasks

    script:
    def yamlFile = file("${moduleDir}/modifications_and_models.yaml")
    def yaml = new org.yaml.snakeyaml.Yaml()
    def config = yaml.load(yamlFile.text)

    def baseTemplate = meta.pore == 'r941' ?
        config.templates[meta.pore].basic :
        config.templates[meta.pore][meta.experiment_type].basic
    def ubam_name = "${params.sample}:basic:${meta.experiment_type}_${meta.pore}.ubam"
    def modConfig = meta.experiment_type == 'dna' ? 
        config.models[meta.pore].dna : 
        config.models[meta.pore].rna[meta.pore_speed]
    def baseCommand = baseTemplate
                        .replace('\n', '')
                        .replace('\\', '')
                        .replaceAll('\\s+', ' ')
                        .replace('{args}', task.ext.args ?: '')
                        .replace('{basecalling_model}', modConfig.basic)
                        .replace('{ubam_name}', ubam_name)

    def tasks = [[command: baseCommand, ubam: ubam_name] + meta]
    
    if (params.basecall_modifications) {
        def modTemplate = meta.pore == 'r941' ?
            config.templates[meta.pore].modifications :
            config.templates[meta.pore][meta.experiment_type].modifications
        modConfig.modifications.each { modName, modModel ->
            def mod_ubam_name = "${params.sample}:${modName.replaceAll(',','-')}:${meta.experiment_type}_${meta.pore}.ubam"
            def modCommand = modTemplate
                                .replace('\n', '')
                                .replace('\\', '')
                                .replaceAll('\\s+', ' ')
                                .replace('{args}', task.ext.args ?: '')
                                .replace('{modifications}', modName.replaceAll(',',' '))
                                .replace('{basecalling_model}', modModel)
                                .replace('{ubam_name}', mod_ubam_name)
            tasks.add([command: modCommand, ubam: mod_ubam_name, modification: modName] + meta)
        }
    }

    def jsonCommands = tasks.withIndex().collect { taskData, idx ->
        def jsonContent = new groovy.json.JsonBuilder(taskData).toPrettyString()
        "cat > tasks_${idx}.json << 'JSONEOF'\n${jsonContent}\nJSONEOF"
    }.join('\n\n')

    """
    ${jsonCommands}
    """
}


process DORADO_BASECALLING {
    tag "$meta.ubam"
    label 'gpu_intensive_task'
    // cpus task.accelerator.request * 32
    // memory "${task.accelerator.request * 64}.GB"
    cpus 32
    memory 64
    stageInMode 'symlink'

    conda "${moduleDir}/environment.yml"
    container 'nanoporetech/dorado:latest'  // базовый контейнер
    

    input:
    tuple val(meta), path(pod5_files)

    output:
    tuple val(meta), path("*.ubam"), emit: ubam
    path "*used_model.txt",          emit: used_model  
    path "versions.yml",             emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    task.container = meta.pore == 'r941' ? 'nanoporetech/dorado:sha268dcb4cd02093e75cdc58821f8b93719c4255ed' :
                 meta.pore in ['r1041', 'rp4'] ? 'nanoporetech/dorado:shaf2aed69855de85e60b363c9be39558ef469ec365' :
                 'nanoporetech/dorado:latest' 
    // если продвинутый dorado не заработает: nanoporetech/dorado:shae423e761540b9d08b526a1eb32faf498f32e8f22

    def dorado_cmd = meta.command
    def tag = "BASECALLING_${file(meta.ubam).baseName.replaceAll(':', '_')}"
    """
    ${dorado_cmd}

    samtools view \\
    -H ${meta.ubam} \\
    | grep -oP \\
    'basecall_model=\\K[^ ]+' \\
    | head -1 \\
    > ${file(meta.ubam).baseName}_used_model.txt

    cat <<-END_VERSIONS > versions.yml
    "${tag}":
        dorado: \$(dorado --version 2>&1 | head -n1 | sed 's/dorado //')
    END_VERSIONS
    """
}
