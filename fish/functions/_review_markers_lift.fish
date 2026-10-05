# Takes the uncommitted REVIEW[n] markers out of a review head tree so it can be moved to
# another commit, and records each one as an anchor in `.review/anchors.json`.
#
#   _review_markers_lift <tree> <from-sha> <to-sha>
#   _review_markers_lift --undo <tree>
#
# Reached from `review refresh`. An anchor is self-contained -- the commit, the file, the
# line number at that commit, the text of the code line the marker sits above, the lines
# around it, and the marker itself -- so re-anchoring (`_review_markers_reapply`) never has
# to read the old commit, which a force push may have removed from the remote.
#
# A marker is an added line: only added lines of `git diff HEAD` are taken for one, so a
# committed line that happens to read `REVIEW[1]` stays. The marker lines are deleted from
# the file in place and everything else in it -- edits that are not markers -- is left as it
# was. The files as they were go to `.review/refresh-backup/`; `--undo` puts them back.

if test "$argv[1]" = --undo
    set -l tree $argv[2]
    set -l backup "$tree/.review/refresh-backup"
    for saved in (find $backup -type f)
        cp -p $saved (string replace -- "$backup/" "$tree/" $saved)
    end
    rm -rf $backup "$tree/.review/anchors.json"
    return 0
end

set -l tree $argv[1]
set -l from $argv[2]
set -l to $argv[3]
set -l state "$tree/.review/anchors.json"
set -l backup "$tree/.review/refresh-backup"
rm -rf $backup
mkdir -p $backup

set -l anchors
set -l marked_files
set -l dropped_lines
for file in (git -C $tree diff --name-only -z HEAD | string split0)
    test -f "$tree/$file"; or continue

    # The hunks give the line numbers of the added markers, and how far every other line
    # has moved relative to the commit.
    set -l marker_lines
    set -l hunk_ends
    set -l hunk_shifts
    set -l new_line 0
    for diff_line in (git -C $tree diff -U0 --no-color --no-ext-diff --no-textconv HEAD -- $file)
        set -l hunk (string match -r -- '^@@ -\d+,?(\d*) \+(\d+),?(\d*) @@' $diff_line)
        if test (count $hunk) -eq 4
            set -l removed $hunk[2]
            set -l added $hunk[4]
            test -z "$removed"; and set removed 1
            test -z "$added"; and set added 1
            set new_line $hunk[3]
            # A hunk that only deletes is positioned at the line before the deletion.
            set -a hunk_ends (math "$new_line + max($added, 1) - 1")
            set -a hunk_shifts (math "$added - $removed")
            continue
        end
        # The `+++` file header comes before the first hunk; after it every `+` is content.
        if test (count $hunk_ends) -gt 0; and string match -q -- '+*' $diff_line
            string match -qr -- 'REVIEW\[\d+\]' $diff_line; and set -a marker_lines $new_line
            set new_line (math $new_line + 1)
        end
    end
    test (count $marker_lines) -gt 0; or continue

    set -l lines (cat -- "$tree/$file")
    for marker_line in $marker_lines
        # The code a marker annotates is the first line below it that is not itself a marker.
        set -l code_line (math $marker_line + 1)
        while contains -- $code_line $marker_lines
            set code_line (math $code_line + 1)
        end
        set -l above (math $marker_line - 1)
        while test $above -gt 0; and contains -- $above $marker_lines
            set above (math $above - 1)
        end
        set -l below (math $code_line + 1)
        while contains -- $below $marker_lines
            set below (math $below + 1)
        end

        set -l code_text
        set -l above_text
        set -l below_text
        test $code_line -le (count $lines); and set code_text $lines[$code_line]
        test $above -gt 0; and set above_text $lines[$above]
        test $below -le (count $lines); and set below_text $lines[$below]

        set -l head_line $code_line
        for i in (seq (count $hunk_ends))
            test $hunk_ends[$i] -lt $code_line; and set head_line (math "$head_line - $hunk_shifts[$i]")
        end

        set -l marker $lines[$marker_line]
        set -l id (string match -r -- 'REVIEW\[(\d+)\]' $marker)[2]
        set -l text (string match -r -- 'REVIEW\[\d+\][a-z]*(?:\+\d+)?:\s*(.*)$' $marker)[2]
        set -a anchors (jq -nc --arg head $from --arg file $file --argjson id $id \
            --argjson line $head_line --arg line_text "$code_text" \
            --arg before "$above_text" --arg after "$below_text" \
            --arg marker "$marker" --arg text "$text" \
            '{id: $id, head: $head, file: $file, line: $line, line_text: $line_text,
              before: $before, after: $after, marker: $marker, text: $text}')
    end

    set -a marked_files $file
    set -a dropped_lines (string join , -- $marker_lines)
end

# The anchors are on disk before the first file is touched.
set -l joined_anchors (string join , -- $anchors)
jq -n --arg from $from --arg to $to --argjson anchors "[$joined_anchors]" \
    '{from: $from, to: $to, applied: false, anchors: $anchors}' >$state

for i in (seq (count $marked_files))
    set -l file $marked_files[$i]
    # Rewritten from the saved copy into the file itself, which keeps its mode.
    mkdir -p (dirname "$backup/$file")
    cp -p "$tree/$file" "$backup/$file"
    set -l last_byte (tail -c1 "$backup/$file" | od -An -tx1 | string trim)
    set -l no_newline 0
    test "$last_byte" != 0a; and set no_newline 1
    awk -v drop=$dropped_lines[$i] -v no_newline=$no_newline '
        BEGIN { count = split(drop, dropped, ","); for (i = 1; i <= count; i++) skip[dropped[i]] = 1 }
        !(NR in skip) { printf "%s%s", (kept++ ? "\n" : ""), $0 }
        END { if (kept && !no_newline) printf "\n" }
    ' "$backup/$file" >"$tree/$file"
end
