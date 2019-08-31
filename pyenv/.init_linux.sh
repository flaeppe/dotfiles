#!/usr/bin/env fish

# Install pyenv for all users

set install_path /usr/local/bin/pyenv.git

sudo git clone --depth 1 git://github.com/pyenv/pyenv.git $install_path
# Figure out what to point the pyenv program to
set ln_src (find -L $install_path/bin -type f -exec readlink -f {} \;)
# Symlink to /usr/local/bin folder to enable executable
sudo ln -s $ln_src /usr/local/bin/pyenv
# Trigger pyenv python-build plugin install
cd $install_path/plugins/python-build && sudo env PREFIX=/usr/local ./install.sh
