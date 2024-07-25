#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status.
set -u  # Treat unset variables as an error when substituting.
set -v  # Print shell input lines as they are read.
set -x  # Print commands and their arguments as they are executed.

# удаляем этот скрипт из автозагрузки:
rm /etc/cron.d/provision

# системный диск это устройство sd[a-z], на котором находится том LogVol00
SYS_PART=$(sudo pvs --no-headings -o pv_name,lv_name | grep LogVol00 \
  | awk '{print $1}')
TMP_PART=$(sudo pvs --no-headings -o pv_name,lv_name | grep LogVolTmpRoot \
  | awk '{print $1}')

# удаляем корневой раздел:
lvremove --yes /dev/mapper/VolGroup00-LogVol00

# перемещаем том LogVolTmpRoot на другой диск
pvmove --name LogVolTmpRoot "${TMP_PART}" "${SYS_PART}"

# переименовываем LogVolTmpRoot в LogVol00
lvrename VolGroup00 LogVolTmpRoot LogVol00

# обновляем /etc/fstab и конфигурацию загрузчика
sed 's|\bLogVolTmpRoot\b|LogVol00|g' -i /etc/fstab
sed 's|\bLogVolTmpRoot\b|LogVol00|g' -i /etc/default/grub
sed 's|\bLogVolTmpRoot\b|LogVol00|g' -i /boot/grub2/grub.cfg

# генерируем файлы в /home:
mkdir /home/vagrant/files
for f in {01..20}; do
  dd if=/dev/urandom of="/home/vagrant/files/${f}.bin" bs=4096 count=1
done

# снимаем snapshot /home:
lvcreate --snapshot --size 1G --name SnapHome VolGroup00/LogVolHome

# удаляем часть файлов:
rm /home/vagrant/files/{11..20}.bin -f
ls -la /home/vagrant/files/

# восстанавливаем snapshot:
umount /home
lvconvert --merge VolGroup00/SnapHome
mount /home
ls -la /home/vagrant/files/

# создаём том под /opt, форматируем, добавляем в fstab:
lvcreate --size 4G --name LogVolOpt VolGroup00 "${SYS_PART}"
sleep 1  # ждём обновления информации о томах
mkfs.btrfs /dev/mapper/VolGroup00-LogVolOpt

# создаём subvolume @opt на LogVolOpt и делаем его snapshot:
mount /dev/mapper/VolGroup00-LogVolOpt /mnt
btrfs subvolume create /mnt/@opt
btrfs subvolume snapshot /mnt/@opt \
  "/mnt/@opt_snapshot_$(date --iso-8601=seconds)"
umount /mnt

# подключаем cache:
lvconvert --yes --type cache --cachepool CachePool VolGroup00/LogVolOpt

# добавляем /opt в fstab и монтируем:
echo "/dev/mapper/VolGroup00-LogVolOpt /opt btrfs subvol=@opt 0 0" \
  >> /etc/fstab
mount /opt
