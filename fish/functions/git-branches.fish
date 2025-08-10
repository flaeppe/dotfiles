# This function generates the formatted list of Git branches for fzf
function __gb_list_branches
    git branch --list --sort=-committerdate --sort=-HEAD --format='%(HEAD) %(color:yellow)%(refname:short) %(color:green)(%(committerdate:relative))∑%(color:blue)%(subject)%(color:reset)' --color=always | column -ts'∑'
end

function gb --description "Fuzzy find Git branches with advanced preview and actions"
    # Get the initial list of branches and pipe them directly into fzf
    __gb_list_branches | \
    fzf --ansi \
        --height 80% \
        --layout reverse --multi --min-height 20+ \
        --border \
        --border-label-pos 2 \
        --border-label '🌲 Branches ' \
        --header "💡 CTRL-D: Delete Branch | Enter: Paste Branch(es)" \
        --header-border horizontal \
        --tiebreak begin \
        --cycle \
        --info inline \
        --no-hscroll \
        --expect enter \
        --bind "ctrl-d:execute(
            # Extract the branch name from the fzf highlighted line
            set -l branch (echo {} | sed 's/^\* //' | awk '{print \$1}');
            # Require confirmation before deleting
            read -P \"Delete branch \$branch? (y/N) \" confirm;

            if test \"\$confirm\" = y;
                # Prevent deletion of 'main' or 'master' branches
                if test \"\$branch\" = \"main\" -o \"\$branch\" = \"master\"
                    echo \"Error: Cannot delete the '\$branch' branch. Deleting 'main' or 'master' is not allowed.\"
                    echo \"Press any key to continue...\"
                    read -n 1 # Wait for any key press
                else
                    if not git branch -D \"\$branch\";
                        echo \"Error: Failed to delete branch \$branch.\"
                        echo \"Press any key to continue...\"
                        read -n 1 # Wait for any key press
                    end
                end
            end
        )+reload(source ~/.config/fish/functions/gb.fish; __gb_list_branches)+refresh-preview" \
        --preview-window 'down,border-top,40%' \
        --preview-border line \
        --preview '
            # Extract the branch name from the formatted fzf input
            set -l branch_name (echo {} | cut -c3- | cut -d" " -f1)
            git log $branch_name --oneline --graph --date=short --decorate --color=always --pretty="format:%C(auto)%cd %h%d %s"
        ' | sed 's/^\* //' | awk '{print $1}' | sed -n '/^enter$/,$p' | sed '1d' | string join " "
end
