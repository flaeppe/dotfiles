# Puts the markers recorded in `.review/anchors.json` back into a review head tree, now at
# its new commit, and prints what became of them.
#
#   _review_markers_reapply <tree>
#
# Reached from `review refresh`, after `_review_markers_lift` and the move. A marker whose
# code line is found again goes back unchanged. One whose line is not goes to the best
# guess -- its old line number, clamped into the file -- tagged `STALE(<sha7>:<file>:<line>)`
# for the reviewer to place by hand; `review post` refuses while one exists.
#
# A line is found again when its text (ignoring indentation) is:
#   - at the line it had, or
#   - the only such line in the file, or
#   - the only such line whose neighbours are also the lines it had.
# A blank line is only ever found at the line it had, with its neighbours. A file renamed by
# the new commits is followed; a file that no longer exists is re-created holding just its
# markers, so they are not lost.
#
# Resumable: an anchor with an `outcome` is done, so running it again finishes the rest.

set -l tree $argv[1]
set -l state "$tree/.review/anchors.json"
set -l backup "$tree/.review/refresh-backup"
mkdir -p $backup

set -l from (jq -r .from $state)
set -l to (jq -r .to $state)
set -l from7 (string sub -l 7 -- $from)

# Needs the old commit, which is why a rename is the one thing a force push can hide.
set -l renamed_from
set -l renamed_to
for change in (git -C $tree diff -M --name-status $from $to 2>/dev/null)
    set -l fields (string split \t -- $change)
    string match -q 'R*' -- $fields[1]; or continue
    set -a renamed_from $fields[2]
    set -a renamed_to $fields[3]
end

set -l pending_files (jq -r '[.anchors[] | select(.outcome == null) | .file] | unique[]' $state)
for file in $pending_files
    set -l target_file $file
    set -l renamed (contains -i -- $file $renamed_from)
    and set target_file $renamed_to[$renamed]
    set -l target "$tree/$target_file"

    set -l file_exists 0
    set -l total 0
    if test -f $target
        set file_exists 1
        set total (count (cat -- $target))
    end

    set -l inserts "$backup/.inserts"
    : >$inserts
    set -l indexes (jq -r --arg file $file '.anchors | to_entries[]
        | select(.value.file == $file and .value.outcome == null) | .key' $state)
    set -l outcomes
    set -l placements
    for index in $indexes
        set -l line (jq -r ".anchors[$index].line" $state)
        set -l line_text (jq -r ".anchors[$index].line_text" $state)
        set -l before (jq -r ".anchors[$index].before" $state)
        set -l after (jq -r ".anchors[$index].after" $state)
        set -l marker (jq -r ".anchors[$index].marker" $state)

        set -l outcome stale
        set -l placed (math "min(max($line, 1), $total + 1)")
        if test $file_exists -eq 0
            set outcome deleted
            set placed 1
        else
            set -l found
            set -l found_in_context
            set -l hits (ANCHOR_TEXT="$line_text" ANCHOR_BEFORE="$before" ANCHOR_AFTER="$after" awk '
                function trim(text) { gsub(/^[ \t]+|[ \t]+$/, "", text); return text }
                { text[NR] = trim($0) }
                END {
                    want = trim(ENVIRON["ANCHOR_TEXT"])
                    want_before = trim(ENVIRON["ANCHOR_BEFORE"])
                    want_after = trim(ENVIRON["ANCHOR_AFTER"])
                    for (n = 1; n <= NR; n++) {
                        if (text[n] != want) continue
                        before_ok = ((n == 1 ? "" : text[n - 1]) == want_before)
                        after_ok = ((n == NR ? "" : text[n + 1]) == want_after)
                        print n, (before_ok && after_ok) ? 1 : 0
                    }
                }' $target)
            for hit in $hits
                set -l parts (string split ' ' -- $hit)
                set -a found $parts[1]
                test $parts[2] -eq 1; and set -a found_in_context $parts[1]
            end

            set -l has_text 0
            string match -qr '\S' -- "$line_text"; and set has_text 1
            if contains -- $line $found; and begin
                    test $has_text -eq 1; or contains -- $line $found_in_context
                end
                set outcome kept
                set placed $line
            else if test $has_text -eq 1; and test (count $found) -eq 1
                set outcome kept
                set placed $found[1]
            else if test $has_text -eq 1; and test (count $found_in_context) -eq 1
                set outcome kept
                set placed $found_in_context[1]
            end
        end

        # Tagged right after the colon, where the editor reads a marker's text from, so the
        # marker keeps its id, kind and extent. A marker with no text takes the tag after
        # its id. One already tagged by an earlier refresh keeps that tag.
        set -l inserted "$marker"
        if test $outcome != kept; and not string match -q -- '*STALE(*' "$marker"
            set -l tag "STALE($from7:$file:$line)"
            set -l with_text (string match -r -- '^(.*?REVIEW\[\d+\][a-z]*(?:\+\d+)?:)\s?(.*)$' "$marker")
            set -l bare (string match -r -- '^(.*?REVIEW\[\d+\][a-z]*(?:\+\d+)?)(.*)$' "$marker")
            if test (count $with_text) -eq 3
                set inserted (string trim -r -- "$with_text[2] $tag $with_text[3]")
            else if test (count $bare) -eq 3
                set inserted "$bare[2] $tag$bare[3]"
            end
        end
        printf '%s:%s\n' $placed "$inserted" >>$inserts
        set -a outcomes $outcome
        set -a placements $placed
    end

    set -l source $target
    if test $file_exists -eq 0
        mkdir -p (dirname $target)
        set source /dev/null
    end
    set -l last_byte (tail -c1 $source | od -An -tx1 | string trim)
    set -l no_newline 0
    test $file_exists -eq 1; and test "$last_byte" != 0a; and set no_newline 1
    awk -v inserts=$inserts -v no_newline=$no_newline '
        function emit(text) { printf "%s%s", (printed++ ? "\n" : ""), text }
        BEGIN {
            while ((getline entry < inserts) > 0) {
                split_at = index(entry, ":")
                position = substr(entry, 1, split_at - 1) + 0
                count[position]++
                marker[position, count[position]] = substr(entry, split_at + 1)
            }
        }
        {
            for (k = 1; k <= count[NR]; k++) emit(marker[NR, k])
            emit($0)
        }
        END {
            for (k = 1; k <= count[NR + 1]; k++) emit(marker[NR + 1, k])
            if (printed && !no_newline) printf "\n"
        }
    ' $source >"$backup/.rewritten"
    and cat "$backup/.rewritten" >$target

    for i in (seq (count $indexes))
        # Where the marker sits once everything above it has been inserted.
        set -l now_line $placements[$i]
        for j in (seq (count $indexes))
            test $placements[$j] -lt $placements[$i]; and set now_line (math $now_line + 1)
            test $placements[$j] -eq $placements[$i]; and test $j -lt $i; and set now_line (math $now_line + 1)
        end
        jq --argjson index $indexes[$i] --arg outcome $outcomes[$i] --arg now_file $target_file \
            --argjson now_line $now_line \
            '.anchors[$index] += {outcome: $outcome, now_file: $now_file, now_line: $now_line}' \
            $state >"$state.tmp"
        and mv "$state.tmp" $state
    end
end

jq '.applied = true' $state >"$state.tmp"; and mv "$state.tmp" $state
rm -rf $backup

set -l total_count (jq '.anchors | length' $state)
test $total_count -gt 0; or return 0
set -l kept_count (jq '[.anchors[] | select(.outcome == "kept")] | length' $state)
set -l stale_count (jq '[.anchors[] | select(.outcome == "stale")] | length' $state)
set -l deleted_count (jq '[.anchors[] | select(.outcome == "deleted")] | length' $state)
echo "markers: $kept_count re-applied, $stale_count stale, $deleted_count in a deleted file"
jq -r '.anchors[] | select(.outcome == "stale")
    | "  stale    REVIEW[\(.id)] \(.file):\(.line) -> placed at \(.now_file):\(.now_line)"' $state
jq -r '.anchors[] | select(.outcome == "deleted")
    | "  deleted  REVIEW[\(.id)] \(.file):\(.line) -> \(.file) is gone; re-created holding only its markers"' $state
if git -C $tree cat-file -e "$from^{commit}" 2>/dev/null
    echo "  anchors carry their line text, so re-anchoring did not read old head $from7 (still in this clone)"
else
    echo "  old head $from7 is gone from this clone (force push?); re-anchoring does not need it -- only rename tracking did, so a renamed file counts as deleted"
end
if test (math $stale_count + $deleted_count) -gt 0
    echo "  place each STALE marker, then delete its STALE(...) tag -- review post refuses until none are left:  git grep -n 'STALE('"
end
