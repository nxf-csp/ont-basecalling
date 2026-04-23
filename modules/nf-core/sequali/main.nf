process SEQUALI {
    tag "$meta.ubam"
    label 'process_medium'
    scratch true
    //stageInMode 'symlink'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'community.wave.seqera.io/library/pip_sequali:7cf7ece924aad25a':
        'quay.io/biocontainers/sequali:1.0.2--py310h7c10099_1' }"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.html"), emit: html
    tuple val(meta), path("*.json"), emit: json
    path "versions.yml"            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def read_1_bam = reads.size() == 1 ? reads : reads[0]
    def read_2 = reads.size() == 2 ? reads[1]: ""

    def qc_name = file(meta.ubam).baseName
    """
    sequali \\
        $args \\
        -t $task.cpus \\
        --html basecalling_${qc_name}_sequali.html \\
        --json basecalling_${qc_name}_sequali.json \\
        $read_1_bam \\
        $read_2

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sequali: \$(sequali --version |& sed '1!d ; s/sequali //')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}.html
    touch ${prefix}.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sequali: \$(sequali --version |& sed '1!d ; s/sequali //')
    END_VERSIONS
    """
}

