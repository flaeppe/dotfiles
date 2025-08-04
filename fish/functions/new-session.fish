# Check if an argument is provided
if test -z "$argv[1]"
    echo "Usage: new-session <session_file_path>"
    return 1
end

# Normalizes path to use '~' if it starts with $HOME, as Kitty prefers this.
set -l session_path (string replace -- "$HOME/" "~/" "$argv[1]")

# The path to home manager applications relies on github:hraban/mac-app-util.
# Opens Kitty:
# '-a' for app
# '-n' for new instance (forces a new instance regardless of one running).
#    Similar to --detach for Kitty, but macOS prefers 'open -n'.
# '--args' to pass arguments to the Kitty application.
open -a ~/Applications/Home\ Manager\ Apps/kitty.app/Contents/MacOS/kitty -n \
  --args --session "$session_path"
