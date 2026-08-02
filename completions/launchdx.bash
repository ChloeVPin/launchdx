# bash completion for launchdx
# source this file from .bashrc or place it in the bash-completion directory

_launchdx_complete() {
    local cur prev words
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
    words=("diagnose" "evidence")

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=($(compgen -W "${words[*]} --help -h" -- "${cur}"))
        return 0
    fi

    case "${prev}" in
        diagnose | evidence)
            COMPREPLY=($(compgen -f -- "${cur}"))
            return 0
            ;;
        --json | --verbose | --no-color)
            COMPREPLY=($(compgen -f -- "${cur}"))
            return 0
            ;;
    esac

    case "${cur}" in
        -*)
            COMPREPLY=($(compgen -W "--json --verbose --no-color --help -h" -- "${cur}"))
            return 0
            ;;
        *)
            COMPREPLY=($(compgen -f -- "${cur}"))
            return 0
            ;;
    esac
}

complete -F _launchdx_complete launchdx
