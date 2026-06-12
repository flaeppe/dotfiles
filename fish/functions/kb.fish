function kb --description 'Personal knowledge base (~/kb)'
    switch "$argv[1]"
        case up
            docker start qdrant
        case eval
            uv run --project ~/kb kb eval
        case sync add rebuild extract todos convert ''
            docker start qdrant 2>/dev/null
            uv run --project ~/kb kb $argv
        case '*'
            echo "usage: kb [sync | up | add NAME ROOT [-g GLOB ...] | todos | extract CORPUS|all | convert ... | eval | rebuild]"
            return 1
    end
end
