# Kilobytes as a size in the largest unit that keeps it above one.
#
#   _wt_size <kilobytes>

if test -z "$argv[1]"
    echo ?
    return
end

if test $argv[1] -lt 1024
    printf '%dK\n' $argv[1]
else if test $argv[1] -lt 1048576
    printf '%.0fM\n' (math $argv[1] / 1024)
else
    printf '%.1fG\n' (math $argv[1] / 1048576)
end
