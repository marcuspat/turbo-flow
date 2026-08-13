#!/usr/bin/env bash
# Rebuilds demo.gif from the two VHS tapes in this directory.
#
# Why two tapes: the full codespace_setup.sh -> setup.sh -> post-setup.sh ->
# tmux-workspace.sh chain runs several real minutes. A single VHS capture of
# a run that long is prone to crash on export (~14k+ frames of a 1400x800
# capture is tens of GB of raw frame data). Splitting into two tapes and
# reattaching to the same live tmux session in between keeps memory bounded
# without losing continuity -- Part B is a real `tmux attach` to the session
# Part A's script actually created, not a separate/staged session.
#
# Part A: real `codespace_setup.sh` run, low framerate (scrolling text, not
#         motion) with PlaybackSpeed 6 baked in at capture time.
# Part B: reattach to the live tmux session, tour all 4 windows, launch the
#         real `claude` CLI through to the real (unauthenticated) login
#         screen. No API key on the recording box -- that's the real first-run
#         UX, not a mockup.
#
# Usage: ./build-demo.sh
# Requires: vhs (https://github.com/charmbracelet/vhs), ffmpeg

set -euo pipefail
cd "$(dirname "$0")"

echo "==> Recording Part A (codespace_setup.sh run)..."
vhs demo-a-setup.tape

echo "==> Recording Part B (tmux tour + claude launch)..."
vhs demo-b-tmux-claude.tape

echo "==> Compositing final demo.gif..."
# Part A is sped up an additional 2.7x on top of its capture-time
# PlaybackSpeed 6 (~16x total vs. real time) so the install montage stays
# brisk without starving Part B -- the post-setup walkthrough is the more
# important half of the demo and keeps its native pacing (fps resample only,
# no speed change). Adjust the 2.7 divisor to retime Part A if the source
# scripts' runtime changes materially.
ffmpeg -y -i demo-a-setup.gif -i demo-b-tmux-claude.gif -filter_complex "
  [0:v]setpts=PTS/2.7,fps=15,scale=1400:-1:flags=lanczos[a];
  [1:v]fps=15,scale=1400:-1:flags=lanczos[b];
  [a][b]concat=n=2:v=1:a=0[outv];
  [outv]split[s0][s1];
  [s0]palettegen=stats_mode=diff[p];
  [s1][p]paletteuse=dither=bayer
" ../demo.gif

echo "==> Done: ../demo.gif"
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=0 ../demo.gif
