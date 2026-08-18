# fish completion for launchdx

complete -c launchdx -f

complete -c launchdx -n "__fish_use_subcommand" -a diagnose -d "Inspect an application, disk image, or installer package and explain the evidence behind a launch blocker"
complete -c launchdx -n "__fish_use_subcommand" -a evidence -d "Show raw evidence for an application, disk image, or installer package"
complete -c launchdx -n "__fish_use_subcommand" -l help -s h -d "Show help"

complete -c launchdx -n "__fish_seen_subcommand_from diagnose evidence" -l json -d "Emit a machine readable JSON report"
complete -c launchdx -n "__fish_seen_subcommand_from diagnose evidence" -l verbose -d "Include suggested repair actions"
complete -c launchdx -n "__fish_seen_subcommand_from diagnose evidence" -l no-color -d "Disable colored output"
complete -c launchdx -n "__fish_seen_subcommand_from diagnose evidence" -l help -s h -d "Show help"

complete -c launchdx -n "__fish_seen_subcommand_from diagnose evidence" -a "(__fish_complete_suffix .app)" -d "Application bundle"
complete -c launchdx -n "__fish_seen_subcommand_from diagnose evidence" -a "(__fish_complete_suffix .dmg)" -d "Disk image"
complete -c launchdx -n "__fish_seen_subcommand_from diagnose evidence" -a "(__fish_complete_suffix .pkg)" -d "Installer package"
