#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status.
set -u  # Treat unset variables as an error when substituting.
set -v  # Print shell input lines as they are read.
set -x  # Print commands and their arguments as they are executed.

# обновление репозиторие CentOS (в связи с End Of Life)
sudo sed 's|^\(mirrorlist=\)|#\1|' -i "/etc/yum.repos.d/CentOS-Base.repo"
sudo sed 's|^#\(baseurl=\)|\1|' -i "/etc/yum.repos.d/CentOS-Base.repo"
sudo sed 's|mirror\.centos\.org/centos/$releasever|vault.centos.org/7.5.1804|' \
  -i "/etc/yum.repos.d/CentOS-Base.repo"

sudo yum install -y gdisk xfsdump

# при наличии нескольких дисков /dev/sda не обязательно системный диск...

# системный диск это устройство sd[a-z], на котором находится том LogVol00
SYS_DISK=$(sudo pvs --no-headings -o pv_name,lv_name | grep LogVol00 \
  | sed 's|.*/\(sd[a-z]\).*|\1|')
# диски (кроме системного) по их размеру (от наименьшего):
DISKS=$(grep --with-filename ^ /sys/block/sd*/size \
  | grep --fixed-strings --invert-match "${SYS_DISK}" \
  | sort --general-numeric-sort --field-separator=: --key=2 \
  | sed 's|.*/\(sd[a-z]\)/.*|\1|')
# 2 диска под /var, наименьшего размера:
VAR_DISK1=$(echo "${DISKS}" | sed --quiet '1p')
VAR_DISK2=$(echo "${DISKS}" | sed --quiet '2p')
# диск под /home, среднего размера:
HOME_DISK=$(echo "${DISKS}" | sed --quiet '3p')
# дополнительный диск:
ADD_DISK=$(echo "${DISKS}" | sed --quiet '4p')

# на всех свободных дисках создаём разделы под по lvm:
for dev in ${DISKS}; do
  (
    sudo sgdisk --clear "/dev/${dev}"
    sudo sgdisk --new="0:0:0" "/dev/${dev}"
    sudo sgdisk --typecode="1:8e00" "/dev/${dev}"
    sudo pvcreate "/dev/${dev}1"
  ) &
done
wait

# создаём том под /home:
sudo vgextend VolGroup00 "/dev/${HOME_DISK}1"
sudo lvcreate --size 2016M --name LogVolHome VolGroup00 "/dev/${HOME_DISK}1"

# создаём том под /var в зеркало:
sudo vgcreate VolGroupVar "/dev/${VAR_DISK1}1" "/dev/${VAR_DISK2}1"
sudo lvcreate --size 992M --mirrors 1 --name LogVolVar VolGroupVar

# создаём том под cachepool:
sudo vgextend VolGroup00 "/dev/${ADD_DISK}1"
sudo lvcreate --type cache-pool --cachemode writethrough --size 1G \
  --name CachePool VolGroup00 "/dev/${ADD_DISK}1"

# создаём временный том под корневую ФС:
sudo lvcreate --size 8G --name LogVolTmpRoot VolGroup00 \
  "/dev/${ADD_DISK}1"

# форматируем будующие /home, /var и /
sleep 1  # ждём обновления информации о томах
sudo mkfs.xfs /dev/mapper/VolGroup00-LogVolTmpRoot
sudo mkfs.xfs /dev/mapper/VolGroup00-LogVolHome
sudo mkfs.ext4 /dev/mapper/VolGroupVar-LogVolVar

# делаем snapshot корневого раздела
sudo lvcreate --snapshot --size 512M --name SnapVol00 \
  VolGroup00/LogVol00 "/dev/${ADD_DISK}1"

# копируем файлы из корневого раздела на созданные тома:
sudo mkdir /mnt/SnapVol00
sudo mkdir /mnt/LogVolTmpRoot
sudo mkdir /mnt/home
sudo mkdir /mnt/var
sudo mount -o nouuid /dev/mapper/VolGroup00-SnapVol00 /mnt/SnapVol00
sudo mount /dev/mapper/VolGroup00-LogVolTmpRoot /mnt/LogVolTmpRoot
sudo mount /dev/mapper/VolGroup00-LogVolHome /mnt/home
sudo mount /dev/mapper/VolGroupVar-LogVolVar /mnt/var
sudo xfsdump -J - /mnt/SnapVol00 | sudo xfsrestore -J - /mnt/LogVolTmpRoot
sudo cp --archive --recursive /mnt/SnapVol00/home /mnt/
sudo cp --archive --recursive /mnt/SnapVol00/var /mnt/

# удаляем snapshot корневого раздела:
sudo umount /mnt/SnapVol00
sudo lvremove --yes VolGroup00/SnapVol00

# удаляем файлы внутри /home и /var на новом корневом разделе:
sudo rm --recursive /mnt/LogVolTmpRoot/home
sudo rm --recursive /mnt/LogVolTmpRoot/var
sudo mkdir /mnt/LogVolTmpRoot/home
sudo mkdir /mnt/LogVolTmpRoot/var

# добавляем разделы в /etc/fstab, монтируем по имени, так как
# UUID оргинального LVM тома и его snapshot'а будет совпадать
sudo sed 's|\bLogVol00\b|LogVolTmpRoot|g' -i /mnt/LogVolTmpRoot/etc/fstab
echo "/dev/mapper/VolGroup00-LogVolHome /home xfs defaults 0 0" \
  | sudo tee --append /mnt/LogVolTmpRoot/etc/fstab
# ext4 необходимо периодически проверять, поэтому defaults 0 2
echo "/dev/mapper/VolGroupVar-LogVolVar /var ext4 defaults 0 2" \
  | sudo tee --append /mnt/LogVolTmpRoot/etc/fstab

# обновляем конфигурацию загрузчика для загрузки с LogVolTmpRoot:
sudo mount -t proc proc /mnt/LogVolTmpRoot/proc
sudo mount -t sysfs sysfs /mnt/LogVolTmpRoot/sys
sudo mount -t devtmpfs devtmpfs /mnt/LogVolTmpRoot/dev
sudo umount /boot
sudo mount "/dev/${SYS_DISK}2" /mnt/LogVolTmpRoot/boot
sudo sed 's|\bLogVol00\b|LogVolTmpRoot|g' \
  -i /mnt/LogVolTmpRoot/etc/default/grub
sudo chroot /mnt/LogVolTmpRoot grub2-mkconfig -o /boot/grub2/grub.cfg
sudo umount /mnt/LogVolTmpRoot/proc
sudo umount /mnt/LogVolTmpRoot/sys
sudo umount /mnt/LogVolTmpRoot/dev
sudo umount /mnt/LogVolTmpRoot/boot

# добавляем скрипт, который будем запускаться после перезагрузки:
cat <<EOF | sudo tee /mnt/LogVolTmpRoot/etc/cron.d/provision
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
@reboot root /bin/bash /vagrant/provision2.sh > /vagrant/provision2.log 2>&1
EOF

# перезагружаемся в систему на LogVolTmpRoot:
sudo umount /dev/mapper/VolGroup00-LogVolTmpRoot
sudo umount /dev/mapper/VolGroup00-LogVolHome
sudo umount /dev/mapper/VolGroupVar-LogVolVar
sudo reboot
