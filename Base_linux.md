This file is how to create base linux image in VBox on COE.

## HW configuration

8 cpu\
32g mem\
160g disk\
2 nic(Default, Interna)

## Installation Option

Ubuntu24\
English keyboard, english mode\
bdsuser, login automatically\
reboot,\
System automatically detect available updates. -> update.

## change boot screen

***

edit /etc/default/grub\
GRUB\_CMDLINE\_LINUX\_DEFAULT="nosplash"\
sudo update-grub2\
poweroff

## Install VBox guest additons

***

sudo apt update\
sudo apt install linux-headers-\$(uname -r) build-essential

sudo apt install -y net-tools git curl\
sudo apt install -y openssh-server\
sudo systemctl status ssh\
sudo apt install -y fontconfig\
\#sudo apt install -y lsb

## system settings

***

sudo systemctl set-default multi-user.target
<-> sudo systemctl set-default graphical.target

How to stop s20auto-upgrades\
sudo vi /etc/apt/apt.conf.d/20auto-upgrades\
&#x20; APT::Periodic::Update-Package-Lists "0";\
&#x20; APT::Periodic::Unattended-Upgrade "0";

## For zscaler

***

#for corporate COE only  \
import zscaler cert into Firefox\
sudo cp -p zscaler.cer /usr/local/share/ca-certificates/\
sudo update-ca-certificates --fresh\
echo "cacert=/home/bduser/zscaler.cer" >> \$HOME/.curlrc

## For Development tools

sudo apt install -y openjdk-17-jdk\
sudo apt install -y maven  

vsc install\

この後
・必要に応じてHWリソース変更。\
・sudo hostnamectl set-hostname xxxxx.demo.local\
・hostname -f\
必要に応じてIP固定、MAC変更\
sudo reboot

```
```
