function kb --description 'Personal knowledge base (~/kb)'
    if test "$argv[1]" = up
        docker compose -f ~/kb/docker-compose.yaml up -d
    else
        uv run --project ~/kb kb $argv
    end
end
