# Part B of the Turbo Flow demo: reattach to the real tmux workspace that
# devpods/codespace_setup.sh created in Part A, tour all four windows, then
# launch `claude` for real (fresh/unauthenticated HOME -- no API key on this
# box) through to the real login screen.

Output demo-b-tmux-claude.gif

Set Shell "bash"
Set FontSize 13
Set Width 1400
Set Height 800
Set Theme "Dracula"
Set Padding 20
Set WindowBar Colorful
Set BorderRadius 8
Set TypingSpeed 40ms

Type "tmux attach -t workspace"
Enter
Sleep 1.5s

# Window 1: Claude-2 (secondary workspace)
Ctrl+B
Sleep 300ms
Type "1"
Sleep 1.5s

# Window 2: Claude-Monitor
Ctrl+B
Sleep 300ms
Type "2"
Sleep 1.5s

# Window 3: htop (system monitor) -- let it breathe to show it's live
Ctrl+B
Sleep 300ms
Type "3"
Sleep 3.5s

# Back to window 0
Ctrl+B
Sleep 300ms
Type "0"
Sleep 1s

Type "# From this point you will login to claude and start coding"
Enter
Sleep 500ms

# Real `claude` launch -- fresh/unauthenticated HOME since there's no API key here
Type "HOME=/tmp/demo_fakehome_b claude"
Enter
Sleep 4s

Enter
Sleep 1.5s

Down
Sleep 500ms
Enter
Sleep 3s

Sleep 4s
