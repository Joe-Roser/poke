#!/usr/bin/bash

zig build release

mkdir -p ~/.local/bin
cp zig-out/release/* ~/.local/bin/
mkdir -p ~/.config/systemd/user
cp poke.service ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable poke.service
systemctl --user start poke.service
