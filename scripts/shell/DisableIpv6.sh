if [ $(cat /etc/default/grub |grep 'ipv6.disable=1' |grep GRUB_CMDLINE_LINUX|wc -l) -eq 0 ];then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg 
    /usr/sbin/grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
fi
