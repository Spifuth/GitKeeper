# GitKeeper bash completion
# Source this file or copy to /etc/bash_completion.d/

_gitkeeper_completions() {
    local cur prev words cword
    _init_completion || return
    
    local commands="check init install-hooks uninstall-hooks explain configure version help"
    local scopes="staged push pr stash all"
    
    # Get current word and previous word
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Complete commands
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return 0
    fi
    
    # Complete based on command
    local cmd="${COMP_WORDS[1]}"
    
    case "$cmd" in
        check|explain)
            case "$prev" in
                --scope)
                    COMPREPLY=($(compgen -W "$scopes" -- "$cur"))
                    return 0
                    ;;
                --config)
                    _filedir
                    return 0
                    ;;
            esac
            
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--scope --config --verbose --quiet" -- "$cur"))
            elif [[ "$cur" == --scope=* ]]; then
                local scope_prefix="${cur#--scope=}"
                COMPREPLY=($(compgen -W "${scopes}" -P "--scope=" -- "$scope_prefix"))
            fi
            ;;
        
        init)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--force --output" -- "$cur"))
            fi
            ;;
        
        install-hooks)
            case "$prev" in
                --hooks-dir)
                    _filedir -d
                    return 0
                    ;;
            esac
            
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--hooks-dir --link" -- "$cur"))
            fi
            ;;
        
        configure)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--config" -- "$cur"))
            fi
            ;;
    esac
    
    # Global options
    if [[ "$cur" == -* && -z "${COMPREPLY[*]}" ]]; then
        COMPREPLY=($(compgen -W "--config --verbose --help --version" -- "$cur"))
    fi
    
    return 0
}

# Fallback if _init_completion is not available
if ! declare -F _init_completion &>/dev/null; then
    _init_completion() {
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        return 0
    }
fi

complete -F _gitkeeper_completions gitkeeper
