# Part A of the Turbo Flow demo: real devpods/codespace_setup.sh run
# (chains setup.sh -> post-setup.sh -> tmux-workspace.sh -> attaches to tmux).
# Low framerate here (it's scrolling text, not motion) to keep the capture
# lightweight over several real minutes; sped up further on export.

Output demo-a-setup.gif

Set Shell "bash"
Set FontSize 13
Set Width 1400
Set Height 800
Set Theme "Dracula"
Set Padding 20
Set WindowBar Colorful
Set BorderRadius 8
Set TypingSpeed 40ms
Set Framerate 3
Set PlaybackSpeed 6

Type "cd ~/work/turbo-flow-take2"
Enter
Sleep 500ms

Type "bash devpods/codespace_setup.sh"
Enter
Sleep 340s
