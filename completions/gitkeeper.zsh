# GitKeeper zsh completion

#compdef gitkeeper

_gitkeeper() {
    local -a commands scopes
    
    commands=(
        'check:Run rules on a scope'
        'init:Generate a starter config file'
        'install-hooks:Install pre-commit and pre-push hooks'
        'uninstall-hooks:Remove hooks configuration'
        'explain:Show what will be checked'
        'configure:Interactive configuration wizard'
        'version:Show version information'
        'help:Show help message'
    )
    
    scopes=(
        'staged:Files staged for commit'
        'push:Commits to be pushed'
        'pr:PR/MR diff for CI'
        'stash:Stash contents'
        'all:All tracked files'
    )
    
    _arguments -C \
        '1:command:->command' \
        '*::arg:->args'
    
    case "$state" in
        command)
            _describe -t commands 'gitkeeper command' commands
            ;;
        args)
            case "${words[1]}" in
                check|explain)
                    _arguments \
                        '--scope=[Scope to check]:scope:(staged push pr stash all)' \
                        '--config=[Config file]:file:_files' \
                        '-v[Verbose output]' \
                        '--verbose[Verbose output]' \
                        '-q[Quiet output]' \
                        '--quiet[Quiet output]'
                    ;;
                init)
                    _arguments \
                        '-f[Force overwrite]' \
                        '--force[Force overwrite]' \
                        '-o[Output file]:file:_files' \
                        '--output=[Output file]:file:_files'
                    ;;
                install-hooks)
                    _arguments \
                        '--hooks-dir=[Hooks directory]:directory:_directories' \
                        '--link[Create symlinks instead of copies]'
                    ;;
                configure)
                    _arguments \
                        '--config=[Config file]:file:_files'
                    ;;
            esac
            ;;
    esac
}

_gitkeeper "$@"
