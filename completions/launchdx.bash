# bash completion for launchdx
# source this file from .bashrc or place it in the bash-completion directory

_launchdx_complete() {
    local cur prev words
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
    words=("diagnose" "evidence")

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=($(compgen -W "${words[*]} --help -h --version -V" -- "${cur}"))
        return 0
    fi

    if [[ "${cur}" == -* ]]; then
        COMPREPLY=($(compgen -W "--json --verbose --no-color --help -h --version -V" -- "${cur}"))
        return 0
    fi

    case "${prev}" in
        diagnose | evidence | --json | --verbose | --no-color)
            COMPREPLY=($(compgen -f -- "${cur}"))
            return 0
            ;;
    esac

    COMPREPLY=($(compgen -f -- "${cur}"))
}

complete -F _launchdx_complete launchdx
