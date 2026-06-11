function kb --description 'Personal knowledge base (~/kb)'
    switch "$argv[1]"
        case up
            docker start qdrant
        case add
            docker start qdrant 2>/dev/null
            uv run --project ~/kb ~/kb/sync.py add $argv[2..-1]
        case eval
            uv run --project ~/kb ~/kb/sync.py eval
        case todos
            docker start qdrant 2>/dev/null
            uv run --project ~/kb ~/kb/todos.py
            and uv run --project ~/kb ~/kb/sync.py
        case extract
            docker start qdrant 2>/dev/null
            uv run --project ~/kb ~/kb/extract.py $argv[2..-1]
            and uv run --project ~/kb ~/kb/sync.py
        case rebuild
            docker start qdrant 2>/dev/null
            uv run --project ~/kb ~/kb/sync.py --rebuild
        case sync ''
            docker start qdrant 2>/dev/null
            uv run --project ~/kb ~/kb/sync.py
        case '*'
            echo "usage: kb [sync | up | add NAME ROOT [-g GLOB ...] | todos | extract CORPUS|all | eval | rebuild]"
            return 1
    end
end
