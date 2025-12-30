# bindkey -s '^F' "tmux-sessionizer\n"

# . "$HOME/.cargo/env"
export XDG_CONFIG_HOME=$HOME/.config
# export GOPATH=$HOME/.local/go
# export DEV="$HOME/Dev"
# export DENO_INSTALL="$HOME/.deno"

# setxkbmap -option caps:escape

addToPath() {
    if [[ "$PATH" != *"$1"* ]]; then
        export PATH=$PATH:$1
    fi
}

addToPathFront() {
    if [[ "$PATH" != *"$1"* ]]; then
        export PATH=$1:$PATH
    fi
}

# addToPathFront $HOME/.local/bin
# addToPathFront $HOME/.local/go/bin
# addToPathFront $HOME/.local/scripts
# addToPathFront $HOME/.cargo/bin
# addToPathFront $DENO_INSTALL
