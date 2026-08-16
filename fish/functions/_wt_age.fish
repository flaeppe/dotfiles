# A unix timestamp as a short age, to one unit.
#
#   _wt_age <unix-seconds>

if test -z "$argv[1]"
    echo ?
    return
end

set -l seconds (math (date +%s) - $argv[1])

if test $seconds -lt 3600
    printf '%dm\n' (math -s0 $seconds / 60)
else if test $seconds -lt 86400
    printf '%dh\n' (math -s0 $seconds / 3600)
else if test $seconds -lt 1209600
    printf '%dd\n' (math -s0 $seconds / 86400)
else if test $seconds -lt 5184000
    printf '%dw\n' (math -s0 $seconds / 604800)
else
    printf '%dmo\n' (math -s0 $seconds / 2592000)
end
