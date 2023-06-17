if test (count $argv) -ne 1
    echo 'Usage: workon [project]'
    return
end

set -l dev_dir $HOME
set -l project_dirs repos/ goods/repos

for dir in $project_dirs
    if test -d $dev_dir'/'$dir'/'$argv
        cd $dev_dir'/'$dir'/'$argv
        if test -e .venv/bin/activate.fish
            source .venv/bin/activate.fish
        end
        echo 'Working on: "'$argv'".'
        return
    end
end

echo 'Project '$argv' was not found.'
