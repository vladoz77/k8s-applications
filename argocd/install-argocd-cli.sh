#!/bin/bash
#check if run with sudo
if (( $UID != 1000 )); then
    echo "Please run as root"
    exit
fi
#check argocd cli if install
argocd > /dev/null 2>&1
if [ "${?}" != 0 ]
    then 
        echo 'installing argocd'
        curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    else
        echo 'argocd already installed'
fi
    