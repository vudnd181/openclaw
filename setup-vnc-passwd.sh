#!/bin/sh
# Generate x11vnc password file from VNC_PASSWORD env var
x11vnc -storepasswd "${VNC_PASSWORD:-changeme}" /tmp/.vnc_passwd
chmod 644 /tmp/.vnc_passwd
