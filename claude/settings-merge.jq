# Input: [on-disk settings, flake settings]. Flake keys win, except that
# permissions.allow/ask/deny are unioned so rules a tool's own setup command
# added on disk survive activation.
.[0] as $disk | .[1] as $flake
| ($disk * $flake)
| reduce ("allow", "ask", "deny") as $key (.;
    if ($disk.permissions[$key] // $flake.permissions[$key]) == null then .
    else .permissions[$key] = (($flake.permissions[$key] // []) + ($disk.permissions[$key] // []) | unique)
    end)
