# Linux Process Monitoring Tool

A Bash script that checks whether processes are running on a Linux system and verifies that their instance counts fall within configured thresholds. It produces either a colored text report or JSON output for use by other tools.

Each execution captures a single snapshot of the processes using `ps`: the script does not monitor continuously or start or stop services.

## Features

- Configure checks from the command line, a file, or both sources.
- Search by name, path, or command with arguments.
- Specify alternative names for the same check, such as `cron,crond`.
- Use descriptive aliases and filter by user and parent process ID (PPID).
- Set minimum and maximum thresholds for the number of matching processes.
- Generate a text report with a summary or a JSON array.

## Requirements

- Linux with Bash, available at `/bin/bash` for direct execution.
- `ps` compatible with procps/procps-ng options (`-ww -eo user,ppid,args --no-headers`).
- The `awk`, `grep`, `sed`, and `basename` utilities.

No additional libraries are required. Results depend on the process visibility available to the user running the script.

## Quick Start

From the project directory:

```bash
chmod +x process_monitor.sh
./process_monitor.sh -P "proc=sshd:alias=ssh:min=1:max=10"
```

Alternatively, without changing permissions:

```bash
bash process_monitor.sh -P "proc=sshd:alias=ssh:min=1:max=10"
```

To display the built-in help:

```bash
./process_monitor.sh -h
```

## Options

```text
./process_monitor.sh [-P <list>] [-F <file>] [-J]
./process_monitor.sh -h
```

| Option      | Description                                                                                |
| ----------- | ------------------------------------------------------------------------------------------ |
| `-P <list>` | Defines one or more checks separated by `%`. Can be repeated.                              |
| `-F <file>` | Reads one check per line from the specified file. If repeated, only the last file is used. |
| `-J`        | Returns the report in JSON format.                                                         |
| `-h`        | Displays help.                                                                             |

When combining `-P` and `-F`, command-line checks are processed first, followed by checks from the file. Duplicates are not removed.

## Check Format

```text
proc=name[,alternative_name]:alias=label:user=username:ppid=parent_pid:min=1:max=1
```

Only `proc` is required. All other fields can be omitted.

| Field   | Meaning                                                      | Default                                                                 |
| ------- | ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| `proc`  | Name or command to search for; commas separate alternatives. | Required                                                                |
| `alias` | Label for the check in the report.                           | Text output uses `proc`; JSON output derives the name from the command. |
| `user`  | Process owner, compared with the user reported by `ps`.      | No filter                                                               |
| `ppid`  | Parent process ID.                                           | No filter                                                               |
| `min`   | Minimum number of instances, inclusive.                      | `1`                                                                     |
| `max`   | Maximum number of instances, inclusive.                      | `1`                                                                     |

**Without explicit thresholds, a check requires exactly one process.** Also specify `max` when increasing `min`. Use non-negative integers without leading zeros and a consistent range (`min <= max`). Values containing anything other than digits are treated as `1` during comparison.

Searches use literal strings, not regular expressions. Simple names are matched using `grep -F -w`; strings containing whitespace, `/`, or `=` are matched as substrings using `grep -F`. Searches are not limited to the executable name and may also match command arguments.

When multiple alternatives are provided, the script uses **the first one that finds processes matching the filters**. Instances matching subsequent alternatives are neither counted nor checked, even if the first alternative is outside the configured range.

The parser uses the separators `:`, `,`, `%`, and `|` and provides no escaping mechanism for them. Avoid these characters in values except where required by the syntax. Enclose the entire `-P` value in quotes to preserve spaces.

## Examples

### Multiple Processes from the Command Line

```bash
./process_monitor.sh -P "proc=nginx:alias=web:min=1:max=8%proc=mysqld:alias=database:user=mysql"
```

You can repeat `-P`; empty segments between `%` separators are ignored:

```bash
./process_monitor.sh -P "proc=cron,crond:alias=cron" -P "proc=redis-server%%%proc=sshd:min=1:max=10"
```

### Filtering by User and Parent Process

```bash
./process_monitor.sh -P "proc=redis-server:alias=cache:user=redis:ppid=1"
```

The `ppid=1` filter is appropriate only if the target process actually has parent process ID `1`.

### Command with Arguments

```bash
./process_monitor.sh -P "proc=sapstart pf=/usr/sap/SMA/SYS/profile/SMA_ASCS01:alias=sap_ascs01:user=smaadm:min=1:max=2"
```

### Configuration from a File

For example, create a `processes.txt` file with the following content:

```text
# Services to monitor
proc=nginx:alias=webserver:min=1:max=8
proc=mysqld:alias=database:user=mysql
proc=redis-server:alias=cache:user=redis
proc=cron,crond:alias=cron_service
proc=syslogd,rsyslogd,syslog-ng:alias=syslog
```

Empty lines and lines whose first non-whitespace character is `#` are ignored. Inline comments after a definition are not supported.

```bash
./process_monitor.sh -F processes.txt
./process_monitor.sh -F processes.txt -P "proc=sshd:alias=ssh:min=1:max=10" -J
```

## Interpreting Results

The text report distinguishes three outcomes:

| Outcome                  | Meaning                                                                   |
| ------------------------ | ------------------------------------------------------------------------- |
| `[OK] ...: ACTIVE`       | At least one process was found and the count falls within the thresholds. |
| `[KO] ...: OUT OF RANGE` | Processes were found, but the count is outside the thresholds.            |
| `[KO] ...: NOT FOUND`    | No process matches the search and filters.                                |

In the text summary, the `not found` counter includes all KO checks, including those marked `OUT OF RANGE`.

### JSON Output

```bash
./process_monitor.sh -P "proc=cron,crond:alias=cron_service" -J
```

Illustrative example, formatted for readability; actual results depend on the system:

```json
[
  {
    "ALIAS": "cron_service",
    "USER": "",
    "STATUS": "1",
    "PROCESSES": "/usr/sbin/cron -f",
    "COUNT": "1",
    "MIN": "1",
    "MAX": "1"
  }
]
```

All values are **strings**, including counts and status:

- `ALIAS`: the configured label or one derived from the command.
- `USER`: the requested user filter; an empty string if not specified.
- `STATUS`: `"1"` if processes were found and their count is within range; `"0"` otherwise.
- `PROCESSES`: matching commands joined with `, `; an empty string if none were found. Double quotes in commands are removed.
- `COUNT`: the number of instances found after applying the filters.
- `MIN` and `MAX`: the configured thresholds, or `"1"` if omitted.

The JSON does not include process IDs or the PPID filter. Even with `min=0`, an absent process produces `STATUS="0"`.

## Exit Codes and Automation

The exit code **does not represent process status**: a report that completes normally returns `0` even when some checks are KO. To integrate the script with a monitoring system, read the `STATUS` field of each JSON object.

Help (`-h` or execution without arguments), invalid options, a missing or unreadable file, and the absence of valid checks in text mode result in exit code `1`. In JSON mode, if there are no valid checks, the script returns `[]` with exit code `0`.

Definitions without a `proc` value are ignored, with a warning only in text mode. Option or file errors produce a text message even with `-J`: check the exit code before parsing the output as JSON.

For periodic checks, schedule separate executions using cron or a systemd timer.
