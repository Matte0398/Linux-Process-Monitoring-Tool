# Linux-Process-Monitoring-Tool

Bash script that checks whether one or more processes are running on a Linux system.

The script supports advanced filtering and can return both human-readable and JSON output.

## Features

- Check process existence
- Monitor one or more processes
- Support alternative process names
- Alias support
- User filtering
- Parent PID filtering
- Minimum and maximum process count thresholds
- JSON output
- File-based process list
- Command-line process definition

## Process format

```bash
proc=process_name[,alternative_name]:alias=label:user=username:ppid=parent_pid:min=<min>:max=<max>
```

## Usage

```bash
./process_monitor.sh -P "proc=nginx"
./process_monitor.sh -P "proc=nginx%proc=mysql:alias=database:user=mysql" -J
./process_monitor.sh -P "proc=syslogd,rsyslogd,syslog-ng:alias=syslog"
./process_monitor.sh -F /tmp/processes.txt -J
