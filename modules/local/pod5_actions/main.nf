process FAST5_TO_POD5 {
    tag "$fast5_file"
    label 'process_low'
    containerOptions "-v ${file(fast5_file).parent}:${file(fast5_file).parent}"
    stageOutMode 'move'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pod5:0.3.23--pyhdfd78af_0' :
        'quay.io/biocontainers/pod5:0.3.23--pyhdfd78af_0' }"

    input:
    tuple val(meta), val(fast5_file)

    output:
    tuple val(meta), path("*.pod5"), emit: pod5
    path "versions.yml"            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    pod5 convert fast5 \\
        $args \\
        --threads 2 \\
        --output ${file(fast5_file).baseName}.pod5 \\
        $fast5_file
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pod5: \$(pod5 --version 2>&1 | sed 's/Pod5 version: //')
    END_VERSIONS
    """
}


process EXTRACT_POD5_METADATA {
    tag "$pod5_file"
    label 'process_low'
    containerOptions "-v ${file(pod5_file).parent}:${file(pod5_file).parent}"
    
    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pod5:0.3.23--pyhdfd78af_0' :
        'quay.io/biocontainers/pod5:0.3.23--pyhdfd78af_0' }"

    input:
    tuple val(meta), val(pod5_file)
    
    output:
    tuple val(meta), val(pod5_file), env('POD5_METADATA'), emit: pod5_with_metadata
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    # Получаем JSON и записываем в переменную окружения
    export POD5_METADATA=\$(pod5_parser.py ${pod5_file})
    
    # Создаем versions.yml
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pod5: \$(pod5 --version 2>&1 | sed 's/Pod5 version: //')
        pod5_parser: \$(pod5_parser.py version)
    END_VERSIONS
    """
}
