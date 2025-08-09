export XDG_CONFIG_HOME=$HOME/.config
. "$HOME/.cargo/env"

# VIM="nvim"
# PERSONAL=$XDG_CONFIG_HOME/personal
# for i in `find -L $PERSONAL`; do
#	source $i
#done

bindkey -s '^F' "tmux-sessionizer\n"
# setxkbmap -option caps:escape

export GOPATH=$HOME/.local/go
export GIT_EDITOR=$VIM
export DENO_INSTALL="$HOME/.deno"
export DEV_ENV_HOME="$HOME/personal/dev"

function git() {
  if [[ $1 == "l" ]]; then
    shift
    command git log --oneline --graph "$@"
  else
    command git "$@"
  fi
}

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

addToPathFront $DENO_INSTALL
addToPathFront $HOME/.local/go/bin
addToPathFront $HOME/.local/scripts
# addToPathFront $HOME/.cargo/bin
