// glog -- read-only Google Cloud Logging CLI.
//
// Exists to be allowlisted wholesale for Claude Code sessions: every verb here
// maps to a read-only Cloud Logging RPC, so there is no write path to gate in
// the first place, unlike shelling out to gcloud directly.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func helpText() string {
	return strings.Join([]string{
		"glog -- read-only Google Cloud Logging CLI",
		"",
		"usage: glog <command> [args]",
		"",
		"commands:",
		"  read <filter>       tail matching log entries (the workhorse)",
		"                        --project P     defaults to `gcloud config get-value project`",
		"                                        or $CLOUDSDK_CORE_PROJECT",
		"                        --limit N       default 50",
		"                        --freshness D   only entries newer than D, e.g. 1h, 2d, 30m",
		"                        --order asc|desc default desc (newest first)",
		"                        --format text|json default text",
		"  logs                list log names            --project P  --limit N (default 200)",
		"  buckets list        list log buckets           --project P  --location L (default -, all)",
		"  buckets describe N  describe a log bucket      --project P  --location L (default global)",
		"  views list          list views on a bucket     --project P  --bucket B  --location L (default global)",
		"  views describe N    describe a view            --project P  --bucket B  --location L (default global)",
		"  sinks list          list log sinks             --project P",
		"  sinks describe N    describe a log sink        --project P",
		"  metrics list        list log-based metrics     --project P",
		"  metrics describe N  describe a log-based metric --project P",
		"  help                this text",
	}, "\n")
}

func run(argv []string) int {
	if len(argv) == 0 || argv[0] == "help" || argv[0] == "-h" || argv[0] == "--help" {
		fmt.Println(helpText())
		return 0
	}
	command, rest := argv[0], argv[1:]
	switch command {
	case "read":
		return cmdRead(rest)
	case "logs":
		return cmdLogs(rest)
	case "buckets":
		return cmdBuckets(rest)
	case "views":
		return cmdViews(rest)
	case "sinks":
		return cmdSinks(rest)
	case "metrics":
		return cmdMetrics(rest)
	}
	fmt.Fprintln(os.Stderr, helpText())
	return 2
}

func main() {
	os.Exit(run(os.Args[1:]))
}

// resolveProject mirrors gcloud's own precedence: an explicit flag wins,
// then the env var gcloud itself honors as an override, then the active
// gcloud config.
func resolveProject(flagValue string) (string, error) {
	if flagValue != "" {
		return flagValue, nil
	}
	if v := os.Getenv("CLOUDSDK_CORE_PROJECT"); v != "" {
		return v, nil
	}
	out, err := exec.Command("gcloud", "config", "get-value", "project").Output()
	if err == nil {
		project := strings.TrimSpace(string(out))
		if project != "" && project != "(unset)" {
			return project, nil
		}
	}
	return "", fmt.Errorf("no project configured: pass --project, set $CLOUDSDK_CORE_PROJECT, or run `gcloud config set project <id>`")
}

// parseFlagsAnywhere lets flags and positional arguments interleave in any
// order, e.g. an empty filter before --limit as readily as after it
// -- the stdlib flag package only accepts flags before the first positional
// argument, but gcloud-style invocations put the filter first out of habit.
// fs must already have every flag defined (so boolean flags can be told
// apart from value flags); it performs the actual parse.
func parseFlagsAnywhere(fs *flag.FlagSet, args []string) ([]string, error) {
	isBoolFlag := map[string]bool{}
	fs.VisitAll(func(f *flag.Flag) {
		if b, ok := f.Value.(interface{ IsBoolFlag() bool }); ok && b.IsBoolFlag() {
			isBoolFlag[f.Name] = true
		}
	})

	var flagArgs, positional []string
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "-" || !strings.HasPrefix(arg, "-") {
			positional = append(positional, arg)
			continue
		}
		flagArgs = append(flagArgs, arg)
		name := strings.TrimLeft(arg, "-")
		if eq := strings.IndexByte(name, '='); eq >= 0 {
			continue // value is embedded in this token: --flag=value
		}
		if isBoolFlag[name] {
			continue // no separate value token
		}
		if i+1 < len(args) {
			i++
			flagArgs = append(flagArgs, args[i])
		}
	}

	if err := fs.Parse(flagArgs); err != nil {
		return nil, err
	}
	return append(positional, fs.Args()...), nil
}

// qualify turns a bare resource id into a full resource name under prefix,
// leaving anything that already looks like a path (contains "/") untouched
// so a fully-qualified name can always be passed straight through.
func qualify(id, prefix string) string {
	if strings.Contains(id, "/") {
		return id
	}
	return prefix + id
}
