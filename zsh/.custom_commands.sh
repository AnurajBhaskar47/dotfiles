#!/bin/zsh

pkgsize(){ expac -SsH M "%m: %n$\t%d" $@ | sort -h | tr '$' '\n'}

listsize(){ LC_ALL=C pacman -Qi | awk '/^Name/{name=$3} /^Installed Size/{print $4$5, name}' | sort -h }
