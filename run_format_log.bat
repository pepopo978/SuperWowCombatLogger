@echo off
cd /d %~dp0
start cmd /k "python.exe format_log_for_upload.py"
